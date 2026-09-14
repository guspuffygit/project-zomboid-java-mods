local checks = 0
local function check(ok, why) assert(ok, why); checks=checks+1 end
require=function() end
local handlers={}
Events=setmetatable({}, {__index=function(t,k) local e={Add=function(fn) handlers[k]=fn end}; rawset(t,k,e); return e end})
ISWorldMap={render=function() end}
WorldMapOptions={getVisibleOptions=function() return {} end,synchUI=function() end}
UIFont={Small=1}; PZMath={floor=math.floor}
local translations, measures, now, language = 0, 0, 0, 'EN'
getTimestampMs=function() return now end
Translator={getLanguage=function() return language end}
getText=function(s) translations=translations+1; return s end
getTextManager=function() return {getFontHeight=function() return 12 end,MeasureStringX=function() measures=measures+1; return 60 end} end
local player={getUsername=function() return 'owner' end}
getPlayer=function() return player end
local function members() return {size=function() return 1 end,get=function() return 'owner' end} end
SafeHouse={hasSafehouse=function() return {getPlayers=members} end}
Faction={getPlayerFaction=function() return {getOwner=function() return 'owner' end,getPlayers=members} end}
AVCS={cacheRevision=1,dbByPlayerID={owner={[1]=true}},dbByVehicleSQLID={
    [1]={OwnerPlayerID='owner',CarModel='Base.Car',LastLocationX=50,LastLocationY=50}}}
local labels, dots = 0, 0
local map={getWidth=function() return 100 end,getHeight=function() return 100 end,
    javaObject={DrawTextureScaledColor=function() dots=dots+1 end,DrawTextCentre=function() labels=labels+1 end},
    mapAPI={worldToUIX=function(_,x) return x end,worldToUIY=function(_,x,y) return y end}}
dofile('another-vehicle-claim-system/media/lua/client/AVCSMapRenderer.lua')
for i=1,1000 do ISWorldMap.render(map) end
check(translations==1 and measures==1 and labels==1000,'Static map reuses metadata and label widths without duplicate group markers')
AVCS.dbByVehicleSQLID[1].LastLocationX=1000; AVCS.cacheRevision=2
ISWorldMap.render(map)
check(labels==1000 and translations==2,'Claim revision immediately moves and culls offscreen marker')
AVCS.dbByVehicleSQLID[1].LastLocationX=110; AVCS.cacheRevision=3
ISWorldMap.render(map)
check(labels==1001,'Label crossing viewport edge remains visible')
handlers.SyncFaction(); ISWorldMap.render(map)
check(translations==4,'Faction update invalidates metadata immediately')
handlers.OnSafehousesChanged(); ISWorldMap.render(map)
check(translations==5,'Safehouse update invalidates metadata immediately')
language='FR'; ISWorldMap.render(map)
check(translations==6,'Locale change invalidates translated labels')
now=2001; ISWorldMap.render(map)
check(translations==7,'Fallback refresh bounds stale data when an event is unavailable')
print('PASS: '..checks..' map cache and viewport checks')
