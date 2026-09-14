local game=assert(arg[1],"Pass game directory")
require=function() end
local n=0
local function check(v,m) assert(v,m);n=n+1 end
local font=16
UIFont={Small=1,Medium=2,NewSmall=3}
getTextManager=function() return {getFontHeight=function() return font end,MeasureStringX=function(_,_,s) return #s*8 end} end
getText=function(s) return s end
getCore=function() return {getScreenWidth=function() return 1280 end,getScreenHeight=function() return 720 end} end
Capability={CanSetupSafehouses=1,FactionCheat=2}
local role={hasCapability=function() return false end}
local player={getUsername=function() return "owner" end,getRole=function() return role end}
local W={};W.__index=W
function W:derive(name) local c={Type=name};c.__index=c;return setmetatable(c,self) end
function W:new(x,y,w,h) return setmetatable({x=x,y=y,width=w,height=h,children={},items={},selected=0},self) end
for _,name in ipairs({"X","Y","Width","Height"}) do
    local key=name:lower();W["set"..name]=function(s,v) s[key]=v end;W["get"..name]=function(s) return s[key] end
end
function W:initialise() end
function W:instantiate() end
function W:enableCancelColor() end
function W:enableAcceptColor() end
function W:setWidthToTitle(w) self.width=w end
function W:getBottom() return self.y+self.height end
function W:getRight() return self.x+self.width end
function W:addChild(c) self.children[#self.children+1]=c;c.parent=self end
function W:getChildren() return self.children end
function W:setEnable(v) self.enable=v end
function W:setVisible(v) self.visible=v end
function W:removeFromUIManager() end
function W:addToUIManager() end
function W:clear() self.items={};self.selected=1 end
function W:addItem(text,item,tip)
    local r={text=text,item=item,tooltip=tip,index=#self.items+1,itemindex=#self.items+1}
    self.items[#self.items+1]=r;return r
end
function W:setScrollHeight(v) self.scrollHeight=v end
function W:setYScroll(v) self.scroll=v end
function W:ensureVisible() end
ISPanel=W:derive("ISPanel");ISScrollingListBox=W:derive("ISScrollingListBox")
ISButton=W:derive("ISButton")
function ISButton:new(x,y,w,h,title,target,callback) local b=W.new(self,x,y,w,h);b.title=title;b.target=target;b.onclick=callback;return b end
ISTextEntryBox=W:derive("ISTextEntryBox")
function ISTextEntryBox:new(text,x,y,w,h) local e=W.new(self,x,y,w,h);e.text=text;return e end
function ISTextEntryBox:getInternalText() return self.text end
function ISTextEntryBox:setText(v) self.text=v end
function ISTextEntryBox:setPlaceholderText(v) self.placeholder=v end
ISLabel=W:derive("ISLabel")
function ISLabel:new(x,y,h,text) local l=W.new(self,x,y,0,h);l.name=text;return l end
function ISLabel:setName(v) self.name=v end
ISModalDialog=W:derive("ISModalDialog")
ISMiniScoreboardUI={OnMiniScoreboardUpdate=function() end}
Events=setmetatable({}, {__index=function(t,k) local e={Add=function() end};rawset(t,k,e);return e end})
local requests,invites=0,{}
scoreboardUpdate=function() requests=requests+1 end
sendSafehouseInvite=function(_,_,name) invites[#invites+1]=name end
sendFactionInvite=sendSafehouseInvite
AdminCore={fit=function() end}
local function list(rows) return {size=function() return #rows end,get=function(_,i) return rows[i+1] end} end
local function scoreboard(names,display) return {usernames=list(names),displayNames=list(display)} end
local names={"owner","Alpha","blocked","zeta"}
local display={"Owner","Friendly Survivor","Blocked","Zed"}
local otherHouse={getTitle=function() return "Other house" end}
local blocked=true
local house={getOwner=function() return "owner" end,isOwner=function() return true end,
    alreadyHaveSafehouse=function(_,name) return name=="blocked" and blocked and otherHouse or nil end}
local faction={isOwner=function(_,name) return name=="owner" end,isMember=function(_,name) return name=="owner" end}
Faction={isAlreadyInFaction=function(name) return name=="blocked" and blocked end}
dofile(game.."/media/lua/client/ISUI/UserPanel/ISSafehouseAddPlayerUI.lua")
dofile(game.."/media/lua/client/ISUI/UserPanel/ISFactionAddPlayerUI.lua")
dofile("universal-admin-core/media/lua/client/AdminCore/InviteSearch.lua")
for _,kind in ipairs({"safehouse","faction"}) do
    local cls=kind=="safehouse" and ISSafehouseAddPlayerUI or ISFactionAddPlayerUI
    local object=kind=="safehouse" and house or faction
    local p=cls:new(10,10,500,500,object,player);p:initialise()
    check(p.uacInviteSearch~=nil,"Ordinary non-admin owners get search: "..kind)
    p.scoreboard=scoreboard(names,display);p:populateList()
    check(#p.playerList.items==3 and p.playerList.selected==0,"Preserve native owner exclusion without auto-selecting")
    local initialRequests=requests
    p.uacInviteSearch:setText(" friendly ");p.uacInviteSearch.onTextChange()
    check(#p.playerList.items==1 and p.playerList.items[1].item[kind=="safehouse" and "username" or "name"]=="Alpha","Find display name without case sensitivity")
    check(requests==initialRequests,"Typing does not request scoreboard data")
    p.playerList.selected=1;p.selectedPlayer="Alpha"
    p.uacInviteSearch:setText("absent");p.uacInviteSearch.onTextChange()
    local before=#invites;p:onClick(p.addPlayer)
    check(#invites==before and not p.addPlayer.enable and not p.selectedPlayer,"Hidden selection cannot invite previous target")
    check(p.uacInviteCount.name=="No matching players","Empty result message")
    p.uacInviteSearch:setText("[");p.uacInviteSearch.onTextChange()
    check(#p.playerList.items==0,"Search treats pattern symbols literally")
    p.uacInviteClear.onclick(p)
    check(#p.playerList.items==3,"Clear restores native list")
    p.uacInviteSearch:setText("blocked");p.uacInviteSearch.onTextChange();p.playerList.selected=1
    p:onClick(p.addPlayer)
    check(#invites==before and not p.addPlayer.enable,"Membership restriction survives filtering and invitation callback")
    p.uacInviteSearch:setText("ALP");p.uacInviteSearch.onTextChange();p.playerList.selected=1
    p:onClick(p.addPlayer)
    check(invites[#invites]=="Alpha","Invite uses correct username through original game callback")
    before=#invites;p.scoreboard=scoreboard({"owner","zeta"},{"Owner","Zed"});p:onClick(p.addPlayer)
    check(#invites==before and #p.playerList.items==0,"Scoreboard refresh removes disconnected selection and retains filter")
    font=28
    local big=cls:new(10,10,500,500,object,player);big:initialise()
    check(big.uacInviteSearch:getBottom()<big.playerList.y and big.no:getBottom()<=big.height,"Large-font field/list/footer do not overlap")
    font=16
end
print("PASS: "..n.." invite-search checks against native dialogs")
