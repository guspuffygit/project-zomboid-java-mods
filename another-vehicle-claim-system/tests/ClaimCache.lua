local root = "another-vehicle-claim-system/media/lua/"
local checks = 0
local function check(ok, why) assert(ok, why); checks = checks + 1 end
local callbacks = {}
Events = setmetatable({}, {__index = function(t, name)
    local event = {Add=function(fn) callbacks[name] = callbacks[name] or {}; callbacks[name][fn] = true end,
                   Remove=function(fn) if callbacks[name] then callbacks[name][fn] = nil end end}
    rawset(t, name, event); return event
end})
local now, player = 100000, {}
getTimestampMs = function() return now end
getTimestamp = function() return math.floor(now / 1000) end
getPlayer = function() return player end
isClient = function() return true end
isServer = function() return false end
local requests = {}
sendClientCommand = function(...) requests[#requests + 1] = {...} end
AVCS = {UI={}}
require = function(name) dofile(root .. "client/" .. name .. ".lua"); return AVCS.Sync end
dofile(root .. "client/AVCSClient.lua")
local S = AVCS.Sync
S.request()
check(#requests == 1 and not S.ready(), "One initial request; unknown is not ready")
for i = 1, 1000 do S.request() end
check(#requests == 1, "1000 desync signals coalesce into one request")
local oldVehicles, oldPlayers = {}, {}
AVCS.dbByVehicleSQLID, AVCS.dbByPlayerID = oldVehicles, oldPlayers
S.receive("vehicle", {[1]={OwnerPlayerID="alice"}}, 1)
check(AVCS.dbByVehicleSQLID == oldVehicles and not S.ready(), "Half snapshot never published")
S.receive("player", {alice={[1]=true}}, 0)
check(not S.ready(), "Old generation ignored")
S.receive("player", {alice={[1]=true}}, 1)
check(S.ready() and AVCS.dbByVehicleSQLID[1] and AVCS.dbByPlayerID.alice[1], "Matching pair published atomically")
check(not callbacks.OnTick[S.hook], "Recovery hook detached after success")
AVCS.dbByPlayerID = nil
local before = AVCS.dbByVehicleSQLID
AVCS.updateClientClaimVehicle({VehicleID=2,OwnerPlayerID="bob"})
check(not before[2] and not S.ready(), "Missing owner index cannot partially claim")
now = now + 5000
S.hook()
check(#requests == 2, "Deferred recovery request is eventually sent")
S.receive("vehicle", {[1]={OwnerPlayerID="alice"}}, 2)
S.receive("player", {}, 2)
check(not S.ready(), "Inconsistent pair rejected")
now = now + 5000; S.hook()
S.receive("player", {alice={[1]=true}}, 3)
S.receive("vehicle", {[1]={OwnerPlayerID="alice"}}, 3)
check(S.ready(), "Player half may arrive first")
AVCS.updateClientUnclaimVehicle({VehicleID=1,OwnerPlayerID="wrong"})
check(AVCS.dbByVehicleSQLID[1] and AVCS.dbByPlayerID.alice[1], "Mismatched owner cannot partially unclaim")
now = now + 5000; S.hook()
S.receive("vehicle", {[1]={OwnerPlayerID="alice"}}, 4)
S.receive("player", {alice={[1]=true}}, 4)
AVCS.updateClientUnclaimVehicle({VehicleID=1,OwnerPlayerID="alice"})
check(not AVCS.dbByVehicleSQLID[1] and not AVCS.dbByPlayerID.alice[1], "Unclaim updates both indexes")
AVCS.updateClientClaimVehicle({VehicleID=2,OwnerPlayerID="bob"})
check(AVCS.dbByVehicleSQLID[2] and AVCS.dbByPlayerID.bob[2], "Claim creates owner index")
AVCS.updateClientSpecifyVehicleUserPermission({VehicleID=2,AllowDrive=true,PermissionRevision=2})
AVCS.updateClientSpecifyVehicleUserPermission({VehicleID=2,AllowDrive=false,PermissionRevision=1})
check(AVCS.dbByVehicleSQLID[2].AllowDrive == true, "Older permission revision cannot overwrite newer state")
AVCS.updateClientSpecifyVehicleUserPermission({VehicleID=2,AllowDrive=false,PermissionRevision=3})
check(AVCS.dbByVehicleSQLID[2].AllowDrive == nil, "Explicit false permission survives transport")
S.request(); now = now + 5000; player = nil
local count = #requests; S.hook()
check(#requests == count, "No sends before player exists")
print("PASS: " .. checks .. " claim-cache failure/recovery checks")
