local module = arg[1] or "guspuffy-atf-patches"
local source = arg[2]
local checks = 0
local function check(ok, message)
    assert(ok, message)
    checks = checks + 1
end
Perks = { Meditation = {}, Cooking = {}, Woodwork = {} }
dofile(module .. "/media/lua/shared/ATFPatches_LifestyleLegacyProgress.lua")
local Legacy = ATFPatches_LifestyleLegacyProgress
local function clone(value)
    if type(value) ~= "table" then
        return value
    end
    local result = {}
    for key, child in pairs(value) do
        result[key] = clone(child)
    end
    return result
end
local incoming = {
    Ambitions = {
        LSRockstar = {
            name = "LSRockstar",
            texture = "LSRockstar",
            cat = "Creativity",
            goal1 = 10,
            completed = true,
            isActive = true,
            goal1progress = 10,
            oldXP = 500,
        },
        LSExplorer = {
            name = "LSExplorer",
            completed = false,
            goal1progress = 300,
            explored = { downtown = true, [400] = true },
        },
        LSUnstoppable = {
            name = "LSUnstoppable",
            Hand_L = {
                true,
                false,
                false,
                true,
                false,
                false,
                ScratchogTime = 12,
                BurnogTime = 30,
            },
        },
        LSPlushies = {
            name = "LSPlushies",
            plushyList = { { "Base.SpiffoBig" }, { "Base.Spiffo", "Base.BorisBadger" } },
        },
        LSWanderer = { name = "LSWanderer", ogX = 5000, ogY = 6000, ogSqr = function() end },
        LSTerminator = { completed = true, goal1progress = 999999 },
        UnknownAmbition = { completed = true },
    },
    LSHiddenSkills = {
        Yoga = { 10, 9000, 9000 },
        Inventing = { 7, 1500, 999999 },
        PingPong = { 1, 80, 999999 },
    },
    LSMoodles = {
        MindfulState = { Value = 1 },
        Dunce = { Value = 0 },
        NeuralHat = { Value = 1 },
        Zen = { Value = 0.4, Level = 100 },
        WasTaughtSkill = { Value = 0.2, Level = 100 },
        PartyGood = { Value = 0.6 },
        Embarrassed = { Value = 0.8 },
        UnknownMoodle = { Value = 1 },
    },
    WasTaughtLast = "Meditation",
    LSCooldowns = { invGnome = 120, TeachCooldown = 60, Other = 9999 },
    invData = {
        NeuralHat = {
            invName = "NeuralHat",
            level = 9,
            lastCreated = 1200,
            numCreated = 2,
            improvementData = { efficiency = { 2, 9 } },
            inventionData = { efficiencyMult = { 0.2, 0.4, 0.1 } },
            workCost = { ["Base.ScrapMetal"] = 3 },
        },
        specialMax = 2,
        specialMax_lvl10 = true,
        lsWkID = false,
        UnknownInvention = { unlocked = true },
    },
    GuitarALearnedTracks = {
        {
            level = 3,
            sound = "GuitarAcoustic03AmazingGrace",
            name = "ContextMenu_03_01_GA",
            length = 150,
            isaddon = 2,
        },
    },
    PlayerMusicLike = "jazz",
    PlayerMusicDislike = "metalno",
    hygieneNeed = 40,
    bathroomNeed = 20,
    hygieneNeedLimit = 100,
    ComfortNeed = 0.5,
    ComfortVal = 0.35,
    BeautyNeed = 70,
    lastBrushTeeth = 30,
    lastCheckYourself = 10,
    IsMeditating = true,
    MindfulnessMinutes = 99999,
    MindfulnessLast = 999999,
    SomeOtherMod = { admin = true },
    arbitraryHealth = 100000,
}
local accepted, reason = Legacy.copy(incoming)
check(accepted ~= nil, "Reviewed trackers copy: " .. tostring(reason))
check(accepted.Ambitions.LSRockstar.completed, "Existing non-Terminator completion persists")
check(accepted.Ambitions.LSExplorer.explored[400], "Numeric and named explored places persist")
check(
    accepted.Ambitions.LSUnstoppable.Hand_L.ScratchogTime == 12,
    "Native body-part wound progress persists"
)
check(
    accepted.Ambitions.LSPlushies.plushyList[2][2] == "Base.BorisBadger",
    "Collected plushies persist"
)
check(accepted.Ambitions.LSWanderer.ogSqr == nil, "Native square reference is never serialized")
check(
    accepted.Ambitions.LSTerminator == nil and accepted.Ambitions.UnknownAmbition == nil,
    "Server-owned and unknown ambitions excluded"
)
check(accepted.LSHiddenSkills.Yoga == nil, "Server-owned Yoga excluded")
check(
    accepted.LSHiddenSkills.Inventing[3] == 3000 and accepted.LSHiddenSkills.PingPong[3] == 250,
    "Hidden thresholds derive from stock level"
)
check(
    accepted.LSMoodles.MindfulState == nil and accepted.LSMoodles.NeuralHat == nil,
    "Migrated passive moodles excluded"
)
check(
    accepted.LSMoodles.Zen.Level == 2 and accepted.LSMoodles.WasTaughtSkill.Level == 1,
    "Native moodle thresholds replace forged levels"
)
check(
    accepted.LSMoodles.Zen.Icon == 3 and accepted.LSMoodles.Zen.Tiers == 1,
    "Stock moodle presentation metadata retained"
)
check(
    accepted.LSCooldowns.Other == nil and accepted.invData.UnknownInvention == nil,
    "Unknown nested namespaces excluded"
)
check(
    accepted.SomeOtherMod == nil
        and accepted.arbitraryHealth == nil
        and accepted.IsMeditating == nil
        and accepted.MindfulnessMinutes == nil
        and accepted.MindfulnessLast == nil,
    "Unrelated state and native reward fields excluded"
)
local current = {
    Ambitions = { LSTerminator = { completed = false } },
    LSHiddenSkills = { Yoga = { 2, 20, 500 } },
    LSMoodles = {
        MindfulState = { Value = 0.2 },
        Dunce = { Value = 0.2 },
        NeuralHat = { Value = 0.2 },
    },
    SomeOtherMod = { retained = true },
    IsMeditating = false,
    MindfulnessMinutes = 12,
    MindfulnessLast = 15,
}
Legacy.apply(current, accepted)
check(
    current.Ambitions.LSTerminator.completed == false and current.LSHiddenSkills.Yoga[1] == 2,
    "Merge preserves trusted ambitions and Yoga"
)
check(
    current.LSMoodles.MindfulState.Value == 0.2 and current.LSMoodles.NeuralHat.Value == 0.2,
    "Merge preserves trusted passives"
)
check(
    current.LSMoodles.Dunce.Value == 0 and current.ATFLegacyDunce == 0,
    "Known failure penalty has a separate server-private marker"
)
check(
    current.SomeOtherMod.retained and not current.IsMeditating and current.MindfulnessMinutes == 12,
    "Merge preserves unrelated and native progress"
)
incoming.Ambitions.LSRockstar.completed = false
incoming.invData.NeuralHat.improvementData.efficiency[1] = 99
check(
    current.Ambitions.LSRockstar.completed
        and current.invData.NeuralHat.improvementData.efficiency[1] == 2,
    "Copied state retains no input table references"
)
local restored = Legacy.copy(current)
check(
    restored.Ambitions.LSRockstar.completed
        and restored.invData.specialMax_lvl10
        and restored.GuitarALearnedTracks[1].sound == accepted.GuitarALearnedTracks[1].sound,
    "Reconnect round trip retains completion, invention unlock and learned tracks"
)

