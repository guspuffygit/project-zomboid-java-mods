# Survivor Leaderboard

A Storm mod for Project Zomboid (Build 42) that tracks **days survived** and **PvP kill count** for every player on a dedicated server, renders a live in-game leaderboard, logs individual kills, and applies a delayed anti-grief penalty when a player kills the same ally more than once in an hour.

Workshop: `3686333544` (prod) / `3705341237` (dev).
Maven group: `com.sentientsimulations.projectzomboid`.
Requires: [Storm](https://steamcommunity.com/sharedfiles/filedetails/?id=3670772371) mod loader.

## What it does

- **Survivor board** — one row per `(steam_id, username)` with `day_count` and `kill_count`. Characters are tracked independently of the Steam account so alts do not share scores. Players with `day_count = 0` are hidden — a freshly-added player only shows up after their first day-count update.
- **Kill board** — players sorted by kill count. Zero-kill players are hidden from this board. Negative scores stay visible.
- **Kill log** — every PvP kill is appended to a `kills` table with an `is_ally` flag (true when killer and victim share a faction or safehouse).
- **Ally-grief penalty** — every in-game hour the server sweeps the kill log; any ally kill whose killer had another ally kill in the preceding 60 wall-clock minutes deducts `-5` from that killer's `kill_count`. The hourly cadence obscures the link between the kill and the score drop so a griefer cannot pinpoint which kill triggered it.
- **Ban / death cleanup** — on a player's death their outgoing kill log is wiped; on a Steam ID ban, all rows (survivor + kills) for that account are removed. Banned accounts are also pruned once on server start.
- **HTTP API** — boards and kill log are exposed as JSON for external dashboards.

## Architecture

```
src/main/java/com/sentientsimulations/projectzomboid/survivorleaderboard/
├── SurvivorLeaderboardMod.java         # Storm entry point + event handlers
├── SurvivorLeaderboardBridge.java      # Business logic; owns DB lifecycle per call
├── SurvivorLeaderboardDatabase.java    # SQLite connection + schema bootstrap
├── SurvivorLeaderboardRepository.java  # All SQL statements (no business logic)
├── SurvivorLeaderboardEndpoints.java   # @HttpEndpoint handlers (Storm HTTP server)
├── commands/                           # Storm client→server command events
└── records/                            # Record types for rows, DTOs, responses
```

Each DB operation opens a fresh `SurvivorLeaderboardDatabase` (a per-call JDBC connection). This keeps the Lua/game-thread path and HTTP worker threads from contending on a shared connection.

## Database

SQLite file: `<save>/survivor_leaderboard.db` (resolved via `ZomboidFileSystem.getFileInCurrentSave`). WAL mode is enabled at startup.

### `survivors`

| column      | type    | notes                                       |
|-------------|---------|---------------------------------------------|
| id          | INTEGER | primary key                                 |
| steam_id    | INTEGER | not null                                    |
| username    | TEXT    | not null; character name                    |
| day_count   | INTEGER | not null, default 0                         |
| kill_count  | INTEGER | not null, default 0 — may go **negative**   |

Unique key: `(steam_id, username)`. Separate characters on the same Steam account get separate rows.

### `kills`

| column           | type    |
|------------------|---------|
| id               | INTEGER primary key |
| killer_steam_id  | INTEGER |
| killer_username  | TEXT    |
| victim_steam_id  | INTEGER |
| victim_username  | TEXT    |
| is_ally          | INTEGER (0/1) |
| created_at       | INTEGER (unix ms) |
| penalty_applied  | INTEGER (0/1) — set to 1 once the hourly sweep has decided whether this kill earns a penalty |

Indexes: `(killer_steam_id, killer_username)` and `(created_at DESC)`.

A schema migration is applied on startup to add `kill_count` to older `survivors` tables that predate it.

## Event flow

### `OnCharacterDeathEvent` (Storm)
`SurvivorLeaderboardMod.onCharacterDeath` dispatches on `victim.getAttackedBy()`:

- **PvP** (`attacker instanceof IsoPlayer` and not self-kill)
  1. Compute `isAlly = Faction.isInSameFaction(killer, victim) || shared SafeHouse`.
  2. `recordPlayerKill(killer, victim, isAlly)` — `+1` to killer, reset victim's `kill_count` to 0 **only if it was positive** (negative values from ally-grief penalties are preserved so dying does not wipe the debt), insert a `kills` row (with `is_ally` and `penalty_applied = 0`), delete the victim's outgoing kill log.
- **Non-PvP death** → `resetKillsForPlayer(victim)` zeroes `kill_count` only when it was positive and wipes the victim's outgoing kill log.

### `EveryHoursEvent` (Storm)
Once per in-game hour, `processAllyKillPenalties()` sweeps the `kills` table. See **Ally-kill penalty** below.

### `OnBanSteamIDEvent` (Storm)
Deletes all `survivors` rows + all `kills` rows where the banned Steam ID is the killer.

### `OnServerStartedEvent` / `OnTickEvent`
- `OnServerStartedEvent` initializes the DB (creating tables and indexes).
- On the first `OnTickEvent`, `pruneBannedSurvivors` iterates distinct Steam IDs in `survivors`, cross-references `ServerWorldDatabase.isSteamIdBanned`, and removes any matches. This runs once per server lifetime.

### Client commands (Lua → Java)
| Command                | Handler                          | Behavior                          |
|------------------------|----------------------------------|-----------------------------------|
| `OnClientAddPlayer`    | `addPlayer`                      | Insert with `day_count = 0`, broadcast |
| `OnClientRefresh`      | `refresh`                        | Rebroadcast current board         |
| `OnClientIncrement`    | `incrementDays(daysSurvived)`    | Set `day_count = daysSurvived`, broadcast |

### Server → client broadcasts
`broadcast(repo)` sends a `UpdateBoard` `GameServer.sendServerCommand` to all clients with the full ordered survivor table. Payload shape (consumed by `LifeBoard_UI.lua`):
```
{ board = [ { displayName, dayCount, killCount }, ... ] }
```

## Ally-kill penalty

Driven by Storm's `EveryHoursEvent`, which fires once per in-game hour. State lives in the `kills` table, so penalties survive server restarts.

**Invariant:** the first ally kill in any rolling 60-minute window is free; every ally kill after that deducts `-5` from the killer's `kill_count`.

Each hourly sweep, implemented in `SurvivorLeaderboardBridge.processAllyKillPenalties`:

1. `SELECT … FROM kills WHERE is_ally = 1 AND penalty_applied = 0 ORDER BY created_at ASC`.
2. For each unapplied ally kill, check whether the same killer has another ally kill in `[created_at - 60 min, created_at)`. If yes, `decrementKillCount(killer, 5)`.
3. Mark the row `penalty_applied = 1` so it is skipped on the next sweep.
4. If any penalty applied, broadcast the refreshed board.

Key properties:

- **Window**: 60 wall-clock minutes (`ALLY_KILL_WINDOW_MS`). The event is the trigger; the timestamps being compared are wall-clock (`System.currentTimeMillis()`).
- **Penalty**: `-5` per qualifying ally kill (`ALLY_KILL_PENALTY`).
- **Worst-case delay**: one in-game hour between the offending kill and the score drop — natural obscurity without a separate scheduler.
- **Negative allowed**: a griefer stays below zero until new legitimate kills recover the score. Zero-kill rows are hidden from the killer board but negative rows remain visible.
- **Ally definition**: same faction OR same safehouse (owner or member). Faction via `Faction.isInSameFaction`; safehouse via `SafeHouse.hasSafehouse` compared with `.equals`.
- **Missing killer row**: if the killer was banned/pruned between the kill and the sweep, the decrement updates zero rows, logs a notice, and the kill is still marked applied.

## HTTP API

The HTTP server is provided by Storm and enabled by launching the game with `-Dstorm.http.port=<port>`. Endpoints are registered via `@HttpEndpoint`.

| Path                    | Query params              | Response                                      |
|-------------------------|---------------------------|-----------------------------------------------|
| `GET /leaderboard/survivors` | `limit` (default 10)      | `{ survivors: [{displayName, dayCount, steamId}] }` |
| `GET /leaderboard/killers`   | `limit` (default 10)      | `{ killers: [{displayName, killCount, steamId}] }`  |
| `GET /leaderboard/kills`     | `limit` (default 50, max 500) | `{ kills: [{killerSteamId, killerUsername, victimSteamId, victimUsername, isAlly, createdAt}] }` |
| `POST /leaderboard/sql`      | `sql=` (or request body)  | Admin escape hatch — runs arbitrary SQL. No sanitization. |

`killers` excludes zero-kill rows. `survivors` excludes zero-day rows. Negative kill counts remain visible on `killers`.

## Sandbox options

`Lifeboard.Cooldown` — integer, minutes, 1…43200 (default 60). Used by the client-side Lua to throttle how often a player can request a board refresh.

## Building

```bash
./gradlew :survivor-leaderboard:spotlessApply :survivor-leaderboard:test
./gradlew :survivor-leaderboard:installStorm
```

`installStorm` copies the built jar + `media/` into `~/Zomboid/Workshop/<workshopIdDev>/` for local dev, matching Storm's `-DstormType=local` resolution.

## Tests

Integration tests use real SQLite files in JUnit `@TempDir`. Coverage includes:

- `SurvivorLeaderboardDecrementTest` — decrement arithmetic, negative values, zero-kill hiding on the killer board only.
- `SurvivorLeaderboardKillLogTest` — insert, ordering, limit, delete-by-killer, delete-by-steam-id.
- `SurvivorLeaderboardAllyKillProcessorTest` — hourly sweep: single-kill free slot, 2nd/3rd kill penalized, out-of-window kills ignored, non-ally kills skipped, idempotency, negative-allowed, chronological ordering.
- `SurvivorLeaderboardBanPruneTest` — startup prune removes banned rows.
- `SurvivorLeaderboardEndpointsTest` — `parseLimit` parsing and clamping.
- `SurvivorLeaderboardSqlEndpointTest` — `/leaderboard/sql` response shapes.
