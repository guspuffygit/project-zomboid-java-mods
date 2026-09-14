local source = arg[1] or 'admin-diagnostics/media/lua/client/AdminDiagnostics/Recorder.lua'
local checks, time, staff, getCellCalls, writerCalls = 0, 0, true, 0, 0
local function check(ok, text) assert(ok, text); checks=checks+1 end
local callbacks, files, failWrite = {}, {}, false
Events=setmetatable({}, {__index=function(t,name)
    local event={Add=function(fn) check(callbacks[name]==nil,'No duplicate event callback');callbacks[name]=fn end,
        Remove=function(fn) if callbacks[name]==fn then callbacks[name]=nil end end}
    rawset(t,name,event);return event
end})
getTimestampMs=function() return time end
isClient=function() return true end
local p={getRole=function() return {hasAdminPower=function() return staff end} end,
    getX=function() return 100 end,getY=function() return 200 end,getZ=function() return 0 end,
    getAccessLevel=function() return 'admin' end,getCurrentSquare=function() return {} end,
    isDead=function() return false end,getVehicle=function() end,isInvisible=function() return true end,
    isGodMod=function() return true end,isNoClip=function() return true end,getAlpha=function() return 1 end,
    getPlayerNum=function() return 0 end}
getPlayer=function() return p end
local vehicles,zombies,animals,players=20,100,10,4
local function list(n) return {size=function() return n end} end
getOnlinePlayers=function() return list(64) end
getCell=function()
    getCellCalls=getCellCalls+1
    return {getVehicles=function() return list(vehicles) end,getZombieList=function() return list(zombies) end,
        getAnimals=function() return list(animals) end,getRemoteSurvivorList=function() return list(players) end}
end
getLuaDebuggerErrorCount=function() return 0 end
getCore=function() return {getVersion=function() return '42.20.4' end,getScreenWidth=function() return 1280 end,getScreenHeight=function() return 720 end} end
local uiCalls=0
UIManager={getUI=function() return {size=function() return 10000 end,get=function()
    uiCalls=uiCalls+1;return {isVisible=function() return true end,getTable=function() return {Type='ISAdminPanelUI'} end}
end} end}
getFileWriter=function(path,create,append)
    writerCalls=writerCalls+1
    if failWrite then error('Injected disk failure') end
    if not append then files[path]='' end
    return {write=function(_,s) files[path]=(files[path] or '')..s end,close=function() end}
end
-- The installed game's Kahlua lacks next(); the recorder must not rely on it.
next=nil
dofile(source)
local D=AdminDiagnostics
check(not D.enabled and getCellCalls==0 and writerCalls==0,'Disabled recorder does no sampling or I/O')
staff=false;check(not D.start() and writerCalls==0,'Nonstaff cannot start')
staff=true;check(D.start(),'Staff starts recording')
check(not D.start(),'Repeated start is idempotent')
local function advance(ms,render,ui)
    for i=1,ms/50 do
        time=time+50
        if callbacks.OnPostRender and render~=false then for j=1,3 do callbacks.OnPostRender() end end
        if callbacks.OnPostUIDraw and ui~=false then for j=1,3 do callbacks.OnPostUIDraw() end end
        if callbacks.OnTick then callbacks.OnTick() end
    end
