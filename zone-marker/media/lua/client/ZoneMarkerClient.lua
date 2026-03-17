if isServer() then return end

require "ZoneMarkerShared"

---@type string
local MODULE = ZoneMarkerShared.MODULE

--
-- Zone cache (populated from server via sendServerCommand)
--

---@class ZoneMarkerCacheTable
---@field categories ZoneMarkerCategory[]
---@field zones table<string, ZoneMarkerZone[]>
---@field version integer Incremented on each sync; used by UI to detect changes
---@field _onServerCommand fun(module: string, command: string, args?: table)|nil Stored for reload cleanup

-- Preserve cache across reloads
if not ZoneMarkerCache then
    ---@type ZoneMarkerCacheTable
    ZoneMarkerCache = {
        categories = {},
        zones = {},
        version = 0,
    }
end

--
-- Receive zone data from server
--

-- Remove previous handler on reload to avoid duplicates
if ZoneMarkerCache._onServerCommand then
    Events.OnServerCommand.Remove(ZoneMarkerCache._onServerCommand)
end

---@param module string
---@param command string
---@param args? table
local function onServerCommand(module, command, args)
    if module ~= MODULE then return end
    if command == "sync" and args then
        ZoneMarkerCache.categories = args.categories or {}
        ZoneMarkerCache.zones = args.zones or {}
        ZoneMarkerCache.version = ZoneMarkerCache.version + 1
        print("[ZoneMarker] cache updated: " .. #ZoneMarkerCache.categories .. " categories")
    end
end

ZoneMarkerCache._onServerCommand = onServerCommand
Events.OnServerCommand.Add(onServerCommand)

--
-- Request sync on game start (and on reload)
--

local function requestSync()
    print("[ZoneMarker] requesting sync from server")
    sendClientCommand(getPlayer(), MODULE, "requestSync", nil)
    Events.OnTick.Remove(requestSync)
end

Events.OnTick.Add(requestSync)
