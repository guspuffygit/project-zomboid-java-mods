-- CSR_PlayerPrefsPanel: floating panel for per-player CSR preference overrides.
-- Opened via the "S" (Settings) button in the Utility HUD header.
-- Each row shows the feature label and a toggle button (ON/OFF).
-- Changes persist immediately via CSR_PlayerPrefs modData storage.
-- Note: features that affect HUD widget visibility (e.g. Sound Cues, DW) take
-- effect on next HUD creation (toggle HUD off/on with the keybind).

require "CSR_FeatureFlags"
require "CSR_PlayerPrefs"
require "CSR_Theme"

CSR_PlayerPrefsPanel = {}

local PrefsPanel = ISPanel:derive("CSRPrefsPanel")

local PANEL_W    = 286
local HEADER_H   = 22
local ROW_H      = 26
local BTN_W      = 56
local BTN_H      = 18
local LABEL_PAD  = 12
local BTN_RPAD   = 12   -- distance from right edge to button right

local function numPrefs()
    return CSR_PlayerPrefs and #CSR_PlayerPrefs.PREFS or 0
end

local function panelHeight()
    return HEADER_H + numPrefs() * ROW_H + 14
end

-- -------------------------------------------------------------------------
function PrefsPanel:new(x, y)
    local o = ISPanel.new(self, x, y, PANEL_W, panelHeight())
    setmetatable(o, self)
    self.__index = self
    o.dragging = false
    o.dragX    = 0
    o.dragY    = 0
    return o
end

function PrefsPanel:initialise()
    ISPanel.initialise(self)
end

function PrefsPanel:createChildren()
    ISPanel.createChildren(self)

    -- Close button (top-right of header)
    self.closeBtn = ISButton:new(self.width - 22, 2, 18, HEADER_H - 4, "X", self, self.onClose)
    self.closeBtn:initialise()
    self.closeBtn:instantiate()
    self.closeBtn.anchorRight = true
    self.closeBtn.anchorTop   = true
    self:addChild(self.closeBtn)
    CSR_Theme.applyButtonStyle(self.closeBtn, "accentRed", false)

    -- One toggle button per pref
    self.prefButtons = {}
    for i, pref in ipairs(CSR_PlayerPrefs.PREFS) do
        local rowY = HEADER_H + (i - 1) * ROW_H
        local btnY = rowY + math.floor((ROW_H - BTN_H) / 2)
        local btnX = self.width - BTN_W - BTN_RPAD
        local btn  = ISButton:new(btnX, btnY, BTN_W, BTN_H, "", self, self.onTogglePref)
        btn:initialise()
        btn:instantiate()
        btn.anchorRight = true
        btn.anchorTop   = true
        btn.prefKey     = pref.key
        self:addChild(btn)
        self.prefButtons[pref.key] = btn
    end

    self:refreshButtons()
end

-- -------------------------------------------------------------------------
function PrefsPanel:refreshButtons()
    if not self.prefButtons then return end
    local colorsOn = true
    if CSR_FeatureFlags and CSR_FeatureFlags.isColoredTogglesEnabled then
        colorsOn = CSR_FeatureFlags.isColoredTogglesEnabled()
    end
    for _, pref in ipairs(CSR_PlayerPrefs.PREFS) do
        local btn = self.prefButtons[pref.key]
        if btn then
            local locked    = pref.adminLocked and pref.adminLocked()
            local effective = pref.effectiveFn()
            local override  = CSR_PlayerPrefs.getOverride(pref.key)
            local hasOver   = override ~= nil

            if locked then
                btn:setTitle(effective and "ON \187" or "OFF \187")
                btn:setTooltip("Controlled by admin/server")
            elseif hasOver then
                btn:setTitle(effective and "ON" or "OFF")
                btn:setTooltip("Player override active. Click to toggle.")
            else
                btn:setTitle(effective and "ON" or "OFF")
                btn:setTooltip("Using server default. Click to override.")
            end

            if colorsOn then
                -- Always solid green (ON) / red (OFF) regardless of override state.
                CSR_Theme.applyButtonStyle(btn, effective and "accentGreen" or "accentRed", true)
            else
                -- Vanilla-styled: clear any custom colors so the button renders default.
                btn.backgroundColor = nil
                btn.backgroundColorMouseOver = nil
                btn.borderColor = nil
            end
        end
    end
end

