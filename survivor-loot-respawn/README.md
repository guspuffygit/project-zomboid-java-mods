# Survivor Loot Respawn

A Storm mod for Project Zomboid (Build 42) that replaces vanilla loot respawn with a per-container, time-based regrowth model. Every looted container is stamped with the in-game hour it was emptied; on each hourly tick the server rolls every eligible container against a chance that ramps from `MinRespawnChance` up to `MaxRespawnChance` along an exponential curve over `HoursTillMaxRespawnChance`. When a roll succeeds the container is *queued*, and the actual item fill happens the next time that chunk is loaded (or on a 10-minute sweep over already-loaded chunks).

Workshop: `3742639806`.
Maven group: `com.sentientsimulations.projectzomboid`.
Server-side only. Requires [Storm](https://steamcommunity.com/sharedfiles/filedetails/?id=3670772371).

## What it does

- **Disables vanilla loot respawn** — `LootRespawnPatch.GetRespawnIntervalAdvice` forces `zombie.LootRespawn.getRespawnInterval` to return `0` whenever the mod is enabled, so the base game's `LootRespawnHours` machinery is inert.
- **Tracks every looted container** in SQLite (`<save>/survivor_loot_respawn.db`). Each row keys on `(square_x, square_y, square_z, container_type, container_index)` plus the world-age hour the container was looted and a nullable `respawn_queued_at_hours`.
- **Rolls hourly** — `EveryHoursEvent` selects all rows whose `looted_game_hours <= worldAgeHours - quiet`, computes a per-container chance, and rolls. Winners get `respawn_queued_at_hours` stamped.
- **Refills on chunk load** — `LootRespawnPatch.ChunkLoadedAdvice` intercepts `chunkLoaded` and runs `ChunkLoadedRespawnHandler.processChunk`, which fills queued containers via `ItemPickerJava.fillContainer` and broadcasts `AddInventoryItemToContainer` packets to nearby players.
- **10-minute fallback sweep** — `EveryTenMinutesEvent` queries the DB for all queued rows grouped by chunk and runs `ChunkLoadedRespawnHandler.processChunkRows` against whichever of those chunks are currently loaded. This catches containers that were queued *after* a chunk was loaded (so the `chunkLoaded` hook already fired).

## The math

Each container rolls once per in-game hour (driven by `EveryHoursEvent`) once `hoursSinceLooted >= quietPeriod`. At roll `k` (k = 1, 2, …), at `h = quiet + (k - 1)`:

```
t      = clamp(h / H, 0, 1)                       # H = HoursTillMaxRespawnChance
curve  = (s^t - 1) / (s - 1)        if s > 1      # s = CurveSteepness
       = t                          if s <= 1
chance = min + (max - min) * curve                # in percent
```

Implemented in `HourlyRespawnRollHandler.computeChance`. Time to respawn `T` (hours since looting) is `quiet + (K - 1)`, where `K` is the trial index of the first success — so:

```
E[T] = quiet + Σ_{k=1..∞}  Π_{j=1..k-1} (1 - p_j)   - 1
```

There is no closed form for `E[T]`, but the sum converges quickly (survival hits zero by `k ≈ H`) and `E[T]` is monotonic in `H`. A binary search inverts it cheaply.

### Calibrating with `scripts/respawn_calc.py`

The math is unintuitive: with the defaults (`min=0`, `max=100`, `steepness=1.05`, `quiet=0`), setting `HoursTillMaxRespawnChance = 96` produces an **average** respawn time of only ~12h, not 96h. Every hour along the rising-chance ramp is another roll, and the cumulative survival probability collapses fast.

The bundled calculator solves the inverse problem — given `min`, `max`, `steepness`, `quiet`, and a target `E[T]`, what `H` do you need?

```
python3 scripts/respawn_calc.py                                 # defaults: target 96h, current sandbox defaults
python3 scripts/respawn_calc.py --target 96 --max 10 --quiet 48 # custom params
python3 scripts/respawn_calc.py --H 96                          # forward: print E[T] for a given H
```

Sample results, all targeting `E[T] = 96` in-game hours:

| min | max | steepness | quiet | required `H` | note                                 |
|----:|----:|----------:|------:|-------------:|--------------------------------------|
|   0 | 100 |      1.05 |     0 |       5767   | current defaults                     |
|   0 | 100 |      1.05 |    48 |       4056   | 48h quiet period                     |
|   0 | 100 |      1.05 |    72 |       2255   | 72h quiet period                     |
|   0 | 100 |       2.0 |     0 |       4123   | steepness pushed to max              |
|   0 |  10 |      1.05 |     0 |        579   | lower the cap (`MaxRespawnChance`)   |
|   0 |   5 |      1.05 |     0 |        290   | even lower cap                       |

The cap and the quiet period are far stronger levers than `H` itself.

## Architecture

```
src/main/java/com/sentientsimulations/projectzomboid/survivorlootrespawn/
├── SurvivorLootRespawnMod.java           # Storm entry point; server-only via StormEnv.isStormServer()
├── ContainerLootedHandler.java           # OnContainerLootedEvent → insert into DB
├── VanillaLootRespawnGate.java           # Square + parent-object eligibility (zone, safehouse, construction, IsoThumpable/IsoDeadBody/IsoCompost)
├── HourlyRespawnRollHandler.java         # EveryHoursEvent → roll eligible rows, mark queued
├── EveryTenMinutesRespawnHandler.java    # EveryTenMinutesEvent → sweep loaded chunks, update gauges
├── ChunkLoadedRespawnHandler.java        # chunkLoaded patch target; fills queued containers
├── patch/LootRespawnPatch.java           # Disables vanilla LootRespawn; hooks chunkLoaded
├── config/SurvivorLootRespawnConfig.java # Sandbox-option readers
├── metrics/SurvivorLootRespawnMetrics.java # Prometheus instruments (counters, histograms, gauges)
└── state/
    ├── ContainerLootState.java           # Record type
    ├── ContainerLootStateRepository.java # SQL (no business logic)
    └── SurvivorLootRespawnDatabase.java  # JDBC connection + schema + migrations
```

The mod is **server-only**. `SurvivorLootRespawnMod.registerEventHandlers` and `getClassTransformers` both early-return on the client JVM via `StormEnv.isStormServer()`. Connecting clients do not need to install the mod.

## Database

SQLite file: `<save>/survivor_loot_respawn.db`. WAL mode, `synchronous=NORMAL`. Single connection shared across the JVM (the mod is server-side only, so contention is bounded). The schema migrates forward in place — `SurvivorLootRespawnDatabase.getConnection` runs `CREATE TABLE IF NOT EXISTS` and a `PRAGMA table_info` check that adds `fill_added_nothing_count` to pre-existing tables.

### `container_loot_state`

| column                    | type    | notes                                                  |
|---------------------------|---------|--------------------------------------------------------|
| square_x, square_y, square_z | INTEGER | World-space square coordinates                       |
| container_type            | TEXT    | `ItemContainer.getType()` (e.g. `crate`, `fridge`)     |
| container_index           | INTEGER | Ordinal position among containers on the square's `IsoObject`s — disambiguates multi-container squares |
| looted_game_hours         | REAL    | `GameTime.getWorldAgeHours()` at loot time             |
| respawn_queued_at_hours   | REAL    | Set when an hourly roll wins; `NULL` while still rolling |
| fill_added_nothing_count  | INTEGER | Number of times `ItemPickerJava.fillContainer` ran but added no items for this row. Hits the retry cap (`ChunkLoadedRespawnHandler.MAX_FILL_NOTHING_RETRIES = 3`) → row evicted with `result=delete_fill_give_up`. |

Primary key: `(square_x, square_y, square_z, container_type, container_index)`, `WITHOUT ROWID`. Partial index `idx_container_loot_state_queued` on the same key, filtered to rows where `respawn_queued_at_hours IS NOT NULL`, to make chunk-load lookups O(queued) instead of O(table).

## Event flow

### `OnContainerLootedEvent` (Storm) — `ContainerLootedHandler.onContainerLooted`
- Fires when items move out of a container via Storm's UUID transfer path. Storm dispatches this for container → inventory, container → container, and container → floor transfers, so the mod no longer needs a separate packet-level subscriber.
- Filters via `VanillaLootRespawnGate.passesSquareGate(sq)` (zone must be `TownZone` / `TownZones` / `TrailerPark`; respects `constructionPreventsLootRespawn` and `safehousePreventsLootRespawn`).
- Skips containers whose parent `IsoObject` is excluded — `IsoThumpable` (player-built furniture), `IsoDeadBody`, or `IsoCompost` — and containers already at or above `SandboxOptions.maxItemsForLootRespawn`.
- Computes `container_index` by walking `sq.getObjects()` and counting containers in declaration order.
- Inserts the row with `INSERT … ON CONFLICT DO NOTHING`, so existing `looted_game_hours` / `respawn_queued_at_hours` / `fill_added_nothing_count` are never overwritten by a re-loot.

### `EveryHoursEvent` — `HourlyRespawnRollHandler.onEveryHour`
- Runs on a daemon thread so the SQL doesn't block the game thread.
- `SELECT … WHERE respawn_queued_at_hours IS NULL AND looted_game_hours <= worldAgeHours - quiet`.
- For each row: compute chance, roll `ThreadLocalRandom.nextDouble() * 100 < chance`, mark queued.

### `EveryTenMinutesEvent` — `EveryTenMinutesRespawnHandler.onEveryTenMinutes`
- `ContainerLootStateRepository.selectAllQueuedByChunk()` returns every queued row grouped by `(chunkWX, chunkWY)`. For each group, looks up the live `IsoChunk` via `ServerMap.instance.getChunk(chunkWX, chunkWY)`; if the chunk isn't loaded the group is skipped (counted in `chunks_skipped_not_loaded`), otherwise `ChunkLoadedRespawnHandler.processChunkRows` runs on the pre-fetched rows.
- Necessary because a container can be marked queued *after* its chunk was loaded — the `chunkLoaded` advice would never fire for that chunk again until reload.
- Also refreshes the `rows_tracked` / `rows_queued` gauges and the `enabled` gauge on the DB executor.

### `chunkLoaded` (advised on `zombie.LootRespawn.chunkLoaded`)
- `ChunkLoadedRespawnHandler.onChunkLoaded` runs on chunk load. The whole body is wrapped in `try/catch (Throwable)` — Byte Buddy's `@Advice.OnMethodExit(suppress = Throwable.class)` would otherwise swallow every failure silently, so the explicit catch logs the error and increments `survivor_loot_respawn_on_chunk_loaded_errors_total`.
- Two phases run per chunk: **discover** (insert pre-existing explored+looted containers the mod hasn't tracked yet) and **process** (refill queued rows).
- For each queued row in the chunk: locate the original `IsoObject` + `ItemContainer` by walking the square's objects and matching `container_index` and `container_type`. If the container is gone, type-changed, or already full, the row is deleted and never re-attempted. If found and fillable, `ItemPickerJava.fillContainer(container, null)` is invoked; newly added items have `setAge(0.0F)` so they look fresh, and an `AddInventoryItemToContainer` packet is broadcast to relative players.
- If `fillContainer` returns with no new items (no loot distribution for the container type, or rolls all came up zero), the row's `fill_added_nothing_count` is incremented. After `MAX_FILL_NOTHING_RETRIES = 3` consecutive empty fills the row is evicted with result `delete_fill_give_up` to prevent a permanent retry leak.

### `zombie.LootRespawn.getRespawnInterval` (advised)
- Forced to return `0` whenever the mod is enabled, disabling vanilla loot respawn entirely. Without this the two systems would double up. Each intercept increments `survivor_loot_respawn_vanilla_interval_intercepted_total` — useful to confirm the patch is actually applied in a running server.

## Sandbox options

Under the **Survivor Loot Respawn** sandbox page. All read via `SandboxOptions.instance.getOptionByName("SurvivorLootRespawn.<name>")`.

| Option                       | Type    | Range / default          | Effect                                                                                                   |
|------------------------------|---------|--------------------------|----------------------------------------------------------------------------------------------------------|
| `LootRespawnType`            | enum    | `Vanilla` / `Exponential` (default) | `Vanilla` disables the mod entirely (no DB writes, no patches' active branches).                          |
| `HoursTillMaxRespawnChance`  | integer | 1…9999, default **96**   | `H` in the formula above. Set via `scripts/respawn_calc.py` for a desired average — see Calibrating.       |
| `MaxRespawnChance`           | integer | 0…100, default **100**   | `max` in the formula. The strongest lever for *slowing down* respawns.                                    |
| `MinRespawnChance`           | integer | 0…100, default **0**     | `min` in the formula. A non-zero floor *speeds up* respawns dramatically — every roll gets a guaranteed chance. |
| `ContainerQuietPeriodHours`  | integer | 0…9998, default **0**    | `quiet` in the formula. Hours after looting during which the row is excluded from rolls.                  |
| `CurveSteepness`             | double  | 1.001…2.0, default **1.05** | `s` in the formula. Closer to 1 is nearly linear; closer to 2 pushes more chance to the end of the window. |

## Metrics

The mod registers Prometheus instruments with Storm's shared `StormPrometheus.registry()`. To actually scrape them, launch the server with `-DprometheusPort=<port>` (see Storm's CLAUDE.md for the launch flags). Without that flag the collectors still register safely but nothing is exposed.

All instruments are prefixed `survivor_loot_respawn_*` so they group together at `/metrics`. Defined in `metrics/SurvivorLootRespawnMetrics.java`.

### Counters

| Name | Labels | Description |
|------|--------|-------------|
| `survivor_loot_respawn_looted_observed_total` | `path` = `event` | Loot events received from `OnContainerLootedEvent` (Storm UUID transfer — covers container→inventory, container→container, and container→floor). |
| `survivor_loot_respawn_looted_tracked_total` | `outcome` = `inserted` \| `duplicate` \| `skipped_no_grid` \| `skipped_zone_gate` \| `skipped_excluded_object` \| `skipped_full` \| `skipped_index_not_found` | Result of attempting to track a looted container in the DB. |
| `survivor_loot_respawn_discovery_inserted_total` | — | Rows inserted by chunk-load discovery (containers found explored & looted before the mod started tracking them). |
| `survivor_loot_respawn_discovery_skipped_total` | `reason` = `zone_gate` \| `null` \| `unexplored` \| `not_looted` \| `no_items` \| `full` \| `no_loot_table` | Containers seen during chunk-load discovery but filtered out before insert. |
| `survivor_loot_respawn_rolls_total` | `outcome` = `won` \| `lost` | Per-container hourly roll outcomes. |
| `survivor_loot_respawn_result_total` | `result` = `respawned` \| `retry_*` \| `delete_*` | One increment per queued row processed in `processChunk`; mirrors the `FillResult` enum (lowercased). |
| `survivor_loot_respawn_fill_added_nothing_total` | `container_type` | Times `fillContainer` returned with no new items for a queued container. Repeated hits for the same type point at an empty / broken loot distribution. |
| `survivor_loot_respawn_fill_give_up_total` | `container_type` | Queued rows evicted after exceeding the retry cap. |
| `survivor_loot_respawn_vanilla_interval_intercepted_total` | — | Times `LootRespawnPatch` forced `LootRespawn.getRespawnInterval` to 0. |
| `survivor_loot_respawn_on_chunk_loaded_errors_total` | — | Unhandled exceptions caught inside the `onChunkLoaded` try/catch. The Byte Buddy advice suppresses throwables, so without this counter failures would be invisible. |
| `survivor_loot_respawn_db_errors_total` | `op` (`insert`, `batch_insert`, `select_rolling`, `select_queued_chunk`, `select_queued_square`, `mark_queued`, `batch_mark_queued`, `delete`, `increment_fill_added_nothing`, `count_total`, `count_queued`) | SQL exceptions raised by the repository. |

### Histograms (native-only — bucket-free, dynamic resolution)

| Name | Description |
|------|-------------|
| `survivor_loot_respawn_chunk_process_duration_seconds` | Time to walk one chunk's queued rows and attempt to fill them. Fires on every chunk load and during the 10-minute sweep. |
| `survivor_loot_respawn_chunk_discover_duration_seconds` | Time to walk one chunk's squares and batch-insert any explored, looted containers not yet tracked. |
| `survivor_loot_respawn_hourly_roll_duration_seconds` | Time for the hourly roll cycle: select eligible rows, compute chance, batch-mark winners as queued. |
| `survivor_loot_respawn_tenmin_sweep_duration_seconds` | Time for the 10-minute fallback sweep over every loaded chunk. |

### Histogram (classic buckets)

| Name | Description |
|------|-------------|
| `survivor_loot_respawn_winning_chance_percent` | Distribution of winning roll chances. Tells you whether wins are clustered low (curve too generous) or high (curve too steep). Buckets: 1, 5, 10, 25, 50, 75, 90, 99, 100. |

### Gauges

| Name | Description |
|------|-------------|
| `survivor_loot_respawn_rows_tracked` | Total rows in `container_loot_state`. Refreshed each 10-minute sweep. |
| `survivor_loot_respawn_rows_queued` | Rows currently queued for respawn (`respawn_queued_at_hours IS NOT NULL`). Refreshed each 10-minute sweep. |
| `survivor_loot_respawn_enabled` | `1` when the sandbox `LootRespawnType` = `Exponential`, `0` when `Vanilla`. |

## Building

```bash
./gradlew :survivor-loot-respawn:spotlessApply :survivor-loot-respawn:test
./gradlew :survivor-loot-respawn:deployMod
```

`deployMod` copies the built jar + `media/` into `${zomboidDir}/mods/survivor-loot-respawn/` per `local.properties`.

## Tests

JUnit + in-memory / `@TempDir` SQLite. Coverage in `src/test/java/.../survivorlootrespawn/`:

- `HourlyRespawnRollHandlerTest` — `computeChance` boundary behaviour (t=0, t=1, steepness branches, `min`/`max` clamping).
- `state/ContainerLootStateRepositoryTest` — insert idempotency, `selectRolling` quiet-period gate, `selectQueuedInChunk` bounds, `markQueued` / `delete` semantics, `fill_added_nothing_count` increment + row-count helpers.
