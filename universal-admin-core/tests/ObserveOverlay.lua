local root = arg[2] or "universal-admin-core"
require = function() end
local checks, now, authorized = 0, 100000, true
local function check(v, m)
    assert(v, m)
    checks = checks + 1
end
getTimestampMs = function()
    return now
end
local UI = {}
UI.__index = UI
function UI:derive()
    local cls = setmetatable({}, self)
    cls.__index = cls
    return cls
end
function UI:new()
    return setmetatable({}, self)
end
for _, name in ipairs({
    "initialise",
    "instantiate",
    "setWantMouseEvents",
    "backMost",
    "addToUIManager",
    "removeFromUIManager",
    "setWidth",
    "setHeight",
    "setStencilRect",
    "clearStencilRect",
}) do
    UI[name] = function() end
end
ISUIElement = UI
getCore = function()
    return {
        getScreenWidth = function()
            return 1920
        end,
        getScreenHeight = function()
            return 1080
        end,
    }
end
local function events()
    return setmetatable({}, {
        __index = function(t, k)
            local e = { Add = function() end }
            rawset(t, k, e)
            return e
        end,
    })
end
Events = events()
AdminCore = {
    operationsAllowed = function()
        return authorized
    end,
    operationsKeepAlive = function() end,
}
dofile(root .. "/media/lua/client/AdminCore/OverlayManager.lua")
local M = AdminOverlayManager
local collects = 0
M.registerOverlay("fixture", {
    permission = "ADMIN_RENDER_DEBUG",
    refreshMs = 1000,
    maxRows = 256,
    collect = function()
        collects = collects + 1
        local out = {}
        for i = 1, 1000 do
            out[i] = { i = i }
        end
        return out
    end,
    renderWorld = function() end,
})
M.enableOverlay("fixture", true)
M.tick()
check(#M.entries.fixture.rows == 256, "Provider results are capped at256 rows")
for _ = 1, 1000 do
    M.tick()
end
check(collects == 1, "No per-frame recollection or full scan")
now = now + 1000
M.tick()
check(collects == 2, "Cache refresh uses bounded interval")
authorized = false
M.tick()
check(
    #M.entries.fixture.rows == 0 and M.ui == nil,
    "Revocation clears cached visual data and removes render layer"
)
authorized = true
M.registerOverlay("failure", {
    permission = "ADMIN_RENDER_DEBUG",
    collect = function()
        error("Injected adapter failure")
    end,
    renderWorld = function() end,
})
M.enableOverlay("failure", true)
M.tick()
check(not M.entries.failure.enabled, "Failing provider is disabled without breaking other overlays")
M.registerOverlay("active-failure", {
    permission = "ADMIN_RENDER_DEBUG",
    active = function()
        error("Unavailable integration")
    end,
    renderWorld = function() end,
})
M.enableOverlay("active-failure", true)
M.tick()
check(
    #M.entries["active-failure"].rows == 0,
    "Failure in optional active predicate hides its output"
)
M.clear()
check(
    M.ui == nil and not M.entries.fixture.enabled,
    "Disconnect cleanup disables all providers and clears layer"
)
-- Profile the actual roster implementation; getters count traversal work.
local players, reads = {}, 0
getPlayer = function()
    return {
        getX = function()
            return 0
        end,
        getY = function()
            return 0
        end,
        getUsername = function()
            return "admin"
        end,
    }
end
getOnlinePlayers = function()
    return {
        size = function()
            return #players
        end,
        get = function(_, i)
            reads = reads + 1
            return players[i + 1]
        end,
    }
end
AdminCore.operationsAllowed = function()
    return true
end
AdminCore.requestOperations = function() end
Events = events()
dofile(root .. "/media/lua/client/AdminCore/ObserverClient.lua")
local V = AdminCore.observer
for _, count in ipairs({ 1, 50, 100, 150 }) do
    players = {}
    for i = 1, count do
        local name = string.format("player-%04d", i)
        players[i] = {
            getUsername = function()
                return name
            end,
            isDead = function()
                return false
            end,
            getX = function()
                return i
            end,
            getY = function()
                return i
            end,
        }
    end
    reads = 0
    -- Kahlua intentionally has no os.clock. Its deterministic fixture clock
    -- cannot measure CPU time, so report traversal counts only in that runtime.
    local cpuClock = os and type(os.clock) == "function" and os.clock or nil
    local started = cpuClock and cpuClock() or nil
    for _ = 1, 200 do
        AdminCore.refreshObserverRoster(true)
    end
    local perRefresh = cpuClock and (cpuClock() - started) * 1000000 / 200 or nil
    check(reads == count * 200, "One roster traversal per permitted refresh")
    local before = reads
    for _ = 1, 1000 do
        AdminCore.refreshObserverRoster()
    end
    check(reads == before, "Normal ticks use cache for " .. count .. " online players")
    if perRefresh and perRefresh > 0 then
        print(
            string.format(
                "MEASURE observer roster: %d players | %.2f us/refresh | %d getters/refresh | 0 cached-tick getters",
                count,
                perRefresh,
                count
            )
        )
    else
        print(
            string.format(
                "MEASURE observer roster: %d players | %s | %d getters/refresh | 0 cached-tick getters",
                count,
                perRefresh and "CPU time below timer resolution" or "CPU timer unavailable",
                count
            )
        )
    end
end
print("PASS: " .. checks .. " bounded overlay/provider failure/roster scaling checks")
