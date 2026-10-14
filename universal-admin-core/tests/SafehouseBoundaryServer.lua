local root = assert(arg[2], "Pass UAC directory")
local checks, now, allowed, edits = 0, 1000, true, 0
local output = print
print = function(message)
    if not tostring(message):find("[Universal Admin Core]", 1, true) then
        output(message)
    end
end
local function check(value, message)
    assert(value, message)
    checks = checks + 1
end
local function empty(value)
    for _ in pairs(value) do
        return false
    end
    return true
end
require = function() end
isServer = function()
    return true
end
getTimestampMs = function()
    return now
end
Capability = { CanSetupSafehouses = 1 }
AdminOperations = {
    authorized = function()
        return allowed
    end,
}
local callbacks = {}
Events = setmetatable({}, {
    __index = function(t, name)
        local value = {
            Add = function(fn)
                callbacks[name] = fn
            end,
        }
        rawset(t, name, value)
        return value
    end,
})
local function player(name)
    return {
        getUsername = function()
            return name
        end,
        getRole = function()
            return {
                hasCapability = function()
                    return allowed
                end,
            }
        end,
    }
end
local actor, other = player("admin"), player("other")
local house = { x = 100, y = 200, w = 10, h = 10, owner = "owner", fingerprint = "original" }
for _, key in ipairs({ "X", "Y", "W", "H", "Owner" }) do
    local field = string.lower(key)
    house["get" .. key] = function(self)
        return self[field]
    end
end
house.getId = function()
    return "native-original-id"
end
house.getTitle = function()
    return "Property"
end
house.getDatetimeCreated = function()
    return 123
end
house.getOnlineID = function()
    return 777
end
SafehouseBoundaryBridge = {
    find = function(_, x, y, w, h)
        if x == house.x and y == house.y and w == house.w and h == house.h then
            return house
        end
    end,
    fingerprint = function()
        return house.fingerprint
    end,
    apply = function(_, target, expected, x, y, w, h)
        if target ~= house or expected ~= house.fingerprint then
            return "Changed"
        end
        house.x, house.y, house.w, house.h = x, y, w, h
        edits = edits + 1
        house.fingerprint = "revision" .. edits
        return "OK"
    end,
}
local persisted, replies, broadcasts = {}, {}, {}
ModData = {
    getOrCreate = function()
        return persisted
    end,
}
sendServerCommand = function(a, b, c, d)
    if d then
        replies[#replies + 1] = { player = a, command = c, args = d }
    else
        broadcasts[#broadcasts + 1] = { command = b, args = c }
    end
end
dofile(root .. "/media/lua/server/SafehouseBoundaryServer.lua")
local function send(command, args, who)
    now = now + 500
    AdminSafehouseBoundaryServer.onCommand(
        "UniversalAdminCoreBoundary",
        command,
        who or actor,
        args
    )
    return replies[#replies]
end
local function snapshot(who)
    return send("snapshot", { x = house.x, y = house.y, w = house.w, h = house.h }, who).args
end
local function commit(s, who)
    return send("commit", {
        x = 95,
        y = 195,
        w = 20,
        h = 20,
        mode = "Expand",
        token = s.token,
        id = s.id,
        reason = "test",
    }, who)
end
allowed = false
send("snapshot", { x = 100, y = 200, w = 10, h = 10 })
check(
    replies[#replies].args.message == "Permission denied.",
    "normal player cannot obtain edit session"
)
allowed = true
for _, value in ipairs({ math.huge, -math.huge, 0 / 0, 1.5, 1000001, "100" }) do
    local answer = send("snapshot", { x = value, y = 200, w = 10, h = 10 })
    check(
        answer.args.message == "Invalid rectangle.",
        "malformed numeric input rejected before native/string formatting"
    )
end
local s = snapshot()
commit(s, other)
check(edits == 0, "another authorized account cannot use owner's edit token")
local fake = { token = s.token, id = "different safehouse" }
commit(fake)
check(edits == 0, "crafted safehouse identity is rejected")
house.fingerprint = "membership changed"
commit(s)
check(
    edits == 0 and empty(persisted.aliases),
    "stale membership rejects mutation and rolls alias back"
)
s = snapshot()
local realApply = SafehouseBoundaryBridge.apply
SafehouseBoundaryBridge.apply = function()
    error("simulated bridge failure")
end
commit(s)
check(
    edits == 0 and empty(persisted.aliases),
    "bridge exception rolls alias back and returns failure"
)
SafehouseBoundaryBridge.apply = realApply
s = snapshot()
allowed = false
commit(s)
check(edits == 0, "revocation after snapshot rejects commit")
allowed = true
s = snapshot()
now = now + 120001
commit(s)
check(edits == 0, "expired edit token is rejected")
s = snapshot()
commit(s)
check(edits == 1 and house.x == 95, "server accepts current authorized edit")
check(
    persisted.aliases["95:195:123"] == "100:200:123",
    "preserves original Community property identity"
)
check(
    #persisted.history == 1 and persisted.history[1].owner == "owner",
    "audit is persisted with owner"
)
check(
    broadcasts[1].command == "changed" and broadcasts[1].args.old.x == 100,
    "same-object update broadcast includes old rectangle"
)
commit(s)
check(edits == 1 and #persisted.history == 1, "replay cannot duplicate mutation or audit")
for i = 1, 105 do
    local nextSnapshot = snapshot()
    commit(nextSnapshot)
end
check(#persisted.history == 100, "history remains bounded")
local history = send("history", {})
check(#history.args.rows == 25, "history response is bounded to 25 rows")
-- Recreate command handler as after reconnect/restart: persisted aliases/history remain,
-- editing tokens disappear. This does not substitute for the native save/load Java test.
AdminSafehouseBoundaryServer = nil
dofile(root .. "/media/lua/server/SafehouseBoundaryServer.lua")
commit(s)
check(edits == 106, "restart cannot revive old editing token")
check(#persisted.history == 100, "restart preserves recent audit")
print("Safehouse boundary server: " .. checks .. " checks passed")
