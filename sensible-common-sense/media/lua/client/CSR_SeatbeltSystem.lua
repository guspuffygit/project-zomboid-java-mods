require "CSR_FeatureFlags"
require "CSR_Theme"

CSR_SeatbeltSystem = {
    seatbeltOn = {},
    -- Pre-crash body part health snapshots keyed by playerNum
    bodyPartsHealthBefore = {},
    -- Flag to track active damage reduction pass
    damageReductionActive = {},
}

local MODDATA_KEY = "CSR_SeatbeltOn"
local DEFAULT_KEY = Keyboard and Keyboard.KEY_ADD or 78
local HUD_PAD_RIGHT = 30
local HUD_PAD_BOTTOM = 80
local DAMAGE_REDUCTION = 0.80  -- 80% crash damage reduced when wearing seatbelt

local options = nil
local seatbeltKeyBind = nil
if PZAPI and PZAPI.ModOptions and PZAPI.ModOptions.create then
    options = PZAPI.ModOptions:create("CommonSenseReborn", "Common Sense Reborn")
    if options and options.addKeyBind then
        seatbeltKeyBind = options:addKeyBind("seatbeltToggle", "Toggle Seatbelt", DEFAULT_KEY)
    end
end

local function getPlayerByIndex(index)
    return getSpecificPlayer and getSpecificPlayer(index) or nil
end

local function getBoundKey()
    if seatbeltKeyBind and seatbeltKeyBind.getValue then
        return seatbeltKeyBind:getValue()
    end
    return DEFAULT_KEY
end

-- =========================================================================
-- Body part health snapshot helpers
-- =========================================================================
local function snapshotBodyPartsHealth(player)
    local bd = player:getBodyDamage()
    if not bd then return nil end
    local parts = bd:getBodyParts()
    if not parts then return nil end
    local snapshot = {}
    for i = 0, parts:size() - 1 do
        local bp = parts:get(i)
        if bp then
            snapshot[bp:getType()] = bp:getHealth()
        end
    end
    return snapshot
end

local function applyDamageReduction(player, beforeSnapshot)
    local bd = player:getBodyDamage()
    if not bd then return end
    if bd:getHealth() <= 0 then return end
    local parts = bd:getBodyParts()
    if not parts then return end

    for i = 0, parts:size() - 1 do
        local bp = parts:get(i)
        if bp then
            local bpType = bp:getType()
            local healthBefore = beforeSnapshot[bpType]
            local healthAfter = bp:getHealth()
            if healthBefore and healthAfter < healthBefore then
                local damage = healthBefore - healthAfter
                local reduced = damage * DAMAGE_REDUCTION
                local restored = math.min(healthBefore, healthAfter + reduced)
                bp:SetHealth(restored)
            end
        end
    end
end

-- Per-tick watcher: continuously snapshot body part health while in vehicle
local function onTickWatchHealth()
    for i = 0, 3 do
        local player = getPlayerByIndex(i)
        if player and player:getVehicle() and not player:isDead() then
            local pNum = player:getPlayerNum()
            if CSR_SeatbeltSystem.seatbeltOn[pNum] and not CSR_SeatbeltSystem.damageReductionActive[pNum] then
                CSR_SeatbeltSystem.bodyPartsHealthBefore[pNum] = snapshotBodyPartsHealth(player)
            end
        end
    end
end

-- Per-tick damage reduction: runs for ONE tick after crash to apply reduction
local function onTickDamageReduction()
    local anyActive = false
    for i = 0, 3 do
        local player = getPlayerByIndex(i)
        if player then
            local pNum = player:getPlayerNum()
            if CSR_SeatbeltSystem.damageReductionActive[pNum] then
                local bd = player:getBodyDamage()
                local healthBefore = player:getModData().CSR_HealthBeforeCrash
                local currentHealth = bd and bd:getHealth() or 0

                if currentHealth ~= healthBefore then
                    -- Damage was applied this tick — restore partial health
                    local snapshot = CSR_SeatbeltSystem.bodyPartsHealthBefore[pNum]
                    if snapshot then
                        applyDamageReduction(player, snapshot)
                    end
                    CSR_SeatbeltSystem.damageReductionActive[pNum] = nil
                    player:getModData().CSR_HealthBeforeCrash = nil
                else
                    anyActive = true
                end
            end
        end
    end
    if not anyActive then
        Events.OnTick.Remove(onTickDamageReduction)
    end
