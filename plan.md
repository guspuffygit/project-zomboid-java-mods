 ---
  map_meta.bin — Investigation

  What it is

  map_meta.bin is a binary save file that persists the runtime state of the world's meta grid (IsoMetaGrid). It lives in the save directory for each game/server (e.g.
  ~/Zomboid/Saves/<mode>/<savename>/map_meta.bin).

  When it's read/written

  - Loaded by IsoMetaGrid.load() at world load time (IsoMetaGrid.java:1100)
  - Saved by IsoMetaGrid.save() during periodic world saves (IsoMetaGrid.java:1637-1639)
  - Also included in the log zip backup by ZipLogs.java:84,102
  - Can be deleted from the Load Game screen's debug tools (LoadGameScreen.lua:233, LuaManager.java:6156) — the "DeleteMapMetaBin" option
  - Preserved during world conversion — WorldConverter.java explicitly skips it during soft-reset operations (lines 137, 176, 293)

  Binary format

  The file is written as a raw ByteBuffer. The structure is:

  Header (20 bytes)

  ┌────────┬─────────┬──────────────────────────┬──────────────────────────────┐
  │ Offset │  Type   │          Value           │         Description          │
  ├────────┼─────────┼──────────────────────────┼──────────────────────────────┤
  │ 0      │ 4 bytes │ M E T A (77, 69, 84, 65) │ Magic bytes / file signature │
  ├────────┼─────────┼──────────────────────────┼──────────────────────────────┤
  │ 4      │ int     │ 244 (current)            │ World version number         │
  ├────────┼─────────┼──────────────────────────┼──────────────────────────────┤
  │ 8      │ int     │ minX                     │ Grid min X coordinate        │
  ├────────┼─────────┼──────────────────────────┼──────────────────────────────┤
  │ 12     │ int     │ minY                     │ Grid min Y coordinate        │
  ├────────┼─────────┼──────────────────────────┼──────────────────────────────┤
  │ 16     │ int     │ maxX                     │ Grid max X coordinate        │
  ├────────┼─────────┼──────────────────────────┼──────────────────────────────┤
  │ 20     │ int     │ maxY                     │ Grid max Y coordinate        │
  └────────┴─────────┴──────────────────────────┴──────────────────────────────┘

  The world size is derived as (maxX - minX + 1) x (maxY - minY + 1). On load, a mismatch with the current map size is logged as a warning.

  Per-cell data (iterated for every cell in the grid)

  For each cell (x, y) from minX..maxX, minY..maxY:

  Rooms section:

  ┌─────────────────┬───────────────────────────────────────────────────────────────────────────────────────────┐
  │      Type       │                                        Description                                        │
  ├─────────────────┼───────────────────────────────────────────────────────────────────────────────────────────┤
  │ int             │ Number of rooms in this cell                                                              │
  ├─────────────────┼───────────────────────────────────────────────────────────────────────────────────────────┤
  │ Per room:       │                                                                                           │
  ├─────────────────┼───────────────────────────────────────────────────────────────────────────────────────────┤
  │ long (8 bytes)  │ Room metaId (unique identifier)                                                           │
  ├─────────────────┼───────────────────────────────────────────────────────────────────────────────────────────┤
  │ short (2 bytes) │ Bitflags: bit 0 = explored, bit 1 = lights active, bit 2 = done spawn, bit 3 = roof fixed │
  └─────────────────┴───────────────────────────────────────────────────────────────────────────────────────────┘

  Buildings section:

  ┌────────────────┬─────────────────────────────────────────┐
  │      Type      │               Description               │
  ├────────────────┼─────────────────────────────────────────┤
  │ int            │ Number of buildings in this cell        │
  ├────────────────┼─────────────────────────────────────────┤
  │ Per building:  │                                         │
  ├────────────────┼─────────────────────────────────────────┤
  │ long (8 bytes) │ Building metaId                         │
  ├────────────────┼─────────────────────────────────────────┤
  │ byte           │ Alarmed (burglar alarm active)          │
  ├────────────────┼─────────────────────────────────────────┤
  │ int            │ Key ID (which key opens it)             │
  ├────────────────┼─────────────────────────────────────────┤
  │ byte           │ Seen (player has seen the building)     │
  ├────────────────┼─────────────────────────────────────────┤
  │ byte           │ Has been visited                        │
  ├────────────────┼─────────────────────────────────────────┤
  │ int            │ Loot respawn hour (when loot refreshes) │
  ├────────────────┼─────────────────────────────────────────┤
  │ int            │ Alarm decay (version >= 201 only)       │
  └────────────────┴─────────────────────────────────────────┘

  Note: Only non-user-defined rooms/buildings are saved (i.e., map-defined structures, not player-built ones).

  Global sections (after all cells)

  ┌────────────────────┬───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │      Section       │                                                                      Format                                                                       │
  ├────────────────────┼───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ SafeHouses         │ int count, then each SafeHouse.save(buffer)                                                                                                       │
  ├────────────────────┼───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Non-PvP Zones      │ int count, then each NonPvpZone.save(buffer)                                                                                                      │
  ├────────────────────┼───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Factions           │ int count, then each Faction.save(buffer)                                                                                                         │
  ├────────────────────┼───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Designation Zones  │ int count, then each DesignationZone.save(buffer)                                                                                                 │
  ├────────────────────┼───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Stash System       │ On server: int (position pointer for skip), then StashSystem.save(). On client: skipped via position pointer. On SP: StashSystem.save() directly. │
  ├────────────────────┼───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Unique RDS Spawned │ int count, then each string via GameWindow.WriteString() — tracks which randomized story spawns have already occurred                             │
  └────────────────────┴───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘

  What each section tracks

  - Room state: Whether the player has explored a room, whether lights are on, whether zombies/loot have spawned there, whether the roof has been fixed
  - Building state: Burglar alarm status/decay, key assignments, whether the player has seen/visited the building, and loot respawn timers
  - SafeHouses: Player-claimed safe zones (multiplayer)
  - Non-PvP Zones: Areas where PvP is disabled (multiplayer)
  - Factions: Player faction data (multiplayer)
  - Designation Zones: Player-designated zones
  - Stash System: Annotated map / story stash locations and their state (already found, etc.)
  - Unique RDS Spawned: Tracks which randomized story events have already spawned to prevent duplicates

  Key behaviors

  1. Version gating: The worldVersion int (currently 244) gates format changes. For example, alarmDecay is only read if version >= 201.
  2. Server/client split: On multiplayer servers, the stash system section has a position-pointer prefix so clients can skip over it (they don't need stash data).
  3. Resilience: If a room or building metaId in the file doesn't match the current map data, it logs an error but keeps going — the file format is forward-compatible with map changes.
  4. Deletable for repair: The Load Game screen exposes "DeleteMapMetaBin" as a debug option, which resets all room/building/safehouse/faction state to defaults — useful for fixing corrupted saves.

✻ Worked for 1m 13s

❯   4. Deletable for repair: The Load Game screen exposes "DeleteMapMetaBin" as a debug option, which resets all room/building/safehouse/faction state to defaults — useful for fixing corrupted saves.

How would this even be possible? Is there a better way that this data could be stored? Give me some different ideas

● Good question. Let me trace what actually happens when the file is missing.

● Searched for 4 patterns, read 1 file (ctrl+o to expand)

● Here's the full picture:

  How deletion "works" as a repair

  When map_meta.bin is missing, the load() method catches FileNotFoundException at line 1125 and silently does nothing — this.loaded stays false. The key consequence is at line 1379-1383:

  public void Create() {
      if (!this.loaded) {
          this.CreateStep1();  // scans map directories, builds grid from lotpack files
          this.CreateStep2();  // populates rooms/buildings from the raw map data
      }
  }

  The structural data (which rooms exist, which buildings exist, their geometry) comes from the map files on disk (media/maps/*/), not from map_meta.bin. The bin file only overlays mutable runtime state
   onto those structures. So when it's gone, everything resets to Java defaults:

  - RoomDef.explored → false (all rooms unexplored)
  - RoomDef.doneSpawn → false (zombies/loot will re-spawn in rooms)
  - RoomDef.lightsActive → false
  - BuildingDef.alarmed → false
  - BuildingDef.seen → false
  - BuildingDef.hasBeenVisited → false
  - BuildingDef.lootRespawnHour → -1 (default)
  - BuildingDef.alarmDecay → 10000000 (default)
  - All SafeHouses, Factions, NonPvpZones, DesignationZones, StashSystem state → gone

  So it "works" as repair because the world geometry is reconstructed from map files — you just lose all player-facing progress tracking and multiplayer social structures.

  ---
  Ideas for better storage

  1. Per-cell files instead of one monolith

  Right now a single corrupted byte can take out the entire file — every room, every building, every faction, every safehouse. The game already does per-cell saving for other data (metacell_%d_%d.bin).
  Room and building state could be split the same way: map_meta_%d_%d.bin per cell. Corruption would be isolated to one cell instead of the entire world. The global sections (safehouses, factions,
  zones, stashes) could go into their own small files.

  2. Separate files by data domain

  The file currently mixes very different concerns:
  - Map exploration state (rooms explored, buildings visited) — per-player in nature
  - World simulation state (loot respawn timers, alarm decay) — global/server
  - Social/governance data (safehouses, factions, non-PvP zones) — multiplayer admin
  - Story progression (stash system, unique RDS spawned) — campaign tracking

  These have different update frequencies, different ownership, and different corruption blast radii. Splitting them means you could delete just faction data without wiping room exploration, or reset
  loot timers without destroying safehouses. The game already does this partially — map_zone.bin and map_animals.bin are separate — but safehouses/factions are still jammed into map_meta.bin.

  3. Checksums / section headers

  The current format has zero integrity checking. A truncated write (power loss, crash mid-save) silently corrupts everything after the truncation point. Adding a CRC32 per section or per cell block
  would let the loader skip corrupted sections and recover the rest. Even just a section-length prefix before each block would allow skipping unreadable sections rather than failing the entire load.

  4. Human-readable format for social/admin data

  Safehouses, factions, non-PvP zones, and designation zones are admin-managed data that server operators frequently want to inspect or edit. Storing these as JSON or a simple text format (instead of
  raw binary) would let admins fix problems without hex editors or third-party tools. The performance cost is negligible — there are at most a few hundred of these entries.

  5. Per-player exploration state

  Room explored and building seen/hasBeenVisited are conceptually per-player, but stored globally. In multiplayer, one player exploring a room marks it explored for everyone. Moving exploration state to
   per-player files would allow individual player resets and more accurate per-player fog-of-war, and would shrink the global file significantly.

  6. Write-ahead / double-buffering

  The game could write to map_meta.bin.tmp, then atomically rename over map_meta.bin on success. If the tmp file exists at load time, it means the last save was interrupted — fall back to the previous
  good copy. This is a standard crash-safe write pattern and would eliminate the most common corruption scenario (crash during save).

  7. SQLite

  A single SQLite database (or one per save) could replace multiple .bin files with indexed, transactional, queryable storage. Room/building state becomes rows in a table, safehouses become another
  table, etc. You get atomic writes, partial corruption recovery, and the ability to query state without loading everything into memory. The game already bundles SQLite for players.db.

  Server vs Client: map_meta.bin is NOT the same

  The file is server/singleplayer only. Clients never read or write it.

  Evidence

  Save side — IsoCell.java:4260:
  if (!GameClient.client) {
      IsoWorld.instance.metaGrid.save();  // only server/SP saves map_meta.bin
  }

  Load side — IsoWorld.java:1967-1978:
  if (!GameClient.client) {
      this.metaGrid.load();           // only server/SP loads map_meta.bin
      this.metaGrid.load("map_zone.bin", ...);
      // etc.
  } else {
      // client skips all of this
  }

  How the client gets this data instead

  The server sends it over the network in pieces:

  ┌────────────────────────────────────────────────────────────────────┬────────────────────────────────────┬──────────────────────────────────────────────────────────────────┐
  │                                Data                                │             Mechanism              │                               When                               │
  ├────────────────────────────────────────────────────────────────────┼────────────────────────────────────┼──────────────────────────────────────────────────────────────────┤
  │ SafeHouses, Factions, NonPvpZones, DesignationZones                │ MetaDataPacket (connection packet) │ Sent to client at login/connect time                             │
  ├────────────────────────────────────────────────────────────────────┼────────────────────────────────────┼──────────────────────────────────────────────────────────────────┤
  │ SafeHouse changes                                                  │ SafehouseSyncPacket                │ Sent on individual changes (members, owner, removal, etc.)       │
  ├────────────────────────────────────────────────────────────────────┼────────────────────────────────────┼──────────────────────────────────────────────────────────────────┤
  │ NonPvpZone changes                                                 │ SyncNonPvpZonePacket               │ Sent when zones are created/removed                              │
  ├────────────────────────────────────────────────────────────────────┼────────────────────────────────────┼──────────────────────────────────────────────────────────────────┤
  │ Room lights                                                        │ MetaGridPacket                     │ Sent when a light switch is toggled                              │
  ├────────────────────────────────────────────────────────────────────┼────────────────────────────────────┼──────────────────────────────────────────────────────────────────┤
  │ Building alarms                                                    │ AddAlarm packet                    │ Sent when an alarm is triggered                                  │
  ├────────────────────────────────────────────────────────────────────┼────────────────────────────────────┼──────────────────────────────────────────────────────────────────┤
  │ Room explored / doneSpawn / building visited / loot respawn timers │ Not synced to clients              │ Server-only state — clients discover rooms through gameplay      │
  ├────────────────────────────────────────────────────────────────────┼────────────────────────────────────┼──────────────────────────────────────────────────────────────────┤
  │ StashSystem                                                        │ Skipped on client                  │ Load path uses position pointer to jump over stash data entirely │
  └────────────────────────────────────────────────────────────────────┴────────────────────────────────────┴──────────────────────────────────────────────────────────────────┘

  Key takeaway

  The file is authoritative only on the server. In multiplayer, the server is the single source of truth for all meta grid state. It sends the social/governance data (safehouses, factions, zones) to
  clients via packets at connect time, and sends incremental updates for things like light switches and alarms. But bulk simulation state — room exploration, loot respawn timers, spawn tracking — stays
  server-side and is never transmitted to clients at all.

