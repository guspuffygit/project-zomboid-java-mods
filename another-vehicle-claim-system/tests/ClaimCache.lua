local root = "another-vehicle-claim-system/media/lua/"
local checks = 0
local function check(ok, why)
    assert(ok, why)
    checks = checks + 1
end
local callbacks = {}
Events = setmetatable({}, {
    __index = function(t, name)
        local event = {
            Add = function(fn)
                callbacks[name] = callbacks[name] or {}
                callbacks[name][fn] = true
            end,
            Remove = function(fn)
                if callbacks[name] then
                    callbacks[name][fn] = nil
                end
            end,
        }
        rawset(t, name, event)
        return event
    end,
})
local now, player = 100000, {}
getTimestampMs = function()
    return now
end
getTimestamp = function()
    return math.floor(now / 1000)
end
getPlayer = function()
    return player
end
isClient = function()
    return true
end
isServer = function()
    return false
end
local requests = {}
sendClientCommand = function(...)
    requests[#requests + 1] = { ... }
end
AVCS = { UI = {} }
require = function(name)
    dofile(root .. "client/" .. name .. ".lua")
    return AVCS.Sync
end
dofile(root .. "client/AVCSClient.lua")
local S = AVCS.Sync
S.request()
check(#requests == 1 and not S.ready(), "Initial snapshot request")
for i = 1, 1000 do
    S.request()
end
check(#requests == 1, "Repeated refresh signals coalesce")
local oldVehicles, oldPlayers =
    { [8] = { OwnerPlayerID = "old", CarModel = "Base.CarNormal" } }, { old = { [8] = true } }
AVCS.dbByVehicleSQLID, AVCS.dbByPlayerID = oldVehicles, oldPlayers
S.receiveSnapshot({ requestId = 0, vehicles = {}, players = {} })
check(AVCS.dbByVehicleSQLID == oldVehicles, "Stale response ignored")
S.receive("vehicle", { [1] = { OwnerPlayerID = "alice", CarModel = "Base.CarNormal" } }, 1)
check(
    S.ready() and AVCS.dbByVehicleSQLID == oldVehicles,
    "Existing cache usable during half snapshot"
)
S.receive("player", {}, 1)
check(S.ready() and AVCS.dbByPlayerID.alice[1], "Missing owner back-reference repaired from claims")
check(not S.hook and not S.waiting, "Successful repair stops retries")
AVCS.updateClientClaimVehicle({ VehicleID = 2, OwnerPlayerID = "bob", CarModel = "Base.CarNormal" })
check(AVCS.dbByVehicleSQLID[2] and AVCS.dbByPlayerID.bob[2], "Claim creates owner index")
AVCS.updateClientClaimVehicle({
    VehicleID = 2,
    OwnerPlayerID = "alice",
    CarModel = "Base.CarNormal",
})
check(
    not AVCS.dbByPlayerID.bob or not AVCS.dbByPlayerID.bob[2],
    "Reclaim clears previous owner index"
)
AVCS.updateClientSpecifyVehicleUserPermission({
    VehicleID = 2,
    AllowDrive = true,
    PermissionRevision = 2,
})
AVCS.updateClientSpecifyVehicleUserPermission({
    VehicleID = 2,
    AllowDrive = false,
    PermissionRevision = 1,
})
check(AVCS.dbByVehicleSQLID[2].AllowDrive, "Older permission revision ignored")
AVCS.updateClientSpecifyVehicleUserPermission({
    VehicleID = 2,
    AllowDrive = false,
    PermissionRevision = 3,
})
check(not AVCS.dbByVehicleSQLID[2].AllowDrive, "Explicit false delivered")
S.request()
now = now + 5000
S.hook()
local first = S.requestId
S.receiveSnapshot({
    requestId = first,
    vehicles = { [4] = { OwnerPlayerID = "carol", CarModel = "Base.CarNormal" } },
    players = { wrong = {
        [4] = true,
    } },
})
check(
    S.ready() and AVCS.dbByPlayerID.carol[4] and not AVCS.dbByPlayerID.wrong,
    "Atomic snapshot rebuilds inconsistent index"
)
local retained = AVCS.dbByVehicleSQLID
S.request()
local before = #requests
for i = 1, 4 do
    now = now + 20000
    if S.hook then
        S.hook()
    end
end
check(
    S.failed and not S.hook and #requests - before <= 3,
    "Missing replies stop after bounded attempts"
)
for i = 1, 1000 do
    S.request()
end
check(not S.hook, "Passive deltas cannot restart an exhausted loop")
check(S.ready() and AVCS.dbByVehicleSQLID == retained, "Retry exhaustion preserves usable cache")
S.request(true)
check(S.hook and not S.failed, "Explicit reopen can retry")
S.receiveSnapshot({ requestId = S.requestId, vehicles = {}, players = {} })
local empty = true
for _ in pairs(AVCS.dbByVehicleSQLID) do
    empty = false
end
check(S.ready() and empty, "Empty snapshot clears removed claims")
for callback in pairs(callbacks.OnDisconnect) do
    callback()
end
check(not S.ready() and not S.hook, "Disconnect clears cache and hooks")
print("PASS: " .. checks .. " claim-cache failure/recovery checks")