end

-- =========================================================================
-- Damage event: intercepts CARCRASHDAMAGE
-- =========================================================================
local function onPlayerGetDamage(character, damageType, damage)
    if damageType ~= "CARCRASHDAMAGE" then return end
    if not character or not instanceof(character, "IsoPlayer") then return end
    if not CSR_FeatureFlags.isSeatbeltEnabled() then return end

    local pNum = character:getPlayerNum()
    if not CSR_SeatbeltSystem.seatbeltOn[pNum] then return end

    -- Record average health before engine applies damage (same tick)
    local bd = character:getBodyDamage()
    if bd then
        character:getModData().CSR_HealthBeforeCrash = bd:getHealth()
    end

    -- Mark this player for damage reduction on next tick
    CSR_SeatbeltSystem.damageReductionActive[pNum] = true
    Events.OnTick.Add(onTickDamageReduction)
end

local function notifySeatbelt(player, enabled)
    if not player then
        return
    end

    if player.Say then
        player:Say(enabled and "Seatbelt on" or "Seatbelt off")
    end

    if HaloTextHelper and HaloTextHelper.addTextWithArrow then
        local text = enabled and "Seatbelt ON" or "Seatbelt OFF"
        HaloTextHelper.addTextWithArrow(player, text, enabled, enabled and HaloTextHelper.getColorGreen() or HaloTextHelper.getColorRed())
    end

    local emitter = player.getEmitter and player:getEmitter() or nil
    if emitter and emitter.playSound then
        emitter:playSound("LockVehicleDoor")
    end
end

local function setSeatbeltState(player, enabled, silent)
    if not player then
        return
    end

    local pNum = player:getPlayerNum()
    CSR_SeatbeltSystem.seatbeltOn[pNum] = enabled == true
    player:getModData()[MODDATA_KEY] = enabled == true

    if not silent then
        notifySeatbelt(player, enabled == true)
    end
end

local function canUseSeatbelt(player)
    return player and not player:isDead() and player:getVehicle() ~= nil and CSR_FeatureFlags.isSeatbeltEnabled()
end

local function toggleSeatbelt(player)
    if not canUseSeatbelt(player) then
        return
    end

    local pNum = player:getPlayerNum()
    local newState = not (CSR_SeatbeltSystem.seatbeltOn[pNum] == true)
    setSeatbeltState(player, newState, false)
end

local function onKeyPressed(key)
    if key ~= getBoundKey() then
        return
    end

    for i = 0, 3 do
        local player = getPlayerByIndex(i)
        if player and player:getVehicle() then
            toggleSeatbelt(player)
        end
    end
end

local function onEnterVehicle(player)
    if not player or not instanceof(player, "IsoPlayer") then
        return
    end

    local saved = player:getModData()[MODDATA_KEY] == true
    CSR_SeatbeltSystem.seatbeltOn[player:getPlayerNum()] = saved
end

local function onExitVehicle(player)
    if not player or not instanceof(player, "IsoPlayer") then
        return
    end

    local pNum = player:getPlayerNum()
    setSeatbeltState(player, false, true)
    CSR_SeatbeltSystem.bodyPartsHealthBefore[pNum] = nil
    CSR_SeatbeltSystem.damageReductionActive[pNum] = nil
end

local function onCreatePlayer(index, player)
    if not player then
        return
    end

    local saved = player:getModData()[MODDATA_KEY] == true
    CSR_SeatbeltSystem.seatbeltOn[player:getPlayerNum()] = saved and player:getVehicle() ~= nil
end

local function onPlayerDeath(player)
    if not player or not instanceof(player, "IsoPlayer") then
        return
    end

    local pNum = player:getPlayerNum()
    CSR_SeatbeltSystem.seatbeltOn[pNum] = false
    CSR_SeatbeltSystem.bodyPartsHealthBefore[pNum] = nil
    CSR_SeatbeltSystem.damageReductionActive[pNum] = nil
end

