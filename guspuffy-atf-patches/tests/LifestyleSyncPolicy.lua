local path = arg[1] or "guspuffy-atf-patches/media/lua/server/ATFPatches_LifestyleSyncPolicy.lua"
dofile(arg[2] or "guspuffy-atf-patches/media/lua/shared/ATFPatches_LifestyleLegacyProgress.lua")
local checks = 0
local function check(ok, message) assert(ok, message); checks = checks + 1 end
Capability = {SandboxOptions={},CanModifyPlayerStatsInThePlayerStatsUI={},AddItem={}}
local permissions = {}
local saved = { OtherMod={private=1}, LSHiddenSkills={Yoga={2,30,500}},
    LSMoodles={MindfulState={Value=0}}, MindfulnessMinutes=0, MindfulnessLast=0,
    Ambitions={Existing={completed=false,isActive=false,ogKills=12}} }
local player = { getModData=function() return saved end, getRole=function()
    return { hasCapability=function(_,key) return permissions[key] == true end }
end }
ScriptManager = {instance={getItem=function(_,name) return name == "Base.Bandage" and {} or nil end}}
dofile(path)
local policy = ATFPatches_LifestyleSyncPolicy
for _, command in ipairs({"UpdateAmbt","UpdateServerBeauty","ImportServerBeauty","CompleteTargetAmbt","ResetTargetAmbt","LSSCTest","AddItems_Player"}) do
    check(not policy.allowCommand(player,command,{"Base.Bandage",1}),"Ordinary role cannot invoke " .. command)
end
permissions[Capability.SandboxOptions]=true
for _, command in ipairs({"UpdateAmbt","UpdateServerBeauty","ImportServerBeauty","LSSCTest"}) do
    check(policy.allowCommand(player,command,{}),"Current sandbox capability allows " .. command)
end
check(not policy.allowCommand(player,"CompleteTargetAmbt",{}),"Settings permission does not imply player permission")
permissions[Capability.CanModifyPlayerStatsInThePlayerStatsUI]=true
check(policy.allowCommand(player,"CompleteTargetAmbt",{}),"Player-stat capability allows target ambition action")
permissions[Capability.AddItem]=true
check(policy.allowCommand(player,"AddItems_Player",{"Base.Bandage",1}),"Authorized valid item grant remains available")
for _, amount in ipairs({0,-1,1.5,101,math.huge,0/0,"17"}) do
    check(not policy.allowCommand(player,"AddItems_Player",{"Base.Bandage",amount}),"Invalid amount denied")
end
check(not policy.allowCommand(player,"AddItems_Player",{"Base.Unknown",1}),"Unknown script denied")
check(not policy.allowCommand(player,"AddItems_Player",{"../../../item",1}),"Invalid item type denied")
permissions={}
check(not policy.allowCommand(player,"UpdateAmbt",{}),"Role loss revokes immediately")
check(policy.allowCommand(player,"SyncItemData_FromPlayer",{1}),"Normal item synchronization remains routed")
check(not policy.allowCommand(nil,"SyncItemData_FromPlayer",{1}),"Missing sender denied")
check(not policy.allowCommand(player,"UpdateAmbt",nil),"Missing command payload denied")
local missingRole={getRole=function() return nil end}
check(not policy.allowCommand(missingRole,"UpdateAmbt",{}),"Missing role denied")
local originalCapability=Capability
Capability=nil
check(not policy.allowCommand(player,"UpdateAmbt",{}),"Unavailable capability API denied")
Capability=originalCapability
local originalHidden, originalMood=saved.LSHiddenSkills,saved.LSMoodles
check(policy.savePlayerData(player,{{PlayerVoice=3, LSClothes={casual={"Base.Shirt",42}},
    LSHiddenSkills={Yoga={10,999999,1}},LSMoodles={MindfulState={Value=1}},
    MindfulnessMinutes=999, MindfulnessLast=1,OtherMod={private=2},newAuthority=true,
    Ambitions={Existing={isActive=true,completed=true,ogKills=-10000},Invented={isActive=true,completed=true}}}}),
    "Healthy preferences accepted from whole legacy payload")
