local root = "another-vehicle-claim-system/media/lua/"
local checks, now, requests = 0, 1000, 0
local function check(ok, message)
    assert(ok, message)
    checks = checks + 1
end
Events = setmetatable({}, {
    __index = function()
        return { Add = function() end, Remove = function() end }
    end,
})
isClient = function()
    return true
end
isServer = function()
    return false
end
getTimestampMs = function()
    return now
end
getTimestamp = function()
    return now / 1000
end
getText = function(key, a, b)
    return key .. ":" .. tostring(a) .. ":" .. tostring(b)
end
local player = {
    getUsername = function()
        return "alice"
    end,
    getAccessLevel = function()
        return "none"
    end,
    setHaloNote = function(self, text)
        self.notice = text
    end,
}
getPlayer = function()
    return player
end
sendClientCommand = function()
    requests = requests + 1
end
SandboxVars = { AVCS = { MaxVehicle = 5 } }
dofile(root .. "shared/AVCSShared.lua")
require = function()
    return AVCS.Sync or dofile(root .. "client/AVCSSync.lua")
end
dofile(root .. "client/AVCSClient.lua")
local S = AVCS.Sync
local function claim(owner)
    return {
        OwnerPlayerID = owner,
        CarModel = "Base.CarNormal",
        LastLocationX = 11,
        LastLocationY = 22,
        AllowDrive = true,
        AllowOpeningTrunk = true,
    }
end
local function snapshot(vehicles, players)
    now = now + 20000
    S.request(true)
    S.receiveSnapshot({ requestId = S.requestId, vehicles = vehicles, players = players or {} })
end
local function vehicle(id)
    return {
        getModData = function()
            return { SQLID = id }
        end,
    }
end
snapshot({ [1] = claim("alice"), [2] = { CarModel = "Base.CarNormal" } })
check(S.ready() and not S.waiting, "first sync completes despite one malformed owner")
check(
    AVCS.dbByVehicleSQLID[1] and S.unavailableCount == 1,
    "healthy claim published with separate unavailable count"
)
check(
    AVCS.dbByVehicleSQLID[2] == nil and S.isUnavailable(2),
    "unresolved claim is not fabricated as a normal record"
)
check(
    not AVCS.getSimpleBooleanPermission(AVCS.checkPermission(player, vehicle(2))),
    "quarantine is denied rather than the unsupported-vehicle false sentinel"
)
check(
    not AVCS.getPublicPermission(vehicle(2), "AllowDrive")
        and not AVCS.getPublicPermission(vehicle(2), "AllowOpeningTrunk"),
    "quarantine cannot inherit unclaimed public driving or cargo access"
)
check(not AVCS.checkManagementPermission(player, 2), "quarantined claim cannot be managed")
check(
    AVCS.getSimpleBooleanPermission(AVCS.checkPermission(player, vehicle(1))),
    "healthy owner access remains usable"
)
check(
    AVCS.checkPermission(player, vehicle(99)) == true,
    "identified damage does not lock unrelated unclaimed vehicles"
)
check(S.warning():find("1:0", 1, true), "warning reports identified and unidentified counts")
local before = requests
AVCS.requestAdminTeleportVehicle(2)
AVCS.requestAdminUntowVehicle(2)
check(requests == before, "unavailable record does not send teleport or untow")
snapshot({ [1] = claim("alice"), [2] = claim("bob"), [3] = claim("alice") })
check(
    not S.degraded() and AVCS.dbByPlayerID.bob[2],
    "repaired snapshot clears quarantine and rebuilds owner index"
)
local old = AVCS.dbByVehicleSQLID[2]
snapshot({ [1] = claim("carol"), [2] = { OwnerPlayerID = false }, [4] = claim("alice") })
check(
    AVCS.dbByVehicleSQLID[2].OwnerPlayerID == old.OwnerPlayerID and S.isUnavailable(2),
    "refresh retains last-known-good damaged claim"
)
check(
    AVCS.dbByVehicleSQLID[1].OwnerPlayerID == "carol" and AVCS.dbByVehicleSQLID[4],
    "healthy additions and owner changes still refresh"
)
check(
    AVCS.dbByVehicleSQLID[3] == nil,
    "valid removal is honored despite another identified bad record"
)
check(
    not AVCS.getPublicPermission(vehicle(2), "AllowDrive"),
    "last-known public allow flag cannot bypass quarantine"
)
snapshot({ [1] = claim("carol"), ["2"] = claim("bob") })
check(
    S.isUnavailable(2) and AVCS.dbByVehicleSQLID[2].OwnerPlayerID == "bob",
    "numeric-string key establishes identity only for quarantine"
)
snapshot({ [1] = claim("alice"), bad = claim("bob") })
check(
    S.unknownCount == 1 and S.isUnavailable(2),
    "unidentified record prevents silently dropping an omitted old claim"
)
check(
    AVCS.dbByVehicleSQLID[1].OwnerPlayerID == "alice",
    "unknown record does not block healthy refresh"
)
check(
    not AVCS.getSimpleBooleanPermission(AVCS.checkPermission(player, vehicle(123))),
    "unresolved identities are unavailable instead of silently unclaimed"
)
local retained = AVCS.dbByVehicleSQLID
now = now + 20000
S.request(true)
S.receiveSnapshot({ requestId = S.requestId, players = {} })
check(
    S.invalidEnvelope and S.waiting and AVCS.dbByVehicleSQLID == retained,
    "missing envelope table preserves cache and retries"
)
S.receiveSnapshot({ requestId = S.requestId, vehicles = {}, players = "broken" })
check(
    AVCS.dbByVehicleSQLID == retained,
    "malformed player envelope is not an empty successful snapshot"
)
S.receiveSnapshot({ requestId = S.requestId, vehicles = {}, players = {} })
local remainingClaims = 0
for _ in pairs(AVCS.dbByVehicleSQLID) do
    remainingClaims = remainingClaims + 1