local function rejects(mutator, message)
    local value = clone(incoming)
    mutator(value)
    check(Legacy.copy(value) == nil, message)
end
rejects(function(value)
    value.LSHiddenSkills.Inventing[1] = 0 / 0
end, "Reject NaN hidden level")
rejects(function(value)
    value.LSHiddenSkills.Inventing[2] = 1000000
end, "Reject XP outside native next-level threshold")
rejects(function(value)
    value.LSHiddenSkills.PingPong[1] = 11
end, "Reject out-of-range hidden level")
rejects(function(value)
    value.LSMoodles.PartyGood.Value = 2
end, "Reject out-of-range party modifier")
rejects(function(value)
    value.LSMoodles.Zen.Value = math.huge
end, "Reject infinite moodle value")
rejects(function(value)
    value.WasTaughtLast = "Administrator"
end, "Reject invented education skill")
rejects(function(value)
    value.Ambitions.LSRockstar.completed = "yes"
end, "Reject nonboolean completion")
rejects(function(value)
    value.Ambitions.LSExplorer.explored.downtown = 100
end, "Reject malformed exploration progress")
rejects(function(value)
    value.Ambitions.LSUnstoppable.Hand_L[3] = 50
end, "Reject malformed wound history")
rejects(function(value)
    value.Ambitions.LSPlushies.plushyList[1][1] = "Base.AssaultRifle"
end, "Reject item outside plushie catalog")
rejects(function(value)
    value.invData.NeuralHat.inventionData.self = value.invData.NeuralHat
end, "Reject cyclic invention table")
rejects(function(value)
    value.invData.NeuralHat = setmetatable({}, {})
end, "Reject metatable-bearing invention record")
rejects(function(value)
    value.invData.NeuralHat.inventionData.bad = function() end
end, "Reject executable nested state")
rejects(function(value)
    value.invData.NeuralHat.inventionData.text = string.rep("x", 513)
end, "Reject oversized nested string")
rejects(function(value)
    value.invData.NeuralHat.inventionData.bad = {}
    for i = 1, 4097 do
        value.invData.NeuralHat.inventionData.bad[i] = true
    end
end, "Reject oversized nested array")
rejects(function(value)
    value.hygieneNeed = -1
end, "Reject invalid hygiene need")
rejects(function(value)
    value.GuitarALearnedTracks[1].length = math.huge
end, "Reject invalid learned song")
local untouched = clone(current)
local malformed = clone(incoming)
malformed.invData.NeuralHat.inventionData.invalid = function() end
local rejected = Legacy.copy(malformed)
if rejected then
    Legacy.apply(current, rejected)
