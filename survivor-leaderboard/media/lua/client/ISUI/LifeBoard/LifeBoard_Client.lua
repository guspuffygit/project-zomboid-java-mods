local timer = 0
local cooldown = nil

local function getDaysSurvived(playerObj)
    local daysSurvived = math.floor(playerObj:getHoursSurvived() / 24)
    return daysSurvived or "Error"
end

local function onLoadCharacter()
	if not getWorld():getGameMode() == "Multiplayer" then return end

	BravensUtilsLB.DelayFunction(function()
		if not LifeBoard.board then return end

		local playerUsername = getPlayer():getUsername()
		for i,player in ipairs(LifeBoard.board) do
			if player.displayName == playerUsername then
				sendClientCommand(getPlayer(), "Lifeboard", "Refresh", {})
				return
			end
		end

		sendClientCommand(getPlayer(), "Lifeboard", "AddPlayer", {})
	end, 300)
end

local function everyMinute()
    if not cooldown then return end
    timer = timer + 1

    if timer >= cooldown then
        if not LifeBoard.board then return end
		local playerObj = getPlayer()
		sendClientCommand(playerObj, "Lifeboard", "Increment", {daysSurvived = getDaysSurvived(playerObj)})
        timer = 0
    end
end

local function onInitGlobalModData(isNewGame)
	if not isClient() then return end

	if ModData.exists("LifeBoard.board") then
		ModData.remove("LifeBoard.board")
	end

	LifeBoard.board = ModData.getOrCreate("LifeBoard.board")
	ModData.request("LifeBoard.board")

    if SandboxVars.Lifeboard then
        cooldown = SandboxVars.Lifeboard.Cooldown or 60
    else
        cooldown = 60
    end

    Events.EveryOneMinute.Add(everyMinute)
end

local function onReceiveGlobalModData(modDataName, data)
    if modDataName ~= "LifeBoard.board" then return end
	if not (LifeBoard.board and type(data) == "table") then return end

    for key, value in pairs(data) do
        LifeBoard.board[key] = value
    end
end

Events.OnInitGlobalModData.Add(onInitGlobalModData)
Events.OnReceiveGlobalModData.Add(onReceiveGlobalModData)
Events.OnCreatePlayer.Add(onLoadCharacter)