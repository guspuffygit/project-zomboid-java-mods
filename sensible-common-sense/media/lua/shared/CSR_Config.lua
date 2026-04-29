CSR_Config = {}

CSR_Config.BASE_PRY_TIME = 300
CSR_Config.BASE_LOCKPICK_TIME = 180
CSR_Config.BASE_IMPROVISED_HOTWIRE_TIME = 220
CSR_Config.BASE_UN_HOTWIRE_TIME = 200
CSR_Config.CORPSE_IGNITE_TIME = 110
CSR_Config.BARRICADE_TIME = 140
CSR_Config.MAKE_BANDAGE_TIME = 90
CSR_Config.BASE_NOISE_RADIUS = 10
CSR_Config.TOOL_DAMAGE_ON_FAIL = 2
CSR_Config.INJURY_DAMAGE = 5
CSR_Config.OPEN_CAN_TIME = 100
CSR_Config.BULK_OPEN_CAN_TIME = 120
CSR_Config.BULK_OPEN_CAN_TIME_PER_ITEM = 35
CSR_Config.OPEN_JAR_TIME = 90
CSR_Config.BULK_OPEN_JAR_TIME = 110
CSR_Config.BULK_OPEN_JAR_TIME_PER_ITEM = 30
CSR_Config.REPAIR_TIME = 200
CSR_Config.CLOTH_TEAR_TIME = 100
CSR_Config.BULK_CLOTH_TEAR_TIME_PER_ITEM = 45
CSR_Config.LIGHTER_REFILL_TIME = 90
CSR_Config.BATTERY_SWAP_TIME = 120
CSR_Config.PLAYER_MAP_REQUEST_TICKS = 600
CSR_Config.PLAYER_MAP_SERVER_MIN_TICKS = 300
CSR_Config.PLAYER_MAP_STALE_TICKS = 720
CSR_Config.PLAYER_MAP_CACHE_TTL_MS = 15000
CSR_Config.PLAYER_MAP_MARKER_RADIUS = 3
CSR_Config.PLAYER_MAP_MARKER_SIZE = 6
CSR_Config.PLAYER_MAP_DRAW_NAMES = true
CSR_Config.ZOMBIE_DENSITY_REQUEST_TICKS = 500          -- Manual-refresh fallback only (server now pushes).
CSR_Config.ZOMBIE_DENSITY_SERVER_MIN_TICKS = 150       -- Anti-spam window for legacy on-demand requests.
CSR_Config.ZOMBIE_DENSITY_STALE_TICKS = 900            -- Client clears stale data after ~14.4 s.
CSR_Config.ZOMBIE_DENSITY_CACHE_TTL_MS = 25000         -- Per-player cell cache lifetime.
CSR_Config.ZOMBIE_DENSITY_CELL_SIZE = 100
CSR_Config.ZOMBIE_DENSITY_CELL_RADIUS = 2              -- Default 5x5 grid (overridden by difficulty configs below).
-- Server push cadence: one zombie scan per N ticks, broadcast to every player with overlay enabled.
-- 25 ticks ~ 400 ms; this is the single most impactful perf knob.
CSR_Config.ZOMBIE_DENSITY_SERVER_PUSH_TICKS = 25
-- Difficulty-scaled grid radius: smaller grids on harder zpop / huge worlds.
CSR_Config.ZOMBIE_DENSITY_CELL_RADIUS_EASY = 2         -- 5x5 grid
CSR_Config.ZOMBIE_DENSITY_CELL_RADIUS_NORMAL = 2       -- 5x5 grid
CSR_Config.ZOMBIE_DENSITY_CELL_RADIUS_HARD = 1         -- 3x3 grid
CSR_Config.ZOMBIE_DENSITY_CELL_RADIUS_INSANE = 1       -- 3x3 grid (high zombie counts -> tighter scan)
-- Nearby Density HUD (small movable widget that replaces the minimap heatmap).
CSR_Config.ZOMBIE_DENSITY_HUD_RADIUS = 30              -- Tile radius for "nearby" count.
CSR_Config.ZOMBIE_DENSITY_HUD_REFRESH_TICKS = 30       -- ~480 ms refresh.
CSR_Config.ZOMBIE_DENSITY_HUD_DEFAULT_X = 8
CSR_Config.ZOMBIE_DENSITY_HUD_DEFAULT_Y = 240
CSR_Config.REQUEST_DEDUPE_WINDOW_MS = 2500
CSR_Config.REQUEST_TIMEOUT_MS = 5000
CSR_Config.MAX_WORLD_INTERACT_DISTANCE = 2
CSR_Config.MAX_VEHICLE_INTERACT_DISTANCE = 3
CSR_Config.BASE_BOLT_CUT_TIME = 250
CSR_Config.BOLT_CUT_NOISE_RADIUS = 12
CSR_Config.OPEN_AMMO_BOX_TIME = 60
CSR_Config.BULK_OPEN_AMMO_BOX_TIME_PER_ITEM = 30
CSR_Config.PACK_AMMO_BOX_TIME = 90
CSR_Config.BULK_PACK_AMMO_BOX_TIME_PER_ITEM = 40
CSR_Config.STAPLE_WOUND_BASE_TIME = 100
CSR_Config.STAPLE_WOUND_PAIN = 30
CSR_Config.STAPLE_WOUND_INFECTION_CHANCE = 3

return CSR_Config
