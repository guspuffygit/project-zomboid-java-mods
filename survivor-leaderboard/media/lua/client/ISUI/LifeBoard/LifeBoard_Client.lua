LifeBoard = LifeBoard or {}
LifeBoard.board = LifeBoard.board or {}

local timer = 0
local cooldown = nil

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
        if not canceled then func() end
    end

    Events.OnTick.Add(onTick)
    return function()
        canceled = true
    end
end


local function onLoadCharacter()
	if not getWorld():getGameMode() == "Multiplayer" then return end

	BravensUtilsLB.DelayFunction(function()
		-- Always tell the server we're here. The server decides whether to insert
		-- a new row or just re-broadcast, and replies with the authoritative board
		-- via the UpdateBoard server command handled in LifeBoard_UI.lua.
		sendClientCommand(getPlayer(), "Lifeboard", "AddPlayer", {})
	end, 300)
end

local function everyMinute()
    if not cooldown then return end
    timer = timer + 1

    if timer >= cooldown then
		local playerObj = getPlayer()
		sendClientCommand(playerObj, "Lifeboard", "Increment", {daysSurvived = getDaysSurvived(playerObj), zombieKills = getZombieKills(playerObj)})
        timer = 0
    end
end

local function onInitGlobalModData(isNewGame)
	if not isClient() then return end

    if SandboxVars.Lifeboard then
        cooldown = SandboxVars.Lifeboard.Cooldown or 60
    else
        cooldown = 60
    end

    Events.EveryOneMinute.Add(everyMinute)
end

Events.OnInitGlobalModData.Add(onInitGlobalModData)
Events.OnCreatePlayer.Add(onLoadCharacter)
