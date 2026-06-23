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
  hours survived + zombie kills), then child rows capturing the character's progression:
  - **Skills** — one `death_skills` row per non-zero perk (level + XP).
  - **Known recipes** — `death_recipes`, from `IsoPlayer.getKnownRecipes()` (mostly taught by skill
    magazines).
  - **Read literature** — `death_read_literature`, from `getReadLiterature()` with pages read via
    `getAlreadyReadPages(fullType)` (skill books + recipe magazines).
  - **Read print media** — `death_read_print_media`, from `getReadPrintMedia()` (newspapers /
    magazines).
  - **Watched recorded media** — `death_watched_media`, the VHS tapes / CDs the character has seen.
    PZ tracks consumption per media *line* on the character (`knownMediaLines`, no public getter),
    so the handler iterates the global `RecordedMedia` catalog and tests each tape's lines against
    the player, recording lines-watched / total and a fully-watched flag.

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

### `death_recipes`

| column      | type    | notes                          |
|-------------|---------|--------------------------------|
| id          | INTEGER | primary key                    |
| death_id    | INTEGER | not null; FK → `deaths(id)`    |
| recipe_name | TEXT    | not null; recipe name          |

### `death_read_literature`

| column     | type    | notes                                   |
|------------|---------|-----------------------------------------|
| id         | INTEGER | primary key                             |
| death_id   | INTEGER | not null; FK → `deaths(id)`             |
| full_type  | TEXT    | not null; item full-type, e.g. `Base.BookCarpentry1` |
| pages_read | INTEGER | not null; pages read for that full-type |

### `death_read_print_media`

| column   | type    | notes                       |
|----------|---------|-----------------------------|
| id       | INTEGER | primary key                 |
| death_id | INTEGER | not null; FK → `deaths(id)` |
| media_id | TEXT    | not null; print-media id    |

### `death_watched_media`

| column        | type    | notes                                      |
|---------------|---------|--------------------------------------------|
| id            | INTEGER | primary key                                |
| death_id      | INTEGER | not null; FK → `deaths(id)`                |
| media_id      | TEXT    | not null; `MediaData.getId()`              |
| media_index   | INTEGER | `MediaData.getIndex()`                     |
| category      | TEXT    | e.g. `Home-VHS`, `Retail-VHS`, `CDs`       |
| media_type    | INTEGER | 0 = CD, 1 = VHS                            |
| title         | TEXT    | translated or EN title                     |
| lines_watched | INTEGER | not null; known lines for this player      |
| line_count    | INTEGER | not null; total lines in the tape          |
| fully_watched | INTEGER | not null; 0/1 (`RecordedMedia.hasListenedToAll`) |

Each child table has an index on `death_id`. Only media with at least one watched line are written.

## Building

```bash
./gradlew :survivor-skill-obelisk:spotlessApply :survivor-skill-obelisk:test
```

## Tests

`SurvivorSkillObeliskDatabaseTest` — schema bootstrap (all tables exist) and the insert paths for
the death row plus every child table (skills, recipes, read literature, print media, watched
media), against a real SQLite file in a JUnit `@TempDir`.
