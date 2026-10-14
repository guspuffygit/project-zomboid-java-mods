-- Run from the repository root with Lua 5.1; no game process or saves required.
local checks = 0
local function check(ok, message)
    assert(ok, message)
    checks = checks + 1
end

isClient = function()
    return true
end
isServer = function()
    return false
end
instanceof = function()
    return false
end
SandboxVars =
    { AVCS = { MuleParts = "", TrunkParts = "", AllowFaction = false, AllowSafehouse = false } }

local player = {
    getUsername = function()
        return "survivor"
    end,
    getAccessLevel = function()
        return "none"
    end,
}
getTimestampMs = function()
    return 1000
end
require = function(name)
    assert(name == "AVCSSync")
    return dofile("another-vehicle-claim-system/media/lua/client/AVCSSync.lua")
end

getPlayer = function()
    return player
end

local sent = {}
sendClientCommand = function(_, module, command)
    sent[#sent + 1] = module .. "." .. command
end

local callbacks = {}
Events = setmetatable({}, {
    __index = function(t, name)
        local event = {
            Add = function(fn)
                callbacks[name] = fn
            end,
            Remove = function()
                callbacks[name] = nil
            end,
        }
        rawset(t, name, event)
        return event
    end,
})

dofile("another-vehicle-claim-system/media/lua/shared/AVCSShared.lua")
dofile("another-vehicle-claim-system/media/lua/client/AVCSClient.lua")

local vehicle = {
    getModData = function()
        return {}
    end,
    getPartById = function()
        return nil
    end,
}
local part = {
    getVehicle = function()
        return vehicle
    end,
    getId = function()
        return "TruckBed"
    end,
}
local trunk = {
    getOutermostContainer = function()
        return nil
    end,
    getVehiclePart = function()
        return part
    end,
}
local crate = {
    getOutermostContainer = function()
        return nil
    end,
    getVehiclePart = function()
        return nil
    end,
    getParent = function()
        return nil
    end,
}

check(AVCS.canAccessVehicleContainer(player, crate), "World containers are never gated")
check(
    not AVCS.canAccessVehicleContainer(player, trunk),
    "Vehicle containers stay hidden until the claim DB arrives"
)

callbacks.OnTick()
check(sent[1] == "AVCS.requestFullSync", "First tick requests the claim DB")
check(callbacks.OnServerCommand ~= nil, "First tick subscribes to server commands")

-- GameServer.sendServerCommand writes no args for an empty table, so the client receives nil
callbacks.OnServerCommand("AVCS", "fullSyncVehicleDB", nil)
callbacks.OnServerCommand("AVCS", "fullSyncPlayerDB", nil)
check(type(AVCS.dbByVehicleSQLID) == "table", "Empty vehicle DB syncs as an empty table")
check(type(AVCS.dbByPlayerID) == "table", "Empty player DB syncs as an empty table")
check(
    AVCS.canAccessVehicleContainer(player, trunk),
    "Unclaimed vehicle containers open on a server with no claims"
)

callbacks.OnServerCommand(
    "AVCS",
    "fullSyncVehicleDB",
    { [42] = { OwnerPlayerID = "owner", CarModel = "Base.CarNormal" } }
)
callbacks.OnServerCommand("AVCS", "fullSyncPlayerDB", { owner = { [42] = true } })
vehicle.getModData = function()
    return { SQLID = 42 }
end
check(
    not AVCS.canAccessVehicleContainer(player, trunk),
    "A stranger's claimed vehicle stays closed"
)
player.getUsername = function()
    return "owner"
end
check(AVCS.canAccessVehicleContainer(player, trunk), "The owner opens their own claimed vehicle")

print("PASS: " .. checks .. " empty claim DB sync checks")
