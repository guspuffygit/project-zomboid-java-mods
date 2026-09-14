require=function() end
UIFont={Small=1}
local measured,draws=0,0
getTextManager=function() return {getFontHeight=function() return 12 end,MeasureStringX=function(_,font,text) measured=measured+1; return #text*6 end} end
PZMath={floor=math.floor,min=math.min,max=math.max,abs=math.abs}
MultiplayerZoneEditorMode={derive=function() return {} end}
ZoneMarkerCache={version=1,categories={{name="A",r=1,g=0,b=0,a=1}},zones={A={{region="Home",xStart=10,yStart=10,xEnd=20,yEnd=20}}}}
dofile("zone-marker/media/lua/client/ZoneMarkerEditorMode.lua")
local mode=setmetatable({}, {__index=MultiplayerZoneEditorMode_ZoneMarker})
mode.categoryCombo={options={},selected=1}
local combo=mode.categoryCombo
function combo:getOptionCount() return #self.options end
function combo:getSelected() return self.selected end
function combo:getOptionData(i) return self.options[i] end
function combo:setSelected(i) self.selected=i end
function combo:clear() self.options={}; self.selected=1 end
function combo:addOptionWithData(label,data) self.options[#self.options+1]=data end
mode.zoneList={items={},selected=0}
function mode.zoneList:clear() self.items={} end
function mode.zoneList:addItem(text,item) self.items[#self.items+1]={text=text,item=item} end
mode:fillCategoryCombo(); mode:refreshZoneList(); mode.zoneList.selected=1
local first=mode.zoneList.items[1].item
ZoneMarkerCache.zones.A={{region="Home",xStart=40,yStart=10,xEnd=50,yEnd=20}}
ZoneMarkerCache.version=2; mode:refreshZoneList()
assert(mode.zoneList.items[1].item~=first and mode.zoneList.items[1].item.xStart==40,"Same-count replacement refreshes selection")
ZoneMarkerCache.categories={{name="B",r=1,g=0,b=0,a=1}}
ZoneMarkerCache.zones={B={{region="Other",xStart=10,yStart=10,xEnd=20,yEnd=20},{region="Far",xStart=10000,yStart=10000,xEnd=10010,yEnd=10010}}}
ZoneMarkerCache.version=3; mode:fillCategoryCombo(); mode:refreshZoneList()
assert(combo.options[1]=="B" and mode.zoneList.selected==0,"Same-count rename replaces category and clears stale selection")
ISWorldMap={render=function() end}
WorldMapOptions={getVisibleOptions=function() return {} end,synchUI=function() end}
dofile("zone-marker/media/lua/client/ZoneMarkerRenderer.lua")
local map={mapAPI={worldToUIX=function(_,x,y) return x end,worldToUIY=function(_,x,y) return y end,
    uiToWorldX=function(_,x,y) return x end,uiToWorldY=function(_,x,y) return y end},
    javaObject={DrawTextureScaledColor=function() draws=draws+1 end,DrawTextCentre=function() end},getWidth=function() return 100 end,getHeight=function() return 100 end}
ISWorldMap.render(map); local count=measured
assert(draws==2,"Offscreen zone is culled, visible zone rectangle and label retained")
ISWorldMap.render(map); assert(measured==count,"Unchanged frames reuse measured label widths")
local options={}; WorldMapOptions_visibleOptionsHooks[1](options); options[1]:setValue(false)
draws=0; ISWorldMap.render(map); assert(draws==0,"Filter change invalidates overlay cache immediately")
print("PASS: 5 zone revision/culling checks")
