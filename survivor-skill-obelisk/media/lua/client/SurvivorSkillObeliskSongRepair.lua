--
-- SurvivorSkillObeliskSongRepair.lua
-- Resolves Lifestyles' canonical track records and repairs learned-song
-- entries that obelisk recoveries wrote with missing or defaulted fields.
--
-- Death rows saved before the level/length/isaddon columns existed restore as
-- {name, sound} only, and Lifestyles' context menus do arithmetic on every
-- learned entry (v.length * 48, v.level <= playerlevel). A single nil field
-- aborts the whole menu build with "__mul not defined", leaving only the
-- sections added before the bad entry (typically just Beginner) visible. The
-- repair pass runs once per game start and re-canonicalizes every entry, so
-- entries the server restored with placeholder numerics also converge to the
-- real track data; the next SongSync push then mirrors the healed lists back
-- to the server.
--

SurvivorSkillObeliskSongRepair = SurvivorSkillObeliskSongRepair or {}
local SongRepair = SurvivorSkillObeliskSongRepair

-- length feeds a timed-action duration (Lifestyles multiplies it by 48); any
-- positive number keeps the menus alive when a track can't be resolved.
SongRepair.FALLBACK_LENGTH = 60

-- Keys must match DeathEventHandler.LIFESTYLES_INSTRUMENT_KEYS values. Module
-- paths are the ones Lifestyles' own context menus require: Piano lives under
-- Instruments/Tracks, everything else under TimedActions.
local TRACK_MODULES = {
    TrumpetLearnedTracks = "TimedActions/PlayTrumpetTracks",
    GuitarALearnedTracks = "TimedActions/PlayGuitarAcousticTracks",
    BanjoLearnedTracks = "TimedActions/PlayBanjoTracks",
    KeytarLearnedTracks = "TimedActions/PlayKeytarTracks",
    SaxophoneLearnedTracks = "TimedActions/PlaySaxophoneTracks",
    GuitarEBLearnedTracks = "TimedActions/PlayGuitarElectricBassTracks",
    GuitarELearnedTracks = "TimedActions/PlayGuitarElectricTracks",
    FluteLearnedTracks = "TimedActions/PlayFluteTracks",
    PianoLearnedTracks = "Instruments/Tracks/PlayPianoTracks",
    ViolinLearnedTracks = "TimedActions/PlayViolinTracks",
    HarmonicaLearnedTracks = "TimedActions/PlayHarmonicaTracks",
}

-- false = tried and failed (Lifestyles absent); nil = not tried yet.
local trackCache = {}

local function getTracks(modDataKey)
    local cached = trackCache[modDataKey]
    if cached ~= nil then
        if cached == false then
            return nil
        end
        return cached
    end
    local ok, tracks = pcall(require, TRACK_MODULES[modDataKey])
    if not ok or type(tracks) ~= "table" then
        trackCache[modDataKey] = false
        return nil
    end
    trackCache[modDataKey] = tracks
    return tracks
end

-- Returns Lifestyles' canonical record for a learned song, or nil if the mod
-- (or the track) is gone. isaddon == 2 entries are practice-only variants that
-- share names with real tracks and are filtered out of every menu, so never
-- resolve to one. When the same name has several real variants, an exact sound
-- match wins over the first name match.
function SongRepair.resolveTrack(modDataKey, name, sound)
    if name == nil then
        return nil
    end
    local tracks = getTracks(modDataKey)
    if tracks == nil then
        return nil
    end
    local byName = nil
    for i = 1, #tracks do
        local rec = tracks[i]
        if type(rec) == "table" and rec.name == name and rec.isaddon ~= 2 then
            if sound == nil or rec.sound == sound then
                return rec
            end
            byName = byName or rec
        end
    end
    return byName
end

local function repairEntry(modDataKey, entry)
    if type(entry) ~= "table" or entry.name == nil then
        return
    end
    local rec = SongRepair.resolveTrack(modDataKey, entry.name, entry.sound)
    if rec then
        if rec.sound ~= nil then
            entry.sound = rec.sound
        end
        if type(rec.level) == "number" then
            entry.level = rec.level
        end
        if type(rec.length) == "number" then
            entry.length = rec.length
        end
        if type(rec.isaddon) == "number" then
            entry.isaddon = rec.isaddon
        end
    end
    -- Track no longer exists in Lifestyles: inert defaults beat nil arithmetic.
    if type(entry.level) ~= "number" then
        entry.level = 1
    end
    if type(entry.length) ~= "number" then
        entry.length = SongRepair.FALLBACK_LENGTH
    end
    if type(entry.isaddon) ~= "number" then
        entry.isaddon = 0
    end
end

function SongRepair.repairPlayer(player)
    if player == nil then
        return
    end
    local modData = player:getModData()
    if modData == nil then
        return
    end
    for key in pairs(TRACK_MODULES) do
        local list = modData[key]
        if type(list) == "table" then
            for i = 1, #list do
                repairEntry(key, list[i])
            end
        end
    end
end

if not SongRepair.registered then
    SongRepair.registered = true
    Events.OnGameStart.Add(function()
        SongRepair.repairPlayer(getPlayer())
    end)
end
