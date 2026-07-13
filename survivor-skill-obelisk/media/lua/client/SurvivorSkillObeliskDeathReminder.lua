--
-- SurvivorSkillObeliskDeathReminder.lua
-- On the local player's death, pop a modal reminding them their perks can be
-- partially recovered at an obelisk. Suppressed when server-side skill recovery
-- is off (RecoverSkills=false or SkillRecoveryPercent=0) so the promise matches
-- what the server will actually restore.
--

require("ISUI/ISModalRichText")

local VISIBILITY_NONE = 3

local function readSandbox()
    return SandboxVars and SandboxVars.SkillObelisk or nil
end

local function getRecoveryPercent(sv)
    local percent = sv and sv.SkillRecoveryPercent
    if type(percent) ~= "number" then
        return 100
    end
    if percent < 0 then
        return 0
    end
    if percent > 100 then
        return 100
    end
    return math.floor(percent + 0.5)
end

local function obelisksShownOnMap(sv)
    local mode = sv and sv.MapObeliskVisibility
    if type(mode) ~= "number" then
        return true
    end
    return mode ~= VISIBILITY_NONE
end

local function buildText(percent, mapMention)
    local where = mapMention and "that you can find on the map" or "hidden across the world"
    -- ISRichTextPanel drops whitespace adjacent to <RGB:...> tags; force real
    -- spaces around the coloured percent with explicit <SPACE> tags.
    return string.format(
        " <CENTRE> <SIZE:medium> Return to an obelisk %s <LINE> to recover <SPACE> <RGB:1,0.85,0.35> %d%% <RGB:1,1,1> <SPACE> of your skills!",
        where,
        percent
    )
end

local function onPlayerDeath(player)
    if player == nil then
        return
    end
    local sv = readSandbox()
    if sv and sv.RecoverSkills == false then
        return
    end
    local percent = getRecoveryPercent(sv)
    if percent <= 0 then
        return
    end

    local playerNum = player:getPlayerNum() or 0
    local text = buildText(percent, obelisksShownOnMap(sv))
    local width = 480
    local height = 160
    local screenLeft = getPlayerScreenLeft(playerNum)
    local screenTop = getPlayerScreenTop(playerNum)
    local screenW = getPlayerScreenWidth(playerNum)
    local screenH = getPlayerScreenHeight(playerNum)
    local x = screenLeft + math.floor((screenW - width) / 2)
    local y = screenTop + math.floor(screenH * 0.18)

    local modal = ISModalRichText:new(x, y, width, height, text, false, nil, nil, playerNum)
    modal.alwaysOnTop = true
    modal:initialise()
    modal:addToUIManager()
    modal:setHeightToContents()
    modal:bringToTop()

    -- ISPostDeathUI grabs joypad focus during OnPlayerDeath; take it over so
    -- controller players can dismiss the modal with A, then it restores focus
    -- back to the death panel on close.
    local joypad = JoypadState.players and JoypadState.players[playerNum + 1]
    if joypad then
        modal.prevFocus = joypad.focus
        setJoypadFocus(playerNum, modal)
    end
end

Events.OnPlayerDeath.Add(onPlayerDeath)
