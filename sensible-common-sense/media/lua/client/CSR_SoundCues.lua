
require "CSR_FeatureFlags"
require "CSR_Theme"

CSR_SoundCues = {
    panel = nil,
    cues = {},
    lastEventByKey = {},
}

local MODDATA_PLAYER = "CSRSoundCuePlayers"
local MODDATA_ZOMBIE = "CSRSoundCueZombies"
local MODDATA_OTHER = "CSRSoundCueOthers"

local MAX_VISIBLE = 4
local BASE_LIFETIME_MS = 1200
local PLAYER_SOUND_COOLDOWN_MS = 700
local GLOBAL_SOUND_COOLDOWN_MS = 120
local MIN_IMPORTANCE = 2.5
local RING_RADIUS = 96

local TYPE_META = {
    ZOMBIES = { label = "Z", accent = "accentGreen" },
    VEHICLES = { label = "V", accent = "accentBlue" },
    ALARMS = { label = "!", accent = "accentRed" },
    PLAYERS = { label = "P", accent = "accentViolet" },
    DEVICES = { label = "D", accent = "accentAmber" },
    OTHER = { label = "?", accent = "accentSlate" },
}

local lastGlobalSoundAt = 0

local function nowMs()
    return getTimestampMs and getTimestampMs() or os.time() * 1000
end

local function getPlayerSafe()
    return getPlayer and getPlayer() or nil
end

local function getSoundModData()
    local player = getPlayerSafe()
    local modData = player and player.getModData and player:getModData() or nil
    if not modData then
        return nil
    end

    if modData[MODDATA_PLAYER] == nil then
        modData[MODDATA_PLAYER] = true
    end
    if modData[MODDATA_ZOMBIE] == nil then
        modData[MODDATA_ZOMBIE] = true
    end
    if modData[MODDATA_OTHER] == nil then
        modData[MODDATA_OTHER] = true
    end

    return modData
end

function CSR_SoundCues.isPlayerSourceEnabled()
    local modData = getSoundModData()
    return modData == nil or modData[MODDATA_PLAYER] ~= false
end

function CSR_SoundCues.isZombieSourceEnabled()
    local modData = getSoundModData()
    return modData == nil or modData[MODDATA_ZOMBIE] ~= false
end

function CSR_SoundCues.isOtherSourceEnabled()
    local modData = getSoundModData()
    return modData == nil or modData[MODDATA_OTHER] ~= false
end

function CSR_SoundCues.togglePlayerSource()
    local modData = getSoundModData()
    if modData then
        modData[MODDATA_PLAYER] = not CSR_SoundCues.isPlayerSourceEnabled()
    end
end

function CSR_SoundCues.toggleZombieSource()
    local modData = getSoundModData()
    if modData then
        modData[MODDATA_ZOMBIE] = not CSR_SoundCues.isZombieSourceEnabled()
    end
end

function CSR_SoundCues.toggleOtherSource()
    local modData = getSoundModData()
    if modData then
        modData[MODDATA_OTHER] = not CSR_SoundCues.isOtherSourceEnabled()
    end
end

local function isPlayerInSourceVehicle(player, objsource)
    if not player or not objsource or not instanceof or not instanceof(objsource, "BaseVehicle") then
        return false
    end

    if objsource:getDriver() == player then
        return true
    end

    for seat = 1, 8 do
        if objsource:getCharacter(seat) == player then
            return true
        end
    end

    return false
end

local function classifySource(objsource)
    local sourceText = tostring(objsource or "")
    if string.find(sourceText, "IsoZombie", 1, true) then
        return "ZOMBIES"
    end
    if string.find(sourceText, "BaseVehicle", 1, true) then
        return "VEHICLES"
    end
    if string.find(sourceText, "IsoPlayer", 1, true) then
        return "PLAYERS"
    end
    if string.find(string.lower(sourceText), "alarm", 1, true) then
        return "ALARMS"
    end
    if string.find(sourceText, "IsoRadio", 1, true) or string.find(sourceText, "IsoTelevision", 1, true) or string.find(sourceText, "IsoGenerator", 1, true) then
        return "DEVICES"
    end
    return "OTHER"
end

local function adjustedRadius(player, radius)
    local result = radius or 0
    if player:hasTrait(CharacterTrait.DEAF) then
        return 0
    end
    if player:hasTrait(CharacterTrait.KEEN_HEARING) then
        result = result * 1.15
    elseif player:hasTrait(CharacterTrait.HARD_OF_HEARING) then
        result = result * 0.80
    end
    return result
end

