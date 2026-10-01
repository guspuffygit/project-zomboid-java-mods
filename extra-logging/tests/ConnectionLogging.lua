-- Run from the repository root with Lua 5.1; no game process or saves required.
local checks = 0
local function check(ok, message)
    assert(ok, message)
    checks = checks + 1
end
dofile("extra-logging/media/lua/shared/openutils/logutils.lua")
local steamID
getCurrentUserSteamID = function()
    return steamID
end
local player = {
    getUsername = function()
        return "guest"
    end,
}
check(
    logutils.GetLogLinePrefix(player, "connected") == 'non-steam "guest" connected',
    "nil Steam ID fallback"
)
steamID = ""
check(
    logutils.GetLogLinePrefix(player, "connected") == 'non-steam "guest" connected',
    "empty Steam ID fallback"
)
steamID = "76561198000000000"
check(
    logutils.GetLogLinePrefix(player, "connected") == steamID .. ' "guest" connected',
    "Steam identity preserved"
)
local callbacks = {}
Events = setmetatable({}, {
    __index = function(t, name)
        local event = {
            Add = function(fn)
                callbacks[name] = fn
            end,
            Remove = function(fn)
                check(callbacks[name] == fn, "Unsubscribe the same callback")
                callbacks[name] = nil
            end,
        }
        rawset(t, name, event)
        return event
    end,
})
SandboxVars = { LogExtender = { PlayerConnected = true } }
dofile("extra-logging/media/lua/client/loggers/PlayerClientLogger.lua")
callbacks.OnCreatePlayer(0)
getPlayer = function()
    return nil
end
callbacks.OnTick()
check(callbacks.OnTick ~= nil, "Wait until a player exists")
local attempts = 0
getPlayer = function()
    return player
end
logutils.GetLogLinePrefix = function()
    attempts = attempts + 1
    check(callbacks.OnTick == nil, "Remove before invoking potentially failing logging")
    error("Injected snapshot failure")
end
local tick = callbacks.OnTick
check(pcall(tick), "Snapshot failure does not escape into the tick loop")
check(callbacks.OnTick == nil and attempts == 1, "Failed snapshot cannot retry each frame")
print("PASS: " .. checks .. " connection logging checks")
