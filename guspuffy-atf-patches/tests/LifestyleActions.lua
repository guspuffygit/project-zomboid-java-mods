-- Run actual vendor files with disposable items, coordinates and UI state.
local root = (arg[1] or "guspuffy-atf-patches/build/vendor-fixtures") .. "/mod-LifestyleHobbies/common/media/lua/"
local baseline = arg[2] == "baseline"
local checks, reproduced = 0, 0
local function check(ok, why) assert(ok, why); checks = checks + 1 end
local function result(ok, value, expected, why)
    if baseline then
        check(not ok, why .. " reproduces in the original source")
        reproduced = reproduced + 1
    else
        check(ok and value == expected, why .. ": " .. tostring(value))
    end
end
require = function() return {} end

-- Neural Hat: original duration runs once; each supported state uses item data.
local duration, durationCalls, state, hatData = 300, 0, 1, {}
ItemBodyLocation = {HAT="Hat"}
ISReadABook = {getDuration=function() durationCalls=durationCalls+1; return duration end}
local hat = {getType=function() return "NeuralHat" end,
    getVisual=function() return {getTextureChoice=function() return state end} end,
    getModData=function() return hatData end}
local hasHat = true
local reader = {getWornItems=function() return {getItem=function() return hasHat and hat end} end,
    getModData=function() return {LSMoodles={Dunce={Level=2}}} end}
invData = nil
dofile(root .. "shared/TimedActions/hooks/Read.lua")
for _, case in ipairs({{1,67.5},{3,105},{4,75},{5,45}}) do
    state, hatData = case[1], {invData={fastRead=true,efficiencyMult={1,2}}}
    local before=durationCalls
    local ok, value=pcall(ISReadABook.getDuration, {character=reader})
    result(ok,value,case[2],"Active Neural Hat state " .. state)
    check(durationCalls==before+1,"Native reading duration called exactly once")
end
state=0; check(ISReadABook.getDuration({character=reader})==300,"Inactive hat retains duration")
state=2; check(ISReadABook.getDuration({character=reader})==1200,"Bad hat retains fourfold penalty")
duration=50; state=1; check(ISReadABook.getDuration({character=reader})==50,"Short action is unchanged")
duration=300; hasHat=false; check(ISReadABook.getDuration({character=reader})==900,"Dunce path retained")
hasHat=true
if not baseline then
    state=1
    for _, data in ipairs({{}, {invData=true}, {invData="invalid"}, {invData={}}, {invData={efficiencyMult=true}}, {invData={efficiencyMult={}}},
        {invData={efficiencyMult={1,0}}}, {invData={efficiencyMult={1,-2}}},
        {invData={efficiencyMult={1,"bad"}}}, {invData={efficiencyMult={1,math.huge}}}, {invData={efficiencyMult={1,0/0}}}}) do
        hatData=data
        check(ISReadABook.getDuration({character=reader})==300,"Missing or invalid efficiency keeps native duration")
    end
    hatData={invData={fastRead=false,efficiencyMult={1,2}}}
    check(ISReadABook.getDuration({character=reader})==135,"Normal active bonus without fast reading")
    hatData={invData={fastRead=true,efficiencyMult={1,100}}}
    check(ISReadABook.getDuration({character=reader})==15,"Maximum reading speed remains bounded")
    hatData={invData={fastRead=true,efficiencyMult={1,0.2}}}
    check(ISReadABook.getDuration({character=reader})==150,"Low efficiency keeps existing multiplier clamp")
    state=6; check(ISReadABook.getDuration({character=reader})==300,"Unknown state retains duration")
end
-- Both repair callbacks must finish native repair, parity update and sync.
local nativeRepairs=0
ISHandcraftAction={perform=function() end,performRecipe=function() nativeRepairs=nativeRepairs+1 end}
ISFixVehiclePartAction={perform=function() end,complete=function() nativeRepairs=nativeRepairs+1 end}
instanceof=function(_, kind) return kind=="InventoryItem" end
local server=true
isServer=function() return server end
dofile(root .. "shared/TimedActions/hooks/FixActions.lua")
local repairData, repairCount, synced, stats, bullet, transmitted
local item={getModData=function() return repairData end,getHaveBeenRepaired=function() return repairCount end,
    setHaveBeenRepaired=function(_,value) repairCount=value end,syncItemFields=function() synced=synced+1 end}
