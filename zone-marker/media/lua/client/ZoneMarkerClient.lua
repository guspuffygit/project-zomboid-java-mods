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
ZoneMarkerCache = {
    categories = {},
    zones = {},
}

--
-- Receive zone data from server
--

---@param module string
---@param command string
---@param args? table
local function onServerCommand(module, command, args)
    print("[ZoneMarker] onServerCommand: module=" .. tostring(module) .. " command=" .. tostring(command))
    if module ~= MODULE then return end
    if command == "sync" and args then
        print("[ZoneMarker] sync received, args type=" .. type(args))
        print("[ZoneMarker] args.categories type=" .. type(args.categories) .. " args.zones type=" .. type(args.zones))
        if args.categories then
            print("[ZoneMarker] categories count=" .. tostring(#args.categories))
            for i, cat in ipairs(args.categories) do
                print("[ZoneMarker]   cat " .. i .. ": name=" .. tostring(cat.name))
            end
        end
        ZoneMarkerCache.categories = args.categories or {}
        ZoneMarkerCache.zones = args.zones or {}
        print("[ZoneMarker] cache updated: " .. #ZoneMarkerCache.categories .. " categories")
    end
end

Events.OnServerCommand.Add(onServerCommand)

--
-- Request sync on game start
--

local function requestSync()
    print("[ZoneMarker] requesting sync from server")
    sendClientCommand(getPlayer(), MODULE, "requestSync", nil)
    Events.OnTick.Remove(requestSync)
end

Events.OnTick.Add(requestSync)
