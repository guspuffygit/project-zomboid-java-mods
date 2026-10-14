local checks = 0
local function check(ok, why) assert(ok, why); checks = checks + 1 end
local function event()
    local e={handlers={}}
    e.Add=function(fn) e.handlers[fn]=true end
    e.Remove=function(fn) e.handlers[fn]=nil end
    return e
end
Events=setmetatable({}, {__index=function(t,k) local e=event(); rawset(t,k,e); return e end})
local dead = false
local player = {x=0,y=0,z=0,getX=function(s) return s.x end,getY=function(s) return s.y end,getZ=function(s) return s.z end,isDead=function() return dead end}
local current = player
getPlayer=function() return current end
local lifestyle,radio=0,0
LSAtEveryTick=function() lifestyle=lifestyle+1 end
TMRadio={adjustSounds=function() radio=radio+1 end}
Events.OnTick.Add(LSAtEveryTick); Events.OnTick.Add(TMRadio.adjustSounds)
local root="guspuffy-atf-patches/media/lua/client/"
dofile(root.."ATFPatches_PlayerTickGuards.lua")
local function tick() for fn in pairs(Events.OnTick.handlers) do fn() end end
current=nil; tick(); check(lifestyle==0 and radio==0,"Missing local player cannot enter unsafe callbacks")
current=player; dead=true; tick(); check(lifestyle==0 and radio==0,"Dead player skips tick work")
dead=false; tick(); check(lifestyle==1 and radio==1,"Live player still gets original behavior")
dofile(root.."ATFPatches_PlayerTickGuards.lua"); tick()
check(lifestyle==2 and radio==2,"Reload does not double-register callbacks")
local maxCoords, exported = 0, 0
ChunkList={chunkSize=10,playerIsAdmin=function() return true end,
    dumpSelection=function(s) for _ in pairs(s.dumpList) do exported=exported+1 end end,
    getBoundarySquares=function(_,x,y) return {{x*10,y*10},{x*10+9,y*10+9}} end,
    highlightSquares=function(_,coords) maxCoords=math.max(maxCoords,#coords) end}
dofile(root.."ATFPatches_ChunkListBudget.lua")
ChunkList:startSelection("route")
for i=1,1000 do player.x=i*10; ChunkList.highlightTask(player) end
check(maxCoords<=18,"Highlight work bounded by nine nearby chunks after long journey")
ChunkList:stopSelection(); check(#ChunkList.highlightCoords==0,"Preview coordinates released on stop")
ChunkList:dumpSelection("route"); check(exported==1000,"Budgeting preserves every selected export chunk")
local remaining=0; for _ in pairs(ChunkList.dumpList) do remaining=remaining+1 end
check(remaining==0,"Export storage released after send")
local list={}
for i=1,100 do local x=i*100; list[i]={getX=function() return x end,getX2=function() return x+20 end,getY=function() return 0 end,getY2=function() return 20 end} end
SafeHouse={getSafehouseList=function() return {size=function() return #list end,get=function(_,i) return list[i+1] end} end}
ATF={HUD={InvalidateCache=function() end}}
GetSafehouseList=function() error("Original noisy scan must be replaced") end
IsPlayerInSafehouse=function() end
dofile(root.."ATFPatches_SafehouseHUDIndex.lua")
for x=0,10200 do
    local expected=false
    for _,h in ipairs(list) do if x>=h:getX() and x<=h:getX2() then expected=true; break end end
    check(IsPlayerInSafehouse(x,20)==expected,"Indexed inclusive safehouse boundary matches original")
end
list={}; GetSafehouseList(); check(not IsPlayerInSafehouse(100,10),"Deleted safehouse immediately disappears from index")
print("PASS: "..checks.." third-party callback/index checks")
