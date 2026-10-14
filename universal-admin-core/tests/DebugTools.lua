-- Bounds, authorization and replay checks for the small non-debug-mode subset.
local root = "universal-admin-core/media/lua/"
local count, now = 0, 10000
local function check(value, message)
    assert(value, message)
    count = count + 1
end
require = function() end
Events = setmetatable({}, {
    __index = function(t, key)
        local event = { Add = function() end }
        rawset(t, key, event)
        return event
    end,
})
Capability = setmetatable({}, {
    __index = function(_, key)
        return key
    end,
})
local admin, caps = true, {}
local role = {
    hasAdminPower = function()
        return admin
    end,
    hasCapability = function(_, cap)
        return caps[cap] ~= false
    end,
}
local player = {
    getRole = function()
        return role
    end,
    getUsername = function()
        return "admin"
    end,
    isDead = function()
        return false
    end,
    getX = function()
        return 100
    end,
    getY = function()
        return 100
    end,
    getZ = function()
        return 0
    end,
}
isServer = function()
    return true
end
getTimestampMs = function()
    return now
end
local data = {}
ModData = {
    getOrCreate = function(key)
        data[key] = data[key] or {}
        return data[key]
    end,
}
local replies, lookups, mutations, transmissions = {}, 0, 0, 0
sendServerCommand = function(_, _, _, args)
    replies[#replies + 1] = args
end
local vehicle = {
    skin = 0,
    x = 100,
    y = 100,
    z = 0,
    getId = function()
        return 7
    end,
    getSkinCount = function()
        return 3
    end,
    getSkinIndex = function(self)
        return self.skin
    end,
    setSkinIndex = function(self, value)
        mutations = mutations + 1
        self.skin = value
    end,
    transmitSkinIndex = function()
        transmissions = transmissions + 1
    end,
    getX = function(self)
        return self.x
    end,
    getY = function(self)
        return self.y
    end,
    getZ = function(self)
        return self.z
    end,
    getScript = function()
        return {
            getFullName = function()
                return "Base.TestVehicle"
            end,
        }
    end,
    getPartCount = function()
        return 10
    end,
}
getVehicleById = function(id)
    lookups = lookups + 1
    if id == 7 then
        return vehicle
    end
end
local objectReads, unloaded = 0, false
local obj = {
    getObjectName = function()
        objectReads = objectReads + 1
        return "FixtureObject"
    end,
    getSprite = function()
        return {
            getName = function()
                return "fixture_sprite_01"
            end,
        }
    end,
    getContainer = function()
        return {
            getType = function()
                return "crate"
            end,
            getItems = function()
                return {
                    size = function()
                        return 42
                    end,
                }
            end,
        }
    end,
}
getCell = function()
    return {
        getGridSquare = function()
            if unloaded then
                return nil
            end
            return {
                getObjects = function()
                    return {
                        size = function()
                            return 10000
                        end,
                        get = function()
                            return obj
                        end,
                    }
                end,
            }
        end,
    }
end
dofile(root .. "shared/AdminCore/OperationsPermissions.lua")
dofile(root .. "server/PowerDebugServer.lua")
local S = AdminPowerDebugServer
local function request(command, args)
    now = now + 1000
    args = args or {}
    args.token = 1
    S.onCommand("UniversalAdminDebug", command, player, args)
end
admin = false
request("skin", { vehicle = 7, index = 1, expected = 0 })
check(
    mutations == 0 and lookups == 0,
    "Ordinary player cannot resolve or edit a vehicle through forged debug command"
)
admin = true
caps.ManipulateVehicle = false
request("skin", { vehicle = 7, index = 1, expected = 0 })
check(
    mutations == 0 and lookups == 0,
    "Debug feature alone never grants the native vehicle capability"
)
caps.ManipulateVehicle = true
local policy = AdminOperations.policy()
policy.disabled = { ADMIN_DEBUG_TOOLS = true }
request("skin", { vehicle = 7, index = 1, expected = 0 })
check(mutations == 0 and lookups == 0, "Server feature policy cannot be bypassed by crafted packet")
policy.disabled = nil
policy.disabledTools = { ["debug.vehicleSkin"] = true }
request("skin", { vehicle = 7, index = 1, expected = 0 })
check(mutations == 0 and lookups == 0, "Server tool disable is enforced by the handler")
policy.disabledTools = nil
for _, id in ipairs({ 0 / 0, math.huge, -math.huge, 7.5, 9999999, "7" }) do
    request("skin", { vehicle = id, index = 1, expected = 0 })
end
check(lookups == 0, "Malformed vehicle identifiers are rejected before native lookup")
vehicle.x = 200
request("skin", { vehicle = 7, index = 1, expected = 0 })
check(mutations == 0, "Remote vehicles cannot be edited")
vehicle.x, vehicle.z = 100, 1
request("skin", { vehicle = 7, index = 1, expected = 0 })
check(mutations == 0, "Vehicle on another floor cannot be edited")
vehicle.z = 0
for _, index in ipairs({ -1, 3, 1.1, math.huge, 0 / 0, "1" }) do
    request("skin", { vehicle = 7, index = index, expected = 0 })
end
check(mutations == 0, "Skin must be a finite available integer index")
request("skin", { vehicle = 7, index = 1, expected = 0 })
check(
    mutations == 1 and transmissions == 1 and vehicle.skin == 1,
    "Valid nearby skin change uses native setter and replication"
)
request("skin", { vehicle = 7, index = 1, expected = 0 })
check(mutations == 1, "Lost response/replay never repeats a stale edit")
request("skin", { vehicle = 7, index = 1, expected = 1 })
check(mutations == 1, "Already applied desired state is a no-op")
check(
    #data["UniversalAdminCore.OperationsAudit.v1"].rows == 1,
    "Only one meaningful skin audit is recorded"
)
request("vehicle", { vehicle = 7 })
check(
    replies[#replies].text:find("Base.TestVehicle", 1, true),
    "Vehicle diagnostic reports the real script"
)
caps.UseDebugContextMenu = false
request("objects", { x = 100, y = 100, z = 0 })
check(objectReads == 0, "Object inspection has its own native capability")
caps.UseDebugContextMenu = true
request("objects", { x = 110, y = 100, z = 0 })
check(objectReads == 0, "Object inspection stays within proximity bound")
unloaded = true
request("objects", { x = 100, y = 100, z = 0 })
check(
    objectReads == 0 and replies[#replies].text:find("not loaded", 1, true),
    "Unloaded square fails safely"
)
unloaded = false
request("objects", { x = 100, y = 100, z = 0 })
check(
    objectReads == 20 and #replies[#replies].text <= 6000,
    "Object inspection bounds work and payload even on pathological tile"
)
check(
    replies[#replies].text:find("item count: 42", 1, true),
    "Container summary reports count without enumerating contents"
)
S.onCommand("UniversalAdminDebug", "objects", player, { token = 2, x = 100, y = 100, z = 0 })
check(objectReads == 20, "Rapid requests are rate limited before scanning")
print("Admin debug tools: " .. count .. " checks passed")