end
check(
    current.invData.NeuralHat.improvementData.efficiency[1]
            == untouched.invData.NeuralHat.improvementData.efficiency[1]
        and current.Ambitions.LSRockstar.completed == untouched.Ambitions.LSRockstar.completed,
    "Failed validation cannot partially apply accepted progress"
)
for _, value in ipairs({ 0.45, 1, 0.435, 0.2 + 0.2 + 0.2 + 0.2 + 0.2 }) do
    local copied =
        Legacy.copy({ LSMoodles = { Embarrassed = { Value = value }, Zen = { Value = value } } })
    check(
        copied and copied.LSMoodles.Embarrassed.Value <= 1,
        "Continuous native modifiers and repeated Yoga sums persist"
    )
end
local reset = Legacy.copy({
    LSCooldowns = { invGnome = false },
    BeautyNeed = false,
    bathroomNeed = 100.05,
    hygieneNeedLimit = 110,
    Ambitions = { LSBladeMaster = { goal1progress = -10 } },
})
check(
    reset
        and reset.LSCooldowns.invGnome == 0
        and reset.BeautyNeed == 50
        and reset.bathroomNeed == 100
        and reset.hygieneNeedLimit == 110
        and reset.Ambitions.LSBladeMaster.goal1progress == -10,
    "False resets, bladder overshoot, hygiene limit adjustment and native XP loss normalize safely"
)

