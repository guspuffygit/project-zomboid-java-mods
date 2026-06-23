# Survivor Skill Obelisk

A Storm mod for Project Zomboid (Build 42). On a dedicated server it snapshots a player's
progression to a SQLite database when they die — the seed for an in-world "obelisk" that will
surface that history later.

Maven group: `com.sentientsimulations.projectzomboid`.
Requires: [Storm](https://steamcommunity.com/sharedfiles/filedetails/?id=3670772371) mod loader.

## What it does (so far)

- Subscribes to Storm's `OnCharacterDeathEvent` (server-side only), mirroring the extra-logging
  mod's death handler.
- On a player death, opens/creates the SQLite DB and writes a `deaths` row (identity + position +
  hours survived + zombie kills) plus one `death_skills` row per non-zero perk (level and XP).

Journals read and VHS watched are the next things to capture — schema/extraction TBD once the
source data on `IsoPlayer` is mapped out.

## Architecture

```
src/main/java/com/sentientsimulations/projectzomboid/survivorskillobelisk/
├── SurvivorSkillObeliskMod.java         # Storm entry point; subscribes to death event (server only)
├── DeathEventHandler.java               # Extracts player data, resolves DB path, persists snapshot
├── SurvivorSkillObeliskDatabase.java    # SQLite connection + schema bootstrap (per-call connection)
└── SurvivorSkillObeliskRepository.java  # SQL inserts (no business logic)
```

Each death opens a fresh `SurvivorSkillObeliskDatabase` connection, matching the per-call pattern
used by survivor-leaderboard so the game thread never contends on a shared connection.

## Database

SQLite file: `<save>/survivor_skill_obelisk.db` (resolved via
`ZomboidFileSystem.getFileInCurrentSave`). WAL mode is enabled at startup.

### `deaths`

| column         | type    | notes                          |
|----------------|---------|--------------------------------|
| id             | INTEGER | primary key                    |
| ts             | INTEGER | not null; unix ms at death     |
| username       | TEXT    | character username             |
| steam_id       | INTEGER | account steam id               |
| forename       | TEXT    | character forename             |
| surname        | TEXT    | character surname              |
| hours_survived | REAL    | in-game hours survived         |
| zombie_kills   | INTEGER | lifetime zombie kills          |
| x, y, z        | REAL    | death position                 |

### `death_skills`

| column   | type    | notes                                   |
|----------|---------|-----------------------------------------|
| id       | INTEGER | primary key                             |
| death_id | INTEGER | not null; FK → `deaths(id)`             |
| perk     | TEXT    | not null; perk name                     |
| level    | INTEGER | not null; perk level at death           |
| xp       | REAL    | not null; accumulated XP for the perk   |

Index: `idx_death_skills_death` on `death_skills(death_id)`. Only perks with a non-zero level or XP
are written.

## Building

```bash
./gradlew :survivor-skill-obelisk:spotlessApply :survivor-skill-obelisk:test
```

## Tests

`SurvivorSkillObeliskDatabaseTest` — schema bootstrap (tables exist) and the death + skills insert
path, against a real SQLite file in a JUnit `@TempDir`.
