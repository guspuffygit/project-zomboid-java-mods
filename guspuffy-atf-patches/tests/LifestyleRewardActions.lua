-- Exact-source action formulas and paired native lifecycle callbacks, offline.
local vendor=(arg[1] or "guspuffy-atf-patches/build/vendor-fixtures").."/mod-LifestyleHobbies/common/media/lua/"
local module=arg[2] or "guspuffy-atf-patches"
local dependencyRoot=arg[3] and (arg[3].."/") or vendor
local checks=0
local function check(ok,message) assert(ok,message); checks=checks+1 end
local function list(values)
    return {size=function() return #values end,get=function(_,index) return values[index+1] end}
end
local function event()
    local result={handlers={}}
    result.Add=function(fn) result.handlers[fn]=true end
    result.Remove=function(fn) result.handlers[fn]=nil end
    return result
end
Events=setmetatable({}, {__index=function(t,name) local value=event(); rawset(t,name,value); return value end})
local function fire(name) for callback in pairs(Events[name].handlers) do callback() end end
local server,client=true,false
isServer=function() return server end; isClient=function() return client end
local real,hours,dayLength=0,0,120
getTimestampMs=function() return real end
getGameTime=function() return {getWorldAgeHours=function() return hours end} end
getSandboxOptions=function() return {getDayLengthMinutes=function() return dayLength end} end
local function advance(units) real=real+units/12*1000; hours=hours+units/3600; fire("OnTick") end
local players={}
getPlayerByOnlineID=function(id) return players[id] end
local current
getPlayer=function() return current end
local nativeChecks=0
ATFLifestyleNativeAction={ownsAction=function(action,player) nativeChecks=nativeChecks+1; return action.actor==player and action.connected end}
ISBaseTimedAction={derive=function(_,name) return {Type=name} end,stop=function() end,perform=function() end}
Perks=setmetatable({}, {__index=function(t,k) rawset(t,k,k); return k end})
CharacterTrait=setmetatable({}, {__index=function(t,k) rawset(t,k,k); return k end})
CharacterStat=setmetatable({}, {__index=function(t,k) rawset(t,k,k); return k end})
Fluid={Bleach="Bleach",CleaningLiquid="CleaningLiquid"}
newrandom=function() return {random=function(_,a,b) return b and a or 1 end} end
ZombRand=function(a,b) return b and a or 0 end
getText=function(key) return key end
getSoundManager=function() error("Server reward paths must not need client sound manager") end
sendClientCommand=function() error("Server reward paths must not send client commands") end
local syncs,statWrites,halos=0,0,0
local sentCommands={}
sendServerCommand=function(actor,module,name,args) sentCommands[#sentCommands+1]={actor=actor,module=module,name=name,args=args} end
SyncXp=function() syncs=syncs+1 end
sendPlayerStat=function() statWrites=statWrites+1 end
sendRemoveItemFromContainer=function() end
triggerEvent=function() end
HaloTextHelper={addTextWithArrow=function() halos=halos+1 end}
local loaded={}
require=function(name)
    if loaded[name] then return loaded[name] end
    local value
    if name=="ATFPatches_LifestyleRewards" or name=="ATFPatches_LifestyleRewardTracks" then
        value=dofile(module.."/media/lua/shared/"..name..".lua")
    elseif name=="ISAmbt/AmbtMng_utils" then value=dofile(dependencyRoot.."shared/"..name..".lua")
    else value={} end
    loaded[name]=value or true
    return value
end
LSSync={isClientOnly=function() return client and not server end,transmit=function() end}
local originalHiddenGet=function() return 4 end
local originalHiddenAdd=function() end
local originalHiddenRemove=function() end
HiddenSkills={getLevel=originalHiddenGet,addXP=originalHiddenAdd,removeXP=originalHiddenRemove}
dofile(vendor.."shared/LSUtil.lua")
local Rewards=ATFPatches_LifestyleRewards
local squares={}
local function square(x,y,z,blood,dirt)
    local value={getX=function() return x end,getY=function() return y end,getZ=function() return z end,
        haveBlood=function() return blood end,removeBlood=function() blood=false end}
    value.getObjects=function() return list(dirt and {{getAttachedAnimSprite=function() return nil end,
        getTextureName=function() return "trash_junk_1" end,getOverlaySprite=function() return nil end}} or {}) end
    squares[x..":"..y..":"..z]=value
    return value
end
getCell=function() return {getGridSquare=function(_,x,y,z) return squares[x..":"..y..":"..z] end} end
luautils={stringStarts=function(value,prefix) return value:sub(1,#prefix)==prefix end}
local function object(sq,data,name)
    return {getSquare=function() return sq end,getObjectIndex=function() return 1 end,getModData=function() return data end,
        getSprite=function() return {getProperties=function() return {has=function() return true end,get=function() return name end} end} end,
        transmitModData=function() end,getSpriteName=function() return "notYogaMat" end,getTextureName=function() return "notYogaMat" end}
end
local nextID=1
local function player()
    local id=nextID; nextID=nextID+1
    local data,inventory,xp,levels,traits,capabilities={},{},{},{},{},{}
    local scans={calls=0,items=0}
    local health=50
    local moving,dead,vehicle,asleep=false,false,false,false
    local nativeStats={get=function(_,kind) return kind=="ENDURANCE" and 1 or 0 end,
        add=function() statWrites=statWrites+1 end,remove=function() statWrites=statWrites+1 end,set=function() statWrites=statWrites+1 end}
    local inv={}
    inv.getFirstEvalRecurse=function(_,predicate)
        scans.calls=scans.calls+1
        for _,item in ipairs(inventory) do scans.items=scans.items+1; if predicate(item) then return item end end
    end
    inv.getFirstTypeEvalRecurse=function(_,full,predicate) for _,item in ipairs(inventory) do if item:getFullType()==full and predicate(item) then return item end end end
    inv.getItemsFromType=function(_,kind) local values={}; for _,item in ipairs(inventory) do if item:getType()==kind then values[#values+1]=item end end; return list(values) end
    inv.isExistYet=function() return true end; inv.isRemoveItemAllowed=function() return true end
    inv.DoRemoveItem=function(_,item) for index=#inventory,1,-1 do if inventory[index]==item then table.remove(inventory,index) end end end
    inv.setDrawDirty=function() end; inv.setHasBeenLooted=function() end
    local value={getOnlineID=function() return id end,getModData=function() return data end,getInventory=function() return inv end,
        getPerkLevel=function(_,perk) return levels[perk] or 0 end,hasTrait=function(_,name) return traits[name] or false end,
        getRole=function() return {hasCapability=function(_,capability) return capabilities[capability] or false end} end,
        getBodyDamage=function() return {AddGeneralHealth=function(_,amount) health=health+amount end} end,getHealth=function() return health end,
        getStats=function() return nativeStats end,isInvisible=function() return false end,
        isDead=function() return dead end,getVehicle=function() return vehicle end,isAsleep=function() return asleep end,
        isPlayerMoving=function() return moving end,isRunning=function() return false end,isAiming=function() return false end,
        getX=function() return 10 end,getY=function() return 10 end,getZ=function() return 0 end,
        getSquare=function() return squares["10:10:0"] end,isSitOnGround=function() return false end,
        isTimedActionInstant=function() return false end,getClothingItem_Hands=function() return nil end,setMetabolicTarget=function() end,
        removeAttachedItem=function() end,isEquipped=function() return false end}
    value.test={inventory=inventory,xp=xp,levels=levels,traits=traits,capabilities=capabilities,scans=scans,setMoving=function(v) moving=v end,
        setDead=function(v) dead=v end,setVehicle=function(v) vehicle=v end,setAsleep=function(v) asleep=v end}
    players[id]=value
    Rewards.ensureData(value)
    return value
end
addXp=function(character,perk,amount)
    check(type(amount)=="number" and amount>0 and amount<math.huge,"Only finite earned XP awarded")
    character.test.xp[perk]=(character.test.xp[perk] or 0)+amount
end
addXpNoMultiplier=function() error("No unvalidated negative native XP") end
local function item(owner,kind,fluid)
    local id=#owner.test.inventory+1
    local primary={getFluidTypeString=function() return fluid end}
    local fluidCont={getAmount=function() return 10 end,getPrimaryFluid=function() return primary end,
        isPureFluid=function(_,kind) return kind==fluid end,getSpecificFluidAmount=function() return 10 end}
    local value={getID=function() return id end,getType=function() return kind end,getFullType=function() return "Base."..kind end,
        getContainer=function() return owner:getInventory() end,isBroken=function() return false end,
        getFluidContainer=function() return fluid and fluidCont end,getFluidContainerFromSelfOrWorldItem=function() return fluid and fluidCont end,
        IsDrainable=function() return false end,isEquipped=function() return false end,getCurrentUses=function() return 10 end}
    owner.test.inventory[#owner.test.inventory+1]=value
    return value
end
instanceof=function(value,kind) return kind=="InventoryItem" and value.getID~=nil end
LSHygiene={DS={getFromSpriteName=function() return {} end}}
SandboxVars={Meditation={},Music={},Dancing={},Yoga={RequiresMat=false},LSHygiene={}}
local classes={"LSMeditateAction","PlayInstrumentTraining","PlayInstrumentActionNew","PlayInstrumentVocal","PlayDJBoothAction",
    "PlayerIsDancingToMusic","LSCanvasPaintingAction","LSSculptingAction","CleanRoomAction","LSUnclogToilet","LSFixAction","LSCleanObject","LSYogaAction"}
for _,name in ipairs(classes) do dofile(vendor.."shared/TimedActions/"..name..".lua") end
local sq=square(10,10,0,false,false)
local function native(action,actor) action.netAction={actor=actor or action.character,connected=true}; action:serverStart(); return action end
local function xpTotal(value) local total=0; for _,amount in pairs(value.test.xp) do total=total+amount end; return total end

-- Installing Java helpers alone must leave unchanged Lifestyle rewards alone.
check(not Rewards.serverRoutesEnabled(),"Module-only helpers do not activate native reward routes")
check(HiddenSkills.getLevel==originalHiddenGet and HiddenSkills.addXP==originalHiddenAdd
    and HiddenSkills.removeXP==originalHiddenRemove,"Module-only loading preserves existing hidden skill functions")
local untouched=player()
Rewards.addHiddenXP(untouched,"Yoga",100)
check(untouched:getModData().LSHiddenSkills.Yoga==nil,"Disabled hidden rewards do not alter progression")
local unpaired=native(LSMeditateAction:new(untouched,"sound",5000,0,1,0,0,0,"Meditate"))
advance(101)
check(not Rewards.context(untouched) and xpTotal(untouched)==0,"Disabled action hooks and tick do not add parallel XP")
check(unpaired:complete(),"Disabled wrapped completion retains its original result")
check(not Rewards.pose(untouched,"Circle") and not Rewards.settle(untouched),"Disabled pose and nudge paths cannot award")
LSUtil.giveXP(untouched,"Music",7)
check(untouched.test.xp.Music==7,"Module-only LSUtil preserves its existing direct server reward")
server=false; client=true
check(not Rewards.enableServerRoutes(),"Clients cannot activate server reward routes")
server=false; client=false
ISInventoryPage={}
local solo=player()
item(solo,"Screws")
local soloData={isBroken=true,repairList={Screws=1},cooldownTime=1}
local soloMachine=object(sq,{movableData={inventionData=soloData}},"Invention")
local soloRepair=LSFixAction:new(solo,soloMachine,soloData,soloData.repairList,200)
check(soloRepair:complete(),"Single-player completion reaches the original resource callback")
check(#solo.test.inventory==0 and soloData.isBroken==false and soloData.repairList==false,
    "Single-player repair consumes materials and updates its invention")
local soloYogi=player()
local soloYoga=LSYogaAction:new(soloYogi,0,{"Beginner",50,1,2})
soloYoga.setOverrideHandModels=function() end
soloYoga.setActionAnim=function() end
soloYoga:start()
soloYoga:doInteraction()
soloYoga:grantXP()
check(soloYogi.test.xp.Fitness==3 and soloYogi.test.xp.Nimble==1,"Single-player Yoga retains its direct pose XP")
server=true; client=false

-- Only the paired actual server dispatcher turns on the migrated native routes.
Capability=setmetatable({}, {__index=function(t,key) rawset(t,key,key); return key end})
dofile(module.."/media/lua/server/ATFPatches_LifestyleSyncPolicy.lua")
dofile(vendor.."server/LSservercommands.lua")
check(Rewards.serverRoutesEnabled(),"Paired server dispatcher activates native rewards")
check(HiddenSkills.getLevel==Rewards.getHiddenLevel and HiddenSkills.addXP==Rewards.addHiddenXP,
    "Paired activation installs authoritative hidden progression functions")

-- Actual server formulas, expected output and duplicate-command nudges.
local reader=player(); current=reader
local meditate=native(LSMeditateAction:new(reader,"sound",5000,0,999999,0,0,0,"Meditate"))
check(Rewards.context(reader)~=nil,"Meditation native lifecycle opens context")
check(Rewards.settle(reader) and xpTotal(reader)==0,"No immediate or client-supplied 999999 reward")
advance(101)
check(reader.test.xp.Meditation>0,"Normal meditation earns source-computed XP")
local earned=xpTotal(reader)
for index=1,100 do Rewards.settle(reader) end
check(xpTotal(reader)==earned,"Repeated client nudges cannot replay earned interval")
meditate:serverStop(); advance(200)
check(xpTotal(reader)==earned and not reader:getModData().IsMeditating,"Cancellation stops future rewards")
check(not meditate:complete(),"Cancelled native completion is rejected")

local musician=player(); musician.test.levels.Music=4
local instrument=item(musician,"GuitarAcoustic")
local training=native(PlayInstrumentTraining:new(musician,instrument,"GuitarAcoustic",nil))
advance(61)
check(musician.test.xp.Music==16,"Training retains exact existing level-four XP formula")
training:serverStop()
local song=native(PlayInstrumentActionNew:new(musician,instrument,"GuitarAcoustic","GuitarAcoustic00DrinktoMeOnlywithThineEyes",1,9999,false,false,nil))
check(song.trackLevel==0 and Rewards.context(musician)~=nil,"Track level comes from installed sound definitions")
advance(121)
check(musician.test.xp.Music>16,"Valid song XP awarded")
local before=xpTotal(musician)
check(song:complete(),"Normal music native completion succeeds")
check(xpTotal(musician)>before and not song:complete(),"Final music reward occurs once")
local forged=native(PlayInstrumentActionNew:new(musician,instrument,"GuitarAcoustic","forged-song",1,9999,false,false,nil))
check(not Rewards.context(musician) and not forged:complete(),"Unknown track cannot earn native XP")

local singer=player(); singer.test.levels.Music=4
local mic=object(sq,{},"Microphone")
local vocal=native(PlayInstrumentVocal:new(singer,mic,"Microphone","VocalDuet04LetsGroove",1,9999,false,true))
advance(121); check(singer.test.xp.Music>0 and vocal.level==4,"Valid vocal formula uses actual track level")
vocal:serverStop()
local dj=player(); local booth=object(sq,{},"Booth")
local djAction=native(PlayDJBoothAction:new(dj,booth,"sound","mode",1,999999,0,0,"action",false))
advance(121); check((dj.test.xp.Music or 0)>0,"DJ native action still awards Music")
djAction:serverStop()
local dancer=player()
local dancing=native(PlayerIsDancingToMusic:new(dancer,0))
advance(121)
check(dancer.test.xp.Dancing>0 and dancer.test.xp.Fitness>0,"Dancing grants both permitted source perks")
dancing:serverStop()
check(statWrites==0 and halos==0,"Server XP calculation has no duplicate mood or UI side effects")

-- Cross-player, ownership and live native actor mapping are mandatory.
local victim=player(); local attacker=player()
local spoof=native(LSMeditateAction:new(victim,"sound",5000,0,1,0,0,0,"Meditate"),attacker)
check(not Rewards.context(victim) and not spoof:complete(),"Native action with forged character is rejected")
local twoActors=LSMeditateAction:new(attacker,"sound",5000,0,1,0,0,0,"Meditate")
twoActors.player=victim
native(twoActors)
check(not Rewards.context(attacker),"An additional mismatched player field cannot authorize rewards")
local stolen=native(PlayInstrumentTraining:new(victim,instrument,"GuitarAcoustic",nil))
check(not Rewards.context(victim),"Another player's instrument cannot authorize rewards")
local fakeItem=item(victim,"FakeGuitarAcousticTool")
local fakeInstrument=native(PlayInstrumentTraining:new(victim,fakeItem,"GuitarAcoustic",nil))
check(not Rewards.context(victim),"Owned item containing an instrument name is not approved")
local bench=object(sq,{},"Bench")
local fakePiano=native(PlayInstrumentTraining:new(victim,"notYogaMat","Piano",bench))
check(not Rewards.context(victim),"An adjacent bench cannot act as a piano")
IsoDirections={E="E",W="W",N="N",S="S"}
local pianoOther=square(11,10,0,false,false)
local piano=object(sq,{},"Piano")
piano.getSpriteName=function() return "recreational_01_8" end
sq.getAdjacentSquare=function(_,direction) return direction=="E" and pianoOther end
local half=native(PlayInstrumentTraining:new(victim,"recreational_01_8","Piano",piano))
check(not Rewards.context(victim),"Missing second piano piece cannot authorize XP")
local other=object(pianoOther,{},"Piano")
other.getSpriteName=function() return "recreational_01_9" end
pianoOther.getObjects=function() return list({other}) end
local pianoPractice=native(PlayInstrumentTraining:new(victim,"recreational_01_8","Piano",piano))
advance(61)
check((victim.test.xp.Music or 0)>0,"Actual two-piece stationary piano still earns practice XP")
pianoPractice:serverStop()
for _,change in ipairs({"setMoving","setDead","setVehicle","setAsleep"}) do
    local value=player(); local action=native(LSMeditateAction:new(value,"sound",5000,0,1,0,0,0,"Meditate"))
    value.test[change](true); advance(101)
    check(xpTotal(value)==0 and not Rewards.context(value),"Live state cancels rewards: "..change)
    check(not value:getModData().IsMeditating,"Invalid live state ends the meditation flag: "..change)
end
local disconnected=player(); native(LSMeditateAction:new(disconnected,"sound",5000,0,1,0,0,0,"Meditate"))
players[disconnected:getOnlineID()]=nil; advance(101)
check(not Rewards.context(disconnected) and xpTotal(disconnected)==0,"Disconnected native actor cannot collect rewards")

-- Real art records/resources replace the client artwork table and duration.
local painter=player(); local brush=item(painter,"oldPaintBrush"); local palette=item(painter,"paintPalette")
local painting={size="medium",level=2}
local easel=object(sq,{painting=painting,progress=300},"Easel")
local art=native(LSCanvasPaintingAction:new(painter,easel,{size="large",level=9999},1,{brush=brush,palette=palette}))
check(art.painting==painting,"Painting reward ignores forged client quality/size data")
advance(100)
check(art:complete() and painter.test.xp.Art==20,"Actual medium level-two painting completion formula retained")
local sculptor=player(); local hammer=item(sculptor,"Hammer"); local chisel=item(sculptor,"CarpentryChisel")
local sculpture={size="small",level=2}
local station=object(sq,{sculpture=sculpture,progress=300},"Workstation")
local sculpt=native(LSSculptingAction:new(sculptor,station,{size="large",level=9999},1,{item1=hammer,item2=chisel,cont1=sculptor:getInventory()}))
advance(100)
check(sculpt:complete() and sculptor.test.xp.Art==10,"Sculpture uses owned tools and actual record, not container fields")

-- Hygiene contexts revalidate source resources, elapsed time and result.
local cleaner=player(); local mop=item(cleaner,"Mop"); local bleach=item(cleaner,"Bleach","Bleach")
local dirtySq=square(11,10,0,true,false)
local room=native(CleanRoomAction:new(cleaner,mop,{Bleach=bleach},dirtySq,true,1))
check(not room:complete() and xpTotal(cleaner)==0,"Forged instant cleaning duration cannot finish")
room=native(CleanRoomAction:new(cleaner,mop,{Bleach=bleach},dirtySq,true,1))
advance(200)
check(room:complete() and cleaner.test.xp.Cleaning==10 and not dirtySq:haveBlood(),"Valid elapsed cleaning completes native blood removal and XP")
local plunger=item(cleaner,"Plunger")
local toilet=object(sq,{movableData={isClogged=100}},"Toilet")
local unclog=native(LSUnclogToilet:new(cleaner,toilet,"Chemical",plunger,1))
advance(30)
check(unclog:complete() and cleaner.test.xp.Cleaning==310,"Unclogging retains exact server perk-based reward")
local sponge=item(cleaner,"Sponge"); local detergent=item(cleaner,"CleaningLiquid2","CleaningLiquid")
local fixture=object(sq,{movableData={condition=10,dirtyLevel=1}},"Sink")
local cleanObject=native(LSCleanObject:new(cleaner,fixture,nil,"sprite",50,{condition=999,dirtyLevel=3},sponge,detergent))
check(cleanObject.syncData==fixture:getModData().movableData,"Server cleaning does not accept forged object data")
advance(21)
check(cleaner.test.xp.Cleaning==320,"Object cleaning retains actual calcXP reward")
for index=1,50 do cleanObject:adjustXP() end
check(cleaner.test.xp.Cleaning==320,"Repeated animation XP events cannot replay reward")
cleanObject:serverStop()
local mechanic=player(); mechanic.test.levels.Maintenance=5
item(mechanic,"Screwdriver")
local screws=item(mechanic,"Screws")
local invention={isBroken=true,repairList={Screws=1},cooldownTime=1}
local machine=object(sq,{movableData={inventionData=invention}},"Invention")
local repair=native(LSFixAction:new(mechanic,machine,{isBroken=false,repairList={Screws=9999}},{Screws=9999},1))
check(repair.itemList==invention.repairList,"Repair materials come from the actual invention record")
advance(100)
check(repair:complete() and mechanic.test.xp.Maintenance==5,"Native repair consumes real materials before awarding source XP")
check(#mechanic.test.inventory==1 and invention.isBroken==false and invention.repairList==false,"Repair removes materials and updates actual broken state")
check(not repair:complete() and mechanic.test.xp.Maintenance==5,"Repair completion cannot consume or reward twice")
invention.isBroken=true; invention.repairList={Screws=1}
local emptyRepair=native(LSFixAction:new(mechanic,machine,invention,{Screws=1},200))
check(not Rewards.context(mechanic) and not emptyRepair:complete(),"Missing repair materials cannot establish reward context")

-- Yoga uses allowed poses and actual elapsed action time, not XP scalar input.
local yogi=player()
local yoga=native(LSYogaAction:new(yogi,9999,{"Master",0,9999,9999}))
check(yoga.skillLevel==0 and yoga.poseLimit==2 and yoga.bonus==1,"Yoga derives level/effects/limit from server skills")
check(not Rewards.pose(yogi,"Circle") and xpTotal(yogi)==0,"No Yoga reward before the pose duration")
advance(331)
check(not Rewards.pose(yogi,"TreeLegHard"),"Higher-level Yoga pose is rejected")
check(Rewards.pose(yogi,"Circle") and yogi.test.xp.Fitness==3 and yogi.test.xp.Nimble==1,"Valid Yoga pose receives source-calculated native XP")
check(yogi:getModData().LSHiddenSkills.Yoga[2]==2,"Yoga hidden XP is earned on the server")
local yogaXP=xpTotal(yogi)
check(not Rewards.pose(yogi,"Circle") and xpTotal(yogi)==yogaXP,"Pose replay does not add XP")
advance(551)
check(yoga:complete() and not yoga:complete(),"Yoga final reward completes once after the rest phase")
check(yogi:getModData().LSHiddenSkills.Yoga[2]>2,"Yoga bonus updates authoritative hidden progression")

-- Clock epochs, bounded catch-up and reload ownership.
local resetPlayer=player(); native(LSMeditateAction:new(resetPlayer,"sound",5000,0,1,0,0,0,"Meditate"))
hours=hours+500; fire("OnTick")
check(not Rewards.context(resetPlayer) and xpTotal(resetPlayer)==0,"Abrupt world time jumps cannot create reward debt")
local dayPlayer=player(); native(LSMeditateAction:new(dayPlayer,"sound",5000,0,1,0,0,0,"Meditate"))
dayLength=60; fire("OnTick")
check(not Rewards.context(dayPlayer),"Day length change invalidates existing action clock context")
dayLength=120; Rewards.clock()
local catchup=player(); local callbacks=0
local synthetic={character=catchup,netAction={actor=catchup,connected=true}}
check(Rewards.start(synthetic,{interval=1,periodic=function(self) callbacks=callbacks+1; LSUtil.giveXP(self.character,"Music",1) end}),"Bounded-work control starts")
real=real+100/12*1000; hours=hours+100/3600
Rewards.settle(catchup)
check(callbacks==32,"One settlement runs at most 32 earned cycles")
Rewards.finish(synthetic,false)
while #Rewards._pending>0 do fire("OnTick") end
check(callbacks>=99 and callbacks<=100,"Previously earned catch-up debt is retained across frames")
local reloadPlayer=player(); local reloadAction=native(LSMeditateAction:new(reloadPlayer,"sound",5000,0,1,0,0,0,"Meditate"))
dofile(module.."/media/lua/shared/ATFPatches_LifestyleRewards.lua")
local ticks,commands=0,0
for _ in pairs(Events.OnTick.handlers) do ticks=ticks+1 end
for _ in pairs(Events.OnServerCommand.handlers) do commands=commands+1 end
check(ticks==1 and commands==1,"Helper reload replaces both event handlers")
check(ATFPatches_LifestyleRewards.context(reloadPlayer).action==reloadAction,"Reload retains active context ownership")
check(HiddenSkills.addXP==ATFPatches_LifestyleRewards.addHiddenXP,"Reload rebinds hidden progression capture closures")
reloadAction:serverStop()

-- Exercise the actual vendor dispatcher and current source policy together.
local function command(actor,name,args)
    for callback in pairs(Events.OnClientCommand.handlers) do callback("LS",name,actor,args) end
end
local claimant=player()
command(claimant,"AddXP",{"Music",999999999})
command(claimant,"AddXPBatch",{{"Music",999999999},{"Fitness",999999999}})
command(claimant,"AddGeneralHealth",{999999999})
check(xpTotal(claimant)==0 and claimant:getHealth()==50,"Actual result RPCs cannot mint XP or health without native action")
local authorized=native(LSMeditateAction:new(claimant,"sound",5000,0,999999,0,0,0,"Meditate"))
real=real+101/12*1000; hours=hours+101/3600
command(claimant,"AddXP",{"Strength",999999999})
check((claimant.test.xp.Meditation or 0)>0 and claimant.test.xp.Strength==nil,"Dispatcher settles only the current action's actual source perks")
local total=xpTotal(claimant)
for index=1,100 do
    command(claimant,"AddXP",{"Music",999999999})
    command(claimant,"AddXPBatch",{{"Fitness",999999999}})
end
command(claimant,"AddGeneralHealth",{999999999})
check(xpTotal(claimant)==total and claimant:getHealth()==50,"Actual repeated result RPCs cannot replay XP or heal")
authorized:serverStop()
claimant.test.capabilities.AddXP=true
command(claimant,"AddXP",{"Music",500})
check(xpTotal(claimant)==total,"Staff normal action nudges cannot duplicate native rewards")
command(claimant,"ATF_AdminXP",{"Music",500})
check(xpTotal(claimant)==total+500,"Explicit staff diagnostic route preserves its intended 500 XP")
total=xpTotal(claimant)
for _,args in ipairs({{"Fitness",500},{"Music",-5},{"Music",math.huge},{"Music",10001},{"Music","500"},{"Music",0/0}}) do
    command(claimant,"ATF_AdminXP",args)
end
check(xpTotal(claimant)==total,"Staff diagnostic rejects other perks and malformed or excessive values")
claimant.test.capabilities.AddXP=false
command(claimant,"ATF_AdminXP",{"Music",500})
check(xpTotal(claimant)==total,"Revoked staff capability cannot grant diagnostic XP")
local dispatchYogi=player()
local dispatchYoga=native(LSYogaAction:new(dispatchYogi,0,{"Beginner",50,1,2}))
command(dispatchYogi,"ATF_YogaPose",{"Circle"})
check(xpTotal(dispatchYogi)==0,"Actual Yoga dispatch enforces server time")
advance(331)
command(dispatchYogi,"ATF_YogaPose",{"Circle"})
check(dispatchYogi.test.xp.Fitness==3 and dispatchYogi.test.xp.Nimble==1,"Actual Yoga dispatch retains legitimate pose reward")
total=xpTotal(dispatchYogi)
command(dispatchYogi,"ATF_YogaPose",{"Circle"})
command(dispatchYogi,"ATF_YogaPose",{})
command(dispatchYogi,"ATF_YogaPose",false)
check(xpTotal(dispatchYogi)==total,"Actual Yoga dispatch rejects replay and malformed payloads")
dispatchYoga:serverStop()

-- Run the stock client phase machine against a separate native server action.
-- The first pose packet is delayed, while the second and completion arrive on time.
local phasePlayer=player()
local phaseServer=native(LSYogaAction:new(phasePlayer,0,{"Beginner",50,1,2}))
local sourceTime,completeTime,poseTimes,acceptedTimes=0,nil,{},{}
local posePackets={}
local oldGameTime,oldSendClient,oldGTLSCheck=getGameTime,sendClientCommand,GTLSCheck
getGameTime=function() return {getWorldAgeHours=function() return hours end,getGameWorldSecondsSinceLastUpdate=function() return 1 end} end
GTLSCheck=1
Metabolics={Fitness="Fitness",FitnessHeavy="FitnessHeavy"}
sendClientCommand=function(actor,module,name,args)
    check(actor==phasePlayer and module=="LS" and name=="ATF_YogaPose","Stock client sends a pose intent rather than scalar XP")
    poseTimes[#poseTimes+1]=sourceTime
    posePackets[#posePackets+1]={name=args[1],time=sourceTime+(#poseTimes==1 and 70 or 0)}
end
server=false; client=true
local phaseClient=LSYogaAction:new(phasePlayer,0,{"Beginner",50,1,2})
phaseClient.setOverrideHandModels=function() end
phaseClient.setActionAnim=function() end
phaseClient.reduceStiffness=function() end
phaseClient.reducePainStressBoredom=function() end
phaseClient.forceComplete=function() completeTime=sourceTime end
phaseClient.sandboxFailChance=false
phaseClient:start()
for time=1,1300 do
    sourceTime=time
    real=real+1000/12; hours=hours+1/3600
    server=true; client=false; fire("OnTick")
    server=false; client=true; phaseClient:update()
    server=true; client=false
    for index=#posePackets,1,-1 do
        local packet=posePackets[index]
        if packet.time<=time then
            check(Rewards.pose(phasePlayer,packet.name),"An earned stock client pose survives differing packet delays")
            acceptedTimes[#acceptedTimes+1]=time
            table.remove(posePackets,index)
        end
    end
    if completeTime then break end
end
check(poseTimes[1]==331 and poseTimes[2]==662,"Stock client ends two poses at its actual strict phase thresholds")
check(acceptedTimes[1]==401 and acceptedTimes[2]==662,"Delayed first receipt does not shift the next earned pose interval")
check(completeTime==1212 and completeTime-poseTimes[2]==550,"Stock client rest and finish require 550 units after the last pose")
check(phaseServer:complete(),"Native minimum accepts completion from the actual stock client phase machine")
check(not phaseServer:complete(),"Stock phase completion still cannot replay")
getGameTime,sendClientCommand,GTLSCheck=oldGameTime,oldSendClient,oldGTLSCheck

-- Native Yoga updates must not replace live, unsaved legacy hidden progress.
local legacyPlayer=player(); current=legacyPlayer
local legacyData=legacyPlayer:getModData()
legacyData.LSHiddenSkills={Yoga={0,2,100},Inventing={3,91,750},PingPong={2,37,500}}
Rewards.syncData(legacyPlayer)
local outgoing=sentCommands[#sentCommands].args.LSHiddenSkills
check(outgoing.Yoga==legacyData.LSHiddenSkills.Yoga and outgoing.Inventing==nil and outgoing.PingPong==nil,
    "Server payload includes only migrated Yoga hidden progression")
local liveInventing,livePingPong=legacyData.LSHiddenSkills.Inventing,legacyData.LSHiddenSkills.PingPong
server=false; client=true
for callback in pairs(Events.OnServerCommand.handlers) do
    callback("LS","ATF_RewardData",{actorOnlineID=legacyPlayer:getOnlineID(),LSHiddenSkills={Yoga={1,10,250},Inventing={0,0,100},PingPong={0,0,100}}})
end
check(legacyData.LSHiddenSkills.Yoga[1]==1 and legacyData.LSHiddenSkills.Inventing==liveInventing
    and legacyData.LSHiddenSkills.PingPong==livePingPong,"Incoming native Yoga sync preserves unsaved legacy skill records")
server=true; client=false

-- Count actual recursive inventory predicate visits, with tools at the end of
-- 10,000-item inventories. Compare against the previous every-frame scan cost.
local benchMusic=player(); benchMusic.test.levels.Music=4
for index=1,10000 do benchMusic.test.inventory[index]={} end
local benchGuitar=item(benchMusic,"GuitarAcoustic")
local benchPractice=native(PlayInstrumentTraining:new(benchMusic,benchGuitar,"GuitarAcoustic",nil))
benchMusic.test.scans.calls,benchMusic.test.scans.items=0,0
local musicNativeBefore=nativeChecks
for index=1,30 do advance(0.2) end
local musicVisits=benchMusic.test.scans.items
local musicBaseline=30*10001
check(musicVisits<musicBaseline/4,"Large-inventory music spends under a quarter of former frame scan work")
check(nativeChecks-musicNativeBefore>=30,"Cheap native ownership checks remain on every music frame")
advance(55)
check(benchMusic.test.xp.Music==16,"Throttled validation preserves the exact first healthy practice interval")
advance(59)
benchMusic:getInventory():DoRemoveItem(benchGuitar)
advance(1)
check(benchMusic.test.xp.Music==16 and not Rewards.context(benchMusic),"A tool lost inside the cache interval cannot earn the next practice award")

local benchPainter=player()
for index=1,10000 do benchPainter.test.inventory[index]={} end
local benchBrush=item(benchPainter,"oldPaintBrush"); local benchPalette=item(benchPainter,"paintPalette")
local benchEasel=object(sq,{painting={size="medium",level=2},progress=300},"Easel")
local benchArt=native(LSCanvasPaintingAction:new(benchPainter,benchEasel,{size="medium",level=2},1,{brush=benchBrush,palette=benchPalette}))
benchPainter.test.scans.calls,benchPainter.test.scans.items=0,0
local artNativeBefore=nativeChecks
for index=1,30 do advance(0.2) end
local artVisits=benchPainter.test.scans.items
local artBaseline=30*(10001+10002)
check(artVisits<artBaseline/4,"Large-inventory painting spends under a quarter of former frame scan work")
check(nativeChecks-artNativeBefore>=30,"Cheap native ownership checks remain on every painting frame")
advance(100)
local artBefore=xpTotal(benchPainter)
benchPainter:getInventory():DoRemoveItem(benchPalette)
check(not benchArt:complete() and xpTotal(benchPainter)==artBefore,"Completion forces a fresh tool check even immediately after a cached healthy tick")

local function testEarlyYoga(startOffset,laterDelay)
    startOffset=startOffset or 11
    if laterDelay==nil then laterDelay=11 end
    local actor=player()
    local nativeAction,sourceAction
    local time,sourceComplete=0,nil
    local messages,sourcePoses={},{ }
    local firstDelivery,firstAward,nextDelivery
    local originalGameTime,originalSendClient,originalGTLS=getGameTime,sendClientCommand,GTLSCheck
    getGameTime=function() return {getWorldAgeHours=function() return hours end,getGameWorldSecondsSinceLastUpdate=function() return 1 end} end
    GTLSCheck=1
    sendClientCommand=function(sender,module,name,args)
        check(sender==actor and module=="LS" and name=="ATF_YogaPose","Early stock client still sends only a pose intent")
        sourcePoses[#sourcePoses+1]=time
        messages[#messages+1]={name=args[1],at=time+(#sourcePoses==1 and 0 or laterDelay)}
    end
    server=false; client=true
    sourceAction=LSYogaAction:new(actor,0,{"Beginner",50,1,2})
    sourceAction.setOverrideHandModels=function() end
    sourceAction.setActionAnim=function() end
    sourceAction.reduceStiffness=function() end
    sourceAction.reducePainStressBoredom=function() end
    sourceAction.forceComplete=function() sourceComplete=time end
    sourceAction.sandboxFailChance=false
    sourceAction:start()
    -- Native StartAction can arrive later than the stock client's first frame.
    -- Later messages either retain the skew or arrive with the normal delay.
    for index=1,1240 do
        time=index
        real=real+1000/12; hours=hours+1/3600
        server=true; client=false
        if nativeAction then fire("OnTick") end
        if firstDelivery and not firstAward and xpTotal(actor)>0 then firstAward=index-startOffset end
        server=false; client=true
        if not sourceComplete then sourceAction:update() end
        server=true; client=false
        if index==startOffset then nativeAction=native(LSYogaAction:new(actor,0,{"Beginner",50,1,2})) end
        for messageIndex=#messages,1,-1 do
            local message=messages[messageIndex]
            if message.at<=index then
                check(Rewards.pose(actor,message.name),"Healthy early-first and timely-next stock pose intents are accepted")
                if not firstDelivery then
                    firstDelivery=index-startOffset
                    check(xpTotal(actor)==0 and Rewards.context(actor).pendingPose==message.name,"Early first intent occupies one slot without awarding XP")
                    check(not Rewards.pose(actor,message.name) and not Rewards.pose(actor,"Tree"),"Duplicate and additional intents cannot occupy another pending slot")
                else
                    nextDelivery=index-startOffset
                    if nextDelivery<660 then
                        check(nativeAction.poseCount==1 and Rewards.context(actor).pendingPose==message.name,
                            "Persistent skew holds the second pose without early extra credit")
                    end
                end
                table.remove(messages,messageIndex)
            end
        end
        if sourceComplete and index>=sourceComplete+laterDelay then break end
    end
    check(firstDelivery==331-startOffset and firstAward>=330 and firstAward<=331,"Early first pose earns only when native 330 is reached")
    check(sourcePoses[1]==331 and sourcePoses[2]==662 and nextDelivery==662+laterDelay-startOffset,
        "Actual next stock pose survives the configured packet skew")
    check(sourceComplete==1212 and nativeAction.poseCount==2 and nativeAction:complete(),
        "Healthy early stock routine retains completion after both native-earned poses")
    local committed=xpTotal(actor)
    actor.test.setMoving(true); advance(30)
    check(not Rewards.context(actor) and xpTotal(actor)==committed and not nativeAction:complete(),
        "Walking after official completion neither loses the bonus nor replays it")
    getGameTime,sendClientCommand,GTLSCheck=originalGameTime,originalSendClient,originalGTLS
end
testEarlyYoga()
testEarlyYoga(20,0)

local function testPendingYogaBoundaries()
    local actor=player()
    local action=native(LSYogaAction:new(actor,0,{"Beginner",50,1,2}))
    advance(299)
    check(not Rewards.pose(actor,"Circle") and Rewards.context(actor).pendingPose==nil,"More than30 early units cannot hold a pose")
    advance(21)
    check(not Rewards.pose(actor,"TreeLegHard") and not Rewards.pose(actor,"forged-pose")
        and Rewards.context(actor).pendingPose==nil,"Wrong-level and unknown poses cannot occupy the pending slot")
    check(Rewards.pose(actor,"Circle") and xpTotal(actor)==0,"Recognized pose can be held within its early window")
    local state=Rewards.context(actor)
    action:serverStop()
    check(state.pendingPose==nil and not Rewards.context(actor),"Cancellation explicitly drops the unearned pose")
    advance(11)
    check(xpTotal(actor)==0 and not action:complete(),"Cancelled pending intent cannot earn or complete after its deadline")

    local earlyComplete=player()
    local completing=native(LSYogaAction:new(earlyComplete,0,{"Beginner",50,1,2}))
    advance(320); check(Rewards.pose(earlyComplete,"Circle"),"Completion boundary holds its initial intent")
    state=Rewards.context(earlyComplete)
    check(not completing:complete() and state.pendingPose==nil,"Premature completion drops an unearned intent")
    advance(11); check(xpTotal(earlyComplete)==0,"Premature completion cannot receive deferred pose XP")

    local replay=player()
    local replayAction=native(LSYogaAction:new(replay,0,{"Beginner",50,1,2}))
    advance(320); check(Rewards.pose(replay,"Circle"),"Replay boundary holds its first recognized pose")
    advance(11)
    local firstCredit=xpTotal(replay)
    advance(330)
    check(not Rewards.pose(replay,"Circle") and xpTotal(replay)==firstCredit,
        "A duplicate accepted pose cannot claim a later accrued interval")
    check(Rewards.pose(replay,"Tree"),"A different legitimate pose can consume the next earned interval")
    advance(518)
    check(not replayAction:complete(),"Completion more than 30 units before its native deadline is rejected")

    local disconnected=player()
    local disconnectedAction=native(LSYogaAction:new(disconnected,0,{"Beginner",50,1,2}))
    advance(329.9); check(Rewards.pose(disconnected,"Circle"),"Connection boundary holds a valid pending intent")
    disconnectedAction.netAction.connected=false
    advance(0.2)
    check(xpTotal(disconnected)==0 and not Rewards.context(disconnected),"Native ownership is revalidated before releasing the intent")

    local oldObjects,oldEast=sq.getObjects,sq.getE
    local oldRequirement=SandboxVars.Yoga.RequiresMat
    local neighbor=square(11,10,0,false,false)
    local firstMat=object(sq,{},"YogaMat"); firstMat.getSpriteName=function() return "floors_rugs_01_52" end
    local secondMat=object(neighbor,{},"YogaMat"); secondMat.getSpriteName=function() return "floors_rugs_01_53" end
    sq.getObjects=function() return list({firstMat}) end
    sq.getE=function() return neighbor end
    neighbor.getObjects=function() return list({secondMat}) end
    SandboxVars.Yoga.RequiresMat=true
    local matUser=player(); native(LSYogaAction:new(matUser,0,{"Beginner",50,1,2}))
    advance(329.9); check(Rewards.pose(matUser,"Circle"),"An actual two-piece Yoga mat authorizes the pending intent")
    neighbor.getObjects=function() return list({}) end
    advance(0.2)
    check(xpTotal(matUser)==0 and not Rewards.context(matUser),"A mat lost within the250ms cache interval cannot release earned pose XP")
    sq.getObjects,sq.getE=oldObjects,oldEast
    SandboxVars.Yoga.RequiresMat=oldRequirement
end
testPendingYogaBoundaries()

local function testLocalRewardRouting()
    local primary,secondary=player(),player()
    local primaryData,secondaryData=primary:getModData(),secondary:getModData()
    primaryData.LSHiddenSkills.Yoga={0,1,100}; secondaryData.LSHiddenSkills.Yoga={0,2,100}
    local locals={[0]=primary,[1]=secondary}
    local oldSpecific,oldCurrent=getSpecificPlayer,current
    getSpecificPlayer=function(index) return locals[index] end
    current=primary
    server=false; client=true
    local function receive(id,level)
        for callback in pairs(Events.OnServerCommand.handlers) do
            callback("LS","ATF_RewardData",{actorOnlineID=id,LSHiddenSkills={Yoga={level,10,250}},MindfulState={Value=0.4,Level=2}})
        end
    end
    receive(secondary:getOnlineID(),2)
    check(primaryData.LSHiddenSkills.Yoga[1]==0 and primaryData.LSMoodles.MindfulState.Value==0,
        "Secondary reward sync preserves the primary local actor")
    check(secondaryData.LSHiddenSkills.Yoga[1]==2 and secondaryData.LSMoodles.MindfulState.Value==0.4,
        "Secondary reward sync reaches only its own local actor")
    receive(primary:getOnlineID(),1)
    check(primaryData.LSHiddenSkills.Yoga[1]==1 and secondaryData.LSHiddenSkills.Yoga[1]==2,
        "Primary reward sync preserves the secondary local actor")
    local foreign=player(); current=foreign
    for _,id in ipairs({foreign:getOnlineID(),-1,0/0,math.huge,primary:getOnlineID()+0.5}) do receive(id,9) end
    receive(nil,9)
    check(primaryData.LSHiddenSkills.Yoga[1]==1 and secondaryData.LSHiddenSkills.Yoga[1]==2
        and foreign:getModData().LSHiddenSkills.Yoga==nil,"Foreign or malformed reward targets cannot mutate any local")
    local replacement=player(); locals[1]=replacement; current=secondary
    receive(secondary:getOnlineID(),9)
    check(secondaryData.LSHiddenSkills.Yoga[1]==2 and replacement:getModData().LSHiddenSkills.Yoga==nil,
        "Stale actor IDs do not fall back to getPlayer or a replaced local slot")
    primary.test.setDead(true); receive(primary:getOnlineID(),9)
    check(primaryData.LSHiddenSkills.Yoga[1]==1,"Dead local actors reject reward sync")
    primary.test.setDead(false)
    getSpecificPlayer,current=oldSpecific,oldCurrent
    server=true; client=false
    Rewards.syncData(secondary)
    check(sentCommands[#sentCommands].args.actorOnlineID==secondary:getOnlineID(),"Server reward payload identifies its precise actor")
end
testLocalRewardRouting()

local function testYogaLevelRefresh()
    local actor=player(); current=actor
    actor:getModData().LSHiddenSkills.Yoga={0,99,100}
    actor.getEmitter=function() return {playSound=function() end} end
    local oldFitness,oldZen=FitnessExercises,LSupdateZenBonus
    FitnessExercises={exercisesType={squats={xpMod=1}}}
    local zenUpdates=0
    LSupdateZenBonus=function(data) zenUpdates=zenUpdates+1 end
    server=false; client=true
    local action=LSYogaAction:new(actor,0,{"Beginner",50,1,2})
    action.setOverrideHandModels=function() end; action.setActionAnim=function() end
    action:start()
    for callback in pairs(Events.OnServerCommand.handlers) do
        callback("LS","ATF_RewardData",{actorOnlineID=actor:getOnlineID(),LSHiddenSkills={Yoga={1,0,250}}})
    end
    check(action.skillLevel==0 and actor:getModData().LSHiddenSkills.Yoga[1]==1,"Received authoritative Yoga level can change during a routine")
    action:perform()
    check(action.skillLevel==1 and actor:getModData().LSMoodles.Zen.Value==0.25 and zenUpdates==1,
        "Stock completion refreshes level zero to one and retains its earned Zen effect")
    check(FitnessExercises.exercisesType.squats.xpMod==1.05 and xpTotal(actor)==0,
        "Stock Zen exercise bonus remains while client completion grants no duplicate XP")
    FitnessExercises,LSupdateZenBonus=oldFitness,oldZen
    server=true; client=false
end
testYogaLevelRefresh()
print("Recursive inventory visits over 30 frames: music "..musicVisits.." / "..musicBaseline..", painting "..artVisits.." / "..artBaseline.." before throttling")
print("Lifestyle native action rewards: "..checks.." checks passed across 13 exact-source action families")
