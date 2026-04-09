LifeBoard = {}
LifeBoard.board = {}

LifeBoard.UpdateClients = function ()
    print("Lifeboard is now updating clients...")
    local onlinePlayers = getOnlinePlayers()
    for i = 1, onlinePlayers:size() do
        local player = onlinePlayers:get(i - 1)

        if player then
            sendServerCommand(player, "Lifeboard", "UpdateBoard", {})
        end
    end
end

LifeBoard.AddPlayer = function(playerObj)
    if not playerObj then return end
    local playerUsername = playerObj:getUsername()
    local playerValues = {displayName = playerUsername, dayCount = 0}
    table.insert(LifeBoard.board, playerValues)
    print("Player "..playerUsername.." has been added to the Lifeboard!")
    LifeBoard.UpdateClients()
end

LifeBoard.Refresh = function(playerObj)
    local playerUsername = playerObj:getUsername()
    if LifeBoard.board then
        for _,player in ipairs(LifeBoard.board) do
            if player.displayName == playerUsername then
                LifeBoard.UpdateClients()
                return
            end
        end
    end
end

LifeBoard.Increment = function(playerObj, daysSurvived)
    if not playerObj then return end
    local playerUsername = playerObj:getUsername()

    if LifeBoard.board then
        for _,player in ipairs(LifeBoard.board) do
            if player.displayName == playerUsername then
                player.dayCount = daysSurvived
                LifeBoard.UpdateClients()
                return
            end
        end
    end
end

LifeBoard.DeleteEntry = function(entry)
    if not entry then return end

    if(entry == "All") then
        for k,v in pairs(LifeBoard.board) do
            LifeBoard.board[k] = nil
          end
        print("The Lifeboard has been erased by an Admin.")
    elseif LifeBoard.board then
        for i,player in ipairs(LifeBoard.board) do
            if player.displayName == entry.displayName then
                player.dayCount = 0
                table.remove(LifeBoard.board, i)
                print("Player "..entry.displayName.."'s Lifeboard entry has been erased by an Admin.")
            end
        end
    end

    LifeBoard.UpdateClients()
end

local function onClientCommand(module, command, playerObj, args)
    if module ~= "Lifeboard" then return end

    if command == "AddPlayer" then
        LifeBoard.AddPlayer(playerObj)
    end

    if command == "Refresh" then
        LifeBoard.Refresh(playerObj)
    end

    if command == "Increment" then
        LifeBoard.Increment(playerObj, args.daysSurvived)
    end

    if command == "DeleteEntry" then
        LifeBoard.DeleteEntry(args.player)
    end

    if command == "DeleteAllEntries" then
        LifeBoard.DeleteEntry("All")
    end
end

local function onInitGlobalModData(isNewGame)
    LifeBoard.board = ModData.getOrCreate("LifeBoard.board")
end

Events.OnClientCommand.Add(onClientCommand)
Events.OnInitGlobalModData.Add(onInitGlobalModData)
