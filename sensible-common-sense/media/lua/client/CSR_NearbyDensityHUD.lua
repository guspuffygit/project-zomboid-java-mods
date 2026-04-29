-- CSR_NearbyDensityHUD.lua
--
-- Small, draggable on-screen HUD that replaces the (removed) minimap heatmap
-- overlay. Samples zombies within ZOMBIE_DENSITY_HUD_RADIUS tiles of the local
-- player using cell:getZombieList() (the same fast path the server now uses)
-- and renders one colored count line: "Nearby Density: 12".
--
-- Why client-local sampling here instead of server data?
--  * Zombies in the player's immediate radius are always loaded on the local
--    machine in MP (chunks within ~30 tiles are guaranteed loaded), so this is
--    free and adds no network traffic.
--  * Server push grid is coarse (100-tile cells); HUD wants tile-precise count.
--  * Update independently at HUD refresh cadence without waiting on RPC.
--
-- Cost per refresh tick: one cell:getZombieList() walk (typically 10-200
-- entries) + one squared-distance compare + one drawText. Much cheaper than
-- the minimap heatmap render path it replaces.

require "CSR_Config"
require "CSR_FeatureFlags"
require "CSR_Theme"

CSR_NearbyDensityHUD = CSR_NearbyDensityHUD or {}

local HUD = nil           -- ISCollapsableWindow instance (or fallback ISPanel)
local _tickCounter = 0
local _cachedCount = 0
local _cachedTier = 0     -- 0=safe, 1=light, 2=heavy, 3=horde
local _lastSampleErr = nil

local TIER_LABEL = { [0] = "Safe", [1] = "Light", [2] = "Heavy", [3] = "Horde" }
local TIER_COLOR_KEY = { [0] = "accentGreen", [1] = "accentAmber", [2] = "accentRed", [3] = "accentViolet" }

local function tierForCount(n)
    if n >= 30 then return 3
    elseif n >= 15 then return 2
    elseif n >= 5 then return 1
    else return 0 end
end

local function getPlayerModData()
    local p = getSpecificPlayer(0)
    return p and p.getModData and p:getModData() or nil
end

local function loadHudPos()
    local md = getPlayerModData()
    local x = (md and md.CSRZDensityHudX) or CSR_Config.ZOMBIE_DENSITY_HUD_DEFAULT_X
    local y = (md and md.CSRZDensityHudY) or CSR_Config.ZOMBIE_DENSITY_HUD_DEFAULT_Y
    return x, y
end

local function saveHudPos(x, y)
    local md = getPlayerModData()
    if not md then return end
    md.CSRZDensityHudX = x
    md.CSRZDensityHudY = y
end

local function loadHudVisible()
    local md = getPlayerModData()
    if md and md.CSRZDensityHudVisible ~= nil then
        return md.CSRZDensityHudVisible == true
    end
    return true
end

local function saveHudVisible(v)
    local md = getPlayerModData()
    if not md then return end
    md.CSRZDensityHudVisible = v == true
end

-- =============================================================================
-- Sampling
-- =============================================================================
local function sampleNearby()
    local p = getSpecificPlayer(0)
    if not p then return 0 end
    local cell = p.getCell and p:getCell() or getCell()
    if not cell then return 0 end
    -- Prefer the typed zombie list; fall back to the all-objects list on legacy builds.
    local zlist = (cell.getZombieList and cell:getZombieList())
                  or (cell.getObjectListForLua and cell:getObjectListForLua())
                  or nil
    if not zlist then return 0 end
    local px, py, pz = p:getX(), p:getY(), p:getZ()
    local radius = CSR_Config.ZOMBIE_DENSITY_HUD_RADIUS or 30
    local rSq = radius * radius
    local needsTypeCheck = (cell.getZombieList == nil)
    local count = 0
    local sz = zlist:size()
    for i = 0, sz - 1 do
        local z = zlist:get(i)
        if z and not z:isDead() and (not needsTypeCheck or instanceof(z, "IsoZombie")) then
            local zx, zy, zz = z:getX(), z:getY(), z:getZ()
            -- Same-floor only; keeps the HUD honest in multi-storey buildings.
            if math.abs(zz - pz) <= 1 then
                local dx, dy = zx - px, zy - py
                local d2 = dx * dx + dy * dy
                if d2 <= rSq then
                    count = count + 1
                end
            end
        end
    end
    return count
end

-- =============================================================================
-- HUD widget
-- =============================================================================
local NearbyHUD = ISCollapsableWindow:derive("CSR_NearbyDensityHUD")

function NearbyHUD:createChildren()
    ISCollapsableWindow.createChildren(self)
    self.title = "Nearby Density"
    self.resizable = false
    if self.setResizable then self:setResizable(false) end
    if self.closeButton and self.closeButton.setVisible then
        self.closeButton:setOnClick(function() CSR_NearbyDensityHUD.setVisible(false) end)
    end
