-- Engine boundaries are fixtures. Run in Lua 5.1 and installed B42 Kahlua.
local root = assert(arg[1])
local total = 0
local function check(value, label) total = total + 1; assert(value, label) end
local client, now, permitted, canInteract, dead = false, 10000, true, true, false
local removed, serverSends, clientSends, audits = 0, {}, {}, {}
local handlers = {}
Events = setmetatable({}, {__index = function(t, key)
    local event = {Add = function(fn) handlers[key] = handlers[key] or {}; table.insert(handlers[key],fn) end}
    rawset(t,key,event); return event
end})
isClient = function() return client end
isDebugEnabled = function() return true end
getTimestampMs = function() return now end
Capability = {UseDebugContextMenu = "debug"}
SafeHouse = {isSafehouseAllowInteract = function() return canInteract end}
local role = {hasCapability = function() return permitted end}
local player = {x=100.5,y=100.5,z=0,notes={}}
function player:getRole() return role end
function player:getX() return self.x end
function player:getY() return self.y end
function player:getZ() return self.z end
function player:isDead() return dead end
function player:getUsername() return "admin" end
function player:setHaloNote(text) table.insert(self.notes,text) end
local objects = {rows={}}
function objects:size() return #self.rows end
function objects:get(index) return self.rows[index+1] end
function objects:contains(obj) for _,o in ipairs(self.rows) do if o==obj then return true end end; return false end
local square = {mode="remove"}
function square:getX() return 100 end
function square:getY() return 100 end
function square:getZ() return 0 end
function square:getObjects() return objects end
function square:transmitRemoveItemFromSquare(obj, multiTile)
    self.lastMultiTile = multiTile
    removed=removed+1
    if self.mode=="throw-before" then error("native failure") end
    if self.mode~="no-op" then objects.rows={} end
    if self.mode=="throw-after" then error("partial failure") end
