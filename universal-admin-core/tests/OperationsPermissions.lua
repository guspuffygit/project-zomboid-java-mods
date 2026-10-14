local root = "universal-admin-core/media/lua/"
require = function() end
local count, clock, server = 0, 100000, true
local function check(v, message)
    assert(v, message)
    count = count + 1
end
local caps, admin, store, replies, callbacks = {}, true, {}, {}, {}
Capability = setmetatable({}, {
    __index = function(_, key)
        return key
    end,
})
local player = {
    getUsername = function()
        return "moderator"
    end,
    getRole = function()
        return {
            hasAdminPower = function()
                return admin
            end,
            hasCapability = function(_, cap)
                return caps[cap] == true
            end,
        }
    end,
}
getPlayer = function()
    return player
end
isServer = function()
    return server
end
getTimestampMs = function()
    return clock
end
ModData = {
    getOrCreate = function(key)
        store[key] = store[key] or {}
        return store[key]
    end,
}
Events = setmetatable({}, {
    __index = function(t, key)
        local e = {
            Add = function(fn)
                callbacks[key] = callbacks[key] or {}
                table.insert(callbacks[key], fn)
            end,
        }
        rawset(t, key, e)
        return e
    end,
})
sendServerCommand = function(_, module, command, args)
    replies[#replies + 1] = { module, command, args }
end
sendClientCommand = function()
    replies[#replies + 1] = "request"
end
dofile(root .. "shared/AdminCore/OperationsPermissions.lua")
local O = AdminOperations
for key in pairs(O.features) do
    check(not O.authorized(player, key), "Missing native caps deny " .. key)
end
check(not O.authorized(player, "madeup"), "Unknown feature denied")
caps.CanSetupSafehouses = true
check(O.authorized(player, "ADMIN_SAFEHOUSE_EDIT"), "Existing native cap grants boundary feature")
local policy = O.policy()
policy.disabled = { ADMIN_SAFEHOUSE_EDIT = true }
check(not O.authorized(player, "ADMIN_SAFEHOUSE_EDIT"), "Server switch narrows feature")
policy.disabled.ADMIN_SAFEHOUSE_EDIT = false
policy.users = { moderator = { ADMIN_SAFEHOUSE_EDIT = false } }
check(not O.authorized(player, "ADMIN_SAFEHOUSE_EDIT"), "Per-admin restriction applied")
policy.users.moderator.ADMIN_SAFEHOUSE_EDIT = true
caps.CanSetupSafehouses = nil
check(
    not O.authorized(player, "ADMIN_SAFEHOUSE_EDIT"),
    "User true never grants absent native capability"
)
caps.TeleportToPlayer = true
check(not O.authorized(player, "ADMIN_SPECTATOR"), "Spectator also needs online player visibility")
caps.SeePlayersConnected = true
check(O.authorized(player, "ADMIN_SPECTATOR"), "Spectator native permissions accepted")
admin = false
check(not O.authorized(player, "ADMIN_SPECTATOR"), "Normal player cannot use advanced tools")
admin = true
policy.disabledTools = { ["core.vehicle"] = true }
check(not O.toolAllowed(player, "core.vehicle"), "Server can remove Mini tool")
dofile(root .. "server/AdminOperationsServer.lua")
local command = callbacks.OnClientCommand[1]
command("UniversalAdminOperations", "permissions", player, nil)
check(#replies == 1 and replies[1][3].features.ADMIN_SPECTATOR, "Server derives lease grants")
command(
    "UniversalAdminOperations",
    "permissions",
    player,
    { features = { ADMIN_WORLD_EDIT = true } }
)
check(#replies == 1, "Permission polling rate limited")
clock = clock + 1001
command("UniversalAdminOperations", "setPolicy", player, { ADMIN_WORLD_EDIT = true })
check(#replies == 1, "There is no client policy mutation endpoint")
caps.TeleportToPlayer = false
command(
    "UniversalAdminOperations",
    "permissions",
    player,
    { features = { ADMIN_SPECTATOR = true } }
)
check(
    replies[2][3].features.ADMIN_SPECTATOR == false,
    "Forged grants ignored after role revocation"
)
server, AdminCore = false, {}
dofile(root .. "client/AdminCore/OperationsClient.lua")
local C = AdminCore
caps.TeleportToPlayer = true
check(not C.operationsAllowed("ADMIN_SPECTATOR"), "Client fails closed before grant")
local receive = callbacks.OnServerCommand[1]
receive("UniversalAdminOperations", "permissions", {
    features = { ADMIN_SPECTATOR = true },
    ttl = 999999,
    deniedTools = { ["core.vehicle"] = true },
})
check(C.operationsAllowed("ADMIN_SPECTATOR"), "Granted local capability active")
check(not C.operationToolAllowed("core.vehicle"), "Client respects denied Mini tool")
caps.TeleportToPlayer = false
check(
    not C.operationsAllowed("ADMIN_SPECTATOR"),
    "Local role removal closes capability immediately"
)
caps.TeleportToPlayer = true
clock = clock + 15001
check(not C.operationsAllowed("ADMIN_SPECTATOR"), "Lease expires even if server stops replying")
local before = #replies
callbacks.OnTick[1]()
check(#replies == before, "Closed tools do not continuously poll")
C.operationsKeepAlive("test", true)
check(#replies == before + 1, "Active UI requests permissions")
C.operationsKeepAlive("test", false)
clock = clock + 6000
callbacks.OnTick[1]()
check(#replies == before + 1, "Closing UI stops polling")
callbacks.OnDisconnect[1]()
check(
    C.operationsState.expires == 0 and not O.hasEntries(C.operationsState.owners),
    "Disconnect clears lease and owners"
)
print("PASS: " .. count .. " operations permission checks")
