
require "CSR_FeatureFlags"
require "CSR_PlayerPrefs"
require "CSR_Theme"
require "CSR_Utils"
require "CSR_Guide"
require "CSR_NearbyDensityHUD"

local HUD_TOGGLE_DEFAULT_KEY    = Keyboard and Keyboard.KEY_DIVIDE  or 181
local DW_TOGGLE_DEFAULT_KEY     = Keyboard and Keyboard.KEY_NUMPAD8 or 72
local LEDGER_TOGGLE_DEFAULT_KEY = Keyboard and Keyboard.KEY_NUMPAD4 or 75
local DENSITY_TOGGLE_DEFAULT_KEY = Keyboard and Keyboard.KEY_NUMPAD0 or 82
local hudOptions     = nil
local hudKeyBind     = nil
local dwKeyBind      = nil
local ledgerKeyBind  = nil
local densityKeyBind = nil
if PZAPI and PZAPI.ModOptions and PZAPI.ModOptions.create then
    hudOptions = PZAPI.ModOptions:create("CommonSenseRebornUtilityHud", "Common Sense Reborn - Utility HUD")
    if hudOptions and hudOptions.addKeyBind then
        hudKeyBind     = hudOptions:addKeyBind("utilityHudToggle",  "Toggle Utility HUD",         HUD_TOGGLE_DEFAULT_KEY)
        dwKeyBind      = hudOptions:addKeyBind("dualWieldToggle",   "Toggle Dual Wield",          DW_TOGGLE_DEFAULT_KEY)
        ledgerKeyBind  = hudOptions:addKeyBind("ledgerToggle",      "Toggle Survivor's Ledger",   LEDGER_TOGGLE_DEFAULT_KEY)
        densityKeyBind = hudOptions:addKeyBind("densityHudToggle",  "Toggle Nearby Density HUD",  DENSITY_TOGGLE_DEFAULT_KEY)
    end
end

local function getHudBoundKey()
    if hudKeyBind and hudKeyBind.getValue then
        return hudKeyBind:getValue()
    end
    return HUD_TOGGLE_DEFAULT_KEY
end

local function getDwBoundKey()
    if dwKeyBind and dwKeyBind.getValue then
        return dwKeyBind:getValue()
    end
    return DW_TOGGLE_DEFAULT_KEY
end

local function getLedgerBoundKey()
    if ledgerKeyBind and ledgerKeyBind.getValue then
        return ledgerKeyBind:getValue()
    end
    return LEDGER_TOGGLE_DEFAULT_KEY
end

local function getDensityBoundKey()
    if densityKeyBind and densityKeyBind.getValue then
        return densityKeyBind:getValue()
    end
    return DENSITY_TOGGLE_DEFAULT_KEY
end

CSR_UtilityHud = {
    panel = nil,
    -- Item wipe scheduler state (populated by server ItemWipeStatus command)
    itemWipeState = {
        enabled          = false,
        remainingSeconds = nil,   -- seconds remaining at last server update
        serverUpdateTime = 0,     -- os.time() at last server update
        wiping           = false, -- wipe currently in progress
    },
}

local MODDATA_X = "CSRUtilityHudX"
local MODDATA_Y = "CSRUtilityHudY"
local MODDATA_LOCKED = "CSRUtilityHudLocked"
local MODDATA_HIDDEN = "CSRUtilityHudHidden"
local MODDATA_WIDTH = "CSRUtilityHudWidth"
local MODDATA_DW = "CSRDualWieldEnabled"
local PANEL_WIDTH = 220
local PANEL_HEIGHT = 128
local HEADER_HEIGHT = 22
local TOGGLE_ROW_HEIGHT = 24
local LINE_HEIGHT = 16
local STATUS_SCAN_TICKS = 90
local MIN_PANEL_WIDTH = 220
local MAX_PANEL_WIDTH = 360
local CONTENT_PADDING = 10

local function getPlayerSafe()
    return getPlayer and getPlayer() or nil
end

local function getPlayerModData()
    local player = getPlayerSafe()
    return player and player:getModData() or nil
end

local function savePanelState(panel)
    local modData = getPlayerModData()
    if not modData or not panel then
        return
    end

    modData[MODDATA_X] = math.floor(panel:getX())
    modData[MODDATA_Y] = math.floor(panel:getY())
    modData[MODDATA_LOCKED] = panel.locked == true
    if panel.userWidth then
        modData[MODDATA_WIDTH] = panel.userWidth
    end
end

local function defaultX()
    local core = getCore and getCore() or nil
    local screenWidth = core and core:getScreenWidth() or 1280
    return math.max(20, screenWidth - PANEL_WIDTH - 24)
end

local function defaultY()
    return 84
end

local function restorePanelState()
    local modData = getPlayerModData()
    if not modData then
        return defaultX(), defaultY(), false, nil
    end

    return tonumber(modData[MODDATA_X]) or defaultX(),
        tonumber(modData[MODDATA_Y]) or defaultY(),
        modData[MODDATA_LOCKED] == true,
        tonumber(modData[MODDATA_WIDTH]) or nil
end

local function getPlayerCount()
    local data = CSR_PlayerMapTracker and CSR_PlayerMapTracker.playerData or nil
    if type(data) ~= "table" then
        return 0
    end

    return #data
