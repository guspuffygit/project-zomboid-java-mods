LifeBoard = LifeBoard or {}
LifeBoard.board = LifeBoard.board or {}

local timer = 0
local cooldown = nil

-- In-game minutes since the board was last requested from the server; nil = never.
-- LifeBoard_UI.lua consults this on open so repeated opens inside the Update
-- Frequency window reuse the cached board instead of re-requesting.
local minutesSinceRefresh = nil

function LifeBoard.shouldRefresh()
    if minutesSinceRefresh == nil then
        return true
    end
    return minutesSinceRefresh >= (cooldown or 60)
end

function LifeBoard.markRefreshed()
    minutesSinceRefresh = 0
end

local function getDaysSurvived(playerObj)
    local daysSurvived = math.floor(playerObj:getHoursSurvived() / 24)
    return daysSurvived or "Error"
end

local function getZombieKills(playerObj)
    return playerObj:getZombieKills() or 0
end

BravensUtilsLB = {}

BravensUtilsLB.DelayFunction = function(func, delay)
    delay = delay or 1
    local ticks = 0
    local canceled = false

    local function onTick()
        if not canceled and ticks < delay then
            ticks = ticks + 1
            return
        end

        Events.OnTick.Remove(onTick)
        if not canceled then
            func()
        end
    end

    Events.OnTick.Add(onTick)
    return function()
        canceled = true
    end
end

local function onLoadCharacter()
    if getWorld():getGameMode() ~= "Multiplayer" then
        return
    end

    BravensUtilsLB.DelayFunction(function()
        -- Tell the server we're here so it can insert our row if needed. The board
        -- itself is only fetched when the player opens the UI (see LifeBoard_UI.lua).
        sendClientCommand(getPlayer(), "Lifeboard", "AddPlayer", {})
    end, 300)
end

local function everyMinute()
    if minutesSinceRefresh ~= nil then
        minutesSinceRefresh = minutesSinceRefresh + 1
    end
    if not cooldown then
        return
    end
    timer = timer + 1

    if timer >= cooldown then
        local playerObj = getPlayer()
        sendClientCommand(
            playerObj,
            "Lifeboard",
            "Increment",
            { daysSurvived = getDaysSurvived(playerObj), zombieKills = getZombieKills(playerObj) }
        )
        timer = 0
    end
end

local function onInitGlobalModData(isNewGame)
    if not isClient() then
        return
    end

    if SandboxVars.Lifeboard then
        cooldown = SandboxVars.Lifeboard.Cooldown or 60
    else
        cooldown = 60
    end

    Events.EveryOneMinute.Add(everyMinute)
end

Events.OnInitGlobalModData.Add(onInitGlobalModData)
Events.OnCreatePlayer.Add(onLoadCharacter)
