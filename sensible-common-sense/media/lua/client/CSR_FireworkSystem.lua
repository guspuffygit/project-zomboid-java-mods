require "CSR_FeatureFlags"
require "CSR_Utils"

-- ─────────────────────────────────────────────────
-- CSR_FireworkSystem
-- Right-click a Distraction Firework with a lighter
-- to light the fuse. After a short delay, the
-- firework goes off: loud noise attracting zombies,
-- colored light bursts, and a 30-second confusion
-- zone that keeps zombies fixated on the spot.
-- ─────────────────────────────────────────────────

print("[CSR] FireworkSystem loaded")

CSR_FireworkSystem = CSR_FireworkSystem or {}

local FUSE_TIME_TICKS = 200       -- ~3.3 seconds at 60 tps
local EFFECT_DURATION_SEC = 30
local EFFECT_RADIUS = 30          -- tiles
local NOISE_RADIUS = 120          -- zombie-attract radius
local NOISE_VOLUME = 120
local BURST_COUNT = 6             -- number of light bursts during the show
local BURST_INTERVAL_TICKS = 35   -- ticks between bursts (~0.6s)

local activeFireworks = {}

-- ─────────────────────────────────────────────────
-- Visual overlay system (screen-space burst sprites + flash)
-- ─────────────────────────────────────────────────

local BURST_TEXTURES = {
    "media/textures/CSR_BurstOrange.png",
    "media/textures/CSR_BurstGreen.png",
    "media/textures/CSR_BurstBlue.png",
    "media/textures/CSR_BurstPurple.png",
}

local BURST_DISPLAY_SIZE = 320    -- screen pixels at zoom 1
local BURST_FADE_TICKS = 30       -- how many ticks the sprite fades out (~0.5s)
local FLASH_FADE_TICKS = 12       -- how many ticks the white flash fades (~0.2s)
local FLASH_ALPHA = 0.35          -- peak white flash opacity

local activeBursts = {}           -- {x, y, z, texIdx, ticksLeft, maxTicks}
local activeFlashes = {}          -- {ticksLeft, maxTicks}

-- Fullscreen overlay panel — NOT added to UIManager (avoids blocking input).
-- Instead, instantiated directly for javaObject, rendered via OnPostUIDraw.
require "ISUI/ISPanel"
local CSR_BurstPanel = ISPanel:derive("CSR_BurstPanel")
local burstPanel = nil

function CSR_BurstPanel:new(x, y, w, h)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, self)
    self.__index = self
    o.backgroundColor = {r=0, g=0, b=0, a=0}
    o.borderColor = {r=0, g=0, b=0, a=0}
    o.moveWithMouse = false
    return o
end

function CSR_BurstPanel:initialise()
    ISPanel.initialise(self)
end

function CSR_BurstPanel:isMouseOver()
    return false
end

function CSR_BurstPanel:onMouseDown()
    return false
end

function CSR_BurstPanel:onMouseUp()
    return false
end

function CSR_BurstPanel:onRightMouseDown()
    return false
end

function CSR_BurstPanel:onRightMouseUp()
    return false
end

function CSR_BurstPanel:prerender()
    local sw = getCore():getScreenWidth()
    local sh = getCore():getScreenHeight()
    if self.width ~= sw or self.height ~= sh then
        self:setWidth(sw)
        self:setHeight(sh)
        if self.javaObject then
            self.javaObject:setWidth(sw)
            self.javaObject:setHeight(sh)
        end
    end
end

function CSR_BurstPanel:render()
    if #activeBursts == 0 and #activeFlashes == 0 then return end

    local core = getCore()
    local zoom = core:getZoom(0)
    local offX = IsoCamera.getOffX()
    local offY = IsoCamera.getOffY()
    local sw = core:getScreenWidth()
    local sh = core:getScreenHeight()

    for i = #activeFlashes, 1, -1 do
        local f = activeFlashes[i]
        f.ticksLeft = f.ticksLeft - 1
        if f.ticksLeft <= 0 then
            table.remove(activeFlashes, i)
        else
            local alpha = FLASH_ALPHA * (f.ticksLeft / f.maxTicks)
            self:drawRect(0, 0, sw, sh, alpha, 1.0, 1.0, 1.0)
        end
    end

    for i = #activeBursts, 1, -1 do
        local b = activeBursts[i]
        b.ticksLeft = b.ticksLeft - 1
        if b.ticksLeft <= 0 then
            table.remove(activeBursts, i)
        else
            local tex = getTexture(BURST_TEXTURES[b.texIdx])
            if tex then
                local alpha = b.ticksLeft / b.maxTicks
                local progress = 1.0 - alpha
                local scale = (0.6 + progress * 0.4) / zoom
                local drawSize = BURST_DISPLAY_SIZE * scale

                local sx = IsoUtils.XToScreen(b.x + 0.5, b.y + 0.5, b.z, 0)
                local sy = IsoUtils.YToScreen(b.x + 0.5, b.y + 0.5, b.z, 0)
                sx = (sx - offX) / zoom
                sy = (sy - offY) / zoom

                local dx = sx - drawSize / 2
                local dy = sy - drawSize / 2

                self:drawTextureScaled(tex, dx, dy, drawSize, drawSize, alpha, 1.0, 1.0, 1.0)
            end
        end
    end
