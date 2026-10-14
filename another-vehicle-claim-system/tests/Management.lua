local path = "another-vehicle-claim-system/media/lua/"
local n = 0
local function check(value, msg)
    assert(value, msg)
    n = n + 1
end
Events = setmetatable({}, {
    __index = function()
        return { Add = function() end }
    end,
})
isClient = function()
    return false
end
isServer = function()
    return true
end
getTimestamp = function()
    return 100
end
writeLog = function() end
local now = 100000
getTimestampMs = function()
    return now
end
ModData = { add = function() end }
local replies = {}
sendServerCommand = function(...)
    replies[#replies + 1] = { ... }
end
dofile(path .. "shared/AVCSShared.lua")
dofile(path .. "server/AVCSAudit.lua")
dofile(path .. "server/AVCSServer.lua")
local function player(name, role)
    return {
        getUsername = function()
            return name
        end,
        getAccessLevel = function()
            return role
        end,
    }
end
local owner = player("owner", "none")
local guest = player("guest", "none")
local admin = player("admin", "admin")
AVCS.dbByVehicleSQLID = { [12] = { OwnerPlayerID = "owner", AllowDrive = true } }
AVCS.dbByPlayerID = { owner = {} }
check(AVCS.checkManagementPermission(owner, 12), "Owner may manage claim")
check(AVCS.checkManagementPermission(admin, 12), "Admin may manage claim")
check(
    not AVCS.checkManagementPermission(guest, 12),
    "Faction/safehouse trust alone cannot manage claim"
)
check(
    not AVCS.checkManagementPermission(owner, nil) and not AVCS.checkManagementPermission(owner, {}),
    "Malformed claim IDs fail closed"
)
AVCS.onClientCommand(
    "AVCS",
    "updateSpecifyVehicleUserPermission",
    guest,
    { VehicleID = 12, AllowDrive = false }
)
check(
    AVCS.dbByVehicleSQLID[12].AllowDrive == true,
    "Rejected management request does not change permissions"
)
check(not AVCS.updateSpecifyVehicleUserPermission({
    VehicleID = 12,
    AllowDrive = false,
    AllowPassenger = "bad",
}), "Reject malformed permission values")
check(
    AVCS.dbByVehicleSQLID[12].AllowDrive == true,
    "Invalid mixed update cannot partially change claim"
)
check(not AVCS.updateSpecifyVehicleUserPermission({
    VehicleID = 12,
    AllowDrive = false,
    OwnerPlayerID = "guest",
}), "Unknown fields reject the entire update")
check(
    AVCS.dbByVehicleSQLID[12].AllowDrive == true
        and AVCS.dbByVehicleSQLID[12].OwnerPlayerID == "owner",
    "Mixed malicious update cannot partially change claim"
)
check(
    AVCS.updateSpecifyVehicleUserPermission({ VehicleID = 12, AllowDrive = false }),
    "Known boolean accepted"
)
check(AVCS.dbByVehicleSQLID[12].AllowDrive == nil, "Explicit false clears permission")
getVehicleById = function()
    return nil
end
check(
    pcall(AVCS.claimVehicle, owner, nil) and pcall(AVCS.claimVehicle, owner, { vehicle = 9 }),
    "Missing or stale vehicle does not crash claim handler"
)
local detached = 0
local car = {
    getModData = function()
        return { SQLID = 12 }
    end,
    getVehicleTowing = function()
        return {}
    end,
    getVehicleTowedBy = function()
        return nil
    end,
    breakConstraint = function(_, a, b)
        check(a == true and b == false, "Untow uses vanilla detach flags")
        detached = detached + 1
    end,
    getScript = function()
        return {
            getFullName = function()
                return "Base.ModVehicle"
            end,
        }
    end,
    getX = function()
        return 1
    end,
    getY = function()
        return 2
    end,
}
getCell = function()
    return {
        getVehicles = function()
            return {
                iterator = function()
                    local used = false
                    return {
                        hasNext = function()
                            return not used
                        end,
                        next = function()
                            used = true
                            return car
                        end,
                    }
                end,
            }
        end,
    }
end
AVCS.adminUntowVehicle(guest, 12)
check(detached == 0, "Non-admin cannot untow")
AVCS.adminUntowVehicle(admin, 12)
check(detached == 1, "Admin untows matching loaded mod vehicle")
AVCS.adminUntowVehicle(admin, 99)
check(detached == 1, "Unknown claim cannot detach another vehicle")
print("PASS: " .. n .. " vehicle contribution regression checks")

local before = #replies
AVCS.sendFullSync(player("reconnected", "none"), 1, 3)
check(
    #replies == before + 1 and replies[#replies][3] == "fullSyncSnapshotV3",
    "One atomic reply per V3 request"
)
AVCS.sendFullSync(player("reconnected", "none"), 2, 3)
check(#replies == before + 1, "New player object with same username cannot bypass limiter")
now = now + 4001
AVCS.sendFullSync(player("reconnected", "none"), 3, 3)
check(#replies == before + 2, "Limiter permits recovery after interval")
check(
    not AVCS.updateSpecifyVehicleUserPermission({ VehicleID = 0 / 0, AllowDrive = true }),
    "NaN claim identifier rejected"
)
check(
    not AVCS.updateSpecifyVehicleUserPermission({ VehicleID = 12, PermissionRevision = 999 }),
    "Client cannot overwrite server revision"
)
print("PASS: " .. n .. " permission/limiter checks")
