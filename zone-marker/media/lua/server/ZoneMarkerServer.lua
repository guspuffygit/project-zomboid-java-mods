if not isServer() then return end

require "ZoneMarkerShared"

---@type string
local MODULE = ZoneMarkerShared.MODULE
---@type string
local MODDATA_KEY = ZoneMarkerShared.MODDATA_KEY

print("[ZoneMarker] Server Lua loaded")

--- Initialize empty ModData structure on first server start
---@return nil
local function onServerStarted()
    local data = ModData.getOrCreate(MODDATA_KEY)
    if not data.categories then
        data.categories = {}
    end
    if not data.zones then
        data.zones = {}
    end
end

Events.OnServerStarted.Add(onServerStarted)

--
-- Helpers
--

--- Broadcast current zone data to all connected clients
---@return nil
local function broadcastSync()
    local data = ModData.getOrCreate(MODDATA_KEY)
    local syncArgs = {}
    syncArgs.categories = data.categories or {}
    syncArgs.zones = data.zones or {}
    sendServerCommand(MODULE, "sync", syncArgs)
end

--- Send sync to a specific player
---@param player IsoPlayer
local function sendSyncToPlayer(player)
    local data = ModData.getOrCreate(MODDATA_KEY)
    local syncArgs = {}
    syncArgs.categories = data.categories or {}
    syncArgs.zones = data.zones or {}
    sendServerCommand(player, MODULE, "sync", syncArgs)
end

--- Find category index by name
---@param data ZoneMarkerData
---@param name string
---@return number|nil index
local function findCategoryIndex(data, name)
    for i, cat in ipairs(data.categories) do
        if cat.name == name then
            return i
        end
    end
    return nil
end

--
-- Handle client commands
--

---@param module string
---@param command string
---@param player IsoPlayer
---@param args table
local function onClientCommand(module, command, player, args)
    if module ~= MODULE then return end

    if command == "requestSync" then
        print("[ZoneMarker] handling requestSync")
        sendSyncToPlayer(player)
        return
    end

    local data = ModData.getOrCreate(MODDATA_KEY)

    if command == "addCategory" then
        if not args or not args.name or args.name == "" then return end
        if not ZoneMarkerShared.isValidColor(args.r, args.g, args.b, args.a) then return end
        if findCategoryIndex(data, args.name) then return end
        table.insert(data.categories, {
            name = args.name,
            r = args.r,
            g = args.g,
            b = args.b,
            a = args.a or 1.0,
        })
        if not data.zones[args.name] then
            data.zones[args.name] = {}
        end
        print("[ZoneMarker] added category: " .. args.name)
        broadcastSync()

    elseif command == "removeCategory" then
        if not args or not args.name then return end
        local idx = findCategoryIndex(data, args.name)
        if not idx then return end
        table.remove(data.categories, idx)
        data.zones[args.name] = nil
        print("[ZoneMarker] removed category: " .. args.name)
        broadcastSync()

    elseif command == "addZone" then
        if not args or not args.category or not args.name then return end
        if not findCategoryIndex(data, args.category) then return end
        if not args.xStart or not args.yStart or not args.xEnd or not args.yEnd then return end
        if not data.zones[args.category] then
            data.zones[args.category] = {}
        end
        table.insert(data.zones[args.category], {
            xStart = args.xStart,
            yStart = args.yStart,
            xEnd = args.xEnd,
            yEnd = args.yEnd,
            region = args.name,
        })
        print("[ZoneMarker] added zone: " .. args.name .. " to " .. args.category)
        broadcastSync()

    elseif command == "removeZone" then
        if not args or not args.category or not args.name then return end
        local zones = data.zones[args.category]
        if not zones then return end
        for i, zone in ipairs(zones) do
            if zone.region == args.name then
                table.remove(zones, i)
                print("[ZoneMarker] removed zone: " .. args.name .. " from " .. args.category)
                broadcastSync()
                return
            end
        end
    end
end

Events.OnClientCommand.Add(onClientCommand)
