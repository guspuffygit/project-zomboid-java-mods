require("ATFCombatHealth/KeyBinding")
require("ATFCombatHealth/HUD")
require("ATFCombatHealth/HealthOpener")
require("ISUI/ISEquippedItem")
local H = ATFCombatHealth
if H.clientInstalled then
    return
end
H.clientInstalled = true
function H.bindHealthButton(sidebar)
    local health = sidebar and sidebar.healthBtn
    if not health or health.atfCombatHealthBound then
        return
    end
    health.atfCombatHealthBound = true
    local originalRight = health.onRightMouseUp
    health.onRightMouseUp = function(button, ...)
        if originalRight then
            originalRight(button, ...)
        end
        local panel = H.ensure(sidebar.chr)
        if not panel then
            return false
        end
        local menu = ISContextMenu.get(sidebar.playerNum, getMouseX(), getMouseY())
        local option = menu:addOption(getText("UI_ATFCombatHealth_Title"), nil, function()
            H.toggle(sidebar.playerNum)
        end)
        menu:setOptionChecked(option, panel.prefs.enabled)
        menu:addOption(getText("UI_ATFCombatHealth_Options"), nil, function()
            panel:options()
        end)
        return true
    end
end
-- B42 creates the sidebar buttons in initialise(), after createChildren().
local initialise = ISEquippedItem.initialise
function ISEquippedItem:initialise(...)
    initialise(self, ...)
    H.bindHealthButton(self)
end
local function bindExistingSidebar()
    H.bindHealthButton(ISEquippedItem.instance)
end
bindExistingSidebar()
Events.OnGameStart.Add(function()
    bindExistingSidebar()
    ATFPlayerMiniHUDTelemetry.installYoga()
    for num = 0, 3 do
        ATFPlayerMiniHUDHealthOpener.bind(num)
        H.ensure(getSpecificPlayer(num))
    end
end)
Events.OnCreatePlayer.Add(function(num, player)
    bindExistingSidebar()
    ATFPlayerMiniHUDHealthOpener.bind(num)
    H.ensure(player or getSpecificPlayer(num))
end)
Events.OnPlayerUpdate.Add(function(player)
    local panel = H.ensure(player)
    if panel then
        local now = getTimestampMs()
        if now - panel.lastBind >= 1000 then
            panel.lastBind = now
            ATFPlayerMiniHUDHealthOpener.bind(player:getPlayerNum())
        end
        panel:sample(now)
    end
end)
Events.OnPlayerDeath.Add(function(player)
    local num = player:getPlayerNum()
    local panel = H.panels[num]
    if panel and panel.player == player then
        H.release(panel, true)
    end
end)
Events.OnDisconnect.Add(H.cleanup)
Events.AddXP.Add(function(player, perk, amount)
    local panel = player and H.panels[player:getPlayerNum()]
    if panel and panel.player == player and panel.prefs.enabled and panel.prefs.showXP then
        ATFPlayerMiniHUDTelemetry.onXP(panel.telemetry, player, perk, amount, getTimestampMs())
    end
end)
Events.OnKeyPressed.Add(function(key)
    local bound = getCore():getKey("ATFCombatHealthToggle")
    if bound and bound > 0 and key == bound and not getCore():isDoingTextEntry() then
        H.toggle(0)
    end
end)