local vehicle={updatePartStats=function() stats=stats+1 end,updateBulletStats=function() bullet=bullet+1 end,
    transmitPartItem=function() transmitted=transmitted+1 end}
local ambition={isActive=true,completed=true}
local repairer={getModData=function() return {Ambitions={LSJuryRigger=ambition}} end}
local recipe={getCategory=function() return "Repair" end}
local action={character=repairer,item=item,vehiclePart={getVehicle=function() return vehicle end},
    logic={getRecipeData=function() return {getRecipe=function() return recipe end} end},
    items={size=function() return 1 end,get=function() return item end}}
for _, method in ipairs({ISHandcraftAction.performRecipe, ISFixVehiclePartAction.complete}) do
    for _, case in ipairs({{marker=false,count=2,next=1,total=2}, {marker=false,count=1,next=0,total=0},
        {marker=0,count=3,next=1,total=3}, {marker=1,count=3,next=2,total=2},
        {marker=2,count=3,next=3,total=3}, {marker=3,count=4,next=4,total=3}}) do
        for _, mode in ipairs({true,false}) do
            repairData={JRrepair=case.marker or nil}; repairCount=case.count
            synced,stats,bullet,transmitted=0,0,0,0
            server=mode
            local before=nativeRepairs
            local ok,value=pcall(method,action)
            if baseline and not case.marker and case.count>=2 then
                check(not ok and repairData.JRrepair==1 and synced==0,"Original repair nil marker reproduced after marker update")
                reproduced=reproduced+1
            else
                check(ok,"Repair completes: " .. tostring(value))
                check(repairData.JRrepair==case.next and repairCount==case.total,"Repair parity and count preserved")
                check(synced==(mode and 1 or 0),"Item fields sync only on server")
                if method==ISFixVehiclePartAction.complete then
                    check(stats==1 and bullet==1 and transmitted==1,"Vehicle stats and transmission finish exactly once")
                else
                    check(stats==0 and transmitted==0,"Recipe does not mutate vehicle stats")
                end
            end
            check(nativeRepairs==before+1,"Native repair invoked once")
        end
    end
end

for _,method in ipairs({ISHandcraftAction.performRecipe,ISFixVehiclePartAction.complete}) do
    for _, completed in ipairs({true,false}) do
        ambition.isActive=false; ambition.completed=completed
        repairData={JRrepair=1}; repairCount=3; synced,stats,bullet,transmitted=0,0,0,0
        local before=nativeRepairs
        check(pcall(method,action),"Inactive ambition repair completes")
        check(nativeRepairs==before+1 and repairCount==3 and repairData.JRrepair==1 and synced==0,"Inactive ambition preserves native repair and marker")
        local expected=(completed and method==ISFixVehiclePartAction.complete) and 1 or 0
        check(stats==expected and bullet==expected and transmitted==expected,"Inactive vehicle stat controls preserved")
    end
end
ambition.isActive=true; ambition.completed=true

