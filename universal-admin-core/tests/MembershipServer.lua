-- Regression tests without starting or changing the test world.
local client="universal-admin-core/media/lua/client/AdminCore/"
local n=0
local function check(value,message) assert(value,message); n=n+1 end
require=function() end
local callbacks={}
Events=setmetatable({}, {__index=function(t,k) local e={Add=function(fn) callbacks[k]=fn end}; rawset(t,k,e); return e end})
ISPanel={derive=function(_,name) return {} end}
ISSafehouseAddPlayerUI={initialise=function() end}
ISFactionAddPlayerUI={initialise=function() end}
Capability=setmetatable({}, {__index=function(_,k) return k end})
local users={
    {name="old",last="2026-08-01 12:00:00",online=false},
    {name="new",last="2026-09-11 12:00:00",online=false},
    {name="online",last="2026-09-01 12:00:00",online=true},
}
local function javaList(rows) return {size=function() return #rows end,get=function(_,i) return rows[i+1] end} end
for _,u in ipairs(users) do
    function u:getUsername() return self.name end
    function u:getLastConnection() return self.last end
    function u:isOnline() return self.online end
end
getUsers=function() return javaList(users) end
AdminCore={stats={}}
dofile(client.."OfflinePlayers.lua")
local sorted=AdminCore.sortedAccounts()
check(sorted[1].username=="online" and sorted[2].username=="new" and sorted[3].username=="old","Online first, then most recent offline account")
check(#AdminCore.sortedAccounts("new")==2,"Exclude current owner from replacement list")

-- In-world selection must lock on release; preserve vanilla Non-PVP behavior.
local removed=0
local function legacy() return {creatingZone=true,setVisible=function() end,removeFromUIManager=function() removed=removed+1 end} end
ISAddSafeZoneUI={instance=legacy()}; ISAddNonPvpZoneUI={new=function() return legacy() end}
ISAdminPanelUI={onOptionMouseDown=function() end}
ISPvpZonePanel={onClick=function() end}
AdminCore.legacyNonPvp=legacy()
dofile(client.."WorldSafezone.lua")
AdminCore.cancelZoneSelection()
check(removed==2 and ISAddSafeZoneUI.instance==nil and AdminCore.legacyNonPvp==nil,"Competing creators dismissed")
local x,y,w,h=AdminCore.zoneBounds(10,20,7,15)
check(x==7 and y==15 and w==4 and h==6,"Reverse drag gives normalized inclusive rectangle")
local zone={drawing=true,dragging=true,heldWorldMenu=true,previousWorldMenu=false,releaseMouse=AdminCoreWorldSafezone.releaseMouse}
ISWorldObjectContextMenu={disableWorldMenu=true}
AdminCoreWorldSafezone.finishDrag(zone)
check(not zone.dragging and not zone.drawing and not ISWorldObjectContextMenu.disableWorldMenu,"Release locks bounds and restores world menu")
local offline=AdminCore.sortedAccounts(nil,true)
check(#offline==2 and offline[1].username=="new","Offline picker excludes online users and keeps recent-first order")

-- Server-side rejection and playtime tracking.
isServer=function() return true end
local now=10000
getTimestampMs=function() return now end
getTimestamp=function() return math.floor(now/1000) end
local persisted={}
ModData={getOrCreate=function() return persisted end}
local caps={}
local player={getUsername=function() return "admin" end,getRole=function() return {hasCapability=function(_,c) return caps[c]==true end} end,
    getX=function() return 1 end,getY=function() return 2 end,getZ=function() return 0 end}
local online={player}
getOnlinePlayers=function() return javaList(online) end
local responses,calls={},{}
sendServerCommand=function(p,m,c,a) responses[#responses+1]={command=c,args=a} end
AdminCoreBridge={
    knownUser=function(_,name) return name=="admin" or name=="guest" end,
    lastSeen=function() return 123 end,
    addMember=function(...) calls[#calls+1]="add"; return "OK" end,
    transferAndRemove=function(...) calls[#calls+1]="transfer"; return "OK" end,
    canObserve=function() return caps.observe end,
    follow=function() return caps.follow end,
    returnFromObserve=function(_,x,y,z) calls[#calls+1]={x=x,y=y,z=z} end,
}
dofile("universal-admin-core/media/lua/server/AdminCoreServer.lua")
local S=AdminCoreServer
local function command(c,a) now=now+1000; S.onCommand("UniversalAdminCore",c,player,a or {}) end
command("stats",{names={"admin"}})
command("addMember",{kind="safehouse",id="1",username="guest"})
command("transferOwner",{kind="faction",id="1",username="guest",replacement="admin"})
check(#responses==0 and #calls==0,"Unprivileged clients cannot query data or change membership")
caps.ReadUserLog=true; caps.CanSetupSafehouses=true; caps.FactionCheat=true
command("stats",{names={"admin"}})
local row=responses[#responses].args.rows[1]
check(not row.tracked,"Missing historical playtime is unavailable")
local tooMany={}; for i=1,51 do tooMany[i]="guest" end
local before=#responses; command("stats",{names=tooMany})
check(#responses==before,"Bound data batch size")
command("addMember",{kind="bad",id="1",username="guest"})
check(#calls==0,"Reject unknown membership kinds")
command("addMember",{kind="safehouse",id="1",username="guest"})
command("transferOwner",{kind="faction",id="1",username="guest",replacement="admin"})
check(calls[1]=="add" and calls[2]=="transfer","Validated requests reach server bridge")
S.tick(); now=now+2000; S.tick()
check(persisted.admin.seconds==2,"Playtime uses real elapsed seconds")
online={}; now=now+2000; S.tick(); now=now+3600000; S.tick()
check(persisted.admin.seconds==2,"Offline time is excluded")
online={player}; now=now+2000; S.tick()
check(persisted.admin.seconds==2,"Rejoin does not credit previous offline interval")
now=now+2000; S.tick(); check(persisted.admin.seconds==4,"Session totals accumulate")
caps.observe=true; caps.follow=true; caps.TeleportToPlayer=true
command("observeStart",{username="guest",x=999,y=999,z=9})
check(persisted.admin.returnPosition.x==1,"Return coordinates are server-owned")
now=now+12000; S.tick()
local returned=calls[#calls]
check(type(returned)=="table" and returned.x==1 and returned.y==2 and returned.z==0,"Expired observation returns to server-recorded origin")
check(persisted.admin.returnPosition==nil,"Completed observation clears pending return")
print("PASS: "..n.." expanded admin regression checks")