end

local function getZombieDensitySummary()
    local cells = CSR_ZombieDensityOverlay and CSR_ZombieDensityOverlay.cells or nil
    if type(cells) ~= "table" or #cells == 0 then
        return "Zombie Density: --"
    end

    local maxDensity = 0
    local highestAmount = 0
    for i = 1, #cells do
        local cell = cells[i]
        if cell then
            maxDensity = math.max(maxDensity, tonumber(cell.density) or 0)
            highestAmount = math.max(highestAmount, tonumber(cell.amount) or 0)
        end
    end

    local label = "Clear"
    if maxDensity == 1 then
        label = "Low"
    elseif maxDensity == 2 then
        label = "Medium"
    elseif maxDensity >= 3 then
        label = "High"
    end

    return string.format("Zombie Density: %s (%d)", label, highestAmount)
end

local function getFreshnessWarning(player)
    local item = CSR_Utils.findSoonStaleFood and CSR_Utils.findSoonStaleFood(player) or nil
    if not item then
        return nil
    end
    local name = item.getDisplayName and item:getDisplayName() or item:getName() or "Food"
    return "Food: " .. name .. " going stale"
end

local function getDuplicateRepairHint(player)
    if not player then
        return nil
    end

    local inventory = player:getInventory()
    local items = inventory and inventory.getItems and inventory:getItems() or nil
    if not items then
        return nil
    end

    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item and CSR_Utils.isRepairableItem(item) then
            local _, pct = CSR_Utils.findBetterDuplicate(player, item)
            if pct then
                local name = item.getDisplayName and item:getDisplayName() or item:getName() or "Item"
                return string.format("Repair: %s has better dup (%d%%)", name, pct)
            end
        end
    end

    return nil
end

local _vehKeyCache = { counter = 0, value = nil, cached = false }

local function getVehicleKeyStatus(player)
    if not player then
        return nil
    end

    -- Perf: inventory walk is O(n); throttle to roughly every 30 render
    -- frames (~0.5s at 60fps) instead of firing every frame.
    _vehKeyCache.counter = _vehKeyCache.counter + 1
    if _vehKeyCache.cached and _vehKeyCache.counter < 30 then
        return _vehKeyCache.value
    end
    _vehKeyCache.counter = 0
    _vehKeyCache.cached = true

    local inventory = player:getInventory()
    local items = inventory and inventory.getItems and inventory:getItems() or nil
    if not items then
        _vehKeyCache.value = nil
        return nil
    end

    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item and item.getModData then
            local md = item:getModData()
            if md and md.CSR_KeyLabel then
                local v = "Key: " .. tostring(md.CSR_KeyLabel)
                _vehKeyCache.value = v
                return v
            end
        end
    end

    _vehKeyCache.value = nil
    return nil
end

local function getItemWipeCountdown()
    local ws = CSR_UtilityHud.itemWipeState
    if not ws.enabled then return nil end
    if ws.wiping then return "Item Wipe: Running..." end
    if ws.remainingSeconds == nil then return nil end
    -- Interpolate countdown using real elapsed time since last server broadcast
    local elapsed = os.time() - (ws.serverUpdateTime or 0)
    local remaining = math.max(0, ws.remainingSeconds - elapsed)
    local h = math.floor(remaining / 3600)
    local m = math.floor((remaining % 3600) / 60)
    local s = math.floor(remaining % 60)
    if h > 0 then
        return string.format("Item Wipe: %dh %02dm", h, m)
    end
    return string.format("Item Wipe: %dm %02ds", m, s)
end

-- Dirty-cache for status lines: avoid rebuilding/remeasuring every frame
local _statusCache = { lines = {}, width = 0, lastKey = "" }

