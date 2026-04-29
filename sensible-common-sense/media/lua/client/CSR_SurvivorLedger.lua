require "CSR_FeatureFlags"

--[[
    CSR_SurvivorLedger.lua
    Compact draggable HUD panel showing 6 survival statistics.

    Icons: CSR_LedgerIcons.png (288x866), 6 icons stacked vertically, each 288x144px.
      0 = calendar   → Days Survived
      1 = zombie      → Total Kills (lifetime, persisted)
      2 = footprints  → Distance Traveled (tiles, persisted)
      3 = kg weight   → Character Weight (live)
      4 = skull+cal   → Session Kills (RAM only)
      5 = bar chart   → Avg Kills / Day

    Persistence: csrLedgerKills, csrLedgerDist (stats), csrLedgerPanelX/Y (position)
    stored in player modData. Client-only. SP + MP. Default OFF (EnableSurvivorLedger).
]]

local BADGE_W     = 8    -- colored square badge width
local BADGE_H     = 8    -- colored square badge height
local ROW_H       = 16
local PAD_X       = 7
local PAD_Y       = 5
local FONT        = UIFont.Small
local SAVE_TICKS  = 300   -- save modData every ~5 seconds

-- ModData keys for panel position
local MD_PANEL_X = "csrLedgerPanelX"
local MD_PANEL_Y = "csrLedgerPanelY"

-- Effective-enable: checks player S-panel override first, then sandbox.
local function isEffectivelyEnabled()
    if CSR_PlayerPrefs then
        local ov = CSR_PlayerPrefs.getOverride("SurvivorLedger")
        if ov ~= nil then return ov == true end
    end
    return CSR_FeatureFlags.isSurvivorLedgerEnabled()
end

-- Badge colors: r, g, b, a  (one per stat row)
local BADGE_COLORS = {
    { 0.35, 0.65, 1.00, 1 },   -- 1: days    – steel blue
    { 1.00, 0.25, 0.25, 1 },   -- 2: kills   – red
    { 0.30, 0.85, 0.45, 1 },   -- 3: dist    – green
    { 1.00, 0.80, 0.20, 1 },   -- 4: weight  – amber
    { 1.00, 0.50, 0.10, 1 },   -- 5: session – orange
    { 0.75, 0.35, 1.00, 1 },   -- 6: avg k/d – purple
}

-- Per-session stats (RAM only)
local _sessionKills = 0

-- Accumulated stats (synced to modData)
local _totalKills   = 0
local _totalDist    = 0   -- tiles (integer accumulation)

-- Last known player position (for delta distance)
local _lastX = nil
local _lastY = nil

-- Tick counter for periodic save
local _tickCount  = 0
local _registered = false

CSR_SurvivorLedger = CSR_SurvivorLedger or {}

-- ---------------------------------------------------------------------------
-- Position persistence helpers
-- ---------------------------------------------------------------------------
local function defaultPos()
    local sw = getCore():getScreenWidth()
    local sh = getCore():getScreenHeight()
    return sw - 220, sh - 330
end

local function restoreLedgerPos()
    local player = getPlayer()
    local dx, dy = defaultPos()
    if not player then return dx, dy end
    local md = player:getModData()
    return tonumber(md[MD_PANEL_X]) or dx,
           tonumber(md[MD_PANEL_Y]) or dy
end

local function saveLedgerPos(panel)
    local player = getPlayer()
    if not player or not panel then return end
    local md = player:getModData()
    md[MD_PANEL_X] = math.floor(panel:getX())
    md[MD_PANEL_Y] = math.floor(panel:getY())
    player:transmitModData()
end

-- ---------------------------------------------------------------------------
-- Draggable ISPanel subclass
-- ---------------------------------------------------------------------------
local LedgerPanel = ISPanel:derive("CSR_LedgerPanel")

function LedgerPanel:new(x, y, w, h)
    local o = ISPanel.new(self, x, y, w, h)
    o.backgroundColor = { r = 0,   g = 0,   b = 0,   a = 0.55 }
    o.borderColor     = { r = 0.6, g = 0.5, b = 0.4, a = 0.7  }
    o.anchorLeft = true
    o.anchorTop  = true
    o.dragging = false
    o.dragX    = 0
    o.dragY    = 0
    return o
end

function LedgerPanel:initialise()
    ISPanel.initialise(self)
end

function LedgerPanel:onMouseDown(x, y)
    self.dragging = true
    self.dragX = x
    self.dragY = y
    return true
end

function LedgerPanel:onMouseMove(dx, dy)
    if self.dragging then
        self:setX((getMouseX and getMouseX() or self:getX()) - self.dragX)
        self:setY((getMouseY and getMouseY() or self:getY()) - self.dragY)
        return true
    end
    return ISPanel.onMouseMove(self, dx, dy)
end

function LedgerPanel:onMouseMoveOutside(dx, dy)
    if self.dragging then
        self:setX((getMouseX and getMouseX() or self:getX()) - self.dragX)
        self:setY((getMouseY and getMouseY() or self:getY()) - self.dragY)
        return true
    end
    return ISPanel.onMouseMoveOutside(self, dx, dy)
end

function LedgerPanel:onMouseUp(x, y)
    if self.dragging then
        self.dragging = false
        saveLedgerPos(self)
        return true
    end
    return ISPanel.onMouseUp(self, x, y)
end