end
local loaded = true
getCell = function() return {getGridSquare=function() return loaded and square or nil end} end
sendServerCommand = function(_,module,command,args) serverSends[#serverSends+1]={module=module,command=command,args=args} end
sendClientCommand = function(_,module,command,args) clientSends[#clientSends+1]={module=module,command=command,args=args} end
writeLog = function(_,text) audits[#audits+1]=text end
local full = false
local container = {getItems=function() return {isEmpty=function() return not full end} end}
local sprite = {getName=function() return "fixtures_fridge_01" end}
local obj = {}
function obj:getSquare() return square end
function obj:getSprite() return sprite end
function obj:getObjectName() return "IsoObject" end
function obj:getObjectIndex() return objects:contains(self) and 0 or -1 end
function obj:getContainerCount() return 1 end
function obj:getContainerByIndex() return container end
local serverPath=root.."/media/lua/server/ATFPatches_AdminTileRemoval.lua"
dofile(serverPath)
local server=ATFPatches_AdminTileRemoval
local function reset()
    server.sessions=setmetatable({}, {__mode="k"})
    objects.rows={obj}; square.mode="remove"
    removed,serverSends,clientSends,audits=0,{},{},{}
    permitted,canInteract,dead,loaded,full=true,true,false,true,false
    player.x,player.y,player.z=100.5,100.5,0
end
local function request(id)
    return {protocol=1,request=id or now,x=100,y=100,z=0,index=0,count=1,sprite="fixtures_fridge_01",objectName="IsoObject"}
end
local function run(args) server.onClientCommand("ATFAdminTile","remove",player,args); return serverSends[#serverSends] and serverSends[#serverSends].args end
reset(); local reply=run(request())
check(reply.ok and removed==1 and not objects:contains(obj),"valid admin request invokes native authoritative removal")
check(square.lastMultiTile==false,"removal cannot expand to unchecked neighboring furniture pieces")
check(#audits==2 and audits[2]:find("removed",1,true),"successful removal has request and completion audit")
objects.rows={obj}; reply=run(request())
check(reply.ok and removed==1 and objects:contains(obj),"duplicate gets receipt and cannot remove successor at same index")
reply=run(request(now-1)); check(not reply.ok and removed==1,"older request cannot replay destructive work")
reset(); permitted=false; run(request()); check(removed==0 and #serverSends==0,"ordinary player cannot use endpoint even with crafted payload")
reset(); canInteract=false; reply=run(request()); check(not reply.ok and reply.text:find("safehouse",1,true) and removed==0,"server safehouse denial preserved and explained")
reset(); player.x=120; reply=run(request()); check(not reply.ok and removed==0,"remote removal blocked")
reset(); player.z=3; reply=run(request()); check(not reply.ok and removed==0,"remote floor blocked")
reset(); dead=true; reply=run(request()); check(not reply.ok and removed==0,"dead admin cannot remove")
reset(); loaded=false; reply=run(request()); check(not reply.ok and reply.text:find("not loaded",1,true) and removed==0,"unloaded server square reported without mutation")
reset(); objects.rows={obj,obj}; reply=run(request()); check(not reply.ok and reply.text:find("lists differ",1,true) and removed==0,"different list length cannot remove another object")
reset(); local args=request(); args.sprite="other_sprite"; reply=run(args); check(not reply.ok and removed==0,"sprite mismatch refused")
reset(); args=request(); args.objectName="IsoDoor"; reply=run(args); check(not reply.ok and removed==0,"object type mismatch refused")
reset(); full=true; reply=run(request()); check(not reply.ok and removed==0 and reply.text:find("contains items",1,true),"inaccessible container contents preserved")
for _,bad in ipairs({{x=-1},{x=0/0},{y=1/0},{z=1.5},{index=-1},{count=0},{count=40000},{sprite=""},{sprite="bad\nname"},{objectName=false},{protocol=2}}) do
    reset(); args=request(); for k,v in pairs(bad) do args[k]=v end
    reply=run(args); check(not reply.ok and removed==0,"malformed or mismatched protocol payload rejected")
end
for _,bad in ipairs({0,-1,1/0,0/0,1.5,"100"}) do
    reset(); args=request(); args.request=bad; run(args)
    check(removed==0 and #serverSends==0,"invalid request identity rejected before processing")
end
reset(); run(request()); objects.rows={obj}; reply=run(request(now+1))
check(not reply.ok and removed==1,"rapid successive removals are rate limited")
now=now+300; reply=run(request(now)); check(reply.ok and removed==2,"admin may remove another tile after rate interval")
for _,mode in ipairs({"throw-before","throw-after","no-op"}) do
    reset(); square.mode=mode; args=request(); reply=run(args)
    check(not reply.ok and removed==1,"engine failure or no-op never claims success: "..mode)
    objects.rows={obj}; run(args); check(removed==1,"uncertain engine outcome cannot replay: "..mode)
end
dofile(serverPath); check(#handlers.OnClientCommand==1,"server hot reload does not duplicate handler")

client=true
local clientPath=root.."/media/lua/client/ATFPatches_DestroyTileShortcut.lua"
dofile(clientPath)
local ui=ATFPatches_DestroyTileShortcut
reset(); ui.pending=nil
ui.destroyTile(obj,player)
check(#clientSends==1 and removed==0 and objects:contains(obj),"client request never removes tile optimistically")
check(ui.pending~=nil,"client tracks pending request")
args=clientSends[1].args
check(args.sprite=="fixtures_fridge_01" and args.count==1 and args.index==0,"request includes identity and list consistency fields")
ui.destroyTile(obj,player); check(#clientSends==1,"repeated clicks cannot queue concurrent deletions")
ui.onServerCommand("ATFAdminTile","removeResult",{request=args.request+1,text="wrong"})
check(ui.pending~=nil,"unmatched server response ignored")
ui.onServerCommand("Other","removeResult",{request=args.request,text="wrong"})
check(ui.pending~=nil,"unrelated module response ignored")
ui.onServerCommand("ATFAdminTile","removeResult",{request=args.request,ok=false,text="Server safehouse denial"})
check(ui.pending==nil and player.notes[#player.notes]=="Server safehouse denial" and removed==0,"server rejection explained with no local mutation")
ui.destroyTile(obj,player); local previous=clientSends[#clientSends].args.request
check(previous>args.request,"request identity increases even in the same millisecond")
now=now+8001; ui.onTick()
check(ui.pending==nil and #clientSends==2 and removed==0,"lost reply times out without retry or local removal")
check(player.notes[#player.notes]:find("Check the tile",1,true),"timeout describes uncertain outcome")
ui.onServerCommand("ATFAdminTile","removeResult",{request=previous,ok=true,text="late"})
check(player.notes[#player.notes]~="late","late timeout reply cannot overwrite current status")
permitted=false; ui.destroyTile(obj,player); check(#clientSends==2,"revoked client capability cannot request removal")
permitted=true; objects.rows={}; ui.destroyTile(obj,player); check(#clientSends==2,"stale local target cannot be requested")
objects.rows={obj}; client=false; ui.destroyTile(obj,player)
check(removed==1 and #clientSends==2,"single-player debug removal retains native path")
dofile(clientPath)
check(#handlers.OnPreFillWorldObjectContextMenu==1 and #handlers.OnServerCommand==1 and #handlers.OnTick==1,"client hot reload keeps one callback per event")
print("Admin tile removal: "..total.." checks passed.")