end
advance(12000)
check(getCellCalls==6,'Snapshot work runs every two seconds')
check(D.incidentNumber==0,'Healthy samples do not create incidents')
check(#D.history==6 and writerCalls==1,'Healthy samples stay in memory')
check(uiCalls==6*128,'UI traversal is capped even with ten thousand elements')
check(D.previous.uiTruncated and #D.previous.panels<1200,'Panel names are bounded')
check(D.previous.heapUsedMiB==nil and not D.previous.jvmProbe,'Absent JVM helper is unavailable rather than fabricated memory')
vehicles=1;advance(2000)
check(D.incidentNumber==1,'Stationary vehicle count collapse creates an incident')
local content='';for _,v in pairs(files) do content=content..v end
check(content:find('"kind":"before"',1,true) and content:find('loadedVehicles_dropped',1,true),'Incident includes pre-event history and cause')
check(content:find('"knownPlayers":64',1,true),'Known-player count included')
local id=D.incidentNumber
D.incident('loadedVehicles_dropped',D.previous)
check(D.incidentNumber==id and D.suppressed>0,'Repeated incident is rate limited')
advance(22000)
content='';for _,v in pairs(files) do content=content..v end
check(content:find('"kind":"after"',1,true),'Post-event samples recorded')
advance(80000)
check(#D.history==30,'History remains capped at thirty snapshots')
local function baseline()
    return {epochMs=200000,elapsedMs=2000,maxTickGapMs=20,renderHz=60,uiDrawHz=60,
        x=100,y=200,z=0,playerPresent=true,squarePresent=true,loadedVehicles=20,loadedZombies=100,
        loadedAnimals=10,loadedRemotePlayers=4,heapUsedMiB=1000,heapMaxMiB=8000,gcMillis=0,selfAlpha=1}
end
local previous,s=baseline(),baseline()
D.movementGraceUntil=0;s.x=1000;s.loadedVehicles=0
local reason=D.detect(s,previous)
check(reason:find('position_jump',1,true) and not reason:find('loadedVehicles_dropped',1,true),'Teleport records movement and suppresses streaming-drop alarms')
s=baseline();s.epochMs=202000;s.loadedVehicles=0
reason=D.detect(s,previous)
check(not reason or not reason:find('loadedVehicles_dropped',1,true),'Teleport grace suppresses later unload samples')
D.movementGraceUntil=0;s=baseline();s.loadedVehicles=nil
reason=D.detect(s,previous)
check(not reason or not reason:find('loadedVehicles_dropped',1,true),'Unavailable count does not become zero')
s=baseline();s.heapUsedMiB=1500
check(D.detect(s,previous):find('heap_spike',1,true),'Heap spike detected')
s=baseline();s.heapUsedMiB=7400
check(D.detect(s,previous):find('heap_pressure',1,true),'High heap occupancy detected')
s=baseline();s.maxTickGapMs=1800
check(D.detect(s,previous):find('client_tick_stall',1,true),'Long main-loop stall detected on resumption')
s=baseline();s.gcMillis=900
check(D.detect(s,previous):find('gc_collection_time_increased',1,true),'GC counter growth detected')
D.lowFrames=0;s=baseline();s.renderHz=4
check(D.detect(s,previous)==nil,'A single low frame sample is not sustained slowdown')
D.detect(s,previous)
check(D.detect(s,previous):find('sustained_low_render_rate',1,true),'Sustained low render callbacks detected')
D.noUiFrames=0;s=baseline();s.uiDrawHz=0
D.detect(s,previous);D.detect(s,previous)
check(D.detect(s,previous):find('ui_draw_callbacks_stopped',1,true),'Stopped UI rendering callbacks detected')
s=baseline();s.uiGlobalVisible=false;previous.uiGlobalVisible=true
check(D.detect(s,previous):find('global_ui_hidden',1,true),'Global UI hide is recorded as a signal')
s=baseline();s.luaErrors=4;previous.luaErrors=0
check(D.detect(s,previous):find('lua_error_count_increased',1,true),'Lua error count changes detected')
s=baseline();s.selfAlpha=0
check(D.detect(s,previous):find('local_player_alpha_dropped',1,true),'Self alpha collapse detected')
time=time+6000;D.mark();check(D.incidentNumber==id+1,'Manual marker works independently of automatic cooldown')
local manualId=D.incidentNumber;D.mark();check(D.incidentNumber==manualId,'Manual marker cannot flood logs')
D.config.maxPartBytes=1024
for i=1,30 do D.write({kind='rotation_test',payload=string.rep('x',900)}) end
local countFiles=0;for _ in pairs(files) do countFiles=countFiles+1 end
check(countFiles<=4,'Disk logging rotates through at most four slots')
staff=false;advance(2000)
check(not D.enabled and callbacks.OnTick==nil and callbacks.OnPostRender==nil,'Losing staff permission removes sampling hooks')
staff=true;D.config.maxPartBytes=2097152;D.start()
failWrite=true;D.mark()
check(not D.enabled and D.writeFailed,'Disk failure disables recorder')
local writes=writerCalls;advance(8000)
check(writerCalls==writes,'A failed writer is not retried each frame')
failWrite=false;D.start();callbacks.OnDisconnect()
check(not D.enabled,'Disconnect records and detaches')
D.start();callbacks.OnResetLua()
check(not D.enabled,'Lua reset detaches recorder')
check(D.encode({text='a\nb"c',bad=0/0}):find('unavailable',1,true),'Encoder handles nonfinite metrics safely')
print('PASS: '..checks..' diagnostics recorder checks')
