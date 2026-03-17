if not isServer() then return end

require "ZoneMarkerShared"

---@type string
local MODULE = ZoneMarkerShared.MODULE
---@type string
local MODDATA_KEY = ZoneMarkerShared.MODDATA_KEY

print("[ZoneMarker] Server Lua loaded")

-- Initialize empty ModData structure on first server start
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
-- Handle client sync requests
--

---@param module string
---@param command string
---@param player IsoPlayer
---@param args table
local function onClientCommand(module, command, player, args)
    print("[ZoneMarker] onClientCommand: module=" .. tostring(module) .. " command=" .. tostring(command))
    if module ~= MODULE then return end
    if command == "requestSync" then
        print("[ZoneMarker] handling requestSync")
        local data = ModData.getOrCreate(MODDATA_KEY)
        local syncArgs = {}
        syncArgs.categories = data.categories or {}
        syncArgs.zones = data.zones or {}
        sendServerCommand(player, MODULE, "sync", syncArgs)
    end
end

Events.OnClientCommand.Add(onClientCommand)