end
check(
    not S.degraded() and remainingClaims == 0,
    "valid empty snapshot authoritatively removes claims and markers"
)
snapshot({
    [-1] = claim("alice"),
    [1.5] = claim("alice"),
    [math.huge] = claim("alice"),
    [1] = claim(""),
})
check(
    S.unknownCount == 3 and S.unavailableCount == 1,
    "invalid numeric identities and empty owner handled without crashes"
)
snapshot({
    [5] = { OwnerPlayerID = "alice", CarModel = "Base.CarNormal", AllowDrive = "yes" },
    [6] = { OwnerPlayerID = "alice" },
})
check(
    S.unavailableCount == 2,
    "malformed permission/model cannot break permission or management consumers"
)
snapshot({ [5] = claim("alice") })
check(not S.degraded(), "repair clears all obsolete unavailable markers")
snapshot({ [5] = { OwnerPlayerID = false } })
AVCS.updateClientClaimVehicle({
    VehicleID = 5,
    OwnerPlayerID = "alice",
    CarModel = "Base.CarNormal",
})
check(not S.isUnavailable(5), "complete authoritative claim delta can repair a known quarantine")
check(
    AVCS.dbByVehicleSQLID[5].ClaimDateTime == 0 and AVCS.dbByVehicleSQLID[5].LastLocationX == 0,
    "repair delta provides safe display defaults"
)
snapshot({ [10] = { OwnerPlayerID = false } })
snapshot({ bad = claim("alice") })
check(
    S.unavailable[10] and S.unavailableCount == 1,
    "unknown snapshot preserves unresolved identities with no last-known-good record"
)
snapshot({ [9] = { OwnerPlayerID = false } })
AVCS.updateClientUnclaimVehicle({ VehicleID = 9, OwnerPlayerID = "alice" })
check(not S.isUnavailable(9), "explicit unclaim removes an unresolved known identity")
getTextOrNull = function(key)
    return key
end
AVCS.onAdminTeleportVehicleResult({ ok = false, reason = "badArgs", VehicleID = 1 })
check(
    player.notice == "IGUI_AVCS_Admin_Teleport_badArgs",
    "failure packet reaches the existing translated client halo handler"
)
print("PASS: " .. checks .. " quarantine, permission, recovery and client failure-message checks")