local function onPlayerUpdate(player)
    if not player or not instanceof(player, "IsoPlayer") then
        return
    end

    local pNum = player:getPlayerNum()
    if CSR_SeatbeltSystem.seatbeltOn[pNum] == true and player:getVehicle() == nil then
        setSeatbeltState(player, false, true)
        CSR_SeatbeltSystem.bodyPartsHealthBefore[pNum] = nil
    end
end

local function drawSeatbeltHud()
    if CSR_FeatureFlags.isUtilityHudEnabled() then
        return
    end

    local player = getPlayer and getPlayer() or nil
    if not player or player:isDead() or not player:getVehicle() then
        return
    end

    local tm = getTextManager and getTextManager() or nil
    if not tm then
        return
    end

    local font = UIFont.Small
    local pNum = player:getPlayerNum()
    local enabled = CSR_SeatbeltSystem.seatbeltOn[pNum] == true
    local text = enabled and "Seatbelt: ON" or "Seatbelt: OFF"
    local width = tm:MeasureStringX(font, text)
    local height = tm:getFontHeight(font)
    local x = getCore():getScreenWidth() - HUD_PAD_RIGHT - width - 16
    local y = getCore():getScreenHeight() - HUD_PAD_BOTTOM - height

    tm:DrawString(font, x - 6, y - 2, "                ", 0, 0, 0, 0)

    if ISUIElement and ISUIElement.drawRectStatic then
        local bg = CSR_Theme.withAlpha(CSR_Theme.getColor("panelBg"), 0.72)
        local border = CSR_Theme.withAlpha(CSR_Theme.getColor("panelBorder"), 0.85)
        local accent = enabled and CSR_Theme.getColor("accentGreen") or CSR_Theme.getColor("accentRed")
        ISUIElement.drawRectStatic(x - 8, y - 2, width + 16, height + 4, bg.a, bg.r, bg.g, bg.b)
        ISUIElement.drawRectStatic(x - 8, y - 2, 4, height + 4, 0.95, accent.r, accent.g, accent.b)
        if ISUIElement.drawRectBorderStatic then
            ISUIElement.drawRectBorderStatic(x - 8, y - 2, width + 16, height + 4, border.a, border.r, border.g, border.b)
        end
    end

    local textColor = CSR_Theme.getColor("text")
    tm:DrawString(font, x, y, text, textColor.r, textColor.g, textColor.b, 1.0)
end

if Events then
    -- v1.8.7 (Phoenix II perf gating): defer event registration to OnGameStart
    -- so we can read the sandbox feature flag. When the seatbelt system is
    -- disabled, none of these handlers (notably the per-frame OnTick health
    -- watch and OnPlayerUpdate) are ever attached, dropping the per-tick cost
    -- to zero.
    local _csrSeatbeltRegistered = false
    local function csrEnsureSeatbeltRegistered()
        if _csrSeatbeltRegistered then return end
        if not (CSR_FeatureFlags and CSR_FeatureFlags.isSeatbeltEnabled
            and CSR_FeatureFlags.isSeatbeltEnabled()) then return end
        _csrSeatbeltRegistered = true
        if Events.OnKeyPressed then Events.OnKeyPressed.Add(onKeyPressed) end
        if Events.OnEnterVehicle then Events.OnEnterVehicle.Add(onEnterVehicle) end
        if Events.OnExitVehicle then Events.OnExitVehicle.Add(onExitVehicle) end
        if Events.OnCreatePlayer then Events.OnCreatePlayer.Add(onCreatePlayer) end
        if Events.OnPlayerDeath then Events.OnPlayerDeath.Add(onPlayerDeath) end
        if Events.OnPlayerUpdate then Events.OnPlayerUpdate.Add(onPlayerUpdate) end
        if Events.OnPostUIDraw then Events.OnPostUIDraw.Add(drawSeatbeltHud) end
        if Events.OnPlayerGetDamage then Events.OnPlayerGetDamage.Add(onPlayerGetDamage) end
        if Events.OnTick then Events.OnTick.Add(onTickWatchHealth) end
    end
    if Events.OnGameStart then Events.OnGameStart.Add(csrEnsureSeatbeltRegistered) end
end

return CSR_SeatbeltSystem
