local root=(arg[1] or "guspuffy-atf-patches/build/vendor-fixtures") .. "/mod-after_the_fall_core_b42/42.14/media/lua/"
local function array(data)
    local a={data=data or {}}
    function a:size() return #self.data end
    function a:get(i) return self.data[i+1] end
    function a:clear() self.data={} end
    function a:add(v) self.data[#self.data+1]=v end
    return a
end
local checks=0
local function check(ok,why) assert(ok,why); checks=checks+1 end
local function house(x,title,owner)
    local h={X=x,Y=20,W=10,H=10,Title=title,Owner=owner,LastVisited=1,DatetimeCreated=2,Location="Town",HitPoints=0,OpenTimer=0,
        Players=array({"bob"}),PlayersRespawn=array({"bob"})}
    for _,field in ipairs({"X","Y","W","H","Title","Owner","LastVisited","DatetimeCreated","Location","HitPoints","OpenTimer","Players","PlayersRespawn"}) do
        h["get"..field]=function(self) return self[field] end
        h["set"..field]=function(self,v) self[field]=v end
    end
    h.getX2=function(self) return self.X+self.W end
    h.getY2=function(self) return self.Y+self.H end
    return h
end
local one,two=house(10,"Shared","alice"),house(100,"Shared","alice")
local houses=array({one,two})
local removed,added=0,0
SafeHouse={getSafehouseList=function() return houses end,updateSafehousePlayersConnected=function() end,
    removeSafeHouse=function(h) for i=#houses.data,1,-1 do if houses.data[i]==h then table.remove(houses.data,i); removed=removed+1 end end end,
    addSafeHouse=function(x,y,w,h,owner) local sh=house(x,"new",owner); houses:add(sh); added=added+1; return sh end}
local events={}
Events=setmetatable({}, {__index=function(t,name)
    local e={Add=function(fn) events[name]=events[name] or {}; events[name][#events[name]+1]=fn end,Remove=function() end}; rawset(t,name,e); return e
end})
local now=0
os.time=function() return now end
local player={getUsername=function() return "alice" end,getAccessLevel=function() return "" end}
getOnlinePlayers=function() return array({player}) end
local sent={}
sendServerCommand=function(p,module,command,args) sent[#sent+1]={command=command,args=args} end
local function fire(event,...) for _,fn in ipairs(events[event] or {}) do fn(...) end end
dofile(root.."server/ATF_SafetySystem/ATF_SafehouseGuard_Server.lua")
fire("EveryOneMinute"); now=60; fire("EveryOneMinute")
check(#sent==1 and #sent[1].args.safehouses==2,"Duplicate titles remain distinct in authoritative snapshot")
now=120; fire("EveryOneMinute"); check(#sent==1,"Unchanged fallback poll sends no full broadcast")
one.LastVisited=99; one.OpenTimer=10; now=180; fire("EveryOneMinute")
check(#sent==1,"Activity-only timers do not cause server-wide resends")
one.Title="Renamed"; now=240; fire("EveryOneMinute")
check(#sent==2 and sent[2].command=="SafehouseSync","Rename refreshes payload without false removal alert")
fire("OnClientCommand","ATF","RequestSafehouseSync",player,{})
check(#sent==3,"On-demand initial synchronization bypasses broadcast suppression")
local payload=sent[3].args
one.Title="Shared"
fire("OnClientCommand","ATF","RequestRelease",player,{title="Shared"})
check(sent[#sent].command=="ReleaseDenied","Ambiguous legacy title cannot release a different house")
fire("OnClientCommand","ATF","RequestRelease",player,{title="Shared",id="10,20,10,10"})
check(sent[#sent].command=="ReleaseApproved","Stable bounds key resolves duplicate title safely")
local localOne,localTwo=house(10,"Old","oldOwner"),house(100,"Shared","oldOwner")
localOne.Players=array({"stale"}); houses=array({localOne,localTwo})
sendSafehouseRelease=function() end
sendClientCommand=function() end
triggerEvent=function() end
getPlayer=function() return player end
dofile(root.."client/ATF_SafetySystem/ATF_SafehouseGuard_Client.lua")
fire("OnServerCommand","ATF","SafehouseSync",payload)
check(added==0 and removed==0 and houses:get(0)==localOne,"Rename updates same native house object in place")
check(localOne.Title=="Renamed" and localOne.Owner=="alice","Title and ownership repaired by stable key")
check(localOne.Players:get(0)=="bob" and localOne.PlayersRespawn:get(0)=="bob","Members and respawn membership preserved")
check(localOne.LastVisited==99 and localOne.DatetimeCreated==2 and localOne.Location=="Town","Metadata preserved")
fire("OnServerCommand","ATF","SafehouseSync",{safehouses={}})
check(houses:size()==2,"Incomplete legacy snapshot cannot delete native membership data")
fire("OnServerCommand","ATF","SafehouseSync",{schema=2})
check(houses:size()==0,"B42 nil-encoded empty authoritative list removes last house")
print("PASS: "..checks.." safehouse synchronization checks")
