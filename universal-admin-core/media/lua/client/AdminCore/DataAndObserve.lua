require("AdminCore/WindowSizing")
local T = AdminCore
T.stats = T.stats or {}
T.statsQueue = {}
local lastSend, lastHeartbeat = 0, 0
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
local function clearObserve()
    T.observing = nil
    lastHeartbeat = 0
    if AdminCoreObserveCamera then
        AdminCoreObserveCamera.stop()
    end
    if T.observePanel then
        T.observePanel:removeFromUIManager()
        T.observePanel = nil
    end
end
function T.stopObserve()
    sendClientCommand("UniversalAdminCore", "observeStop", {})
    clearObserve()
end
local function observePanel(name)
    if T.observePanel then
        T.observePanel:removeFromUIManager()
    end
    local panel = ISPanel:new(12, 60, 430, 85)
    panel:initialise()
    panel.moveWithMouse = true
    local button =
        ISButton:new(10, 40, 410, 30, "Stop observing / return (Esc)", nil, T.stopObserve)
    button:initialise()
    panel:addChild(button)
    panel.prerender = function(self)
        ISPanel.prerender(self)
        self:drawText("Following: " .. name, 10, 8, 1, 1, 1, 1, UIFont.Small)
    end
    panel:addToUIManager()
    T.observePanel = panel
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
    elseif command == "observeStarted" then
        T.observing = args.username
        lastHeartbeat = 0
        observePanel(args.username)
    elseif command == "observeStopped" then
        -- Acknowledgements must not send a second stop: when switching targets
        -- that echo could terminate the new server session.
        clearObserve()
        if args.reason then
            T.message(args.reason)
        end
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
local function observeTick()
    if not T.observing then
        return
    end
    local now = getTimestampMs()
    if not getPlayer() or getPlayer():isDead() then
        T.stopObserve()
        return
    end
    if now - lastHeartbeat >= 2000 then
        lastHeartbeat = now
        sendClientCommand("UniversalAdminCore", "observeHeartbeat", {})
    end
    if AdminCoreObserveCamera then
        AdminCoreObserveCamera.follow(T.observing)
    end
end
Events.OnServerCommand.Add(onServer)
-- Keep camera/heartbeat renewal independent of player-list rendering and stats.
Events.OnTick.Add(observeTick)
Events.OnTick.Add(statsTick)
Events.OnKeyPressed.Add(function(key)
    if key == Keyboard.KEY_ESCAPE and T.observing then
        T.stopObserve()
    end
end)
Events.OnDisconnect.Add(function()
    clearObserve()
    T.stats = {}
    T.statsQueue = {}
    requested = {}
    cacheCount = 0
    T.statsRefreshRequested = false
end)
