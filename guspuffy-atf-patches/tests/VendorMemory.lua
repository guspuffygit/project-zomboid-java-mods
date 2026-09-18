local root=(arg[1] or "guspuffy-atf-patches/build/vendor-fixtures") .. "/"
local checks=0
local function check(ok,why) assert(ok,why); checks=checks+1 end
local function event()
    local e={handlers={}}
    e.Add=function(fn) e.handlers[fn]=true end
    e.Remove=function(fn) e.handlers[fn]=nil end
    return e
end
Events=setmetatable({}, {__index=function(t,k) local e=event(); rawset(t,k,e); return e end})
local function fire(name) local fns={}; for fn in pairs(Events[name].handlers) do fns[#fns+1]=fn end; for _,fn in ipairs(fns) do fn() end end
ISCollapsableWindow={derive=function() return {} end}
MainScreen={onEnterFromGame=function() end,onReturnToGame=function() end}
local now=0
getTimestampMs=function() return now end
local errors={}
getLuaDebuggerErrors=function() return {size=function() return #errors end,get=function(_,i) return errors[i+1] end} end
local E=dofile(root.."mod-errorMagnifier/42.15/media/lua/client/errorMagnifier_Main.lua")
E.Button={setVisible=function() end}
E.getRealTimeStamp=function() return "12:00" end
local refreshes=0
E.MainWindow.instance={isVisible=function() return true end}
E.refreshErrorDisplay=function() refreshes=refreshes+1 end
for i=1,1000 do errors[i]="java.lang.RuntimeException: distinct-"..i end
E.parseErrors(); check(E.errorCount==32,"Parse handles at most 32 incoming entries per callback")
while E.errorCount<#errors do E.parseErrors(); fire("OnTickEvenPaused") end
check(#E.parsedErrorsKeyed==256,"Unique error retention capped at 256")
local retained=0; for _ in pairs(E.parsedErrors) do retained=retained+1 end
check(retained==256 and E.evictedErrors==744,"Eviction removes keys and counts too")
check(refreshes==1,"Burst processing does not repeatedly rebuild visible error list")
now=250; fire("OnTickEvenPaused"); check(refreshes==2,"Final UI refresh occurs after parsing has finished")
errors={"java.lang.RuntimeException: reset-after-clear"}; E.parseErrors()
check(E.errorCount==1,"Reset underlying error buffer restarts cursor safely")
-- Run the actual Lifestyle startup handler with a large empty area.
Events=setmetatable({}, {__index=function(t,k) local e=event(); rawset(t,k,e); return e end})
local list,squareReads={},0
local player={getX=function() return 100 end,getY=function() return 200 end,getZ=function() return 0 end,
    isDead=function() return false end,getModData=function() return {} end}
local current=player
getSpecificPlayer=function() return current end
getCell=function() return {getGridSquare=function() squareReads=squareReads+1; return nil end} end
getGameTime=function() return {getGameWorldSecondsSinceLastUpdate=function() return 0 end} end
GTLSCheck=1
require=function(name) if name=="Properties/Objects/List" then return list end end
dofile(root.."mod-LifestyleHobbies/common/media/lua/client/Properties/Objects/Handler.lua")
fire("OnGameStart"); check(squareReads==0,"Startup event queues rather than scanning 14,641 squares inline")
local ticks=0
while squareReads<14641 and ticks<300 do
    local before=squareReads; fire("OnTick"); ticks=ticks+1
    check(squareReads-before<=64,"Startup tick square budget")
end
check(squareReads==14641,"Budgeted startup visits the complete original 121x121 area")
local before=squareReads; fire("OnTick"); check(squareReads==before,"Finished startup scan stops doing work")
-- Actual radio source: nil player and lost deviceData must not dereference.
require=function() end
getActivatedMods=function() return {contains=function() return false end,size=function() return 0 end} end
DevicePresets={class="presets"}
__classmetatables={presets={__index={addPreset=function() end}}}
getText=function(s) return s end
PZAPI={ModOptions={create=function() return {addTickBox=function() end,addSlider=function() end} end}}
MapObjects={OnLoadWithSprite=function() end}
getPlayer=function() return nil end
dofile(root.."mod-TrueMusicRadio42/42.20/media/lua/client/TrueMusicRadio/TMRadio.lua")
check(pcall(TMRadio.adjustSounds),"Radio nil-player guard precedes coordinate access")
getPlayer=function() return player end
getCore=function() return {getOptionMusicVolume=function() return 5 end} end
getSoundManager=function() return {setMusicVolume=function() end} end
SandboxVars={TrueMusicRadio={TMRRadiosAttractZombies=false}}
isClient=function() return true end
TMRadioClient={UpdatePlaylistFromServer=function() end}
local stopped=0
TMRadio.soundCache={{sound={setVolume=function() end,stop=function() stopped=stopped+1 end}}}
for i=1,6 do TMRadio.adjustSounds() end
check(#TMRadio.soundCache==0 and stopped==1,"Missing deviceData releases sound and removes stale entry")
print("PASS: "..checks.." vendor memory/tick checks")
