require("AdminCore/WindowSizing")
local T = AdminCore
T.stats = T.stats or {}
T.statsQueue = {}
local lastSend = 0
local requested, cacheCount = {}, 0
function T.requestStats()
    T.statsRefreshRequested = true
end

function T.visibleStatNames(now)
    local names, seen = {}, {}
    if not T.allowed(Capability.ReadUserLog) then
        return names
    end
    local function collect(panel, list, directory)
        if not panel or not list or (panel.getIsVisible and not panel:getIsVisible()) then
            return
        end
        local rowHeight = math.max(1, list.itemheight or 60)
        local first = math.max(1, math.floor(-(list:getYScroll() or 0) / rowHeight) + 1)
        local last = math.min(#list.items, first + math.ceil(list.height / rowHeight) + 1)
        for i = first, last do
            local row = list.items[i].item
            local name = directory and row.username or row:getUsername()
            local data = T.stats[name]
            if
                #names < 50
                and not seen[name]
                and (not requested[name] or now - requested[name] >= 10000)
                and (T.statsRefreshRequested or not data or now - (data.receivedAt or 0) >= 30000)
            then
                names[#names + 1] = name
                seen[name] = true
            end
        end
    end
    local users = ISUsersList and ISUsersList.instance
    collect(users, users and users.datas, false)
    collect(T.directoryPanel, T.directoryPanel and T.directoryPanel.list, true)
    T.statsRefreshRequested = false
    return names
end
local function onServer(mod, command, args)
    if mod ~= "UniversalAdminCore" or not args then
        return
    end
    if command == "stats" then
        for _, row in ipairs(args.rows or {}) do
            if not T.stats[row.username] then
                cacheCount = cacheCount + 1
            end
            row.receivedAt = getTimestampMs()
            T.stats[row.username] = row
        end
        if T.directoryPanel then
            T.directoryPanel:populate()
        end
    elseif command == "result" then
        T.message(args.message or "No response message.")
    end
end
local function statsTick()
    local now = getTimestampMs()
    if now - lastSend >= 1000 then
        lastSend = now
        -- Bounded cache and at most one request per second, for visible rows only.
        if cacheCount > 500 then
            T.stats = {}
            requested = {}
            cacheCount = 0
        end
        for name, time in pairs(requested) do
            if now - time >= 10000 then
                requested[name] = nil
            end
        end
        local names = T.visibleStatNames(now)
        if #names > 0 then
            for _, name in ipairs(names) do
                requested[name] = now
            end
            sendClientCommand("UniversalAdminCore", "stats", { names = names })
        end
    end
end
Events.OnServerCommand.Add(onServer)
Events.OnTick.Add(statsTick)
Events.OnDisconnect.Add(function()
    T.stats = {}
    T.statsQueue = {}
    requested = {}
    cacheCount = 0
    T.statsRefreshRequested = false
end)
require("AdminCore/ObserverClient")
