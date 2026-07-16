--
-- SurvivorSkillObeliskSongSync.lua
-- Mirrors the Lifestyles mod's per-instrument learned-song tables from the
-- client to the server-side player modData.
--
-- Lifestyles learns songs in client-only Lua, but B42 player persistence is
-- server-authoritative, and Lifestyles' own client->server modData mirror
-- (LS:SavePlayerData) only runs once per in-game day. Songs learned since the
-- last mirror don't exist on the server, so the obelisk death snapshot never
-- sees them. This script watches the track lists and pushes them to
-- SyncLearnedSongsHandler within a game minute of any change.
--

local MODULE = "SurvivorSkillObelisk"
local SYNC_COMMAND = "syncLearnedSongs"

-- Must match DeathEventHandler.LIFESTYLES_INSTRUMENT_KEYS values.
local INSTRUMENT_KEYS = {
    "TrumpetLearnedTracks",
    "GuitarALearnedTracks",
    "BanjoLearnedTracks",
    "KeytarLearnedTracks",
    "SaxophoneLearnedTracks",
    "GuitarEBLearnedTracks",
    "GuitarELearnedTracks",
    "FluteLearnedTracks",
    "PianoLearnedTracks",
    "ViolinLearnedTracks",
    "HarmonicaLearnedTracks",
}

-- State lives on a global so a hot-reload of this file keeps the signature and
-- doesn't stack a second set of event handlers.
SurvivorSkillObeliskSongSync = SurvivorSkillObeliskSongSync or {}
local SongSync = SurvivorSkillObeliskSongSync

-- Per-instrument entry counts are enough to detect change: Lifestyles only ever
-- appends to these lists (or replaces them wholesale on character reset, which
-- also changes the counts).
local function computeSignature(modData)
    local parts = {}
    for i = 1, #INSTRUMENT_KEYS do
        local list = modData[INSTRUMENT_KEYS[i]]
        parts[i] = list and #list or -1
    end
    return table.concat(parts, ",")
end

local function buildTracksPayload(modData)
    local tracks = {}
    local any = false
    for i = 1, #INSTRUMENT_KEYS do
        local key = INSTRUMENT_KEYS[i]
        local list = modData[key]
        if list ~= nil then
            tracks[key] = list
            any = true
        end
    end
    return tracks, any
end

function SongSync.sync()
    if not isClient() then
        return
    end
    local player = getPlayer()
    if player == nil or player:isDead() then
        return
    end
    local modData = player:getModData()
    if modData == nil then
        return
    end
    local signature = computeSignature(modData)
    if signature == SongSync.lastSignature then
        return
    end
    local tracks, any = buildTracksPayload(modData)
    if any then
        sendClientCommand(player, MODULE, SYNC_COMMAND, { tracks = tracks })
    end
    SongSync.lastSignature = signature
end

if not SongSync.registered then
    SongSync.registered = true
    Events.EveryOneMinute.Add(function()
        SongSync.sync()
    end)
    -- Push afresh after every world join: the server may have restarted (or its
    -- mirror rolled back) while this client session kept its last signature.
    Events.OnGameStart.Add(function()
        SongSync.lastSignature = nil
    end)
end