function LedgerPanel:onMouseUpOutside(x, y)
    if self.dragging then
        self.dragging = false
        saveLedgerPos(self)
        return true
    end
    return ISPanel.onMouseUpOutside(self, x, y)
end

function LedgerPanel:render()
    ISPanel.render(self)

    if not isEffectivelyEnabled() then return end

    local player = getPlayer()
    if not player or player:isDead() then return end

    -- Compute current stats
    local daysSurvived = math.floor(GameTime.getInstance():getWorldAgeHours() / 24)
    local charWeight   = math.floor(player:getNutrition():getWeight() * 10 + 0.5) / 10
    local avgKpd       = _totalKills / math.max(1, daysSurvived)

    local rows = {
        { icon = 1, label = string.format("Days: %d",    daysSurvived) },
        { icon = 2, label = string.format("Kills: %d",   _totalKills)  },
        { icon = 3, label = string.format("Dist: %dm",   math.floor(_totalDist)) },
        { icon = 4, label = string.format("Weight: %.1f", charWeight)  },
        { icon = 5, label = string.format("Session: %d", _sessionKills) },
        { icon = 6, label = string.format("Avg K/D: %.1f", avgKpd)    },
    }

    -- Dynamic resize to fit content
    local maxTextW = 0
    for _, row in ipairs(rows) do
        local tw = getTextManager():MeasureStringX(FONT, row.label)
        if tw > maxTextW then maxTextW = tw end
    end
    local newW = BADGE_W + 5 + maxTextW + PAD_X * 2
    local newH = (#rows * ROW_H) + PAD_Y * 2
    if self.width  ~= newW then self:setWidth(newW)  end
    if self.height ~= newH then self:setHeight(newH) end

    -- Draw rows: colored badge square + text
    for i, row in ipairs(rows) do
        local ry = PAD_Y + (i - 1) * ROW_H
        local rx = PAD_X
        local badgeY = ry + math.floor((ROW_H - BADGE_H) / 2)
        local c = BADGE_COLORS[row.icon]
        if c then
            -- Badge fill
            self:drawRect(rx, badgeY, BADGE_W, BADGE_H, 0.9, c[1], c[2], c[3])
            -- 1px darker border for definition
            self:drawRectBorder(rx, badgeY, BADGE_W, BADGE_H, 0.5, c[1]*0.5, c[2]*0.5, c[3]*0.5)
        end
        self:drawText(row.label, rx + BADGE_W + 5, ry, 1, 1, 1, 0.85, FONT)
    end
end

-- ---------------------------------------------------------------------------
-- Panel create / destroy  (defined before onPlayerUpdate so closures resolve)
-- ---------------------------------------------------------------------------
local function createPanel()
    if CSR_SurvivorLedger.panel or not isEffectivelyEnabled() then
        return
    end
    local x, y = restoreLedgerPos()
    local panel = LedgerPanel:new(x, y, 120, 106)
    panel:initialise()
    panel:instantiate()
    panel:addToUIManager()
    CSR_SurvivorLedger.panel = panel
end

local function destroyPanel()
    if not CSR_SurvivorLedger.panel then return end
    saveLedgerPos(CSR_SurvivorLedger.panel)
    CSR_SurvivorLedger.panel:removeFromUIManager()
    CSR_SurvivorLedger.panel = nil
end

-- ---------------------------------------------------------------------------
-- Event: zombie killed
-- ---------------------------------------------------------------------------
local function onZombieDead(zombie)
    local localPlayer = getPlayer()
    if not localPlayer then return end
    local attacker = zombie:getAttackedBy()
    if attacker ~= localPlayer then return end
    _sessionKills = _sessionKills + 1
    _totalKills   = _totalKills + 1
end

-- ---------------------------------------------------------------------------
-- Event: player update — distance tracking + periodic modData save
-- ---------------------------------------------------------------------------
local function onPlayerUpdate(player)
    if player ~= getPlayer() then return end

    -- Dynamic panel create/destroy when the pref is toggled at runtime
    if isEffectivelyEnabled() then
        if not CSR_SurvivorLedger.panel then createPanel() end
    else
        if CSR_SurvivorLedger.panel then destroyPanel() end
    end

    if not isEffectivelyEnabled() then return end

    local px = player:getX()
    local py = player:getY()
    if _lastX ~= nil then
        local dx = px - _lastX
        local dy = py - _lastY
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist > 0.01 then
            _totalDist = _totalDist + dist
        end
    end
    _lastX = px
    _lastY = py

    _tickCount = _tickCount + 1
    if _tickCount >= SAVE_TICKS then
        _tickCount = 0
        local md = player:getModData()
        md.csrLedgerKills = _totalKills
        md.csrLedgerDist  = math.floor(_totalDist)
        player:transmitModData()
    end
end

-- ---------------------------------------------------------------------------
-- Init: load persisted stats from modData, register events, create panel
-- ---------------------------------------------------------------------------
local function init()
    local player = getPlayer()
    if not player then return end

    local md = player:getModData()
    _totalKills   = tonumber(md.csrLedgerKills) or 0
    _totalDist    = tonumber(md.csrLedgerDist)  or 0
    _lastX        = player:getX()
    _lastY        = player:getY()
    _sessionKills = 0
    _tickCount    = 0

    if not _registered then
        _registered = true
        Events.OnZombieDead.Add(onZombieDead)
        Events.OnPlayerUpdate.Add(onPlayerUpdate)
    end

    createPanel()
end

Events.OnGameStart.Add(init)
