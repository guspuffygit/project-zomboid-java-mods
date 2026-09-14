-- Load the actual AVCS claim window and model parent anchor propagation.
local source = assert(arg[1], "AVCS UserManagerMain.lua path required")
local sizing = arg[2] or "another-vehicle-claim-system/media/lua/client/UI/AVCSVehicleSizing.lua"
require = function() end
local checks = 0
local function check(ok, message) assert(ok, message); checks = checks + 1 end
local font, scale, hasHouse, hasFaction, admin = 14, 1, false, false, false
UIFont = {NewSmall = "small"}
getTextManager = function() return {getFontHeight = function() return font end} end
getText = function(key) return key end
getTexture = function() return {} end
getCore = function() return {
    getScreenWidth = function() return 1920 end,
    getScreenHeight = function() return 1080 end,
    getOptionFontSize = function() return 1 end,
} end
getPlayer = function() return {getAccessLevel = function() return admin and "admin" or "none" end} end
isClient = function() return true end
SafeHouse = {hasSafehouse = function() return hasHouse end}
Faction = {getPlayerFaction = function() return hasFaction end}
SandboxVars = {AVCS = {AllowSafehouse = true, AllowFaction = true}}
local UI = {}
UI.__index = UI
function UI:derive() local class = {}; class.__index = class; return setmetatable(class, {__index = self}) end
function UI:new(x,y,w,h)
    return setmetatable({x=x,y=y,width=w,height=h,children={},anchorTop=true,anchorLeft=true,
        javaObject={fromLua1=function() end,fromLua2=function() end}}, self)
end
for _, name in ipairs({"initialise","instantiate","createChildren","setResizable","setDrawFrame",
    "setImage","setTextureRGBA","setEnable","setTooltip","setBackgroundRGBA","setFont","setView"}) do UI[name]=function() end end
function UI:addChild(child) self.children[#self.children+1]=child; child.parent=self end
for _, axis in ipairs({"Top","Bottom","Left","Right"}) do UI["setAnchor"..axis]=function(self,v) self["anchor"..axis]=v end end
function UI:setX(v) self.x=v end
function UI:setY(v) self.y=v end
function UI:setWidth(v)
    local delta=v-self.width; self.width=v
    for _,child in ipairs(self.children) do
        if child.anchorRight then
            if child.anchorLeft then child:setWidth(child.width+delta) else child:setX(child.x+delta) end
        end
    end
end
function UI:setHeight(v)
    local delta=v-self.height; self.height=v
    for _,child in ipairs(self.children) do
        if child.anchorBottom then
            if child.anchorTop then child:setHeight(child.height+delta) else child:setY(child.y+delta) end
        end
    end
end
ISCollapsableWindow=UI:derive(); ISPanel=UI:derive(); ISButton=UI:derive()
ISScrollingListBox=UI:derive(); ISUI3DScene=UI:derive(); ISLabel=UI:derive()
function ISLabel:new(x,y,h,text) return UI.new(self,x,y,100,h) end
sizingAPI = {
    fit=function(p,w,h) p:setWidth(w); p:setHeight(h); if p.layout then p:layout() end end,
    resizable=function(p,key,w,h,layout) p.layout=layout; p:layout() end,
}

local install
Events={OnGameStart={Add=function(fn) install=fn end}}
local labels={"lblVehicleOwner","lblVehicleOwnerInfo","lblVehicleExpire","lblVehicleExpireInfo",
    "lblVehicleLocation","lblVehicleLocationInfo","lblVehicleLastLocationUpdate","lblVehicleLastLocationUpdateInfo"}
for _, f in ipairs({14,28,40}) do
    font=f; scale=f/14
    for _, membership in ipairs({{false,false},{true,false},{false,true},{true,true}}) do
        hasHouse,hasFaction=unpack(membership)
        for _, isAdmin in ipairs({false,true}) do
            admin=isAdmin
            AVCS={UI={AdminManagerMain={createChildren=function() end},UserPermissionPanel={createChildren=function() end}},getUIFontScale=function() return scale end}
            AVCS.WindowSizing=sizingAPI
            dofile(source)
            AVCS.UI.UserManagerMain.updateListVehicles=function() end
            sizingAPI.vehicleInstalled=false
            dofile(sizing); install()
            local panel=AVCS.UI.UserManagerMain:new(0,0,1500,900)
            panel:createChildren()
            local originalListWidth=panel.listVehicles.width
            for _, size in ipairs({{850,440},{1134,446},{1500,900},{850,440},{1500,900}}) do
                sizingAPI.fit(panel,unpack(size))
                local buttons={}
                for _,b in ipairs(panel.tabButtons) do buttons[#buttons+1]=b end
                buttons[#buttons+1]=panel.btnModify; buttons[#buttons+1]=panel.btnUnclaim
                if panel.btnTeleport then buttons[#buttons+1]=panel.btnTeleport end
                local lastBottom=panel.listVehicles.y
                for _,b in ipairs(buttons) do
                    check(b.y>=lastBottom and b.y+b.height<=panel.height-18,"Toolbar overlaps or escapes window")
                    check(b.width==b.height and b.x+b.width<=panel.leftPaneHolder.width,"Toolbar squares fit left pane")
                    check(b.anchorTop and not b.anchorBottom,"Tabs must not stretch on native resize")
                    lastBottom=b.y+b.height
                end
                local preview=panel.vehiclePreview
                check(preview.anchorTop and not preview.anchorBottom,"Preview must not drift vertically")
                check(preview.y>panel.lblVehicleExpireInfo.y+font,"Preview leaves room for info")
                check(preview.height>0 and preview.y+preview.height<=panel.height-18,"Preview fits vertically")
                check(preview.x+preview.width<=panel.width-8,"Preview fits horizontally")
                check(panel.listVehicles.y+panel.listVehicles.height<=panel.height-18,"List clears resize handle")
                for _,name in ipairs(labels) do check(panel[name].y>=28 and panel[name].y+font<preview.y,"Info stays in header") end
                if size[1]==1500 then check(panel.listVehicles.width==originalListWidth,"Grow restores original list width") end
                -- Deferred parent resizes must not apply a second offset/stretch.
                local y,h=preview.y,buttons[1].height
                panel:setHeight(panel.height+25)
                check(preview.y==y and buttons[1].height==h,"Deferred anchor propagation changes geometry")
                sizingAPI.fit(panel,unpack(size))
            end
        end
    end
end
print("PASS: "..checks.." claim layout checks using actual AVCS UI")
