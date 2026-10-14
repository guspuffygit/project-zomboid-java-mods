local root = "universal-admin-core/media/lua/"
require = function() end
local clock, admin, dead, square, caps, store, sounds, callbacks =
    10000, true, false, {
        getX = function()
            return 123
        end,
        getY = function()
            return 456
        end,
        getZ = function()
            return 1
        end,
    }, { UseDebugContextMenu = true }, {}, {}, {}
isServer = function()
    return true
end
getTimestampMs = function()
    return clock
end
Capability = setmetatable({}, {
    __index = function(_, key)
        return key
    end,
})
ModData = {
    getOrCreate = function(key)
        store[key] = store[key] or {}
        return store[key]
    end,
}
local player = {
    getUsername = function()
        return "admin"
    end,
    isDead = function()
        return dead
    end,
    getCurrentSquare = function()
        return square
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
Events = {
    OnClientCommand = {
        Add = function(fn)
            callbacks[#callbacks + 1] = fn
        end,
        Remove = function(fn)
            for i = #callbacks, 1, -1 do
                if callbacks[i] == fn then
                    table.remove(callbacks, i)
                end
            end
        end,
    },
}
addSound = function(...)
    sounds[#sounds + 1] = { ... }
end
dofile(root .. "shared/AdminCore/OperationsPermissions.lua")
dofile(root .. "server/AdminCore/NoiseServer.lua")
local request = callbacks[1]
local function noise(radius, extra)
    clock = clock + 1000
    local args = extra or {}
    args.radius = radius
    request("UniversalAdminCore", "makeNoise", player, args)
end
noise(500, { x = -999, y = -999, z = -999, volume = 99999 })
assert(
    #sounds == 1
        and sounds[1][1] == player
        and sounds[1][2] == 123
        and sounds[1][3] == 456
        and sounds[1][4] == 1
        and sounds[1][5] == 500
        and sounds[1][6] == 100,
    "The server uses its current square and fixed volume, including radius 500"
)
request("UniversalAdminCore", "makeNoise", player, { radius = 500 })
assert(#sounds == 1, "Repeated requests are rate limited")
dofile(root .. "server/AdminCore/NoiseServer.lua")
assert(#callbacks == 1, "Reload replaces the event handler instead of registering another one")
request = callbacks[1]
request("UniversalAdminCore", "makeNoise", player, { radius = 500 })
assert(#sounds == 1, "Reload keeps the existing request limit")
for _, radius in ipairs({ 10, 20, 50, 100, 200 }) do
    noise(radius)
end
assert(#sounds == 6, "All native radius choices remain available")
for _, radius in ipairs({ 0, -1, 201, 501, 1000000, 20.5, math.huge, "500", false }) do
    noise(radius)
end
noise(0 / 0)
request("UniversalAdminCore", "makeNoise", player, nil)
request("OtherMod", "makeNoise", player, { radius = 500 })
request("UniversalAdminCore", "other", player, { radius = 500 })
request("UniversalAdminCore", "makeNoise", nil, { radius = 500 })
assert(#sounds == 6, "Malformed arguments and unrelated messages cannot create sounds")
admin = false
noise(500)
admin = true
caps.UseDebugContextMenu = nil
caps.UseHealthCheat = true
noise(500)
caps.UseDebugContextMenu = true
dead = true
noise(500)
dead = false
local savedSquare = square
square = nil
noise(500)
square = savedSquare
assert(
    #sounds == 6,
    "Ordinary players, missing native capability, dead players and missing squares are denied"
)
local policy = AdminOperations.policy()
policy.disabled = { ADMIN_DEBUG_TOOLS = true }
noise(500)
policy.disabled = nil
policy.users = { admin = { ADMIN_DEBUG_TOOLS = false } }
noise(500)
policy.users = nil
policy.disabledTools = { ["context.noise.500"] = true }
noise(500)
assert(#sounds == 6, "Feature, per-admin and tool restrictions narrow the native capability")
policy.disabledTools = nil
noise(500)
assert(#sounds == 7, "Restoring authorization permits the next bounded request")
print("PASS: server-authorized noise radius, origin, policy and request limits")
