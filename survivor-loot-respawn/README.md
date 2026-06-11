# Survivor Loot Respawn

A Storm mod for Project Zomboid (Build 42) that replaces vanilla loot respawn with a per-container, time-based regrowth model. Every looted container is stamped with the in-game hour it was emptied; on each hourly tick the server rolls every eligible container against a chance that ramps from `MinRespawnChance` up to `MaxRespawnChance` along an exponential curve over `HoursTillMaxRespawnChance`. When a roll succeeds the container is *queued*, and the actual item fill happens the next time that chunk is loaded (or on a 10-minute sweep over already-loaded chunks).

Workshop: `3742639806`.
Maven group: `com.sentientsimulations.projectzomboid`.
Server-side only. Requires [Storm](https://steamcommunity.com/sharedfiles/filedetails/?id=3670772371).

## What it does

- **Disables vanilla loot respawn** — `LootRespawnPatch.GetRespawnIntervalAdvice` forces `zombie.LootRespawn.getRespawnInterval` to return `0` whenever the mod is enabled, so the base game's `LootRespawnHours` machinery is inert.
- **Tracks every looted container** in SQLite (`<save>/survivor-loot-respawn.db`). Each row keys on `(square_x, square_y, square_z, container_type, container_index)` plus the world-age hour the container was looted and a nullable `respawn_queued_at_hours`.
- **Rolls hourly** — `EveryHoursEvent` selects all rows whose `looted_game_hours <= worldAgeHours - quiet`, computes a per-container chance, and rolls. Winners get `respawn_queued_at_hours` stamped.
- **Refills on chunk load** — `LootRespawnPatch.ChunkLoadedAdvice` intercepts `chunkLoaded` and runs `ChunkLoadedRespawnHandler.processChunk`, which fills queued containers via `ItemPickerJava.fillContainer` and broadcasts `AddInventoryItemToContainer` packets to nearby players.
- **10-minute fallback sweep** — `EveryTenMinutesEvent` walks every `IsoChunk` in every loaded `ServerCell` and runs the same chunk handler. This catches containers that were queued *after* a chunk was loaded (so the `chunkLoaded` hook already fired).

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
├── SurvivorLootRespawnMod.java          # Storm entry point; server-only via StormEnv.isStormServer()
├── ContainerLootedHandler.java          # OnContainerLootedEvent → upsert into DB
├── HourlyRespawnRollHandler.java        # EveryHoursEvent → roll eligible rows, mark queued
├── EveryTenMinutesRespawnHandler.java   # EveryTenMinutesEvent → sweep loaded chunks
├── ChunkLoadedRespawnHandler.java       # chunkLoaded patch target; fills queued containers
├── patch/LootRespawnPatch.java          # Disables vanilla LootRespawn; hooks chunkLoaded
├── config/SurvivorLootRespawnConfig.java # Sandbox-option readers
└── state/
    ├── ContainerLootState.java          # Record type
    ├── ContainerLootStateRepository.java # SQL (no business logic)
    └── SurvivorLootRespawnDatabase.java  # JDBC connection + schema
```

The mod is **server-only**. `SurvivorLootRespawnMod.registerEventHandlers` and `getClassTransformers` both early-return on the client JVM via `StormEnv.isStormServer()`. Connecting clients do not need to install the mod.

## Database

SQLite file: `<save>/survivor-loot-respawn.db`. WAL mode, `synchronous=NORMAL`. Single connection shared across the JVM (the mod is server-side only, so contention is bounded).

### `container_loot_state`

| column                    | type    | notes                                                  |
|---------------------------|---------|--------------------------------------------------------|
| square_x, square_y, square_z | INTEGER | World-space square coordinates                       |
| container_type            | TEXT    | `ItemContainer.getType()` (e.g. `crate`, `fridge`)     |
| container_index           | INTEGER | Ordinal position among containers on the square's `IsoObject`s — disambiguates multi-container squares |
| looted_game_hours         | REAL    | `GameTime.getWorldAgeHours()` at loot time             |
| item_count                | INTEGER | Items left after the loot event                        |
| respawn_queued_at_hours   | REAL    | Set when an hourly roll wins; `NULL` while still rolling |
| last_username, last_steam_id | TEXT | Last player to loot it (diagnostic only)               |

Primary key: `(square_x, square_y, square_z, container_type, container_index)`. Partial index `idx_container_loot_state_queued` on the same key, filtered to rows where `respawn_queued_at_hours IS NOT NULL`, to make chunk-load lookups O(queued) instead of O(table).

## Event flow

### `OnContainerLootedEvent` (Storm) — `ContainerLootedHandler.onContainerLooted`
- Skips containers attached to `IsoThumpable` (player-built furniture) and containers already at or above `SandboxOptions.maxItemsForLootRespawn`.
- Computes `container_index` by walking `sq.getObjects()` and counting containers in declaration order.
- Upserts the row with the current `worldAgeHours`. Existing `respawn_queued_at_hours` is preserved (the `ON CONFLICT … DO UPDATE` clause only overwrites `item_count`, `last_username`, `last_steam_id`).

### `EveryHoursEvent` — `HourlyRespawnRollHandler.onEveryHour`
- Runs on a daemon thread so the SQL doesn't block the game thread.
- `SELECT … WHERE respawn_queued_at_hours IS NULL AND looted_game_hours <= worldAgeHours - quiet`.
- For each row: compute chance, roll `ThreadLocalRandom.nextDouble() * 100 < chance`, mark queued.

### `EveryTenMinutesEvent` — `EveryTenMinutesRespawnHandler.onEveryTenMinutes`
- Walks `ServerMap.instance.loadedCells`, then each cell's `chunks[x][y]`, calling `ChunkLoadedRespawnHandler.processChunk` on each.
- Necessary because a container can be marked queued *after* its chunk was loaded — the `chunkLoaded` advice would never fire for that chunk again until reload.

### `chunkLoaded` (advised on `zombie.LootRespawn.chunkLoaded`)
- `ChunkLoadedRespawnHandler.onChunkLoaded` runs on chunk load.
- For each queued row in the chunk: locate the original `IsoObject` + `ItemContainer` by walking the square's objects and matching `container_index` and `container_type`. If the container is gone, type-changed, or already full, the row is deleted and never re-attempted. If found and fillable, `ItemPickerJava.fillContainer(container, null)` is invoked; newly added items have `setAge(0.0F)` so they look fresh, and an `AddInventoryItemToContainer` packet is broadcast to relative players.

### `zombie.LootRespawn.getRespawnInterval` (advised)
- Forced to return `0` whenever the mod is enabled, disabling vanilla loot respawn entirely. Without this the two systems would double up.

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

## Building

```bash
./gradlew :survivor-loot-respawn:spotlessApply :survivor-loot-respawn:test
./gradlew :survivor-loot-respawn:deployMod
```

`deployMod` copies the built jar + `media/` into `${zomboidDir}/mods/survivor-loot-respawn/` per `local.properties`.

## Tests

JUnit + in-memory / `@TempDir` SQLite. Coverage in `src/test/java/.../survivorlootrespawn/`:

- `HourlyRespawnRollHandlerTest` — `computeChance` boundary behaviour (t=0, t=1, steepness branches, `min`/`max` clamping).
- `state/ContainerLootStateRepositoryTest` — upsert idempotency, `selectRolling` quiet-period gate, `selectQueuedInChunk` bounds, `markQueued` / `delete` semantics.