if source then
    local definitions = dofile(source .. "/client/Properties/Player/LSAmbitions.lua")
    local snapshot, count = { Ambitions = {} }, 0
    for _, definition in ipairs(definitions) do
        if definition.name ~= "LSTerminator" then
            local entry = clone(definition)
            entry.completed, entry.isActive, entry.goal1progress = true, true, 10
            snapshot.Ambitions[definition.name] = entry
            count = count + 1
        end
    end
    local normalized = Legacy.copy(snapshot)
    check(
        count == 18 and normalized ~= nil,
        "Exact installed catalog contains 18 preserved ambitions"
    )
    local saved = { Ambitions = {} }
    Legacy.apply(saved, normalized)
    for _, definition in ipairs(definitions) do
        if definition.name ~= "LSTerminator" then
            check(
                saved.Ambitions[definition.name].completed
                    and saved.Ambitions[definition.name].goal1progress == 10,
                "Actual stock record survives save for " .. definition.name
            )
        end
    end
    Events = { OnGameStart = { Add = function() end } }
    dofile(source .. "/shared/Inventions/inventions_defs.lua")
    dofile(source .. "/client/Inventions/lib/Inv_Inventions.lua")
    dofile(source .. "/client/Inventions/lib/Inv_Toys.lua")
    local inventory = { invData = { specialMax = 2, specialMax_lvl10 = true, lsWkID = false } }
    for _, name in ipairs({ "invLib", "toysLib" }) do
        for _, definition in pairs(InventionsMenu.workbench[name]) do
            local record = clone(definition)
            record.lastCreated, record.numCreated = 1234, 2
            if name == "invLib" then
                record.inventionData = clone(LSInventionDefs.Items[record.invName])
                record.improvementData = {}
                for key, value in pairs(LSInventionDefs.Improvements[record.invName]) do
                    record.improvementData[key] = { 0, value.repeatable and #value.repeatable or 1 }
                end
            end
            inventory.invData[record.invName] = record
        end
    end
    local copied, why = Legacy.copy(inventory)
    check(copied ~= nil, "Actual stock invention records serialize: " .. tostring(why))
    local inventionCount = 0
    for name in pairs(inventory.invData) do
        if name ~= "specialMax" and name ~= "specialMax_lvl10" and name ~= "lsWkID" then
            check(
                type(copied.invData[name]) == "table",
                "Actual unlocked invention persists for " .. name
            )
            inventionCount = inventionCount + 1
        end
    end
    check(inventionCount == 79, "Stock catalog has 79 serializable invention and toy IDs")

    -- Exercise actual trackers, including their full SavePlayerData payload.
    require = function()
        return nil
    end
    local function event()
        local item = { handlers = {} }
        item.Add = function(fn)
            item.handlers[fn] = true
        end
        item.Remove = function(fn)
            item.handlers[fn] = nil
        end
        return item
    end
    Events = {
        OnNewGame = event(),
        OnCreatePlayer = event(),
        OnGameStart = event(),
        OnTick = event(),
        EveryHours = event(),
        EveryOneMinute = event(),
        EveryTenMinutes = event(),
        EveryDays = event(),
    }
    local function fire(name)
        local callbacks = {}
        for callback in pairs(Events[name].handlers) do
            callbacks[#callbacks + 1] = callback
        end
        for _, callback in ipairs(callbacks) do
            callback()
        end
    end
    SandboxVars = {
        Text = { DividerMusicNew = false },
        LS = { MoodUpdate = 9, ModdataUpdate = 2 },
        DayLength = 4,
        LSHygiene = { BladderNeedMultiplier = 1 },
    }
    CharacterTrait = { JAZZ = "JAZZ", METALNO = "METALNO" }
    MoodleType = { FOOD_EATEN = "Food", HUNGRY = "Hungry", THIRST = "Thirst", PANIC = "Panic" }
    BodyPartType = { Torso_Lower = "Lower" }
    local data = clone(incoming)
    data.LSMoodles.BladderNeed = { Value = 0.8, Level = 4 }
    data.LSMoodles.Embarrassed = { Value = 0, Level = 0 }
    data.bathroomNeed, data.PlayerVoice = 99.99, 3
    local actor = {
        getModData = function()
            return data
        end,
        hasModData = function()
            return true
        end,
        isDead = function()
            return false
        end,
        isAsleep = function()
            return false
        end,
        isGodMod = function()
            return false
        end,
        hasTimedActions = function()
            return false
        end,
        isOutside = function()
            return true
        end,
        getVehicle = function()
            return true
        end,
        getHumanVisual = function()
            return {}
        end,
        hasTrait = function(_, trait)
            return trait == "JAZZ" or trait == "METALNO"
        end,
        getMoodles = function()
            return {
                getMoodleLevel = function()
                    return 0
                end,
            }
        end,
    }
    getPlayer = function()
        return actor
    end
    getSpecificPlayer = function()
        return actor
    end
    getNumActivePlayers = function()
        return 1
    end
    isServer = function()
        return false
    end
    isClient = function()
        return true
    end
    ModData = { request = function() end }
    LSUtil = {
        getValidCharacter = function(player)
            return player
        end,
        getCharacterMood = function()
            return 100
        end,
        changeCharacterMoodGroup = function() end,
        changeCharacterMood = function() end,
        addPainBodyPart = function() end,
    }
    HaloTextHelper = { addTextWithArrow = function() end }
    getText = function(value)
        return value
    end
    getSoundManager = function()
        return { playUISound = function() end }
    end
    local function noBodyParts()
        return 0
    end
    BloodBodyPartType = { MAX = { index = noBodyParts } }
    local random = 0
    ZombRand = function()
        return random
    end
    dofile(source .. "/client/Hygiene/ToiletBladderNeed.lua")
    local body = {
        getBodyPart = function()
            return {
                getPain = function()
                    return 100
                end,
            }
        end,
    }
    AdjustBladderNeed(actor, data, body)
    check(data.bathroomNeed > 100, "Actual stock bladder tracker can overshoot a tick")
    local normal = Legacy.copy(data)
    check(
        normal and normal.bathroomNeed == 100,
        "Healthy bladder overshoot never drops saved progress"
    )
    random = 9
    AdjustBladderNeed(actor, data, body)
    check(
        data.LSMoodles.Embarrassed.Value == 0.45,
        "Actual stock accident gives continuous embarrassment"
    )
    check(Legacy.copy(data) ~= nil, "Accident modifier and healthy post-burst data serialize")
    local savedPayload
    sendClientCommand = function(_, moduleName, command, args)
        if moduleName == "LS" and command == "SavePlayerData" then
            savedPayload = args[1]
        end
    end
    random = 0
    dofile(source .. "/client/XpSystem/PlayerTracker.lua")
    fire("OnCreatePlayer")
    for _ = 1, 6 do
        fire("OnTick")
    end
    check(
        savedPayload == data and Legacy.copy(savedPayload) ~= nil,
        "Actual login PlayerTracker full payload is accepted"
    )
    dofile(source .. "/client/ZLSUpdate.lua")
    fire("OnGameStart")
    savedPayload = nil
    fire("EveryOneMinute")
    check(
        savedPayload == data and Legacy.copy(savedPayload) ~= nil,
        "Actual periodic SavePlayerData full payload is accepted"
    )
end
print("Lifestyle legacy progress: " .. checks .. " checks passed")