end

local function ensureBurstPanel()
    if burstPanel and burstPanel.javaObject then return end
    local sw = getCore():getScreenWidth()
    local sh = getCore():getScreenHeight()
    burstPanel = CSR_BurstPanel:new(0, 0, sw, sh)
    burstPanel:initialise()
    burstPanel:instantiate()
    burstPanel.javaObject:setConsumeMouseEvents(false)
    print("[CSR] BurstPanel created (instantiate only, no UIManager) " .. sw .. "x" .. sh)
end

local function onPostUIDraw()
    if #activeBursts == 0 and #activeFlashes == 0 then return end
    if not burstPanel or not burstPanel.javaObject then return end
    burstPanel:prerender()
    burstPanel:render()
end

local _burstScratch = {}
local _flashScratch = {}

local function spawnVisualBurst(x, y, z, burstIndex)
    ensureBurstPanel()
    local texIdx = (burstIndex % #BURST_TEXTURES) + 1
    table.insert(activeBursts, {x=x, y=y, z=z, texIdx=texIdx, ticksLeft=BURST_FADE_TICKS, maxTicks=BURST_FADE_TICKS})
    table.insert(activeFlashes, {ticksLeft=FLASH_FADE_TICKS, maxTicks=FLASH_FADE_TICKS})
end

local function distSq(x1, y1, x2, y2)
    local dx = x1 - x2
    local dy = y1 - y2
    return dx * dx + dy * dy
end

-- ─────────────────────────────────────────────────
-- Light Fuse Timed Action
-- ─────────────────────────────────────────────────

CSR_LightFireworkAction = ISBaseTimedAction:derive("CSR_LightFireworkAction")

function CSR_LightFireworkAction:isValid()
    return self.character and self.character:getInventory():contains(self.item)
end

function CSR_LightFireworkAction:start()
    self:setActionAnim("LightItem")
    self:setOverrideHandModels(nil, nil)
end

function CSR_LightFireworkAction:update()
end

function CSR_LightFireworkAction:stop()
    ISBaseTimedAction.stop(self)
end

function CSR_LightFireworkAction:perform()
    local player = self.character
    local item = self.item
    if not player or not item then
        ISBaseTimedAction.perform(self)
        return
    end

    local x = math.floor(player:getX())
    local y = math.floor(player:getY())
    local z = math.floor(player:getZ())

    player:getInventory():Remove(item)

    if player:getEmitter() then
        player:getEmitter():playSound("FireCrackerEquip")
    end

    CSR_FireworkSystem.ignite(x, y, z, player)

    ISBaseTimedAction.perform(self)
end

function CSR_LightFireworkAction:new(player, item)
    local o = ISBaseTimedAction.new(self, player)
    o.item = item
    o.maxTime = 60
    o.stopOnWalk = true
    o.stopOnRun = true
    return o
end

-- ─────────────────────────────────────────────────
-- Firework effect lifecycle
-- ─────────────────────────────────────────────────

function CSR_FireworkSystem.ignite(x, y, z, player)
    local fw = {
        x = x,
        y = y,
        z = z or 0,
        player = player,
        fuseTicks = FUSE_TIME_TICKS,
        phase = "fuse",
        burstIndex = 0,
        burstCooldown = 0,
        effectTicksLeft = EFFECT_DURATION_SEC * 60,
        soundPulseCD = 0,
    }
    table.insert(activeFireworks, fw)
end

local SMOKE_OFFSETS = {
    {0,0}, {1,0}, {-1,0}, {0,1}, {0,-1},
    {1,1}, {-1,-1}, {1,-1}, {-1,1},
}

local function doBurst(fw)
    local x, y, z = fw.x, fw.y, fw.z
    print("[CSR] doBurst #" .. fw.burstIndex .. " at " .. x .. "," .. y .. "," .. z .. " phase=" .. fw.phase)

    addSound(nil, x, y, z, NOISE_RADIUS, NOISE_VOLUME)

    local cell = getCell()
    local square = cell and cell:getGridSquare(x, y, z) or nil
    if square then
        square:playSound("FireCrackerExplode")
    end

    -- Colored burst sprite overlay + white screen flash
    spawnVisualBurst(x, y, z, fw.burstIndex)

    -- Smoke burst visual ring
    local player = fw.player
    if player and cell then
        local off = SMOKE_OFFSETS[(fw.burstIndex % #SMOKE_OFFSETS) + 1]
        local sx, sy = x + off[1], y + off[2]
        sendClientCommand(player, 'object', 'addSmokeOnSquare', {
            x = sx, y = sy, z = z
        })
    end
end

local function confuseZombiesInRadius(fw)
    -- Repeated noise pulses keep zombies fixated on the firework location
    addSound(nil, fw.x, fw.y, fw.z, EFFECT_RADIUS, NOISE_VOLUME / 2)
end

local function tickFirework(fw)
    if fw.phase == "fuse" then
        fw.fuseTicks = fw.fuseTicks - 1
        if fw.fuseTicks <= 0 then
            fw.phase = "show"
            fw.burstCooldown = 0
        end
        return true
    end

    if fw.phase == "show" then
        if fw.burstCooldown <= 0 and fw.burstIndex < BURST_COUNT then
            doBurst(fw)
            fw.burstIndex = fw.burstIndex + 1
            fw.burstCooldown = BURST_INTERVAL_TICKS
        end
        fw.burstCooldown = fw.burstCooldown - 1

        if fw.burstIndex >= BURST_COUNT then
            fw.phase = "confuse"
        end
        return true
    end

    if fw.phase == "confuse" then
        fw.effectTicksLeft = fw.effectTicksLeft - 1

        fw.soundPulseCD = fw.soundPulseCD - 1
        if fw.soundPulseCD <= 0 then
            addSound(nil, fw.x, fw.y, fw.z, NOISE_RADIUS / 2, NOISE_VOLUME / 2)
            confuseZombiesInRadius(fw)
            fw.soundPulseCD = 120
        end

        if fw.effectTicksLeft <= 0 then
            return false
        end
        return true
    end

    return false
end

local function onTick()
    if #activeFireworks == 0 then return end

    for i = #activeFireworks, 1, -1 do
        local alive = tickFirework(activeFireworks[i])
        if not alive then
            table.remove(activeFireworks, i)
        end
    end
end

-- ─────────────────────────────────────────────────
-- Context menu
-- ─────────────────────────────────────────────────

local function onLightFirework(player, item)
    if not player or not item then return end
    ISTimedActionQueue.add(CSR_LightFireworkAction:new(player, item))
end

local function onPurgeFireworks(player)
    if not player then return end
    sendClientCommand(player, "CommonSenseReborn", "PurgeFireworks", {})
end

local function onFillWorldObjectContextMenu(playerNum, context, worldObjects, test)
    if test then return end

    local player = getSpecificPlayer(playerNum)
    if not player then return end

    -- Admin purge option (available regardless of feature flag)
    local access = player:getAccessLevel()
    if access and (access == "admin" or access == "Admin") then
        context:addOption("[CSR Admin] Purge All Fireworks", player, onPurgeFireworks)
    end

    if not CSR_FeatureFlags.isFireworkEnabled() then return end

    local inv = player:getInventory()
    if not inv then return end

    local firework = inv:getFirstTypeRecurse("CommonSenseReborn.Firework")
    if not firework then return end

    if not CSR_Utils.hasIgnitionSource(player) then return end

    context:addOption("Light Distraction Firework", player, onLightFirework, firework)
end

-- ─────────────────────────────────────────────────
-- Inventory context menu (right-click on item)
-- ─────────────────────────────────────────────────

local function onFillInventoryObjectContextMenu(playerNum, context, items)
    if not CSR_FeatureFlags.isFireworkEnabled() then return end

    local player = getSpecificPlayer(playerNum)
    if not player then return end

    local actualItems = items
    if ISInventoryPane and ISInventoryPane.getActualItems then
        actualItems = ISInventoryPane.getActualItems(items)
    end

    for i = 1, #actualItems do
        local item = actualItems[i]
        if item and item.getFullType and item:getFullType() == "CommonSenseReborn.Firework" then
            if CSR_Utils.hasIgnitionSource(player) then
                context:addOption("Light Distraction Firework", player, onLightFirework, item)
            end
            return
        end
    end
end

-- ─────────────────────────────────────────────────
-- Events
-- ─────────────────────────────────────────────────

-- v1.8.7: lazy-register on the feature flag (Phoenix II). Skipping
-- registration entirely when the firework feature is disabled removes
-- per-tick + draw + context-menu callback overhead on those installs.
local _csrFireworkRegistered = false
local function ensureFireworkRegistered()
    if _csrFireworkRegistered then return end
    if not (CSR_FeatureFlags and CSR_FeatureFlags.isFireworkEnabled
        and CSR_FeatureFlags.isFireworkEnabled()) then return end
    _csrFireworkRegistered = true
    if Events.OnTick then Events.OnTick.Add(onTick) end
    if Events.OnPostUIDraw then Events.OnPostUIDraw.Add(onPostUIDraw) end
    if Events.OnFillWorldObjectContextMenu then Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu) end
    if Events.OnFillInventoryObjectContextMenu then Events.OnFillInventoryObjectContextMenu.Add(onFillInventoryObjectContextMenu) end
end

if Events and Events.OnGameStart then
    Events.OnGameStart.Add(ensureFireworkRegistered)
end
