# SafeHouse SQLite Storage — Implementation Plan

Replace the SafeHouse section of `map_meta.bin` (binary ByteBuffer serialization) with a SQLite database. Work is on branch `safehouse-sqlite` in the `map-meta-sqlite` subproject.

## Prerequisites

- SQLite JDBC driver is already bundled by Project Zomboid at runtime (used for `players.db`), so no additional dependency is needed.
- The game JAR on the compile classpath (via `extractZomboidFiles`) provides access to `zombie.iso.areas.SafeHouse` and related classes.

## Phase 1: Reverse-engineer SafeHouse fields [DONE]

Source: `zombie.iso.areas.SafeHouse` — serialized in `SafeHouse.save(ByteBuffer)` (line 331) and `SafeHouse.load(ByteBuffer, int)` (line 355).

### Serialized fields (written to `map_meta.bin`)

| Field | Java Type | Binary Type | Notes |
|---|---|---|---|
| `x` | int | putInt | Top-left X coordinate |
| `y` | int | putInt | Top-left Y coordinate |
| `w` | int | putInt | Width |
| `h` | int | putInt | Height |
| `owner` | String | WriteString | Owner username |
| `hitPoints` | int | putInt | War damage counter (v216+) |
| `players` | ArrayList\<String\> | int count + WriteString each | Member usernames |
| `lastVisited` | long | putLong | Epoch millis of last owner/member visit |
| `title` | String | WriteString | Display name (default "Safehouse") |
| `datetimeCreated` | long | putLong | Epoch millis of creation (v223+) |
| `location` | String | WriteString | Nearest spawn region name (v223+) |
| `playersRespawn` | ArrayList\<String\> | int count + WriteString each | Members who respawn here |

### Derived / runtime-only fields (NOT serialized)

| Field | Notes |
|---|---|
| `id` | Computed as `x + "," + y + " at " + timestamp` in constructor — unique string identity |
| `onlineId` | Computed as `(x+y)*(x+y+1)/2 + x` in constructor — Cantor pairing for network ID |
| `playerConnected` | Runtime count of online members, recalculated dynamically |
| `openTimer` | Runtime state for safehouse disable timer |

### Version gating in `load()`

- `hitPoints` only read when `worldVersion >= 216`
- `datetimeCreated` and `location` only read when `worldVersion >= 223`

### Key observations

- Constructor takes `(x, y, w, h, owner)` — these are the minimum required fields
- `load()` calls `addPlayer()` for each member, `ChatServer.createSafehouseChat()`, and adds to `safehouseList`
- `players` list includes the owner (added in constructor), but `setOwner()` removes the owner from the players list
- `invites` is a static HashSet, not per-safehouse and not serialized

## Phase 2: SQLite schema & repository layer

**`SafeHouseDatabase.java`** — manages the SQLite connection lifecycle (open/close, create tables, migrations). DB file goes in the save directory as `map_meta.db` (alongside `map_meta.bin`).

**`SafeHouseRepository.java`** — CRUD operations:
- `saveAll(List<SafeHouse>)` — upsert all safehouses in a single transaction
- `loadAll()` — read all rows back
- `deleteAll()` — clear table (for reset scenarios)

### Finalized schema

```sql
CREATE TABLE IF NOT EXISTS safehouses (
    x INTEGER NOT NULL,
    y INTEGER NOT NULL,
    w INTEGER NOT NULL,
    h INTEGER NOT NULL,
    owner TEXT NOT NULL,
    hit_points INTEGER NOT NULL DEFAULT 0,
    last_visited INTEGER NOT NULL,       -- epoch millis
    title TEXT NOT NULL DEFAULT 'Safehouse',
    datetime_created INTEGER NOT NULL,   -- epoch millis
    location TEXT,
    PRIMARY KEY (x, y)
);

CREATE TABLE IF NOT EXISTS safehouse_players (
    safehouse_x INTEGER NOT NULL,
    safehouse_y INTEGER NOT NULL,
    username TEXT NOT NULL,
    PRIMARY KEY (safehouse_x, safehouse_y, username),
    FOREIGN KEY (safehouse_x, safehouse_y) REFERENCES safehouses(x, y) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS safehouse_respawns (
    safehouse_x INTEGER NOT NULL,
    safehouse_y INTEGER NOT NULL,
    username TEXT NOT NULL,
    PRIMARY KEY (safehouse_x, safehouse_y, username),
    FOREIGN KEY (safehouse_x, safehouse_y) REFERENCES safehouses(x, y) ON DELETE CASCADE
);
```

Notes:
- Natural primary key `(x, y)` instead of autoincrement — safehouses are uniquely identified by position
- `players` and `playersRespawn` normalized into separate tables instead of JSON blobs — enables querying by player
- Foreign keys with `ON DELETE CASCADE` so removing a safehouse cleans up members/respawns

## Phase 3: Class transformers (the core)

Two ByteBuddy patches, following the same pattern as `GameServerPatch`:

### `IsoMetaGridSavePatch`
- Targets `zombie.iso.IsoMetaGrid`, method `save()`
- `@Advice.OnMethodExit`: after vanilla save completes, iterate `SafeHouseManager.getSafehouseList()`, write each SafeHouse to SQLite via `SafeHouseRepository.saveAll()`
- The binary `map_meta.bin` still gets written normally (backwards compatibility) — SQLite is the *additional* authoritative store

### `IsoMetaGridLoadPatch`
- Targets `zombie.iso.IsoMetaGrid`, method `load()`
- `@Advice.OnMethodExit`: after vanilla load completes, if `map_meta.db` exists, read SafeHouses from SQLite and replace the in-memory list via `SafeHouseManager`
- If the DB doesn't exist yet (first run / migration), fall through to the vanilla binary data — the next save will populate the DB

## Phase 4: Wire up the mod

- Update `MapMetaSqliteMod.getClassTransformers()` to return the two patch classes
- Add server-only guard (`StormEnv.isStormServer()`) since `map_meta.bin` is server/SP only — clients get SafeHouse data via packets
- Initialize `SafeHouseDatabase` in `registerEventHandlers()`

## Phase 5: Testing

- Unit test `SafeHouseRepository` against an in-memory SQLite DB (`:memory:`)
- Unit test schema creation and migration logic
- Integration testing: deploy to a test server, verify safehouses survive save/load cycles, verify the `.db` file is created

## Key design decisions

- **Dual-write**: Keep writing `map_meta.bin` normally so the save is backwards-compatible if the mod is removed. SQLite is authoritative when present.
- **Server-only**: Skip all transformer registration on clients (they receive SafeHouse data via network packets).
- **Save directory detection**: Use `ZomboidFileSystem` or `IsoMetaGrid` references to find the correct save directory path at runtime.
- **Transaction safety**: Wrap all SQLite writes in a transaction — this gives us atomic saves that the raw ByteBuffer approach lacks.
- **No extra dependencies**: Use the SQLite JDBC driver already bundled with Project Zomboid.

## Implementation order

1. Phase 1 (decompile SafeHouse) — determines the schema
2. Phase 2 (repository layer) — can be unit tested immediately
3. Phase 3 (transformers) — needs the game JAR on classpath
4. Phase 4 (wiring) — straightforward
5. Phase 5 (testing) — continuous
