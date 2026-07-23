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
  - **Read literature** — `death_read_literature`, one row per `literatureTitle` from
    `IsoGameCharacter.getReadLiterature()` (skill books + recipe magazines). PZ stores its own
    constructed "literature title" string per item rather than the item full-type, so that's what
    we persist.
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
├── SurvivorSkillObeliskRepository.java  # SQL inserts (no business logic)
└── patch/                               # Server-only Storm bytecode patches (obelisk protection)
```

## Obelisk indestructibility

Placed obelisk sprites are `solid`, so `ISMoveableSpriteProps:placeMoveableInternal` (which the
brush tool uses) creates them as `IsoThumpable` — in vanilla that makes them destroyable by zombie
thumping, player melee, and the sledgehammer/pickup/disassemble actions (the server performs
removals with no per-object validation). The only allowed removal is an admin whose role has
`Capability.UseBrushToolManager` using the brush tool's "Destroy tile" option.

**The primary destruction path in B42 is not a packet.** Sledgehammer destroy and furniture
pickup/disassemble are synced timed actions: the client streams the action to the server
(`NetTimedAction`) and the *server* runs the action's `complete()`, which removes the object with
direct Java calls (`transmitRemoveItemFromSquare`, `pickUpMoveableViaCursor`,
`scrapObjectViaCursor`) — no removal packet is ever processed. That path is gated by
`media/lua/server/SurvivorSkillObeliskDestroyGuard.lua`, which overrides
`ISDestroyStuffAction:complete` and `ISMoveablesAction:complete` (pickup/scrap) server-side and
consults `SurvivorSkillObeliskApi` (exposed to server Lua by
`SurvivorSkillObeliskApiLuaExposerHandler`) for the role policy, resync, and curse.

Three server-only Storm patches back this up against forged packets and the legacy client path:

- **`SledgehammerDestroyPacketPatch`** — skips `processServer` for obelisk targets unless the
  sender has the brush-tool capability. Brush-tool "Destroy tile" sends this same packet, so the
  sender's *role* is what separates admin deletes from player sledgehammers. Blocking at this
  layer also suppresses the packet's rebroadcast loop (which runs even when the inner remove is
  skipped and would ghost the obelisk on every nearby client).
- **`RemoveItemFromSquarePacketPatch`** — same gate on the generic removal packet.
- **`IsoThumpableGetThumpableForPatch`** — returns null from `getThumpableFor` for obelisks, so
  zombies path around them instead of thumping and player `WeaponHit` no-ops server-side.

Blocked attempts are logged and the sender is resynced with an `AddItemToMap` packet so the
obelisk doesn't linger as a client-side ghost. `ObeliskProtection` holds the packet-side policy;
`SurvivorSkillObeliskApi` holds the action-side policy (both check the same capability). The
tiledefs deliberately carry no `CanScrap` property so disassemble is never offered. Known
residual: fire is not blocked.

### The curse

The sledgehammer destroy option is deliberately left visible. When a non-admin completes the
destroy action, the server blocks the removal as above and — if the `SkillObelisk.CurseOnSledgehammer`
sandbox option is on (default) — `ObeliskCurseHandler` kills the character **server-side** on the
next main-loop tick (`IsoPlayer.Kill` + `die()`), announces
`<username> has been smited by the mighty Obelisk` in server chat (`sendMessageToServerChat`,
main-thread only — the ChatBase/UdpConnection locks invert off it), and sends a targeted
`obeliskCurse` command so `SurvivorSkillObeliskProtection.lua` can play the obelisk sound on the
attacker's machine.

The kill runs on the server, not the client. B42 player health is server-authoritative and the
persisted `networkPlayers.isDead` flag is written from the server's `IsoPlayer`, so the earlier
client-side `player:Kill(player)` only played the death screen: the server character stayed alive,
"create new character" hung on a black screen, and rejoining restored the old character. The
server-side kill runs `DoDeath` (vanilla death log, "is dead" announcement, `OnCharacterDeath` —
which is what drives this mod's own death snapshot), builds the corpse, persists the dead flag via
`removeSaveFile`, and broadcasts `PlayerDeath` so the owning client plays out the death normally.
Cheat clients can neither destroy the obelisk nor decline the death. With the option off, the
attempt is silently blocked and resynced like every other removal path.

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

| column           | type    | notes                                   |
|------------------|---------|-----------------------------------------|
| id               | INTEGER | primary key                             |
| death_id         | INTEGER | not null; FK → `deaths(id)`             |
| literature_title | TEXT    | not null; PZ's `literatureTitle` key (e.g. `BookCarpentry1_translation_42`) |

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

## Art pipeline

The binary `.tiles` and `.pack` files under `media/tiledefinitions/` and
`media/texturepacks/` are **generated** from sources under `art/` and `tiles/`
by [`pztool`](https://github.com/guspuffygit/project-zomboid-tile-cli).
Install `pztool` on `PATH` — a prebuilt binary lives at
`../../project-zomboid-tile-cli/dist/pztool-<os>-<arch>`.

Layout:
```
art/survivor_skill_obelisk.png        # 8x8 tilesheet, 128x256 per tile
tiles/survivor_skill_obelisk.tiles.txt # human-editable tile properties
media/<name>.tiles                     # GENERATED — PZ loads .tiles from media/<name>.tiles
                                       #   per mod.info's `tiledef=<name> N` line; NOT from
                                       #   media/tiledefinitions/. Do not hand-edit.
media/texturepacks/<name>.pack         # GENERATED (do not hand-edit)
```

### Add a new obelisk

1. Paint the new tile(s) onto `art/survivor_skill_obelisk.png` — four cells
   (N/E/S/W). The 4 stub obelisks currently occupy grid positions `(2,2)`,
   `(3,2)`, `(6,3)`, `(7,3)`; drop new ones into any empty cell.
2. Append tile-property blocks to `tiles/survivor_skill_obelisk.tiles.txt`.
   `xy = <col>,<row>` picks the tilesheet cell; the sprite name PZ ends up
   with is `survivor_skill_obelisk_<row * 8 + col>` (this is what `CustomItem`
   and `WorldObjectSprite` reference).
3. Add matching `item` definitions to `media/scripts/SurvivorSkillObelisk.txt`
   pointing at those sprites.
4. Rebuild:
   ```bash
   ./gradlew :survivor-skill-obelisk:packageAssets
   ```
   `deployMod` depends on `packageAssets`, so a full deploy also rebuilds.

Fully-transparent grid cells get dropped by the packer — the sprite must have
non-transparent pixels to end up in the atlas.

## Tests

`SurvivorSkillObeliskDatabaseTest` — schema bootstrap (all tables exist) and the insert paths for
the death row plus every child table (skills, recipes, read literature, print media, watched
media), against a real SQLite file in a JUnit `@TempDir`.
