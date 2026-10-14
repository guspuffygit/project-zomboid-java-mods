local path = "another-vehicle-claim-system/media/lua/"
local checks = 0
local function check(ok, message)
    assert(ok, message)
    checks = checks + 1
end
isClient = function()
    return false
end
local server = true
isServer = function()
    return server
end
Events = setmetatable({}, {
    __index = function()
        return { Add = function() end }
    end,
})
getTimestamp = function()
    return 100
end
writeLog = function() end
local mutations, reads = 0, 0
ModData = {
    add = function()
        mutations = mutations + 1
    end,
}
sendServerCommand = function()
    mutations = mutations + 1
end
sendRemoveItemFromContainer = function()
    mutations = mutations + 1
end
SandboxVars = { AVCS = { RequireTicket = true, ClaimTimeout = 24 } }
local ticket = {}
local hasTicket, limit, connected, dead, removed, reachable, loaded =
    true, true, true, false, false, true, true
local px, py, pz, vz = 10.5, 20.5, 0, 0
local data = {}
local runtimeId = 7
local inventory = {
    getFirstTypeRecurse = function()
        reads = reads + 1
        return hasTicket and ticket or nil
    end,
    Remove = function(_, item)
        check(item == ticket, "Only the actual ticket is consumed")
        mutations = mutations + 1
    end,
}
local function square(z)
    return {
        getX = function()
            return 10
        end,
        getY = function()
            return 20
        end,
        getZ = function()
            return z
        end,
        canReachTo = function()
            return reachable
        end,
    }
end
local player = {
    isDead = function()
        return dead
    end,
    getPlayerNum = function()
        return 0
    end,
    getUsername = function()
        return "owner"
    end,
    getX = function()
        return px
    end,
    getY = function()
        return py
    end,
    getSquare = function()
        return loaded and square(pz) or nil
    end,
    getInventory = function()
        return inventory
    end,
}
local vehicle = {
    isRemovedFromWorld = function()
        return removed
    end,
    getSquare = function()
        return loaded and square(vz) or nil
    end,
    getModData = function()
        return data
    end,
    getSqlId = function()
        return 42
    end,
    getId = function()
        return runtimeId
    end,
    getX = function()
        return 10.5
    end,
    getY = function()
        return 20.5
    end,
    getScript = function()
        return {
            getFullName = function()
                return "Base.CarNormal"
            end,
        }
    end,
}
getVehicleById = function(id)
    return id == runtimeId and vehicle or nil
end
getSpecificPlayer = function()
    return player
end
getOnlinePlayers = function()
    return {
        size = function()
            return connected and 1 or 0
        end,
        get = function()
            return player
        end,
    }
end
AVCS = {
    getVehicleID = function()
        return data.SQLID
    end,
    checkMaxClaim = function()
        return limit
    end,
    audit = function()
        mutations = mutations + 1
    end,
}
dofile(path .. "server/AVCSServer.lua")
local function reset()
    AVCS.dbByVehicleSQLID, AVCS.dbByPlayerID, AVCS.sortedPlayerTimeoutClaim = {}, {}, {}
    data, mutations, reads = {}, 0, 0
end
local function rejected(message, argument)
    reset()
    AVCS.claimVehicle(player, argument or { vehicle = 7 })
    check(
        mutations == 0 and reads == 0 and data.SQLID == nil,
        message .. " leaves tickets and claims untouched"
    )
end
for _, id in ipairs({ -1, 7.5, 32768, math.huge, -math.huge, 0 / 0, "7" }) do
    rejected("Invalid runtime ID", { vehicle = id })
end
rejected("Stale runtime ID", { vehicle = 8 })
px = 30
rejected("Remote claimant")
px = 10.5
py = 40
rejected("Remote claimant on the other axis")
py = 20.5
pz = 1
rejected("Different floor")
pz = 0
dead = true
rejected("Dead claimant")
dead = false
connected = false
rejected("Disconnected claimant")
connected = true
removed = true
rejected("Removed vehicle")
removed = false
loaded = false
rejected("Unloaded target or claimant square")
loaded = true
reachable = false
rejected("Blocked adjacency")
reachable = true
reset()
data.SQLID = 42
hasTicket = false
AVCS.claimVehicle(player, { vehicle = 7 })
check(
    AVCS.dbByVehicleSQLID[42] == nil and AVCS.dbByPlayerID.owner == nil,
    "Missing ticket still rejects the claim"
)
hasTicket, limit = true, false
reset()
data.SQLID = 42
AVCS.claimVehicle(player, { vehicle = 7 })
check(
    AVCS.dbByVehicleSQLID[42] == nil and AVCS.dbByPlayerID.owner == nil,
    "Claim limit still applies"
)
limit = true
reset()
data.SQLID = 42
AVCS.claimVehicle(player, { vehicle = 7 })
check(
    AVCS.dbByVehicleSQLID[42].OwnerPlayerID == "owner" and AVCS.dbByPlayerID.owner[42],
    "Connected adjacent claimant succeeds"
)
check(reads == 2 and mutations > 0, "Valid claim checks and consumes its ticket")
reset()
data.SQLID = 42
runtimeId = 0
AVCS.claimVehicle(player, { vehicle = 0 })
check(AVCS.dbByVehicleSQLID[42].OwnerPlayerID == "owner", "Native runtime vehicle ID zero is valid")
runtimeId = 7
reset()
data.SQLID = 42
server = false
AVCS.claimVehicle(player, { vehicle = 7 })
check(
    AVCS.dbByVehicleSQLID[42].OwnerPlayerID == "owner",
    "Local player can still claim in single player"
)
print("PASS: " .. checks .. " authoritative claim checks")
