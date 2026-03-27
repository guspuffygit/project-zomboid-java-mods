if not isClient() and isServer() then
    return
end

AVCS = AVCS or {}
AVCS.SafehouseAccessCache = AVCS.SafehouseAccessCache or {}
AVCS.SafehouseAccessCache.version = AVCS.SafehouseAccessCache.version or 0
AVCS.SafehouseAccessCache.access = AVCS.SafehouseAccessCache.access or {}

local syncRequested = false

local function onServerCommand(moduleName, command, args)
    if moduleName ~= "AVCSSafehouse" then return end
    if command == "sync" and args.access then
        AVCS.SafehouseAccessCache.access = {}
        for owner, playerList in pairs(args.access) do
            AVCS.SafehouseAccessCache.access[owner] = {}
            for i = 1, #playerList do
                table.insert(AVCS.SafehouseAccessCache.access[owner], playerList[i])
            end
        end
        AVCS.SafehouseAccessCache.version = AVCS.SafehouseAccessCache.version + 1
    end
end

local function requestSync()
    if syncRequested then return end
    syncRequested = true
    sendClientCommand(getPlayer(), "AVCSSafehouse", "requestSync", {})
end

function AVCS.addSafehouseAccess(allowedUsername)
    sendClientCommand(getPlayer(), "AVCSSafehouse", "addAccess", { allowedUsername = allowedUsername })
end

function AVCS.removeSafehouseAccess(allowedUsername)
    sendClientCommand(getPlayer(), "AVCSSafehouse", "removeAccess", { allowedUsername = allowedUsername })
end

Events.OnServerCommand.Add(onServerCommand)
Events.OnGameStart.Add(requestSync)