local function shouldIgnore(player, objsource)
    if not objsource then
        return false
    end

    if objsource == player then
        return true
    end

    if isPlayerInSourceVehicle(player, objsource) then
        return true
    end

    return false
end

local function cueKey(objsource, x, y, cueType)
    if objsource then
        return tostring(objsource)
    end
    return table.concat({ cueType or "OTHER", math.floor(x or 0), math.floor(y or 0) }, ":")
end

local function computeImportance(distance, radius, volume, cueType)
    local radiusValue = tonumber(radius) or 0
    local volumeValue = tonumber(volume) or 0
    local strength = math.max(0, radiusValue - distance) + (volumeValue * 0.35)
    if cueType == "ALARMS" then
        strength = strength + 6
    elseif cueType == "ZOMBIES" then
        strength = strength + 2
    end
    return strength
end

local function refreshCuePosition(cue)
    if not cue then return 0, 0, 0 end

    local src = cue.objsource
    if src then
        -- Only track position on known safe IsoMovingObject subclasses
        if instanceof(src, "IsoZombie") or instanceof(src, "IsoPlayer") or instanceof(src, "BaseVehicle") then
            local cx = src:getX()
            local cy = src:getY()
            local cz = src:getZ() or cue.z or 0
            if cx then return cx, cy, cz end
        end
        -- Clear stale/untrackable reference
        cue.objsource = nil
    end

    return cue.x or 0, cue.y or 0, cue.z or 0
end

local function sortAndTrim()
    table.sort(CSR_SoundCues.cues, function(a, b)
        if a.importance == b.importance then
            return a.createdAt > b.createdAt
        end
        return a.importance > b.importance
    end)

    while #CSR_SoundCues.cues > MAX_VISIBLE do
        table.remove(CSR_SoundCues.cues)
    end
end

local function addOrUpdateCue(data)
    local key = data.key
    for i = 1, #CSR_SoundCues.cues do
        local cue = CSR_SoundCues.cues[i]
        if cue.key == key then
            cue.x = data.x
            cue.y = data.y
            cue.z = data.z
            cue.distance = data.distance
            cue.importance = math.max(cue.importance, data.importance)
            cue.createdAt = data.createdAt
            cue.expiresAt = data.expiresAt
            cue.type = data.type
            cue.objsource = data.objsource
            cue.upDown = data.upDown
            cue.volume = data.volume
            return
        end
    end

    table.insert(CSR_SoundCues.cues, data)
end

local function pruneExpired()
    local now = nowMs()
    for i = #CSR_SoundCues.cues, 1, -1 do
        local cue = CSR_SoundCues.cues[i]
        if not cue or now >= (cue.expiresAt or 0) then
            table.remove(CSR_SoundCues.cues, i)
        end
    end
end

local function drawCue(panel, cue)
    local player = getPlayerSafe()
    if not player or not cue then
        return
    end

    local x, y, z = refreshCuePosition(cue)
    local dx = x - player:getX()
    local dy = y - player:getY()
    local angle = math.atan2(dy, dx) + math.rad(45)
    local core = getCore and getCore() or nil
    local cx = (core and core:getScreenWidth() or 1280) / 2
    local cy = (core and core:getScreenHeight() or 720) / 2
    local px = cx + math.cos(angle) * RING_RADIUS
    local py = cy + math.sin(angle) * RING_RADIUS
    local meta = TYPE_META[cue.type] or TYPE_META.OTHER
    local accent = CSR_Theme.colors[meta.accent]
    local now = nowMs()
    local fade = math.max(0.2, math.min(1.0, ((cue.expiresAt or now) - now) / BASE_LIFETIME_MS))

    panel:drawRect(px - 16, py - 10, 32, 20, 0.80 * fade, 0.10, 0.12, 0.15)
    panel:drawRectBorder(px - 16, py - 10, 32, 20, 0.95 * fade, accent.r, accent.g, accent.b)
    panel:drawText(meta.label, px - 4, py - 7, accent.r, accent.g, accent.b, fade, UIFont.Small)

    if cue.upDown == "UP" then
        panel:drawText("^", px + 7, py - 7, accent.r, accent.g, accent.b, fade, UIFont.Small)
    elseif cue.upDown == "DOWN" then
        panel:drawText("v", px + 7, py - 7, accent.r, accent.g, accent.b, fade, UIFont.Small)
    end
end

local SoundCuePanel = ISUIElement:derive("CSR_SoundCuePanel")

function SoundCuePanel:initialise()
    ISUIElement.initialise(self)
    self:addToUIManager()
    self.javaObject:setWantKeyEvents(false)
    self.javaObject:setConsumeMouseEvents(false)
end

function SoundCuePanel:isMouseOver()
    return false
end