-- -------------------------------------------------------------------------
function PrefsPanel:onTogglePref(btn)
    if not btn or not btn.prefKey then return end
    local pref = CSR_PlayerPrefs._byKey[btn.prefKey]
    if not pref then return end
    if pref.adminLocked and pref.adminLocked() then return end
    CSR_PlayerPrefs.toggle(btn.prefKey)
    self:refreshButtons()
    -- Keep the standalone DW button in the HUD in sync
    if btn.prefKey == "DualWield" then
        if CSR_UtilityHud and CSR_UtilityHud.panel and CSR_UtilityHud.panel.updateDualWieldButton then
            CSR_UtilityHud.panel:updateDualWieldButton()
        end
    elseif btn.prefKey == "DualWieldEmergencySwap" then
        if CSR_UtilityHud and CSR_UtilityHud.panel and CSR_UtilityHud.panel.updateEmergencySwapButton then
            CSR_UtilityHud.panel:updateEmergencySwapButton()
        end
    end
end

function PrefsPanel:onClose()
    self:setVisible(false)
    CSR_PlayerPrefsPanel.isVisible = false
end

-- -------------------------------------------------------------------------
function PrefsPanel:prerender()
    ISPanel.prerender(self)
    CSR_Theme.drawPanelChrome(self, "CSR Personal Settings", HEADER_H)
end

function PrefsPanel:render()
    ISPanel.render(self)
    -- Refresh button states every frame to catch live sandbox/admin changes.
    self:refreshButtons()

    if not CSR_PlayerPrefs then return end
    for i, pref in ipairs(CSR_PlayerPrefs.PREFS) do
        local rowY    = HEADER_H + (i - 1) * ROW_H
        local textY   = rowY + math.floor((ROW_H - 10) / 2) + 2
        local locked  = pref.adminLocked and pref.adminLocked()
        local r, g, b = 0.85, 0.85, 0.85
        if locked then r, g, b = 0.55, 0.55, 0.65 end
        self:drawText(pref.label, LABEL_PAD, textY, r, g, b, 1.0, UIFont.Small)
    end
end

-- -------------------------------------------------------------------------
-- Drag support (header only)
function PrefsPanel:onMouseDown(x, y)
    if y <= HEADER_H then
        self.dragging = true
        self.dragX    = x
        self.dragY    = y
        return true
    end
    return ISPanel.onMouseDown(self, x, y)
end

function PrefsPanel:onMouseMove(dx, dy)
    if self.dragging then
        local mx = getMouseX and getMouseX() or self:getX()
        local my = getMouseY and getMouseY() or self:getY()
        self:setX(mx - self.dragX)
        self:setY(my - self.dragY)
        return true
    end
    return ISPanel.onMouseMove(self, dx, dy)
end

function PrefsPanel:onMouseMoveOutside(dx, dy)
    if self.dragging then
        local mx = getMouseX and getMouseX() or self:getX()
        local my = getMouseY and getMouseY() or self:getY()
        self:setX(mx - self.dragX)
        self:setY(my - self.dragY)
        return true
    end
    return ISPanel.onMouseMoveOutside(self, dx, dy)
end

function PrefsPanel:onMouseUp(x, y)
    self.dragging = false
    return ISPanel.onMouseUp(self, x, y)
end

function PrefsPanel:onMouseUpOutside(x, y)
    self.dragging = false
    return ISPanel.onMouseUpOutside(self, x, y)
end

-- =========================================================================
-- Public API
-- =========================================================================
CSR_PlayerPrefsPanel.isVisible = false
CSR_PlayerPrefsPanel._panel    = nil

-- Toggle visibility. anchorX/anchorY is the spawn position hint (HUD position).
function CSR_PlayerPrefsPanel.toggle(anchorX, anchorY)
    if CSR_PlayerPrefsPanel._panel then
        local vis = not CSR_PlayerPrefsPanel._panel:getIsVisible()
        CSR_PlayerPrefsPanel._panel:setVisible(vis)
        CSR_PlayerPrefsPanel.isVisible = vis
        if vis then
            CSR_PlayerPrefsPanel._panel:refreshButtons()
        end
        return
    end

    -- Clamp to screen
    local core = getCore and getCore()
    local sw   = core and core:getScreenWidth()  or 1280
    local sh   = core and core:getScreenHeight() or 768
    local x    = math.max(4, math.min(anchorX or 100, sw - PANEL_W - 4))
    local y    = math.max(4, math.min(anchorY or 84,  sh - panelHeight() - 4))

    local panel = PrefsPanel:new(x, y)
    panel:initialise()
    panel:instantiate()
    panel:addToUIManager()
    CSR_PlayerPrefsPanel._panel    = panel
    CSR_PlayerPrefsPanel.isVisible = true
end

function CSR_PlayerPrefsPanel.destroy()
    if CSR_PlayerPrefsPanel._panel then
        CSR_PlayerPrefsPanel._panel:removeFromUIManager()
        CSR_PlayerPrefsPanel._panel    = nil
        CSR_PlayerPrefsPanel.isVisible = false
    end
end

return CSR_PlayerPrefsPanel
