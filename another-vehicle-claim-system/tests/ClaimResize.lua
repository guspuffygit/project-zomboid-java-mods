-- Native window/resize-widget methods with a minimal UI backend.
local game=assert(arg[1],"Game directory required")
local claim=assert(arg[2],"AVCS claim source required")
local sizing=arg[3] or "another-vehicle-claim-system/media/lua/client/UI/AVCSVehicleSizing.lua"
local helper=arg[4] or "another-vehicle-claim-system/media/lua/client/UI/AVCSWindowSizing.lua"
require=function() end
local checks=0
local function check(ok,msg) assert(ok,msg); checks=checks+1 end
local sw,sh,mx,my=1920,1080,0,0
UIFont={Small=1,NewSmall=2}
getTextManager=function() return {getFontHeight=function() return 20 end,MeasureStringX=function(_,_,s) return #s*9 end} end
getCore=function() return {getScreenWidth=function() return sw end,getScreenHeight=function() return sh end,
    getOptionFontSize=function() return 1 end,getOptionFontSizeReal=function() return 1 end} end
getText=function(s) return s end; getTexture=function() return {} end
getPlayer=function() return {getAccessLevel=function() return "admin" end} end
isClient=function() return true end
SafeHouse={hasSafehouse=function() return true end}; Faction={getPlayerFaction=function() return true end}
SandboxVars={AVCS={AllowSafehouse=true,AllowFaction=true}}
local UI={};UI.__index=UI
function UI:derive() local c={};c.__index=c;return setmetatable(c,{__index=self}) end
function UI:new(x,y,w,h,text,target,callback)
    return setmetatable({x=x,y=y,width=w,height=h,children={},anchorTop=true,anchorLeft=true,
        borderColor={},backgroundColor={},backgroundColorMouseOver={},target=target,onclick=callback,
        javaObject={fromLua1=function() end,fromLua2=function() end}},self)
end
function UI:initialise() self.children=self.children or {} end
for _,name in ipairs({"instantiate","setImage","setTextureRGBA","setEnable","setTooltip","setBackgroundRGBA","setFont","setView","drawRect","drawRectBorder","drawTextureScaled","drawTextCentre","setStencilRect","clearStencilRect"}) do UI[name]=function() end end
function UI:addChild(c) self.children[#self.children+1]=c;c.parent=self end
function UI:bringToTop()
    if not self.parent then return end
    for i,c in ipairs(self.parent.children) do if c==self then table.remove(self.parent.children,i);break end end
    self.parent.children[#self.parent.children+1]=self
end
for _,axis in ipairs({"Left","Right","Top","Bottom"}) do UI["setAnchor"..axis]=function(self,v) self["anchor"..axis]=v end end
function UI:setX(v) self.x=v end;function UI:setY(v) self.y=v end
function UI:getX() return self.x end;function UI:getY() return self.y end
function UI:getWidth() return self.width end;function UI:getHeight() return self.height end
function UI:setWidth(v)
    local delta=v-self.width;self.width=v
    for _,c in ipairs(self.children or {}) do
        if c.anchorRight then if c.anchorLeft then c:setWidth(c.width+delta) else c:setX(c.x+delta) end end
    end
end
function UI:setHeight(v)
    local delta=v-self.height;self.height=v
    for _,c in ipairs(self.children or {}) do
        if c.anchorBottom then if c.anchorTop then c:setHeight(c.height+delta) else c:setY(c.y+delta) end end
    end
end
function UI:setVisible(v) self.visible=v end
function UI:getIsVisible() return self.visible~=false end
function UI:setCapture(v) self.capture=v end
function UI:getMouseX() return mx-self.x-(self.parent and self.parent.x or 0) end
function UI:getMouseY() return my-self.y-(self.parent and self.parent.y or 0) end
ISPanel=UI:derive();ISButton=UI:derive();ISLabel=UI:derive();ISScrollingListBox=UI:derive();ISUI3DScene=UI:derive()
function ISLabel:new(x,y,h,text) return UI.new(self,x,y,100,h) end
dofile(game.."/media/lua/client/ISUI/ISResizeWidget.lua")
dofile(game.."/media/lua/client/ISUI/ISCollapsableWindow.lua")
local savedFunctions
ISLayoutManager={RegisterWindow=function(_,funcs) savedFunctions=funcs end}
local dialog
ISTextBox={new=function(_,x,y,w,h,text,entry,target,callback)
    dialog={initialise=function() end,addToUIManager=function() end,target=target,callback=callback,
        entry={getText=function() return entry end}}
    return dialog
end}
AVCS={getUIFontScale=function() return 2.25 end,UI={AdminManagerMain={createChildren=function() end},UserPermissionPanel={createChildren=function() end}}}
dofile(helper)
dofile(claim)
AVCS.UI.UserManagerMain.updateListVehicles=function() end
local install
Events={OnGameStart={Add=function(fn) install=fn end}}
dofile(sizing);install()
local p=AVCS.UI.UserManagerMain:new(20,20,1400,900)
p:initialise();p:createChildren()
check(p.resizable and p.resizeWidget:getIsVisible() and p.resizeWidget2:getIsVisible(),"Native resize handles enabled after AVCS constructor disables them")
local function hit(x,y)
    for i=#p.children,1,-1 do local c=p.children[i]
        if c:getIsVisible() and x>=c.x and x<c.x+c.width and y>=c.y and y<c.y+c.height then return c end
    end
end
local function drag(widget,dx,dy)
    local x,y=widget.x+widget.width/2,widget.y+widget.height/2
    check(hit(x,y)==widget,"Resize control must receive mouse clicks above content")
    mx=p.x+x;my=p.y+y
    widget:onMouseDown(0,0)
    check(widget.resizing and widget.capture,"Mouse down captures resize drag")
    mx=mx+dx;my=my+dy
    widget:onMouseMoveOutside(dx,dy)
    widget:onMouseUpOutside(0,0)
    check(not widget.resizing and not widget.capture,"Mouse up releases resize drag")
end
drag(p.resizeWidget,-300,-300)
check(p.width==1100 and p.height==600,"Corner drag changes both dimensions")
drag(p.resizeWidget,200,150)
check(p.width==1300 and p.height==750,"Corner can grow again")
drag(p.resizeWidget2,0,-100)
check(p.width==1300 and p.height==650,"Bottom edge adjusts height only")
check(hit(p.avcsSizeButton.x+5,p.avcsSizeButton.y+5)==p.avcsSizeButton,"Size button is clickable")
p.avcsSizeButton.onclick(p.avcsSizeButton.target,p.avcsSizeButton)
dialog.entry.getText=function() return "1000x620" end
dialog.callback(dialog.target,{internal="OK",parent=dialog})
check(p.width==1000 and p.height==620,"Size dialog applies requested dimensions")
savedFunctions.RestoreLayout(p,"VehicleClaims",{x="20",y="20",width="1150",height="680"})
check(p.width==1150 and p.height==680,"Saved size restores and reflows")
drag(p.resizeWidget,50,20)
check(p.width==1200 and p.height==700,"Drag still works after saved size restores")
drag(p.resizeWidget,-500,-300)
check(p.width==700 and p.height==400,"Claim window can shrink below the old 850x440 minimum")
check(p.lblVehicleLocation.x==p.lblVehicleOwner.x and p.lblVehicleLocation.y>p.lblVehicleExpireInfo.y,
    "Narrow window stacks info columns instead of overflowing")
check(p.vehiclePreview.height>0 and p.vehiclePreview.y+p.vehiclePreview.height<p.resizeWidget.y,
    "Compact preview stays above drag controls")
check(p.resizeWidget.width>=24 and p.resizeWidget.height>=24,"Corner has a usable mouse target")
check(p.children[#p.children-1]==p.resizeWidget2 or p.children[#p.children]==p.resizeWidget2,
    "Resize controls remain above window contents")
p.avcsSizeButton.onclick(p.avcsSizeButton.target,p.avcsSizeButton)
dialog.entry.getText=function() return " 620 x 400 " end
dialog.callback(dialog.target,{internal="OK",parent=dialog})
check(p.width==620 and p.height==400,"Size dialog reaches compact width with spaces")
drag(p.resizeWidget,300,200)
check(p.width==920 and p.height==600,"Compact window can grow by dragging")
print("PASS: "..checks.." native claim resize interaction checks")