function SoundCuePanel:onMouseWheel(del)
    return false
end

function SoundCuePanel:onMouseMove(d)
    return false
end

function SoundCuePanel:onMouseUp(d)
    return false
end

function SoundCuePanel:onMouseDown(d)
    return false
end

function SoundCuePanel:onRightMouseDown(d)
    return false
end

function SoundCuePanel:onRightMouseUp(d)
    return false
end

function SoundCuePanel:onRightMouseDownOutside(d)
    return false
end

function SoundCuePanel:onRightMouseUpOutside(d)
    return false
end

function SoundCuePanel:prerender()
end

function SoundCuePanel:render()
    if not CSR_FeatureFlags.isVisualSoundCuesEnabled() then
        return
    end

    pruneExpired()
    if #CSR_SoundCues.cues == 0 then
        return
    end

    for i = 1, #CSR_SoundCues.cues do
        drawCue(self, CSR_SoundCues.cues[i])
    end
end

local function createPanel()
    if CSR_SoundCues.panel then
        return
    end
    -- Use 1x1 bounds so Java-level hit testing never intercepts mouse events.
    -- Drawing still works because the panel is at (0,0) and PZ does not clip
    -- ISUIElement rendering to its bounds.
    local panel = SoundCuePanel:new(0, 0, 1, 1)
    panel:initialise()
    CSR_SoundCues.panel = panel
end

function CSR_SoundCues.onWorldSound(x, y, z, radius, volume, objsource)
    if not CSR_FeatureFlags.isVisualSoundCuesEnabled() then
        return
    end

    local player = getPlayerSafe()
    if not player or player:isDead() then
        return
    end

    if shouldIgnore(player, objsource) then
        return
    end

    local effectiveRadius = adjustedRadius(player, radius)
    if effectiveRadius <= 0 then
        return
    end

    local distance = IsoUtils.DistanceTo(player:getX(), player:getY(), x, y)
    if distance > effectiveRadius then
        return
    end

    local cueType = classifySource(objsource)
    if cueType == "PLAYERS" and not CSR_SoundCues.isPlayerSourceEnabled() then
        return
    end
    if cueType == "ZOMBIES" and not CSR_SoundCues.isZombieSourceEnabled() then
        return
    end
    if (cueType == "OTHER" or cueType == "VEHICLES" or cueType == "ALARMS" or cueType == "DEVICES") and not CSR_SoundCues.isOtherSourceEnabled() then
        return
    end

    local importance = computeImportance(distance, effectiveRadius, volume, cueType)
    if importance < MIN_IMPORTANCE then
        return
    end

    local now = nowMs()
    if (now - lastGlobalSoundAt) < GLOBAL_SOUND_COOLDOWN_MS and cueType ~= "ALARMS" then
        return
    end

    local key = cueKey(objsource, x, y, cueType)
    local lastSeen = CSR_SoundCues.lastEventByKey[key] or 0
    if (now - lastSeen) < PLAYER_SOUND_COOLDOWN_MS then
        return
    end

    local upDown = nil
    if z and z > player:getZ() then
        upDown = "UP"
    elseif z and z < player:getZ() then
        upDown = "DOWN"
    end

    CSR_SoundCues.lastEventByKey[key] = now
    lastGlobalSoundAt = now

    -- Only store objsource for types with safe IsoMovingObject subclasses
    local trackable = (cueType == "ZOMBIES" or cueType == "VEHICLES" or cueType == "PLAYERS") and objsource or nil

    addOrUpdateCue({
        key = key,
        x = x,
        y = y,
        z = z,
        volume = volume,
        distance = distance,
        importance = importance,
        type = cueType,
        objsource = trackable,
        upDown = upDown,
        createdAt = now,
        expiresAt = now + BASE_LIFETIME_MS + math.floor(math.min(600, importance * 25)),
    })
    sortAndTrim()
end

local function onGameStart()
    CSR_SoundCues.cues = {}
    CSR_SoundCues.lastEventByKey = {}
    createPanel()
end

local function onCreatePlayer()
    createPanel()
end

local function onResolutionChange()
    -- Panel is 1x1; drawCue reads screen size from getCore() each frame.
    -- Nothing to resize.
end

if Events then
    if Events.OnGameStart then Events.OnGameStart.Add(onGameStart) end
    if Events.OnCreatePlayer then Events.OnCreatePlayer.Add(onCreatePlayer) end
    if Events.OnResolutionChange then Events.OnResolutionChange.Add(onResolutionChange) end
    if Events.OnWorldSound then Events.OnWorldSound.Add(CSR_SoundCues.onWorldSound) end
end

return CSR_SoundCues
