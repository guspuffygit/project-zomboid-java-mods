-- Lua 5.1 regression harness. No running game, accounts or saves are modified.
local client = "universal-admin-core/media/lua/client/AdminCore/"
local checks = 0
local function check(value, message) assert(value, message); checks = checks + 1 end
require = function() end
ISUsersList = {doContextMenu=function() end, initialise=function() end}
ISPlayerStatsManageInvUI = {initialise=function() end}
local caps = {}
Capability = setmetatable({}, {__index=function(_, k) return k end})
local role = {hasCapability=function(_, cap) return caps[cap] == true end}
local player = {getRole=function() return role end, getUsername=function() return "admin" end}
getPlayer = function() return player end
local sw, sh = 1280, 720
getCore = function() return {getScreenWidth=function() return sw end, getScreenHeight=function() return sh end} end
dofile(client .. "WindowSizing.lua")
dofile(client .. "AdminTools.lua")
-- Native scrolling lists call the renderer for every offline account too.
local hidden = {height=100,itemheight=40,getYScroll=function() return -400 end}
local touched = 0
local row = {item={getUsername=function() touched=touched+1; error("Hidden row was evaluated") end}}
for y = 1000, 100000 do ISUsersList.drawDatas(hidden, y, row, false) end
check(touched == 0, "Off-screen rows do no account/faction/render work")
local T = AdminCore
local ownershipPickers=0
T.replaceOwner=function() ownershipPickers=ownershipPickers+1 end
local messages = {}
T.message = function(text) messages[#messages+1] = text end
local function window(w, h)
    local p = {width=w, height=h, x=-300,y=-200,minimumWidth=950,minimumHeight=400}
    for _, field in ipairs({"Width", "Height", "X", "Y"}) do
        local key = field:lower()
        p["set"..field] = function(self,v) self[key]=v end
        p["get"..field] = function(self) return self[key] end
    end
    return p
end
local p = window(2200,1500)
T.fit(p,p.width,p.height)
check(p.width==1264 and p.height==704, "Oversized UI must fit 720p")
check(p.x==8 and p.y==8, "UI must not remain offscreen")
T.fit(p,100,100)
check(p.width==950 and p.height==400, "Minimum usable geometry")
sw,sh=800,600; T.fit(p,2000,2000)
check(p.width==784 and p.height==584, "Screen bounds override minimum on small displays")
sw,sh=1280,720

local function menu()
    local m={options={},numOptions=1}
    function m:addOption(name,target,callback,...)
        local args={...}; local o={name=name,target=target,onSelect=callback,param1=args[1],param2=args[2],id=self.numOptions}
        self.options[self.numOptions]=o; self.numOptions=self.numOptions+1; return o
    end
    function m:getNew() return menu() end
    function m:addSubMenu(option,sub) option.sub=sub end
    function m:calcHeight() end
    function m:calcWidth() return 200 end
    function m:setWidth() end
    return m
end
local context=menu()
local callback=function() end
local setRole=context:addOption("Set Role"); setRole.subOption=42
local kick=context:addOption("Kick",ISUsersList,callback,{},"Kick"); kick.notAvailable=true; kick.toolTip={description="Can't kick self"}
local inv=context:addOption("Inventory",ISUsersList,callback,{},"ManageInventory")
local unknown=context:addOption("Other mod option",{},callback,{},"Unrecognized")
local groups=T.groupMenu(context)
check(groups.Moderation.options[1]==kick, "Preserve original action object")
check(kick.notAvailable and kick.toolTip.description=="Can't kick self", "Preserve disabled and explanatory tooltip")
check(groups.Inventory.options[1]==inv and inv.onSelect==callback, "Preserve inventory callback")
check(context.options[1]==setRole and setRole.subOption==42, "Preserve role submenu")
check(context.options[#context.options]==unknown, "Preserve third-party actions")

local house={id="house-a",owner="owner",members={guest=true}}
function house:getId() return self.id end
function house:getOwner() return self.owner end
function house:getTitle() return "Test home" end
function house:getX() return 100 end
function house:getY() return 200 end
function house:getPlayers() return {contains=function(_,name) return self.members[name] end} end
local houses={house}
SafeHouse={getSafehouseList=function() return {size=function() return #houses end,get=function(_,i) return houses[i+1] end} end}
local faction={name="Test faction",owner="owner"}
function faction:getName() return self.name end
function faction:getOwner() return self.owner end
Faction={getPlayerFaction=function(name) if name=="guest" or name=="owner" then return faction end end}
local removedHouse,removedFaction,released,commands=0,0,0,{}
sendSafehouseChangeMember=function() removedHouse=removedHouse+1 end
sendFactionRemoveMember=function() removedFaction=removedFaction+1 end
sendSafehouseRelease=function() released=released+1 end
SendCommandToServer=function(cmd) commands[#commands+1]=cmd end
check(T.safehouse("guest")==house and T.safehouse("owner")==house and not T.safehouse("random"), "Membership includes owners and members only")
T.removeHouseMember("guest"); T.removeFactionMember("guest")
check(removedHouse==0 and removedFaction==0,"Unprivileged callbacks must not send packets")
local hidden=menu(); T.membershipMenu(hidden,"guest")
check(#hidden.options==0,"Unprivileged users must not see management")
caps.CanSetupSafehouses=true; caps.FactionCheat=true
T.removeHouseMember("owner"); T.removeFactionMember("owner")
check(removedHouse==0 and removedFaction==0,"Cannot orphan a safehouse or faction")
check(ownershipPickers==2,"Owner removal opens replacement-owner workflow")
T.removeHouseMember("guest","stale"); T.removeFactionMember("guest","stale")
check(removedHouse==0 and removedFaction==0,"Stale confirmation cannot remove new membership")
T.removeHouseMember("guest","house-a"); T.removeFactionMember("guest","Test faction")
check(removedHouse==1 and removedFaction==1,"Authorized current member removal sends vanilla packets")
local visible=menu(); T.membershipMenu(visible,"guest")
local confirmation
T.confirm=function(text,action) confirmation=action end
for _,o in ipairs(visible.options[1].sub.options) do if o.name=="Delete safehouse claim..." then o.onSelect() end end
check(released==0 and confirmation,"Deletion requires confirmation")
house.id="new-house"; confirmation()
check(released==0,"Changed safehouse cannot be released by stale confirmation")
house.id="house-a"; caps.CanSetupSafehouses=false; confirmation()
check(released==0,"Permission revoked before confirmation")
caps.CanSetupSafehouses=true; confirmation()
check(released==1,"Confirmed current safehouse release uses vanilla packet")
T.teleportCoordinates(100,200,0); check(#commands==0,"Teleport capability required")
caps.TeleportToCoordinates=true; T.teleportCoordinates(100.9,200.9,0)
check(commands[1]=="/teleportto 100,200,0","Coordinates use supported server command")

luautils={trim=function(s) return s:match('^%s*(.-)%s*$') end}
getScriptManager=function() return {FindItem=function(_,id) return id=="Base.Hammer" end} end
local panel={playerUsername="guest",requestDatas=function() end}
local input="Base.Hammer"
local button={internal="OK",parent={entry={getText=function() return input end}}}
ISPlayerStatsManageInvUI.onAddItem(panel,button)
check(#commands==1,"Add item requires capability")
caps.AddItem=true
ISPlayerStatsManageInvUI.onAddItem(panel,button)
check(commands[2]=='/additem "guest" "Base.Hammer"',"Valid item for target player")
input='Base.Hammer"\n/ban admin'; ISPlayerStatsManageInvUI.onAddItem(panel,button)
check(#commands==2,"Reject command injection")
input="Base.DoesNotExist"; ISPlayerStatsManageInvUI.onAddItem(panel,button)
check(#commands==2,"Reject unknown script item")
input="Base.Hammer"; panel.playerUsername='bad"name'; ISPlayerStatsManageInvUI.onAddItem(panel,button)
check(#commands==2,"Reject unsafe username")

local factionReads, online = 0, true
getTimestampMs=function() return 100000 end
UIFont={Small=1}; getTextManager=function() return {getFontHeight=function() return 12 end} end
T.stats={}
T.faction=function() factionReads=factionReads+1; return {getName=function() return "Team" end} end
local account={getUsername=function() return "guest" end,isOnline=function() return online end,
    getLastConnection=function() return "2026-09-13 12:00" end,getRole=function() return {getName=function() return "User" end} end,
    getWarningPoints=function() return 0 end,getSuspicionPoints=function() return 0 end,getKicks=function() return 0 end}
local list={height=100,width=600,itemheight=40,x=0,parent={uacColumns={0,100,200,300,400,500,600}},getYScroll=function() return 0 end}
for _,fn in ipairs({"drawRect","drawRectBorder","setStencilRect","drawText","clearStencilRect"}) do list[fn]=function() end end
ISUsersList.drawDatas(list,0,{item=account},false)
local cached=list.uacDrawCache.guest
for i=1,100 do ISUsersList.drawDatas(list,0,{item=account},false) end
check(list.uacDrawCache.guest==cached and factionReads==1,"Visible rows reuse formatted text and faction display")
online=false; ISUsersList.drawDatas(list,0,{item=account},false)
check(list.uacDrawCache.guest.values[1][2]=="Offline","Changed online state immediately invalidates row text")
T.stats.guest={tracked=true,seconds=3600}; ISUsersList.drawDatas(list,0,{item=account},false)
check(list.uacDrawCache.guest.values[5][1]=="1.00 h","Fresh playtime invalidates cached formatting")
print("PASS: " .. checks .. " player administration regression checks")