local function buildStatusKey(player)
    local parts = {}
    if CSR_FeatureFlags.isVisualSoundCuesEnabled() and CSR_SoundCues then
        local p = CSR_SoundCues.isPlayerSourceEnabled and CSR_SoundCues.isPlayerSourceEnabled()
        local z = CSR_SoundCues.isZombieSourceEnabled and CSR_SoundCues.isZombieSourceEnabled()
        local o = CSR_SoundCues.isOtherSourceEnabled and CSR_SoundCues.isOtherSourceEnabled()
        parts[#parts+1] = (p and "1" or "0") .. (z and "1" or "0") .. (o and "1" or "0")
    end
    if CSR_FeatureFlags.isSeatbeltEnabled() and player and player:getVehicle() then
        local enabled = CSR_SeatbeltSystem and CSR_SeatbeltSystem.seatbeltOn
            and CSR_SeatbeltSystem.seatbeltOn[player:getPlayerNum()] == true
        parts[#parts+1] = enabled and "sbon" or "sboff"
    end
    if CSR_FeatureFlags.isPryEnabled() then
        parts[#parts+1] = CSR_Utils.hasCrowbar(player) and "cwr" or "ncw"
    end
    if CSR_FeatureFlags.isPlayerMapTrackingEnabled() then
        parts[#parts+1] = tostring(getPlayerCount())
    end
    if CSR_FeatureFlags.isZombieDensityOverlayEnabled() or CSR_FeatureFlags.isZombieDensityMinimapEnabled() then
        parts[#parts+1] = getZombieDensitySummary() or ""
    end
    parts[#parts+1] = tostring(getFreshnessWarning(player) or "")
    parts[#parts+1] = tostring(getDuplicateRepairHint(player) or "")
    parts[#parts+1] = tostring(getVehicleKeyStatus(player) or "")
    parts[#parts+1] = tostring(getItemWipeCountdown() or "")
    return table.concat(parts, "|")
end

local function getStatusLines(player)
    local lines = {}

    if CSR_FeatureFlags.isVisualSoundCuesEnabled() and CSR_SoundCues then
        local p = CSR_SoundCues.isPlayerSourceEnabled and CSR_SoundCues.isPlayerSourceEnabled()
        local z = CSR_SoundCues.isZombieSourceEnabled and CSR_SoundCues.isZombieSourceEnabled()
        local o = CSR_SoundCues.isOtherSourceEnabled and CSR_SoundCues.isOtherSourceEnabled()
        lines[#lines + 1] = string.format(
            "Sound Filters: %s %s %s",
            p and "P" or "-",
            z and "Z" or "-",
            o and "O" or "-"
        )
    end

    if CSR_FeatureFlags.isSeatbeltEnabled() and player and player:getVehicle() then
        local enabled = CSR_SeatbeltSystem and CSR_SeatbeltSystem.seatbeltOn
            and CSR_SeatbeltSystem.seatbeltOn[player:getPlayerNum()] == true
        lines[#lines + 1] = enabled and "Seatbelt: ON" or "Seatbelt: OFF"
    end

    if CSR_FeatureFlags.isPryEnabled() then
        lines[#lines + 1] = CSR_Utils.hasCrowbar(player) and "Crowbar: Ready" or "Crowbar: Missing"
    end

    if CSR_FeatureFlags.isPlayerMapTrackingEnabled() then
        lines[#lines + 1] = string.format("Tracked Players: %d", getPlayerCount())
    end

    if CSR_FeatureFlags.isZombieDensityOverlayEnabled() or CSR_FeatureFlags.isZombieDensityMinimapEnabled() then
        lines[#lines + 1] = getZombieDensitySummary()
    end

    local foodWarning = getFreshnessWarning(player)
    if foodWarning then
        lines[#lines + 1] = foodWarning
    end

    local repairHint = getDuplicateRepairHint(player)
    if repairHint then
        lines[#lines + 1] = repairHint
    end

    local vehicleKey = getVehicleKeyStatus(player)
    if vehicleKey then
        lines[#lines + 1] = vehicleKey
    end

    local wipeCountdown = getItemWipeCountdown()
    if wipeCountdown then
        lines[#lines + 1] = wipeCountdown
    end

    return lines
end

local function measureLines(lines)
    local tm = getTextManager and getTextManager() or nil
    if not tm then
        return MIN_PANEL_WIDTH
    end

    local widest = MIN_PANEL_WIDTH
    for i = 1, #lines do
        local text = tostring(lines[i] or "")
        local lineWidth = tm:MeasureStringX(UIFont.Small, text) + (CONTENT_PADDING * 2)
        widest = math.max(widest, lineWidth)
    end

    return math.max(MIN_PANEL_WIDTH, math.min(MAX_PANEL_WIDTH, widest))
end

local _fitCache = {}

local function fitLine(text, maxWidth)
    local tm = getTextManager and getTextManager() or nil
    local value = tostring(text or "")
    if not tm or maxWidth <= 0 then
        return value
    end

    local ck = value .. "\0" .. tostring(maxWidth)
    local cached = _fitCache[ck]
    if cached ~= nil then return cached end

    local result
    if tm:MeasureStringX(UIFont.Small, value) <= maxWidth then
        result = value
    else
        local ellipsis = "..."
        local ellipsisWidth = tm:MeasureStringX(UIFont.Small, ellipsis)
        local out = value
        while #out > 0 and (tm:MeasureStringX(UIFont.Small, out) + ellipsisWidth) > maxWidth do
            out = string.sub(out, 1, #out - 1)
        end
        if out == "" then
            result = ellipsis
        else
            result = out .. ellipsis
        end
    end

    _fitCache[ck] = result
    return result
end

local UtilityHudPanel = ISPanel:derive("CSR_UtilityHudPanel")

function UtilityHudPanel:initialise()
    ISPanel.initialise(self)
end

function UtilityHudPanel:createChildren()
    ISPanel.createChildren(self)

    self.lockButton = ISButton:new(self.width - 54, 2, 50, HEADER_HEIGHT - 4, self.locked and "Unlock" or "Lock", self, self.onToggleLock)
    self.lockButton:initialise()
    self.lockButton:instantiate()
    self.lockButton.anchorTop = true
    self.lockButton.anchorRight = true
    self:addChild(self.lockButton)
    CSR_Theme.applyButtonStyle(self.lockButton, "accentBlue", false)

    self.guideButton = ISButton:new(self.width - 76, 2, 18, HEADER_HEIGHT - 4, "?", self, self.onToggleGuide)
    self.guideButton:initialise()
    self.guideButton:instantiate()
    self.guideButton.anchorTop = true
    self.guideButton.anchorRight = true
    self:addChild(self.guideButton)
    CSR_Theme.applyButtonStyle(self.guideButton, "accentViolet", false)

    self.prefsButton = ISButton:new(self.width - 96, 2, 18, HEADER_HEIGHT - 4, "S", self, self.onTogglePrefs)
    self.prefsButton:initialise()
    self.prefsButton:instantiate()
    self.prefsButton.anchorTop   = true
    self.prefsButton.anchorRight = true
    self:addChild(self.prefsButton)
    CSR_Theme.applyButtonStyle(self.prefsButton, "accentViolet", false)

    if CSR_FeatureFlags.isVisualSoundCuesEnabled() and CSR_SoundCues then
        self.soundPlayerButton = ISButton:new(10, HEADER_HEIGHT + 2, 32, 18, "P", self, self.onToggleSoundPlayers)
        self.soundPlayerButton:initialise()
        self.soundPlayerButton:instantiate()
        self:addChild(self.soundPlayerButton)

        self.soundZombieButton = ISButton:new(46, HEADER_HEIGHT + 2, 32, 18, "Z", self, self.onToggleSoundZombies)
        self.soundZombieButton:initialise()
        self.soundZombieButton:instantiate()
        self:addChild(self.soundZombieButton)

        self.soundOtherButton = ISButton:new(82, HEADER_HEIGHT + 2, 32, 18, "O", self, self.onToggleSoundOthers)
        self.soundOtherButton:initialise()
        self.soundOtherButton:instantiate()
        self:addChild(self.soundOtherButton)

        self:updateSoundButtons()
    end

    if CSR_FeatureFlags.isDualWieldEnabled() or (SandboxVars and SandboxVars.CommonSenseReborn and SandboxVars.CommonSenseReborn.EnableDualWield ~= false) then
        local dwX = self.soundOtherButton and 120 or 10
        self.dualWieldButton = ISButton:new(dwX, HEADER_HEIGHT + 2, 32, 18, "DW", self, self.onToggleDualWield)
        self.dualWieldButton:initialise()
        self.dualWieldButton:instantiate()
        self:addChild(self.dualWieldButton)
        self:updateDualWieldButton()

        -- v1.8.1: Emergency Swap toggle (ES). Auto-recovers when the engine
        -- clears the secondary slot and the off-hand weapon is stuck in
        -- inventory with attachedSlot set (the "vanish + unequipable" bug).
        local esX = self.dualWieldButton:getX() + self.dualWieldButton:getWidth() + 4
        self.emergencySwapButton = ISButton:new(esX, HEADER_HEIGHT + 2, 32, 18, "ES", self, self.onToggleEmergencySwap)
        self.emergencySwapButton:initialise()
        self.emergencySwapButton:instantiate()
        self:addChild(self.emergencySwapButton)
        self:updateEmergencySwapButton()
    end

    -- Entry Actions toggle (pry / lockpick / bolt-cut master switch)
    if SandboxVars and SandboxVars.CommonSenseReborn and SandboxVars.CommonSenseReborn.EnableEntryActions ~= false then
        local eaX = 10
        if self.emergencySwapButton then eaX = self.emergencySwapButton:getX() + self.emergencySwapButton:getWidth() + 4
        elseif self.dualWieldButton then eaX = self.dualWieldButton:getX() + self.dualWieldButton:getWidth() + 4 end
        self.entryActionsButton = ISButton:new(eaX, HEADER_HEIGHT + 2, 32, 18, "EA", self, self.onToggleEntryActions)
        self.entryActionsButton:initialise()
        self.entryActionsButton:instantiate()
        self.entryActionsButton:setTooltip("Toggle Pry / Lockpick / Bolt-Cut actions")
        self:addChild(self.entryActionsButton)
        self:updateEntryActionsButton()
    end

    -- Survivor's Ledger toggle button
    if CSR_FeatureFlags.isSurvivorLedgerEnabled() then
        local ldX = 10
        if self.entryActionsButton then
            ldX = self.entryActionsButton:getX() + self.entryActionsButton:getWidth() + 4
        elseif self.emergencySwapButton then
            ldX = self.emergencySwapButton:getX() + self.emergencySwapButton:getWidth() + 4
        elseif self.dualWieldButton then
            ldX = self.dualWieldButton:getX() + self.dualWieldButton:getWidth() + 4
        end
        self.ledgerButton = ISButton:new(ldX, HEADER_HEIGHT + 2, 32, 18, "LD", self, self.onToggleLedger)
        self.ledgerButton:initialise()
        self.ledgerButton:instantiate()
        self:addChild(self.ledgerButton)
        self:updateLedgerButton()
    end

    -- Nearby Density HUD show/hide button (mirrors the X-close on the density widget)
    if CSR_FeatureFlags.isZombieDensityOverlayEnabled and CSR_FeatureFlags.isZombieDensityOverlayEnabled() then
        local dhX = 10
        if self.ledgerButton then
            dhX = self.ledgerButton:getX() + self.ledgerButton:getWidth() + 4
        elseif self.entryActionsButton then
            dhX = self.entryActionsButton:getX() + self.entryActionsButton:getWidth() + 4
        elseif self.emergencySwapButton then
            dhX = self.emergencySwapButton:getX() + self.emergencySwapButton:getWidth() + 4
        elseif self.dualWieldButton then
            dhX = self.dualWieldButton:getX() + self.dualWieldButton:getWidth() + 4
        end
        self.densityHudButton = ISButton:new(dhX, HEADER_HEIGHT + 2, 32, 18, "DH", self, self.onToggleDensityHud)
        self.densityHudButton:initialise()
        self.densityHudButton:instantiate()
        self:addChild(self.densityHudButton)
        self:updateDensityHudButton()
    end

    -- Aim-cursor pill toggles (second toggle row): HP / Ammo / Zeds.
    -- Only shown when the parent Weapon HUD Overlay is enabled.
    if CSR_FeatureFlags.isWeaponHudOverlayEnabled and CSR_FeatureFlags.isWeaponHudOverlayEnabled() then
        local aimRowY = HEADER_HEIGHT + 2 + TOGGLE_ROW_HEIGHT
        local aimX = 10
        local gap = 6
        -- Per-button widths sized to the actual label length so longer text
        -- ("Ammo", "Zeds") doesn't overflow the next button. Previously every
        -- button was 38px wide which let "Ammo" bleed into "Zeds".
        local hpW   = 32
        local ammoW = 48
        local zedsW = 48

        self.aimHpButton = ISButton:new(aimX, aimRowY, hpW, 18, "HP", self, self.onToggleAimHp)
        self.aimHpButton:initialise()
        self.aimHpButton:instantiate()
        self:addChild(self.aimHpButton)

        local ammoX = aimX + hpW + gap
        self.aimAmmoButton = ISButton:new(ammoX, aimRowY, ammoW, 18, "Ammo", self, self.onToggleAimAmmo)
        self.aimAmmoButton:initialise()
        self.aimAmmoButton:instantiate()
        self:addChild(self.aimAmmoButton)

        local zedsX = ammoX + ammoW + gap
        self.aimZedsButton = ISButton:new(zedsX, aimRowY, zedsW, 18, "Zeds", self, self.onToggleAimZeds)
        self.aimZedsButton:initialise()
        self.aimZedsButton:instantiate()
        self:addChild(self.aimZedsButton)

        self:updateAimCursorButtons()
    end

    self.resizeHandle = ISResizeWidget:new(self.width - 10, self.height - 10, 10, 10, self)
    self.resizeHandle:initialise()
    self:addChild(self.resizeHandle)
end

function UtilityHudPanel:onResize()
    local w = math.max(MIN_PANEL_WIDTH, math.min(MAX_PANEL_WIDTH, self.width))
    self.userWidth = w
    self:setWidth(w)
    if self.lockButton then
        self.lockButton:setX(self.width - 54)
    end
    if self.guideButton then
        self.guideButton:setX(self.width - 76)
    end
    if self.prefsButton then
        self.prefsButton:setX(self.width - 96)
    end
    if self.resizeHandle then
        self.resizeHandle:setX(self.width - 10)
        self.resizeHandle:setY(self.height - 10)
    end
    savePanelState(self)
end

function UtilityHudPanel:updateSoundButtons()
    if self.soundPlayerButton and CSR_SoundCues then
        CSR_Theme.applyButtonStyle(self.soundPlayerButton, "accentViolet", CSR_SoundCues.isPlayerSourceEnabled())
    end
    if self.soundZombieButton and CSR_SoundCues then
        CSR_Theme.applyButtonStyle(self.soundZombieButton, "accentGreen", CSR_SoundCues.isZombieSourceEnabled())
    end
    if self.soundOtherButton and CSR_SoundCues then
        CSR_Theme.applyButtonStyle(self.soundOtherButton, "accentAmber", CSR_SoundCues.isOtherSourceEnabled())
    end
end

function UtilityHudPanel:onToggleLock()
    self.locked = not self.locked
    if self.lockButton and self.lockButton.setTitle then
        self.lockButton:setTitle(self.locked and "Unlock" or "Lock")
    elseif self.lockButton then
        self.lockButton.title = self.locked and "Unlock" or "Lock"
    end
    CSR_Theme.applyButtonStyle(self.lockButton, self.locked and "accentAmber" or "accentBlue", self.locked)
    savePanelState(self)
end

function UtilityHudPanel:onToggleGuide()
    if CSR_Guide and CSR_Guide.toggle then
        CSR_Guide.toggle()
    end
end

function UtilityHudPanel:onToggleSoundPlayers()
    if CSR_SoundCues and CSR_SoundCues.togglePlayerSource then
        CSR_SoundCues.togglePlayerSource()
        self:updateSoundButtons()
    end
end

function UtilityHudPanel:onToggleSoundZombies()
    if CSR_SoundCues and CSR_SoundCues.toggleZombieSource then
        CSR_SoundCues.toggleZombieSource()
        self:updateSoundButtons()
    end
end

function UtilityHudPanel:onToggleSoundOthers()
    if CSR_SoundCues and CSR_SoundCues.toggleOtherSource then
        CSR_SoundCues.toggleOtherSource()
        self:updateSoundButtons()
    end
end

function UtilityHudPanel:onToggleDualWield()
    if CSR_FeatureFlags.isAdminAuthoritative() then return end
    CSR_PlayerPrefs.toggle("DualWield")
    self:updateDualWieldButton()
end

function UtilityHudPanel:onToggleEmergencySwap()
    CSR_PlayerPrefs.toggle("DualWieldEmergencySwap")
    self:updateEmergencySwapButton()
end

function UtilityHudPanel:updateEmergencySwapButton()
    if not self.emergencySwapButton then return end
    local enabled = false
    local pref = CSR_PlayerPrefs and CSR_PlayerPrefs._byKey and CSR_PlayerPrefs._byKey["DualWieldEmergencySwap"]
    if pref then enabled = pref.effectiveFn() == true end
    CSR_Theme.applyButtonStyle(self.emergencySwapButton, enabled and "accentGreen" or "accentRed", enabled)
    self.emergencySwapButton:setTooltip(enabled
        and "Dual Wield Emergency Swap: ON\nAuto-recovers stuck off-hand weapons"
        or  "Dual Wield Emergency Swap: OFF")
end

function UtilityHudPanel:onToggleEntryActions()
    CSR_PlayerPrefs.toggle("EntryActions")
    self:updateEntryActionsButton()
end

function UtilityHudPanel:onToggleLedger()
    CSR_PlayerPrefs.toggle("SurvivorLedger")
    self:updateLedgerButton()
end

function UtilityHudPanel:updateLedgerButton()
    if not self.ledgerButton then return end
    local enabled = CSR_FeatureFlags.isSurvivorLedgerEnabled()
    CSR_Theme.applyButtonStyle(self.ledgerButton, enabled and "accentGreen" or "accentRed", enabled)
    self.ledgerButton:setTooltip(enabled and "Survivor's Ledger: ON (Numpad 4)" or "Survivor's Ledger: OFF (Numpad 4)")
end

function UtilityHudPanel:onToggleDensityHud()
    if CSR_NearbyDensityHUD and CSR_NearbyDensityHUD.toggle then
        CSR_NearbyDensityHUD.toggle()
    end
    self:updateDensityHudButton()
end

function UtilityHudPanel:updateDensityHudButton()
    if not self.densityHudButton then return end
    local visible = CSR_NearbyDensityHUD and CSR_NearbyDensityHUD.isVisible and CSR_NearbyDensityHUD.isVisible() or false
    CSR_Theme.applyButtonStyle(self.densityHudButton, visible and "accentGreen" or "accentSlate", visible)
    self.densityHudButton:setTooltip(visible and "Nearby Density HUD: SHOWN (Numpad 0)" or "Nearby Density HUD: HIDDEN (Numpad 0)")
end

function UtilityHudPanel:updateEntryActionsButton()
    if not self.entryActionsButton then return end
    local enabled = CSR_FeatureFlags.isEntryActionsEnabled()
    CSR_Theme.applyButtonStyle(self.entryActionsButton, enabled and "accentGreen" or "accentRed", enabled)
    self.entryActionsButton:setTooltip(enabled and "Entry actions: ON (pry/pick/cut)" or "Entry actions: OFF")
end

function UtilityHudPanel:onToggleAimHp()
    CSR_PlayerPrefs.toggle("AimingHealthCursor")
    self:updateAimCursorButtons()
end

function UtilityHudPanel:onToggleAimAmmo()
    CSR_PlayerPrefs.toggle("AimingAmmoCursor")
    self:updateAimCursorButtons()
end

function UtilityHudPanel:onToggleAimZeds()
    CSR_PlayerPrefs.toggle("AimingDensityCursor")
    self:updateAimCursorButtons()
end

function UtilityHudPanel:updateAimCursorButtons()
    if self.aimHpButton then
        local on = CSR_FeatureFlags.isAimingHealthCursorEnabled()
        CSR_Theme.applyButtonStyle(self.aimHpButton, on and "accentGreen" or "accentRed", on)
        self.aimHpButton:setTooltip(on and "Aim cursor HP pill: ON" or "Aim cursor HP pill: OFF")
    end
    if self.aimAmmoButton then
        local on = CSR_FeatureFlags.isAimingAmmoCursorEnabled()
        CSR_Theme.applyButtonStyle(self.aimAmmoButton, on and "accentGreen" or "accentRed", on)
        self.aimAmmoButton:setTooltip(on and "Aim cursor ammo pill: ON" or "Aim cursor ammo pill: OFF")
    end
    if self.aimZedsButton then
        local on = CSR_FeatureFlags.isAimingDensityCursorEnabled()
        CSR_Theme.applyButtonStyle(self.aimZedsButton, on and "accentGreen" or "accentRed", on)
        self.aimZedsButton:setTooltip(on and "Aim cursor zombie density pill: ON" or "Aim cursor zombie density pill: OFF")
    end
end

function UtilityHudPanel:onTogglePrefs()
    if not CSR_PlayerPrefsPanel then return end
    local hud = CSR_UtilityHud.panel
    local ax  = hud and math.max(4, hud:getX() - 294) or 100
    local ay  = hud and hud:getY() or 84
    CSR_PlayerPrefsPanel.toggle(ax, ay)
end

function UtilityHudPanel:updateDualWieldButton()
    if not self.dualWieldButton then return end
    local locked = CSR_FeatureFlags.isAdminAuthoritative()
    local enabled = CSR_FeatureFlags.isDualWieldEnabled()
    if locked then
        self.dualWieldButton:setTitle("DW \187")
        CSR_Theme.applyButtonStyle(self.dualWieldButton, enabled and "accentGreen" or "accentRed", enabled)
        self.dualWieldButton:setTooltip("Dual wield: admin-controlled")
    else
        self.dualWieldButton:setTitle("DW")
        CSR_Theme.applyButtonStyle(self.dualWieldButton, enabled and "accentGreen" or "accentRed", enabled)
        self.dualWieldButton:setTooltip(nil)
    end
end

function UtilityHudPanel:onMouseDown(x, y)
    if self.locked or y > HEADER_HEIGHT then
        return ISPanel.onMouseDown(self, x, y)
    end

    self.dragging = true
    self.dragX = x
    self.dragY = y
    return true
end

function UtilityHudPanel:onMouseMove(dx, dy)
    if self.dragging then
        local mouseX = getMouseX and getMouseX() or self:getX()
        local mouseY = getMouseY and getMouseY() or self:getY()
        self:setX(mouseX - self.dragX)
        self:setY(mouseY - self.dragY)
        return true
    end

    return ISPanel.onMouseMove(self, dx, dy)
end

function UtilityHudPanel:onMouseMoveOutside(dx, dy)
    if self.dragging then
        local mouseX = getMouseX and getMouseX() or self:getX()
        local mouseY = getMouseY and getMouseY() or self:getY()
        self:setX(mouseX - self.dragX)
        self:setY(mouseY - self.dragY)
        return true
    end

    return ISPanel.onMouseMoveOutside(self, dx, dy)
end

function UtilityHudPanel:onMouseUp(x, y)
    if self.dragging then
        self.dragging = false
        savePanelState(self)
        return true
    end

    return ISPanel.onMouseUp(self, x, y)
end

function UtilityHudPanel:onMouseUpOutside(x, y)
    if self.dragging then
        self.dragging = false
        savePanelState(self)
        return true
    end

    return ISPanel.onMouseUpOutside(self, x, y)
end

function UtilityHudPanel:prerender()
    ISPanel.prerender(self)
    CSR_Theme.drawPanelChrome(self, "CSR Utility", HEADER_HEIGHT)
end

function UtilityHudPanel:render()
    ISPanel.render(self)

    local player = getPlayerSafe()
    if not player or player:isDead() then
        return
    end

    self:updateSoundButtons()
    local cacheKey = buildStatusKey(player)
    if cacheKey ~= _statusCache.lastKey then
        _statusCache.lines = getStatusLines(player)
        _statusCache.width = measureLines(_statusCache.lines)
        _statusCache.lastKey = cacheKey
        -- Invalidate fitLine memo whenever status content changes
        for k in pairs(_fitCache) do _fitCache[k] = nil end
    end
    local lines = _statusCache.lines
    local contentWidth = _statusCache.width
    local targetWidth = self.userWidth and math.max(self.userWidth, contentWidth) or contentWidth
    targetWidth = math.max(MIN_PANEL_WIDTH, math.min(MAX_PANEL_WIDTH, targetWidth))
    if self.width ~= targetWidth then
        self:setWidth(targetWidth)
        if self.lockButton then
            self.lockButton:setX(self.width - 54)
        end
    end
    local extraTop = ((self.soundPlayerButton or self.dualWieldButton) and TOGGLE_ROW_HEIGHT or 0)
    if self.aimHpButton or self.aimAmmoButton or self.aimZedsButton then
        extraTop = extraTop + TOGGLE_ROW_HEIGHT
    end
    local neededHeight = HEADER_HEIGHT + extraTop + 10 + (#lines * LINE_HEIGHT)
    if self.height ~= neededHeight then
        self:setHeight(neededHeight)
    end
    if self.resizeHandle then
        self.resizeHandle:setX(self.width - 10)
        self.resizeHandle:setY(self.height - 10)
    end

    for i = 1, #lines do
        local text = fitLine(lines[i], self.width - (CONTENT_PADDING * 2))
        local color = CSR_Theme.statusColor(text)
        self:drawText(text, CONTENT_PADDING, HEADER_HEIGHT + extraTop + 4 + ((i - 1) * LINE_HEIGHT), color.r, color.g, color.b, color.a or 1.0, UIFont.Small)
    end
end

local function createPanel()
    if CSR_UtilityHud.panel or not CSR_FeatureFlags.isUtilityHudEnabled() then
        return
    end

    local x, y, locked, savedWidth = restorePanelState()
    local initWidth = savedWidth or PANEL_WIDTH
    local panel = UtilityHudPanel:new(x, y, initWidth, PANEL_HEIGHT)
    panel:initialise()
    panel:instantiate()
    panel.anchorLeft = true
    panel.anchorTop = true
    panel.locked = locked
    panel.dragging = false
    panel.userWidth = savedWidth
    panel:addToUIManager()
    if panel.lockButton then
        panel.lockButton.title = panel.locked and "Unlock" or "Lock"
        CSR_Theme.applyButtonStyle(panel.lockButton, panel.locked and "accentAmber" or "accentBlue", panel.locked)
    end

    CSR_UtilityHud.panel = panel

    local modData = getPlayerModData()
    if modData and modData[MODDATA_HIDDEN] == true then
        panel:setVisible(false)
    end
end

local function destroyPanel()
    if not CSR_UtilityHud.panel then
        return
    end

    savePanelState(CSR_UtilityHud.panel)
    CSR_UtilityHud.panel:removeFromUIManager()
    CSR_UtilityHud.panel = nil
end

local function ensurePanel()
    if CSR_FeatureFlags.isUtilityHudEnabled() then
        createPanel()
    else
        destroyPanel()
    end
end

local function onGameStart()
    -- Load all per-player overrides (also migrates legacy DW modData key).
    if CSR_PlayerPrefs then
        CSR_PlayerPrefs.load()
    end

    ensurePanel()
end

local function onCreatePlayer()
    ensurePanel()
end

local function onResolutionChange()
    if not CSR_UtilityHud.panel then
        return
    end

    local core = getCore and getCore() or nil
    if not core then
        return
    end

    local maxX = math.max(0, core:getScreenWidth() - CSR_UtilityHud.panel.width)
    local maxY = math.max(0, core:getScreenHeight() - CSR_UtilityHud.panel.height)
    CSR_UtilityHud.panel:setX(math.max(0, math.min(CSR_UtilityHud.panel:getX(), maxX)))
    CSR_UtilityHud.panel:setY(math.max(0, math.min(CSR_UtilityHud.panel:getY(), maxY)))
    savePanelState(CSR_UtilityHud.panel)
end

local function onKeyPressed(key)
    -- HUD visibility toggle
    if key == getHudBoundKey() and CSR_FeatureFlags.isUtilityHudEnabled() then
        local panel = CSR_UtilityHud.panel
        if panel then
            local visible = panel:getIsVisible()
            panel:setVisible(not visible)
            local modData = getPlayerModData()
            if modData then
                modData[MODDATA_HIDDEN] = visible == true
            end
        end
        return
    end

    -- Dual Wield toggle
    if key == getDwBoundKey() then
        if not CSR_FeatureFlags.isUtilityHudEnabled() then return end
        if CSR_FeatureFlags.isAdminAuthoritative() then return end
        CSR_PlayerPrefs.toggle("DualWield")
        local panel = CSR_UtilityHud.panel
        if panel and panel.updateDualWieldButton then
            panel:updateDualWieldButton()
        end
    end

    -- Survivor's Ledger toggle
    if key == getLedgerBoundKey() then
        if not CSR_FeatureFlags.isSurvivorLedgerEnabled() then return end
        CSR_PlayerPrefs.toggle("SurvivorLedger")
        local panel = CSR_UtilityHud.panel
        if panel and panel.updateLedgerButton then
            panel:updateLedgerButton()
        end
    end

    -- Nearby Density HUD show/hide toggle
    if key == getDensityBoundKey() then
        if not (CSR_FeatureFlags.isZombieDensityOverlayEnabled
                and CSR_FeatureFlags.isZombieDensityOverlayEnabled()) then
            return
        end
        if CSR_NearbyDensityHUD and CSR_NearbyDensityHUD.toggle then
            CSR_NearbyDensityHUD.toggle()
        end
        local panel = CSR_UtilityHud.panel
        if panel and panel.updateDensityHudButton then
            panel:updateDensityHudButton()
        end
    end
end

Events.OnGameStart.Add(onGameStart)
Events.OnCreatePlayer.Add(onCreatePlayer)
Events.OnResolutionChange.Add(onResolutionChange)
if Events.OnKeyPressed then Events.OnKeyPressed.Add(onKeyPressed) end

-- Receive item wipe schedule state from the server
local function onServerCommand(module, command, args)
    if module ~= "CommonSenseReborn" then return end
    if command == "ItemWipeStatus" then
        if not args then return end
        local ws = CSR_UtilityHud.itemWipeState
        ws.enabled          = true
        ws.remainingSeconds = tonumber(args.remainingSeconds) or 0
        ws.serverUpdateTime = os.time()
        ws.wiping           = args.wiping == true
    elseif command == "ItemWipeWarning" then
        if not args then return end
        local secs = tonumber(args.remainingSeconds) or 0
        local h = math.floor(secs / 3600)
        local m = math.floor((secs % 3600) / 60)
        local s = math.floor(secs % 60)
        local timeStr
        if h > 0 then
            timeStr = string.format("%dh %02dm", h, m)
        elseif m > 0 then
            timeStr = string.format("%dm %02ds", m, s)
        else
            timeStr = string.format("%ds", s)
        end
        local msg = string.format("[CSR] Ground item wipe in %s -- pick up loose loot now.", timeStr)
        if processGeneralMessage then
            processGeneralMessage("<RGB:1,0.6,0.2> " .. msg)
        end
        local p = getPlayerSafe()
        if p and p.setHaloNote then
            p:setHaloNote(msg, 255, 170, 50, 220)
        end
    end
end
if Events.OnServerCommand then Events.OnServerCommand.Add(onServerCommand) end

return CSR_UtilityHud
