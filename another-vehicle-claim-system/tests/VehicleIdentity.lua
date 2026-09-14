local client=false
isClient=function() return client end
isServer=function() return not client end
SandboxVars={AVCS={MuleParts="Engine"}}
Events=setmetatable({}, {__index=function(t,k) local e={Add=function() end,Remove=function() end}; rawset(t,k,e); return e end})
local root="another-vehicle-claim-system/media/lua/"
dofile(root.."shared/AVCSShared.lua")
local vehicleData={SQLID=1234}
local partData={}
local part={getModData=function() return partData end}
local transmissions=0
local vehicle={getModData=function() return vehicleData end,getPartById=function() return part end,
    transmitPartModData=function(_,p) assert(p==part); transmissions=transmissions+1 end}
assert(AVCS.syncVehicleIdentity(vehicle) and partData.AVCSIdentity==1234,"Claim ID enters native part stream")
AVCS.syncVehicleIdentity(vehicle); assert(transmissions==1,"Unchanged identity does not retransmit")
partData.AVCSIdentity=9999
assert(AVCS.getVehicleID(vehicle)==1234,"Server ignores client-editable identity mirror")
AVCS.syncVehicleIdentity(vehicle)
client=true; vehicleData={}
assert(AVCS.getVehicleID(vehicle)==1234,"Client reads identity after unloaded vehicle arrives with native part data")
require=function(name) dofile(root.."client/"..name..".lua"); return AVCS.Sync end
getVehicleById=function() return vehicle end
dofile(root.."client/AVCSClient.lua")
AVCS.registerClientVehicleSQLID({7,6666,true})
assert(vehicleData.SQLID==nil and AVCS.getVehicleID(vehicle)==1234,"Runtime-ID hint cannot overwrite native part identity")
vehicleData.SQLID=1234
AVCS.registerClientVehicleSQLID({7,6666})
assert(vehicleData.SQLID==1234,"Delayed legacy hint cannot replace a known identity")
getVehicleById=function() return nil end
assert(pcall(AVCS.registerClientVehicleSQLID,{7,1234,true}),"Unloaded hint has no retained runtime-ID queue")
print("PASS: 7 native vehicle identity checks")
