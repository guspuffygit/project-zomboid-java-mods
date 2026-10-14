local checks, mutations = 0, 0
local function check(ok, message)
    assert(ok, message)
    checks = checks + 1
end
require = function() end
ISBaseTimedAction = {
    derive = function(_, name)
        return {}
    end,
    new = function(class, character)
        return setmetatable({ character = character }, { __index = class })
    end,
}
isServer = function()
    return true
end
getText = function(value)
    return value
end
ItemTag = { WRENCH = "wrench" }
Perks = { Mechanics = "mechanics" }
IsoObjectChange = { MECHANIC_ACTION_DONE = 1 }
getGameTime = function()
    return {
        getCalender = function()
            return {
                getTimeInMillis = function()
                    return 100
                end,
            }
        end,
    }
end
ZombRand = function()
    return 5
end
sendAddItemsToContainer = function()
    mutations = mutations + 1
end
local allowed, dead, removed, near, carried, broken, tagged, linked =
    true, false, false, true, true, false, true, true
local z, condition, skill = 0, 50, 5
local tool = {
    getID = function()
        return 1
    end,
    hasTag = function(_, tag)
        return tagged and tag == ItemTag.WRENCH
    end,
    isBroken = function()
        return broken
    end,
}
local inventory = {
    containsRecursive = function(_, item)
        return carried and item == tool
    end,
    AddItems = function(_, kind, count)
        check(kind == "Base.EngineParts" and count == 10, "Native item award is retained")
        mutations = mutations + 1
        return {}
    end,
}
local xp = {
    AddXP = function()
        mutations = mutations + 1
    end,
}
local character = {
    isDead = function()
        return dead
    end,
    isTimedActionInstant = function()
        return false
    end,
    getInventory = function()
        return inventory
    end,
    getSquare = function()
        return {
            getZ = function()
                return z
            end,
        }
    end,
    getPerkLevel = function()
        return skill
    end,
    getXp = function()
        return xp
    end,
    sendObjectChange = function()
        mutations = mutations + 1
    end,
    getMechanicsItem = function()
        return false
    end,
    addMechanicsItem = function()
        mutations = mutations + 1
    end,
}
local part
local vehicle = {
    isRemovedFromWorld = function()
        return removed
    end,
    getPartById = function(_, name)
        return linked and name == "Engine" and part or nil
    end,
    getSquare = function()
        return {
            getZ = function()
                return 0
            end,
        }
    end,
    isInArea = function()
        return near
    end,
    getScript = function()
        return {
            getEngineRepairLevel = function()
                return 3
            end,
        }
    end,
    getMechanicalID = function()
        return 7
    end,
    transmitPartCondition = function()
        mutations = mutations + 1
    end,
}
part = {
    getVehicle = function()
        return vehicle
    end,
    getArea = function()
        return "Engine"
    end,
    getCondition = function()
        return condition
    end,
    setCondition = function(_, value)
        condition = value
        mutations = mutations + 1
    end,
}
AVCS = {
    getPublicPermission = function()
        return false
    end,
    checkPermission = function()
        return allowed
    end,
    getSimpleBooleanPermission = function(value)
        return value
    end,
}
dofile("another-vehicle-claim-system/media/lua/shared/TimedActions/ISAVCSTakeEngineParts.lua")
local action = ISAVCSTakeEngineParts:new(character, part, tool, 300)
check(action:isValid(), "Valid wrench in recursive inventory can extract engine parts")
local function rejected(message)
    mutations = 0
    check(not action:isValid(), message .. " is invalid before starting")
    check(
        not action:complete() and mutations == 0 and condition == 50,
        message .. " causes no partial engine or item mutation"
    )
end
action.item = nil
rejected("Missing tool")
action.item = tool
carried = false
rejected("Dropped or transferred tool")
carried = true
broken = true
rejected("Broken wrench")
broken = false
tagged = false
rejected("Non-wrench item")
tagged = true
allowed = false
rejected("Permission revoked while queued")
allowed = true
dead = true
rejected("Dead character")
dead = false
removed = true
rejected("Removed vehicle")
removed = false
linked = false
rejected("Changed or mismatched engine part")
linked = true
near = false
rejected("Moved away from engine area")
near = true
z = 1
rejected("Changed floor")
z = 0
skill = 2
rejected("Insufficient Mechanics")
skill = 5
condition = 0
mutations = 0
check(
    not action:isValid() and not action:complete() and mutations == 0,
    "Already stripped engine cannot grant more items or XP"
)
condition = 50
mutations = 0
check(
    action:complete() and condition == 0 and mutations > 0,
    "Valid authoritative completion grants parts and updates engine"
)
mutations = 0
check(
    not action:complete() and mutations == 0,
    "Repeated completion after extraction has no effects"
)
print("PASS: " .. checks .. " engine extraction checks")