-- Bath exits must use numeric coordinates and only reachable squares.
dofile(root .. "client/Hygiene/BathTubFunctions.lua")
local calls={}
local main,east,west={},{},{}
main.getE=function() return east end; main.getW=function() return west end
main.getS=function() return nil end; main.getN=function() return nil end
east.getW=function() return main end
east.getX=function() return 11 end; east.getY=function() return 10 end
west.getX=function() return 9 end; west.getY=function() return 10 end
local eastOpen,westOpen=false,true
AdjacentFreeTileFinder={privTrySquare=function(_,sq) return sq==west and westOpen or sq==east and eastOpen end}
local position=10
local bather={getX=function() return position end,getY=function() return 10 end,
    setX=function(_,n) assert(type(n)=="number","setX requires number"); calls[#calls+1]={"x",n} end,
    setY=function(_,n) assert(type(n)=="number","setY requires number"); calls[#calls+1]={"y",n} end}
local bath={getSquare=function() return main end,getSprite=function() return {
    getName=function() return "fixtures_bathroom_01_25" end,
    getProperties=function() return {has=function() return true end,get=function() return "N" end} end} end}
for _,x in ipairs({10,8}) do
    position=x; calls={}
    local ok,value=pcall(BathTubFunctions.walkToFront,bather,bath)
    result(ok,value,true,"West bath exit branch at X=" .. x)
    if not baseline then check(#calls==2 and calls[1][2]==9 and calls[2][2]==10,"West numeric coordinates match square") end
end
eastOpen=true; calls={}
check(BathTubFunctions.walkToFront(bather,bath) and calls[1][2]==11 and calls[2][2]==10,"East bath control retained")
eastOpen=false; westOpen=false; calls={}
check(not BathTubFunctions.walkToFront(bather,bath) and #calls==0,"Blocked bath exit does not reposition")
calls={}; check(BathTubFunctions.walkToFront(bather,bath,14,15) and calls[1][2]==14 and calls[2][2]==15,"Saved exit coordinates retained")

-- A clean empty chemical toilet still scans for pure refill bleach.
isClient=function() return false end
sendClientCommand=function() error("Network not allowed in this fixture") end
getText=function(key) return key end; getTexture=function(name) return name end
Translator={getFluidText=function(name) return name end}
local menu={options={}}
local function addOption(self,name,...) local option={name=name,args={...}}; self.options[#self.options+1]=option; return option end
menu.addOption=addOption; menu.addOptionOnTop=addOption
menu.addSubMenu=function() end; menu.getSubMenu=function() return menu end; menu.getNew=function() return menu end
ISContextMenu={getNew=function() return menu end}
local inventory={}
local bladder={LSMoodles={BladderNeed={Value=0.4}}}
local toiletUser={getModData=function() return bladder end,isFemale=function() return false end,hasTrait=function() return false end,
    getInventory=function() return {getItems=function() return {size=function() return #inventory end,get=function(_,i) return inventory[i+1] end} end} end}
CharacterTrait={SLOPPY="Sloppy"}
LSUtil={isValidObj=function() return true end,getValidPlayer=function() return toiletUser end,isCharBusy=function() return false end,
    isCharSitting=function() return false end,getObjTexAndText=function() return "texture","Chemical Toilet" end,
    hasAdminRights=function() return false end,getSimpleTooltip=function(text) return {description=text} end,
    getDummyOption=function(context,name) return context:addOption(name) end,
    itemHasFluid=function(value,fluid,amount,pure) return value.fluid==fluid and value.amount>=(amount or 0) and (not pure or value.pure) end}
LSCleaning={getCleaningTime=function() return 200 end}
LSHygiene={DS={Toilets={chemicalSprite={"dirt1","dirt2","dirt3"}}},TF={getWaterUsage=function() return false end}}
SandboxVars={LSHygiene={CleanClogged=false}}
local toiletData
local toilet={getModData=function() return toiletData end,getOverlaySprite=function() return nil end,setOverlaySprite=function() end,
    getSprite=function() return {getName=function() return "chemicalSprite" end} end}
dofile(root .. "client/Hygiene/ToiletContextMenu.lua")
ToiletContextMenu.LookForTP=function() return false end
local function buildToilet(dirty,uses,items)
    inventory=items or {}; menu.options={}
    toiletData={movableData={dirtyLevel=dirty,condition=0,uses=uses,isClogged=false}}
    return pcall(ToiletContextMenu.doBuildMenu,0,menu,{},toilet,"chemicalSprite","Toilet","Chemical",{})
end
local function option(name) for _,entry in ipairs(menu.options) do if entry.name==name then return entry end end end
local ok,value=buildToilet(0,0)
if baseline then
    check(not ok and option("ContextMenu_Toilet_Refill"),"Original clean empty refill error reproduced during option construction"); reproduced=reproduced+1
else
    check(ok,"Clean empty toilet menu completes")
    check(option("ContextMenu_Toilet_Refill").notAvailable,"Refill disabled without bleach")
    local bleach={fluid="Bleach",amount=1,pure=true,getType=function() return "Bleach" end}
    for _, fluidCase in ipairs({{fluid="Bleach",amount=1,pure=false}, {fluid="Bleach",amount=0.5,pure=true}, {fluid="Water",amount=1,pure=true}}) do
        fluidCase.getType=bleach.getType
        check(buildToilet(0,0,{fluidCase}),"Invalid refill item menu completes")
        check(option("ContextMenu_Toilet_Refill").notAvailable,"Invalid refill fluid is rejected")
    end
    check(buildToilet(0,0,{bleach}),"Pure bleach refill menu completes")
    local refill=option("ContextMenu_Toilet_Refill")
    check(not refill.notAvailable and refill.args[7][4]==bleach and refill.args[8]=="IsRefill","Refill callback retains selected item and command")
    check(toiletData.movableData.uses==0 and bleach.amount==1,"Menu makes no fluid or uses mutation")
end
check(buildToilet(1,0),"Dirty empty toilet control completes")
check(buildToilet(0,1),"Clean nonempty toilet control completes")
check(not option("ContextMenu_Toilet_Refill"),"Nonempty toilet has no refill option")

-- Unknown style must still close the mirror and finish action/item cleanup.
local baseStop,basePerform,closed,reset,clothing,returned,dropped=0,0,0,0,0,0,0
ISBaseTimedAction={derive=function() return {} end,stop=function() baseStop=baseStop+1 end,perform=function() basePerform=basePerform+1 end}
TransferHelper={onMoveItemsTo=function() returned=returned+1 end,dropItem=function() dropped=dropped+1 end}
triggerEvent=function(name) check(name=="OnClothingUpdated","Clothing callback retained"); clothing=clothing+1 end
local style
local female=true
getHairStylesInstance=function() return {FindFemaleStyle=function() return style end,FindMaleStyle=function() return style end} end
getBeardStylesInstance=function() return {FindStyle=function() return nil end} end
dofile(root .. "shared/TimedActions/LSCheckYourselfAP.lua")
local nonAttached="SavedCustomHair"
local visual={getHairModel=function() return "CustomHair" end,getNonAttachedHair=function() return nonAttached end,
    setNonAttachedHair=function(_,v) nonAttached=v end,getNaturalHairColor=function() return "natural" end,
    setHairColor=function() end,getBeardModel=function() return "CustomBeard" end}
local mirrorData={LSMirrorMenuOverlayPanel=true}
local character={getHumanVisual=function() return visual end,isFemale=function() return female end,
    getModData=function() return mirrorData end,resetModel=function() reset=reset+1 end,resetHairGrowingTime=function() end,
    resetBeardGrowingTime=function() end}
local scissors,razor={},{}
local container={isItemAllowed=function() return true end,getType=function() return "container" end}
local floor={isItemAllowed=function() return true end,getType=function() return "floor" end}
local mirrorAction={gameSoundLoop=0,character=character,canTalk=false,
    LSMirrorMenuOverlay={close=function() closed=closed+1 end},oldHairstyle={getName=function() return "Original" end},
    itemsList={Scissors=scissors,ScissorsCont=container,Razor=razor,RazorCont=floor}}
for _, method in ipairs({LSCheckYourselfAP.stop,LSCheckYourselfAP.perform}) do
  for _,sex in ipairs({true,false}) do
    female=sex
    style=nil; mirrorData.LSMirrorMenuOverlayPanel=true; nonAttached="SavedCustomHair"
    baseStop,basePerform,closed,reset,clothing,returned,dropped=0,0,0,0,0,0,0
    ok,value=pcall(method,mirrorAction)
    if baseline then
        check(not ok and baseStop==0 and basePerform==0 and reset==0,"Original unknown hairstyle error skips base cleanup"); reproduced=reproduced+1
    else
        check(ok,"Unknown style cleanup completes: " .. tostring(value))
        check(closed==1 and not mirrorData.LSMirrorMenuOverlayPanel,"Mirror panel closes once and flag clears")
        check(nonAttached=="SavedCustomHair","Unknown style preserves attached model state")
        if method==LSCheckYourselfAP.perform then
            check(basePerform==1 and baseStop==0 and reset==1 and clothing==1,"Model and base completion occur once")
            check(returned==1 and dropped==1,"Borrowed scissors and razor are returned")
        else
            check(baseStop==1 and basePerform==0,"Base cancellation occurs once")
        end
    end
  end
end
style={isAttachedHair=function() return false end,getLevel=function() return 1 end,getName=function() return "Known" end}
mirrorAction.oldHairstyle=nil
for _,method in ipairs({LSCheckYourselfAP.stop,LSCheckYourselfAP.perform}) do
    nonAttached="TiedHair"; mirrorData.LSMirrorMenuOverlayPanel=true
    check(pcall(method,mirrorAction),"Known hairstyle cleanup control completes")
    check(nonAttached==nil,"Known untied hairstyle clears attached state")
end
style.isAttachedHair=function() return true end
for _,method in ipairs({LSCheckYourselfAP.stop,LSCheckYourselfAP.perform}) do
    nonAttached=nil; mirrorData.LSMirrorMenuOverlayPanel=true
    check(pcall(method,mirrorAction),"Known attached hairstyle cleanup completes")
    check(nonAttached=="CustomHair","Known attached hairstyle records model")
end
print("Lifestyle action regressions: " .. checks .. " checks passed; original failures reproduced: " .. reproduced)
