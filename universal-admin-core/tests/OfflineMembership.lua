-- Exercise the actual offline picker callbacks and their network payloads.
require = function() end
local checks = 0
local function check(ok, message) assert(ok, message); checks = checks + 1 end
local UI = {}; UI.__index = UI
function UI:derive() return setmetatable({}, {__index=self}) end
function UI:new(x,y,w,h,text,target,callback)
    return setmetatable({width=w,height=h,target=target,callback=callback}, self)
end
function UI:initialise() end
function UI:addChild(b) self.button=b end
function UI:setHeight(h) self.height=h end
function UI:setVisible() end
function UI:removeFromUIManager() end
ISPanel=UI; ISButton=UI
ISSafehouseAddPlayerUI=UI:derive(); ISFactionAddPlayerUI=UI:derive()
AdminCore={allowed=function() return true end,fit=function() end}
Capability={CanSetupSafehouses=1,FactionCheat=2}
Events={OnNetworkUsersReceived={Add=function() end}}
local sent
sendClientCommand=function(module,command,args) sent={command=command,args=args} end
dofile("universal-admin-core/media/lua/client/AdminCore/OfflinePlayers.lua")
local T=AdminCore
T.pickAccount=function(_,_,_,callback) callback("offline-account") end
T.confirm=function(_,callback) callback() end
local function house(localId)
    return {getId=function() return localId end,getX=function() return 300 end,
        getY=function() return 400 end,getW=function() return 10 end,getH=function() return 10 end,
        getOwner=function() return "owner" end}
end
local server,client=house("server-timestamp"),house("client-timestamp")
check(T.safehouseKey(server)==T.safehouseKey(client),"Client and server must agree despite different IDs")
check(T.safehouseKey(client)=="300,400,10,10","Network key matches the complete bounds")
for _,transfer in ipairs({false,true}) do
    local panel=setmetatable({width=500,height=400,safehouse=client,changeOwnership=transfer},{__index=ISSafehouseAddPlayerUI})
    panel:initialise(); panel.button.callback(panel)
    check(sent.args.id=="300,400,10,10","Offline action must send network bounds instead of local ID")
    check(sent.command==(transfer and "transferOnly" or "addMember"),"Correct membership action")
    check((sent.args.replacement or sent.args.username)=="offline-account","Selected account preserved")
end
T.replaceOwner("safehouse",client,"owner")
check(sent.command=="transferOwner" and sent.args.id=="300,400,10,10","User List ownership transfer uses same key")
check(sent.args.username=="owner" and sent.args.replacement=="offline-account","Owner staleness guard retained")
local faction={getName=function() return "Faction name" end,getOwner=function() return "owner" end}
local panel=setmetatable({width=500,height=400,faction=faction},{__index=ISFactionAddPlayerUI})
panel:initialise(); panel.button.callback(panel)
check(sent.args.kind=="faction" and sent.args.id=="Faction name","Faction lookup remains name-based")
print("PASS: "..checks.." offline membership payload checks")
