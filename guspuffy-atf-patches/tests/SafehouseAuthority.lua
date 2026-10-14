-- Run the patched vendor handler with local objects; no game/network mutation.
local root = (arg[1] or "guspuffy-atf-patches/build/vendor-fixtures")
    .. "/mod-after_the_fall_core_b42/42.14/media/lua/"
local checks = 0
local function check(value, message)
    assert(value, message)
    checks = checks + 1
end
local function empty(values)
    for _ in pairs(values) do
        return false
    end
    return true
end
local function array(data)
    return {
        size = function()
            return #data
        end,
        get = function(_, index)
            return data[index + 1]
        end,
    }
end
local function actor(name, access, manages, rolePresent)
    local role = rolePresent ~= false
            and {
                hasCapability = function(_, capability)
                    return capability == Capability.CanSetupSafehouses and manages == true
                end,
            }
        or nil
    return {
        getUsername = function()
            return name
        end,
        getAccessLevel = function()
            return access
        end,
        getRole = function()
            return role
        end,
    }
end
local capability = {}
Capability = { CanSetupSafehouses = capability }
local function scenario(player)
    ATF = nil
    local houses, callbacks, sent = {}, {}, {}
    local created, removed, writes, nativeSync = 0, 0, 0, 0
    local function house(x, owner)
        local fields = {
            X = x,
            Y = 20,
            W = 10,
            H = 10,
            Title = "Home",
            Owner = owner,
            LastVisited = 1,
            DatetimeCreated = 2,
            Location = "Town",
            HitPoints = 0,
            OpenTimer = 0,
            Players = array({}),
            PlayersRespawn = array({}),
        }
        local h = {}
        for field, value in pairs(fields) do
            local key = field
            h["get" .. key] = function()
                return fields[key]
            end
            h["set" .. key] = function(_, replacement)
                fields[key] = replacement
            end
        end
        h.getX2 = function()
            return fields.X + fields.W
        end
        h.getY2 = function()
            return fields.Y + fields.H
        end
        return h
    end
    houses[1] = house(10, "owner")
    local staff = actor("staff", "custom", true)
    local ordinary = actor("ordinary", "none", false)
    getOnlinePlayers = function()
        return array({ ordinary, player, staff })
    end
    SafeHouse = {
        getSafehouseList = function()
            return array(houses)
        end,
        getSafehouseOverlapping = function()
            return nil
        end,
        addSafeHouse = function(x, y, w, h, owner)
            created = created + 1
            local value = house(x, owner)
            houses[#houses + 1] = value
            return value
        end,
        removeSafeHouse = function(target)
            removed = removed + 1
            for i = #houses, 1, -1 do
                if houses[i] == target then
                    table.remove(houses, i)
                end
            end
        end,
    }
    ATFSafehouseNativeSync = {
        sync = function()
            nativeSync = nativeSync + 1
        end,
    }
    Events = setmetatable({}, {
        __index = function(self, key)
            local event = {
                Add = function(fn)
                    callbacks[key] = callbacks[key] or {}
                    callbacks[key][#callbacks[key] + 1] = fn
                end,
            }
            rawset(self, key, event)
            return event
        end,
    })
    sendServerCommand = function(target, module, command, args)
        sent[#sent + 1] = { target = target, command = command, args = args }
    end
    getServerOptions = function()
        return {
            getInteger = function()
                return 144
            end,
        }
    end
    getFileWriter = function()
        writes = writes + 1
        return { write = function() end, close = function() end }
    end
    local function fire(event, ...)
        for _, fn in ipairs(callbacks[event] or {}) do
            fn(...)
        end
    end
    dofile(root .. "server/ATF_SafetySystem/ATF_SafehouseGuard_Server.lua")
    return {
        command = function(command)
            fire("OnClientCommand", "ATF", command, player, {
                title = "Home",
                id = "10,20,10,10",
                owner = "new-owner",
                x = 100,
                y = 20,
                w = 10,
                h = 10,
            })
        end,
        fire = fire,
        counts = function()
            return created, removed, writes, nativeSync
        end,
        sent = sent,
        staff = staff,
        clearHouse = function()
            houses[1] = nil
        end,
    }
end
local ordinaryActors = {
    actor("other", "none", false),
    actor("other", "", false),
    actor("other", "custom-player", false),
    actor("other", "admin", false),
    actor("other", "none", false, false),
}
for index, player in ipairs(ordinaryActors) do
    local state = scenario(player)
    state.command("RequestRelease")
    check(state.sent[1].command == "ReleaseDenied", "Non-owner role denied " .. index)
    check(empty(ATF.SafehouseGuard.pendingReleases), "Denied release has no intent " .. index)
    state.command("AdminAssignSafehouse")
    state.command("ForceRelease")
    state.command("DumpSafehouseList")
    local created, removed, writes, synced = state.counts()
    check(
        created == 0 and removed == 0 and writes == 0 and synced == 0,
        "Non-capable role has no admin effects " .. index
    )
    for _, reply in ipairs(state.sent) do
        if reply.command == "SafehouseAlert" then
            check(reply.target == state.staff, "Alerts reach capable staff only " .. index)
        end
    end
end
for _, access in ipairs({ "", "none", "custom-player" }) do
    local state = scenario(actor("owner", access, false))
    state.command("RequestRelease")
    check(state.sent[1].command == "ReleaseApproved", "Owner release remains available " .. access)
    check(
        ATF.SafehouseGuard.pendingReleases["10,20,10,10"].username == "owner",
        "Owner intent remains bound to stable house identity " .. access
    )
end
local authorized = actor("manager", "custom-manager", true)
local state = scenario(authorized)
state.command("RequestRelease")
check(state.sent[1].command == "ReleaseApproved", "Capability permits staff release")
state.command("AdminAssignSafehouse")
local created, removed, writes, synced = state.counts()
check(created == 1 and synced == 1, "Capability permits native-synchronized assignment")
state.command("ForceRelease")
created, removed = state.counts()
check(removed == 1, "Capability permits forced release")
state.command("DumpSafehouseList")
created, removed, writes = state.counts()
check(writes == 1, "Capability permits diagnostic dump")
-- Current authority is queried for each command, including after role loss.
authorized.getRole = function()
    return {
        hasCapability = function()
            return false
        end,
    }
end
state.command("AdminAssignSafehouse")
state.command("ForceRelease")
state.command("DumpSafehouseList")
local afterCreated, afterRemoved, afterWrites = state.counts()
check(
    afterCreated == created and afterRemoved == removed and afterWrites == writes,
    "Role loss immediately revokes staff actions"
)
state = scenario(actor("other", "none", false))
state.fire("EveryOneMinute")
state.clearHouse()
state.fire("OnSafehousesChanged")
local alerts = 0
for _, reply in ipairs(state.sent) do
    if reply.command == "SafehouseAlert" then
        alerts = alerts + 1
        check(reply.target == state.staff, "Unexpected-removal alert reaches capable staff only")
    end
end
check(alerts == 1, "One authorized recipient receives removal alert")
for _, api in ipairs({ "missing-role-method", "missing-capability", "missing-role-capability" }) do
    local player = actor("other", "admin", true)
    if api == "missing-role-method" then
        player.getRole = nil
    end
    if api == "missing-role-capability" then
        player.getRole = function()
            return {}
        end
    end
    if api == "missing-capability" then
        Capability = nil
    end
    state = scenario(player)
    state.command("AdminAssignSafehouse")
    local created = state.counts()
    check(created == 0, "Unavailable authority API fails closed: " .. api)
    Capability = { CanSetupSafehouses = capability }
end
print("PASS: " .. checks .. " safehouse authority checks")