end

function NearbyHUD:prerender()
    ISCollapsableWindow.prerender(self)
end

function NearbyHUD:render()
    ISCollapsableWindow.render(self)
    local tm = getTextManager()
    if not tm then return end
    local font = UIFont.Small
    local label = tostring(_cachedCount) .. "  (" .. (TIER_LABEL[_cachedTier] or "?") .. ")"
    local accent = CSR_Theme.getColor(TIER_COLOR_KEY[_cachedTier] or "accentSlate")
    local textColor = CSR_Theme.getColor("text")
    local pad = 6
    local th = self:titleBarHeight() or 16
    local innerW = self:getWidth() - pad * 2
    -- Color swatch + count
    self:drawRect(pad, th + pad, 6, tm:getFontHeight(font), accent.a or 1.0, accent.r, accent.g, accent.b)
    self:drawText(label, pad + 12, th + pad - 1, textColor.r, textColor.g, textColor.b, 1.0, font)
end

function NearbyHUD:onMouseUp(x, y)
    ISCollapsableWindow.onMouseUp(self, x, y)
    if self.moving then return end -- ISCollapsableWindow clears moving in onMouseUp
    saveHudPos(self:getX(), self:getY())
end

-- ISCollapsableWindow drag is implemented via OnMouseUp on the title bar; capture both.
function NearbyHUD:onMouseUpOutside(x, y)
    ISCollapsableWindow.onMouseUpOutside(self, x, y)
    saveHudPos(self:getX(), self:getY())
end

local function ensureHud()
    if HUD then return HUD end
    local x, y = loadHudPos()
    HUD = NearbyHUD:new(x, y, 150, 46)
    HUD:initialise()
    HUD:addToUIManager()
    if HUD.setVisible then HUD:setVisible(loadHudVisible()) end
    return HUD
end

function CSR_NearbyDensityHUD.isVisible()
    return HUD ~= nil and HUD.isVisible and HUD:isVisible()
end

function CSR_NearbyDensityHUD.setVisible(v)
    ensureHud()
    if HUD and HUD.setVisible then HUD:setVisible(v == true) end
    saveHudVisible(v == true)
end

function CSR_NearbyDensityHUD.toggle()
    CSR_NearbyDensityHUD.setVisible(not CSR_NearbyDensityHUD.isVisible())
end

-- Public accessors used by the aim-cursor density pill.
function CSR_NearbyDensityHUD.getCachedCount()
    return _cachedCount or 0
end

function CSR_NearbyDensityHUD.getCachedTier()
    return _cachedTier or 0
end

function CSR_NearbyDensityHUD.getTierColorKey(tier)
    return TIER_COLOR_KEY[tier or _cachedTier or 0] or "accentSlate"
end

function CSR_NearbyDensityHUD.getTierLabel(tier)
    return TIER_LABEL[tier or _cachedTier or 0] or "?"
end

-- =============================================================================
-- Event wiring
-- =============================================================================
local function isFeatureEnabled()
    -- Reuse the overlay sandbox flag; the HUD is part of the same feature surface.
    return CSR_FeatureFlags.isZombieDensityOverlayEnabled()
end

local function onTick()
    if not isFeatureEnabled() then
        if HUD and HUD.isVisible and HUD:isVisible() then HUD:setVisible(false) end
        return
    end
    if not HUD then ensureHud() end
    -- Sample if either the standalone HUD is visible OR the aim-cursor density
    -- pill is enabled (it reads getCachedCount()).
    local aimPillEnabled = CSR_FeatureFlags and CSR_FeatureFlags.isAimingDensityCursorEnabled
        and CSR_FeatureFlags.isAimingDensityCursorEnabled()
    local hudVisible = HUD and HUD.isVisible and HUD:isVisible()
    if not hudVisible and not aimPillEnabled then return end

    _tickCounter = _tickCounter + 1
    local interval = CSR_Config.ZOMBIE_DENSITY_HUD_REFRESH_TICKS or 30
    if _tickCounter < interval then return end
    _tickCounter = 0

    local ok, countOrErr = pcall(sampleNearby)
    if ok then
        _cachedCount = countOrErr or 0
        _cachedTier = tierForCount(_cachedCount)
    else
        _lastSampleErr = countOrErr
    end
end

local function onGameStart()
    _tickCounter = 0
    _cachedCount = 0
    _cachedTier = 0
    if isFeatureEnabled() then ensureHud() end
end

if Events then
    if Events.OnGameStart then Events.OnGameStart.Add(onGameStart) end
    if Events.OnTick then Events.OnTick.Add(onTick) end
end

return CSR_NearbyDensityHUD
