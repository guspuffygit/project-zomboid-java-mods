local callbacks={}
Events=setmetatable({}, {__index=function(t,key) local e={Add=function(fn) callbacks[key]=fn end};rawset(t,key,e);return e end})
local now,calls=1000,0
-- Kahlua does not expose the standard Lua next() global.
next=nil
getTimestampMs=function() return now end
AvcsVehicleSync={apply=function() calls=calls+1;return true end}
dofile(arg[1] or "another-vehicle-claim-system/media/lua/client/AVCSVehicleSync.lua")
callbacks.OnTick();assert(calls==0,"No sync calls while idle")
callbacks.OnServerCommand("Other","vehicleWarp",{vehicle=1,claim=2,x=3,y=4,physicsY=0})
callbacks.OnTick();assert(calls==0,"Ignore unrelated protocol")
callbacks.OnServerCommand("AVCS","vehicleWarp",{vehicle=1,claim=2,x=3,y=4,physicsY=0})
callbacks.OnTick();callbacks.OnTick();assert(calls==1,"Apply once then remove pending sync")
callbacks.OnServerCommand("AVCS","vehicleWarp",{vehicle=1,claim=2,x=3,y=4,physicsY=0})
now=7000;callbacks.OnTick();assert(calls==1,"Expired sync never applies")
print("PASS: 4 AVCS synchronization checks")
