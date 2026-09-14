-- Runs against the installed game's actual Admin Panel, with UI/engine boundaries stubbed.
local game=assert(arg[1],"Pass the installed game directory")
local client="universal-admin-core/media/lua/client/AdminCore/"
require=function() end
local count=0
local function check(value,message) assert(value,message); count=count+1 end
local caps={}
Capability=setmetatable({}, {__index=function(_,key) return key end})
local role={hasCapability=function(_,cap) return caps[cap]~=false end,hasAdminPower=function() return true end}
local player={getRole=function() return role end,getUsername=function() return "admin" end,
    getCurrentSquare=function() return {} end,getX=function() return 1 end,getY=function() return 2 end,getZ=function() return 0 end}
getPlayer=function() return player end
local sw,sh,font=1280,720,16
getCore=function() return {getScreenWidth=function() return sw end,getScreenHeight=function() return sh end} end
getTextManager=function() return {getFontHeight=function() return font end,MeasureStringX=function(_,f,t) return #t*8 end} end
UIFont={Small=1,Medium=2}
getText=function(text) return text end; getTextOrNull=getText
string.sort=function(a,b) return a<b end
local empty={size=function() return 0 end}
Faction={getFactions=function() return empty end}; SafeHouse={getSafehouseList=function() return empty end}
Events=setmetatable({}, {__index=function(t,key) local e={Add=function() end};rawset(t,key,e);return e end})
local W={}
W.__index=W
function W:derive(name) local cls={Type=name}; cls.__index=cls; setmetatable(cls,self); return cls end
function W:new(x,y,w,h) return setmetatable({x=x,y=y,width=w,height=h,children={},visible=true,enable=true},self) end
for _,name in ipairs({"X","Y","Width","Height"}) do
    local field=name:lower()
    W["get"..name]=function(self) return self[field] end
    W["set"..name]=function(self,value) self[field]=value end
end
function W:getBottom() return self.y+self.height end
function W:addChild(child) self.children[#self.children+1]=child; child.parent=self end
function W:getChildren() return self.children end
function W:initialise() end
function W:instantiate() end
function W:setVisible(value) self.visible=value end
function W:getIsVisible() return self.visible end
function W:setEnable(value) self.enable=value end
function W:setTitle(value) self.title=value end
function W:drawText() end
ISPanel=W:derive("ISPanel")
ISButton=W:derive("ISButton")
function ISButton:new(x,y,w,h,title,target,onclick)
    local b=W.new(self,x,y,w,h);b.title=title;b.target=target;b.onclick=onclick;return b
end
ISResizeWidget=W:derive("ISResizeWidget")
ISLayoutManager={RegisterWindow=function() end}
ISTextEntryBox=W:derive("ISTextEntryBox")
function ISTextEntryBox:new(text,x,y,w,h) local e=W.new(self,x,y,w,h);e.text=text;return e end
function ISTextEntryBox:getInternalText() return self.text end
function ISTextEntryBox:setText(text) self.text=text end
dofile(game.."/media/lua/client/ISUI/AdminPanel/ISAdminPanelUI.lua")
dofile(client.."WindowSizing.lua")
dofile(client.."Registry.lua")
dofile(client.."Tools.lua")
dofile(client.."ControlCenter.lua")
local C=AdminCore
local commands={}
SendCommandToServer=function(command) commands[#commands+1]=command end
local p=ISAdminPanelUI:new(10,10,400,400)
p:create()
check(#p.uacNav==10,"All requested control-center categories exist")
check(#commands==0,"Opening control center must not perform a server action")
local native=0
for _,e in ipairs(p.uacEntries) do if not e.action then native=native+1 end end
check(native==17,"All 17 native admin actions survive extraction")
check(p.seeUsersBtn.visible,"User List is a dashboard shortcut")
check(not p.itemListBtn.visible,"World inventory spawning stays out of dashboard")
local climateCalls=0
ISAdminWeather={OnOpenPanel=function() climateCalls=climateCalls+1; return {onMadeActive=function() end} end}
p.uacSearch:setText("weather");p:uacRefresh()
check(p.climateOptionsBtn.visible,"Search finds native actions by topic across categories")
p.climateOptionsBtn.onclick(p.climateOptionsBtn.target,p.climateOptionsBtn)
check(climateCalls==1,"Native action retains original callback")
caps.ClimateManager=false;p:updateButtons()
check(not p.climateOptionsBtn.enable,"Native capability changes still disable action")
check(not C.matchesAction("Save","Server","","Server","[",false),"Search treats Lua patterns literally")
check(not pcall(C.registerAction,{id="unsafe",title="Unsafe",category="Server",run=function() end}),"Extension requires explicit permission gate")
local ran=0
local action={id="test.permission",title="Test gated action",category="Security",capability="Test",run=function() ran=ran+1 end}
C.registerAction(action)
C.message=function() end
C.runAction(action);caps.Test=false;C.runAction(action)
check(ran==1,"Revoked permission is checked again when action executes")
local confirm
C.confirm=function(_,fn) confirm=fn end
C.announce('hello"\n/quit')
check(not confirm and #commands==0,"Announcement rejects parser injection")
C.announce("Restart in 10 minutes")
check(confirm~=nil and #commands==0,"Announcement waits for confirmation")
caps.DisplayServerMessage=false;confirm()
check(#commands==0,"Permission revoked during confirmation prevents broadcast")
caps.DisplayServerMessage=true;C.announce("Restart in 10 minutes");confirm()
check(commands[1]=='/servermsg "Restart in 10 minutes"',"Confirmed message uses native server command")
local added=ISButton:new(0,0,100,30,"Third-party tool",nil,function() end)
added.internal="UNKNOWN_EXTENSION";added.enable=false;added.tooltip="Original tooltip"
p:addChild(added);p.uacSection="Mods";p.uacSearch:setText("");p:uacRefresh()
check(added.visible and not added.enable and added.tooltip=="Original tooltip","Late third-party controls retain state and appear in Mods")
for i=1,90 do C.registerAction({id="test."..i,title="Extra "..i,category="Mods",capability="Test",run=function() end}) end
p.uacDirty=true
for _,screen in ipairs({{1280,720,16},{1280,720,28},{800,600,28}}) do
    sw,sh,font=screen[1],screen[2],screen[3]
    C.fit(p,960,600);p.uacSection="Mods";p.uacPage=1;p.uacSearch:setText("");p:uacRefresh()
    local seen={}
    repeat
        for _,e in ipairs(p.uacEntries) do
            local b=e.button
            if b.visible then
                seen[b]=true
                check(b.x>=180 and b.x+b.width<=p.width-12,"Action fits horizontally")
                check(b.y>=108 and b.y+b.height<=p.height-50,"Action stays above footer")
            end
        end
        if not p.uacNext.enable then break end
        p.uacNext.onclick(p,p.uacNext)
    until false
    local reached=0;for _ in pairs(seen) do reached=reached+1 end
    check(reached==92,"Pagination keeps all native and extension actions reachable")
end
print("PASS: "..count.." control-center integration/layout checks")