check(saved.PlayerVoice==3 and saved.LSClothes.casual[1]=="Base.Shirt","Voice and clothing preferences persist")
check(saved.LSHiddenSkills==originalHidden and saved.LSMoodles==originalMood,"Earned skills and moods unchanged")
check(saved.MindfulnessMinutes==0 and saved.MindfulnessLast==0,"Client cannot activate health rewards")
check(saved.OtherMod.private==1 and saved.newAuthority==nil,"Other mods and unknown authority keys remain untouched")
check(saved.Ambitions.Existing.isActive and not saved.Ambitions.Existing.completed and saved.Ambitions.Existing.ogKills==12,
    "Only existing ambition selection toggles, not achievement")
check(saved.Ambitions.Invented==nil,"Client cannot invent a completed ambition")
local selection
ATFPatches_LifestylePassiveRewards={selectAmbition=function(who,name,active) selection={who,name,active} end}
check(policy.savePlayerData(player,{{Ambitions={LSTerminator={isActive=true,completed=true,ogKills=-9000}}}}),
    "Terminator preference accepted")
check(selection[1]==player and selection[2]=="LSTerminator" and selection[3]==true,"Terminator uses server activation handler")
local supplied={casual={"Base.Shirt"}}
check(policy.savePlayerData(player,{{LSClothes=supplied}}),"Bounded clothing preferences accepted")
supplied.casual[1]="changed"
check(saved.LSClothes.casual[1]=="Base.Shirt","Client table is not retained by reference")
local previous=saved.LSClothes
local cycle={}; cycle.self=cycle
local deep={}; local node=deep; for _=1,8 do node.child={}; node=node.child end
local many={}; for i=1,513 do many["key"..i]=1 end
for _, value in ipairs({cycle,deep,many,{bad=math.huge},{bad=0/0},{bad=string.rep("x",1025)},{bad=function() end}}) do
    check(not policy.savePlayerData(player,{{PlayerVoice=1,LSClothes=value}}),"Malformed or excessive preferences denied")
    check(saved.LSClothes==previous and saved.PlayerVoice==3,"Rejected preference batch makes no partial changes")
end
for _, voice in ipairs({-1,5,1.5,"2",math.huge,0/0}) do
    check(not policy.savePlayerData(player,{{PlayerVoice=voice}}),"Invalid voice denied")
end
check(not policy.savePlayerData(player,{{Ambitions=true}}),"Malformed ambition preference denied")
check(not policy.savePlayerData(player,{{LSClothes=true}}),"Malformed clothing preference denied")
check(not policy.savePlayerData(player,nil),"Missing preferences denied")
check(not policy.savePlayerData(nil,{{}}),"Missing preference sender denied")

check(policy.savePlayerData(player,{{LSHiddenSkills={Inventing={3,120,99999}},
    LSMoodles={Zen={Value=0.4,Level=99}},
    Ambitions={LSRockstar={name="LSRockstar",completed=true,isActive=true,goal1progress=10}}}}),
    "Reviewed nonmigrated legacy progress accepted")
check(saved.LSHiddenSkills.Inventing[1]==3 and saved.LSHiddenSkills.Inventing[3]==750,
    "Inventing progression persists with native threshold")
check(saved.LSMoodles.Zen.Value==0.4 and saved.LSMoodles.Zen.Level==2,
    "Legacy moodle level derives from bounded value")
check(saved.Ambitions.LSRockstar.completed and saved.Ambitions.LSRockstar.goal1progress==10,
    "Nonmigrated ambition progression remains compatible")
check(saved.LSHiddenSkills.Yoga[1]==2 and saved.LSMoodles.MindfulState.Value==0,
    "Legacy progress cannot replace migrated fields")
check(not policy.savePlayerData(player,{{PlayerVoice=1,LSHiddenSkills={Inventing={99,1,100}}}}),
    "Malformed recognized legacy progress rejected")
check(saved.PlayerVoice==3 and saved.LSHiddenSkills.Inventing[1]==3,
    "Invalid legacy batch applies no preferences or partial progress")
dofile(path)
check(ATFPatches_LifestyleSyncPolicy==policy,"Reload retains stable policy API")
print("PASS: " .. checks .. " Lifestyle save/admin policy checks")
