-- Load both real Lua handlers. Model B42's empty-table -> nil wire encoding.
local root = arg[2] or "universal-admin-core"
require = function() end
local checks = 0
local function check(ok, message) assert(ok, message); checks=checks+1 end
local function events()
    return setmetatable({}, {__index=function(t,key)
        local event={handlers={}}
        event.Add=function(fn) event.handlers[#event.handlers+1]=fn end
        rawset(t,key,event); return event
    end})
end
local now, dead, powers = 100000, false, true
getTimestampMs=function() return now end
getTimestamp=function() return math.floor(now/1000) end
Capability=setmetatable({}, {__index=function(_,key) return key end})
Keyboard={KEY_ESCAPE=1}
UIFont={Small=1}
local actor={x=10,y=20,z=0}
function actor:getUsername() return "admin" end
function actor:getX() return self.x end
function actor:getY() return self.y end
function actor:getZ() return self.z end
function actor:isDead() return dead end
function actor:getRole() return {hasCapability=function() return powers end} end
getPlayer=function() return actor end
local online={actor}
getOnlinePlayers=function() return {size=function() return #online end,get=function(_,i) return online[i+1] end} end
local UI={}; UI.__index=UI
function UI:new() return setmetatable({},self) end
for _,name in ipairs({"initialise","addChild","addToUIManager","removeFromUIManager","prerender","drawText"}) do UI[name]=function() end end
ISPanel=UI; ISButton=UI
AdminCore={allowed=function() return false end,message=function() end}
local camera, cameraUpdates = nil, 0
AdminCoreObserveCamera={follow=function(name) camera=name; cameraUpdates=cameraUpdates+1 end,stop=function() camera=nil end}
local toServer,toClient={},{}
local heartbeatCount,stopCount=0,0
sendClientCommand=function(module,command,args)
    if command=="observeHeartbeat" then heartbeatCount=heartbeatCount+1 end
    if command=="observeStop" then stopCount=stopCount+1 end
    if args and next(args)==nil then args=nil end
    toServer[#toServer+1]={module=module,command=command,args=args}
end
sendServerCommand=function(player,module,command,args)
    toClient[#toClient+1]={module=module,command=command,args=args}
end
Events=events()
dofile(root.."/media/lua/client/AdminCore/DataAndObserve.lua")
local clientEvents=Events
local persisted={}
ModData={getOrCreate=function() return persisted end}
isServer=function() return true end
local returns, targetOnline = 0, true
AdminCoreBridge={canObserve=function() return powers end,follow=function()
    if not powers or not targetOnline then return false end
    actor.x=100; actor.y=200; return true
end,returnFromObserve=function(player,x,y,z) returns=returns+1; player.x=x;player.y=y;player.z=z end}
Events=events()
dofile(root.."/media/lua/server/AdminCoreServer.lua")
local function drain()
    for _=1,10 do
        if #toServer==0 and #toClient==0 then return end
        while #toServer>0 do
            local p=table.remove(toServer,1)
            AdminCoreServer.onCommand(p.module,p.command,actor,p.args)
        end
        while #toClient>0 do
            local p=table.remove(toClient,1)
            for _,fn in ipairs(clientEvents.OnServerCommand.handlers) do fn(p.module,p.command,p.args) end
        end
    end
    error("Command echo loop")
end
local clientErrors=0
local function advance(ms,withClient)
    now=now+ms
    if withClient~=false then
        for _,fn in ipairs(clientEvents.OnTick.handlers) do
            if not pcall(fn) then clientErrors=clientErrors+1 end
        end
    end
    drain(); AdminCoreServer.tick(); drain()
end
local function start(name)
    sendClientCommand("UniversalAdminCore","observeStart",{username=name or "guest"}); drain()
end
start()
check(AdminCore.observing=="guest" and persisted.admin.returnPosition.x==10,"Start records origin and acknowledges target")
for _=1,120 do
    advance(1000)
    check(AdminCore.observing=="guest" and returns==0,"Empty-payload heartbeats must keep observation alive beyond 12 seconds")
end
check(heartbeatCount==60 and cameraUpdates==120 and camera=="guest","Bounded heartbeats renew camera continuously")
local beforeStops=stopCount
start("guest-two"); advance(1000)
check(AdminCore.observing=="guest-two","Switching target survives old-session stop acknowledgement")
check(stopCount==beforeStops,"Server acknowledgement must not echo a stop for the new session")
local visible=AdminCore.visibleStatNames
AdminCore.visibleStatNames=function() error("Injected unrelated player-list failure") end
for _=1,15 do advance(1000) end
check(clientErrors==15 and AdminCore.observing=="guest-two" and camera=="guest-two","Stats failures cannot starve heartbeat or camera updates")
AdminCore.visibleStatNames=visible
AdminCore.stopObserve(); drain()
check(AdminCore.observing==nil and camera==nil and AdminCore.observePanel==nil,"Stop clears camera and panel")
check(actor.x==10 and actor.y==20 and persisted.admin.returnPosition==nil,"Nil-payload stop returns immediately to origin")
check(stopCount==beforeStops+1,"Stop acknowledgement does not send redundant commands")
local heartbeatBefore=heartbeatCount
advance(2000)
check(heartbeatCount==heartbeatBefore,"Stopped observation sends no heartbeat")
start(); advance(2000); advance(12000,false)
check(AdminCore.observing==nil and actor.x==10,"Actual lost heartbeat still expires and returns")
start(); advance(2000); powers=false; advance(2000)
check(AdminCore.observing==nil and actor.x==10,"Revoked powers stop observation")
powers=true; start(); advance(2000); targetOnline=false; advance(2000)
check(AdminCore.observing==nil and actor.x==10,"Unavailable target stops observation")
targetOnline=true; start(); advance(2000)
for _,fn in ipairs(clientEvents.OnKeyPressed.handlers) do fn(Keyboard.KEY_ESCAPE) end
drain()
check(AdminCore.observing==nil and actor.x==10,"Escape returns immediately")
start(); advance(2000); online={}
for _,fn in ipairs(clientEvents.OnDisconnect.handlers) do fn() end
advance(2000,false)
check(camera==nil and persisted.admin.returnPosition.x==10,"Disconnect clears camera and retains return point")
online={actor}; advance(2000,false)
check(actor.x==10 and persisted.admin.returnPosition==nil,"Reconnect restores origin")
for _,command in ipairs({"stats","observeStart","createSafehouse","addMember","transferOwner","transferOnly"}) do
    local count=#toClient
    AdminCoreServer.onCommand("UniversalAdminCore",command,actor,nil)
    check(#toClient==count,"Payload-required commands still reject nil")
end
check(clientErrors==15,"No unexpected client handler errors")
print("PASS: "..checks.." observe lifecycle checks with native empty-payload semantics")
