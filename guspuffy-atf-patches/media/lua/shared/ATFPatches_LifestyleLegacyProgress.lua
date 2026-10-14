-- These stock Lifestyle trackers remain client-owned. Bounds are serialization
-- protection, not proof that their progress, unlocks or modifiers were earned.
ATFPatches_LifestyleLegacyProgress = ATFPatches_LifestyleLegacyProgress or {}
local Legacy = ATFPatches_LifestyleLegacyProgress

local function set(words)
    local result = {}
    for word in words:gmatch("%S+") do
        result[word] = true
    end
    return result
end

local ambitions = set([[LSBladeMaster LSMasterPainter LSJuryRigger LSBrushmaster
LSGrimeFighter LSElDorado LSCommando LSTheProfessional LSLordDeath LSUnstoppable
LSGoodEating LSRockstar LSExplorer LSWanderer LSLumberjack LSKnockdown LSPlushies LSDietOfGods]])
local ambitionBools = set([[isHidden isPassive disable resetF reqHas reqNotHas completed isActive
reset forceReset delayUnlock offBhv offbhv clearBP ateRecent resetAdm doUnlock]])
local ambitionCounters = set("ogXP oldXP ogKills recentKills countdown")
local bodyParts = set([[Hand_L Hand_R ForeArm_L ForeArm_R UpperArm_L UpperArm_R Torso_Upper
Torso_Lower Head Neck Groin UpperLeg_L UpperLeg_R LowerLeg_L LowerLeg_R Foot_L Foot_R]])
local woundTimes = set("ScratchogTime CutogTime DeepWoundogTime BurnogTime FractureogTime")
local plushies = {
    set("Base.SpiffoBig"),
    set("Base.Spiffo Base.BorisBadger"),
    set("Base.JacquesBeaver Base.FluffyfootBunny"),
    set("Base.FreddyFox Base.PancakeHedgehog"),
    set("Base.MoleyMole Base.FurbertSquirrel"),
}
local thresholds = { [0] = 100, 250, 500, 750, 1000, 1250, 1750, 3000, 4000, 9000, 9000 }
local learnedTracks =
    set([[PianoLearnedTracks TrumpetLearnedTracks GuitarALearnedTracks BanjoLearnedTracks
KeytarLearnedTracks SaxophoneLearnedTracks GuitarEBLearnedTracks GuitarELearnedTracks FluteLearnedTracks
HarmonicaLearnedTracks ViolinLearnedTracks]])
local genres = set(
    "disco beach classical country holiday jazz metal muzak pop rap rbsoul reggae rock salsa world"
)
local cooldowns =
    set([[invGnome TeachCooldown LessonCooldown InteractionSpam mirrorPT mirrorCD brushmaster
grimefighter unstoppable FortuneTeller mentalBlock dietofgods StinkingCooldown]])
local inventions = set(
    [[Bell Bricktoys Bullhorn BunnySuitBlack BunnyTail CatToy ChristmasWreath ClothToyPenguin CookieJar_Bear DemonCore Dice Dice_20 DogChew Doll DrinkingBuddy EyeOfCthulhu FoodSynthesizer Glasses_3dGlasses Glasses_Cosmetic_MonocleLeft Glasses_Groucho Glasses_Novelty_Xray Glasses_OldWeldingGoggles Glasses_Round_HoloSkulls Gramophone HalloweenCandyBucket Harvester Hat_Antlers Hat_BunnyEarsWhite Hat_Cowboy_Plastic Hat_FurryEars Hat_GoldStar Hat_HalloweenMaskPumpkin Hat_Jay Hat_JokeKnife Hat_PartyHat_Stars Hat_Pirate Hat_Spiffo Hat_Wizard HobbyHorse Hygienator MetalToyDog MetalToyRobot MetalToyRocket NeuralHat OujaBoard Pillow_Happyface Pillow_Heart Pillow_Star Pocketwatch PotScrubberFrog PowerAxe Revolver_CapGun Rifle_CapGun RubberSpider Rubberducky ScrapBushSeed SheepElectricShears SnowGlobe SpiffoSuit SpiffoTail ToothpasteCurio ToyBear_Crafted_Cotton ToyCar ToyChicken ToyNewtonCradle ToyPlane TrashGoblin UmbrellaHat WaterPump WoodToyCamper WoodToyHelicopter WoodToyHorse WoodToyPlane WoodToyRabbit WoodToyShip WoodToyTank WoodToyTrain WoodenToyPlane Yoyo]]
)
-- name -> stock tier, icon and alignment. Level is derived from Value.
local moodles = {
    Dunce = { 0, 0, "Bad" },
    HygieneGood = { 0, 1, "Good" },
    MintFresh = { 0, 0, "Good" },
    HygieneBad = { 3, 0, "Bad" },
    Nauseous = { 0, 0, "Bad" },
    BathCold = { 0, 0, "Bad" },
    BathHot = { 0, 0, "Good" },
    BladderNeed = { 0, 1, "Bad" },
    AtHouse = { 0, 0, "Good" },
    HomeSick = { 3, 0, "Bad" },
    MusicGood = { 1, 0, "Good" },
    MusicBad = { 1, 0, "Bad" },
    DJAudience = { 2, 0, "Good" },
    PartyGood = { 2, 0, "Good" },
    PartyBad = { 2, 0, "Bad" },
    Embarrassed = { 0, 1, "Bad" },
    Uncomfortable = { 0, 0, "Bad" },
    Comfort = { 0, 1, "Good" },
    BeautyNeg = { 3, 0, "Bad" },
    TaughtSkill = { 0, 0, "Good" },
    AdviceWasted = { 0, 0, "Bad" },
    Attractive = { 0, 0, "Good" },
    SmellGood = { 0, 0, "Good" },
    FTGood = { 0, 0, "Good" },
    FTBad = { 0, 0, "Bad" },
    ElDoradoGood = { 3, 0, "Good" },
    ElDoradoBad = { 3, 0, "Bad" },
    BeautyGood = { 3, 0, "Good" },
    Zen = { 1, 3, "Good" },
    WasTaughtSkill = { 1, 3, "Good" },
    Eureka = { 0, 0, "Good" },
    Gloomy = { 0, 0, "Bad" },
    MintCurio = { 0, 0, "Good" },
}
local function number(value, minimum, maximum, integer)
    return type(value) == "number"
        and value == value
        and value >= minimum
        and value <= maximum
        and (not integer or value == math.floor(value))
end
local function string(value, maximum)
    return type(value) == "string" and #value <= maximum
end
local function plain(value)
    return type(value) == "table" and getmetatable(value) == nil
end
local function level(value)
    if value >= 0.7 then
        return 4
    elseif value >= 0.5 then
        return 3
    elseif value >= 0.3 then
        return 2
    elseif value >= 0.15 then
        return 1
    end
    return 0
end

-- Used only below an explicitly recognized Lifestyle namespace.
local function boundedTree(value, budget, active, depth)
    budget.entries = budget.entries + 1
    budget.bytes = budget.bytes + 16
    if budget.entries > 16000 or budget.bytes > 262144 then
        return nil, false
    end
    if type(value) == "boolean" then
        return value, true
    end
    if type(value) == "number" then
        return value, number(value, -1000000000, 1000000000)
    end
    if type(value) == "string" then
        budget.bytes = budget.bytes + #value
        return value, #value <= 512 and budget.bytes <= 262144
    end
    if not plain(value) or depth > 8 or active[value] then
        return nil, false
    end
    active[value] = true
    local copied = {}
    for key, child in pairs(value) do
        if not (string(key, 128) or number(key, 1, 4096, true)) then
            return nil, false
        end
        budget.bytes = budget.bytes + (type(key) == "string" and #key or 16)
        local normalized, ok = boundedTree(child, budget, active, depth + 1)
        if not ok then
            return nil, false
        end
        copied[key] = normalized
    end
    active[value] = nil
    return copied, true
end

local function copyAmbition(name, record)
    if not plain(record) then
        return nil
    end
    local copied, count = {}, 0
    for key, value in pairs(record) do
        count = count + 1
        if count > 128 then
            return nil
        end
        if key == "name" or key == "texture" then
            if value ~= name then
                return nil
            end
            copied[key] = value
        elseif key == "cat" then
            if not string(value, 32) then
                return nil
            end
            copied[key] = value
        elseif ambitionBools[key] then
            if type(value) ~= "boolean" then
                return nil
            end
            copied[key] = value
        elseif type(key) == "string" and key:match("^goal[1-6]$") then
            if not (number(value, 0, 1000000000) or string(value, 128)) then
                return nil
            end
            copied[key] = value
        elseif type(key) == "string" and key:match("^goal[1-6]progress$") then
            if not (number(value, -1000000000, 1000000000) or type(value) == "boolean") then
                return nil
            end
            copied[key] = value
        elseif ambitionCounters[key] then
            if not (value == false or number(value, 0, 1000000000)) then
                return nil
            end
            copied[key] = value
        elseif key == "ogX" or key == "ogY" then
            if not (value == false or number(value, -1000000, 1000000)) then
                return nil
            end
            copied[key] = value
        elseif key == "newWeight" then
            if not (value == false or number(value, 0, 1000)) then
                return nil
            end
            copied[key] = value
        elseif name == "LSExplorer" and key == "explored" then
            if not plain(value) then
                return nil
            end
            local places, count = {}, 0
            for place, seen in pairs(value) do
                count = count + 1
                if
                    count > 4096
                    or not (string(place, 128) or number(place, 1, 1000000, true))
                    or type(seen) ~= "boolean"
                then
                    return nil
                end
                places[place] = seen
            end
            copied[key] = places
        elseif name == "LSPlushies" and key == "plushyList" then
            if not plain(value) then
                return nil
            end
            local groups = {}
            for group, items in pairs(value) do
                if not number(group, 1, 5, true) or not plain(items) then
                    return nil
                end
                groups[group] = {}
                for index, item in pairs(items) do
                    if not number(index, 1, 2, true) or not plushies[group][item] then
                        return nil
                    end
                    groups[group][index] = item
                end
            end
            copied[key] = groups
        elseif name == "LSUnstoppable" and bodyParts[key] then
            if not plain(value) then
                return nil
            end
            local wounds = {}
            for wound, status in pairs(value) do
                if number(wound, 1, 6, true) then
                    if type(status) ~= "boolean" then
                        return nil
                    end
                elseif woundTimes[wound] then
                    if not number(status, 0, 1000000) then
                        return nil
                    end
                else
                    return nil
                end
                wounds[wound] = status
            end
            copied[key] = wounds
        end
        -- In particular ogSqr is a transient native object, never serialized.
    end
    return copied
end

local function copyTracks(tracks)
    if not plain(tracks) then
        return nil
    end
    local copied = {}
    for index, song in pairs(tracks) do
        if
            not number(index, 1, 512, true)
            or not plain(song)
            or not number(song.level, 0, 10, true)
            or not number(song.length, 0, 86400)
            or not string(song.sound, 192)
            or not string(song.name, 192)
        then
            return nil
        end
        local entry =
            { level = song.level, length = song.length, sound = song.sound, name = song.name }
        if song.isaddon ~= nil then
            if not number(song.isaddon, 0, 100, true) then
                return nil
            end
            entry.isaddon = song.isaddon
        end
        copied[index] = entry
    end
    return copied
end

function Legacy.copy(incoming)
    if not plain(incoming) then
        return nil, "player data"
    end
    local accepted, budget = {}, { entries = 0, bytes = 0 }
    if incoming.Ambitions ~= nil then
        if not plain(incoming.Ambitions) then
            return nil, "ambitions"
        end
        accepted.Ambitions = {}
        for name in pairs(ambitions) do
            local record = incoming.Ambitions[name]
            if record ~= nil then
                local copied = copyAmbition(name, record)
                if not copied then
                    return nil, "ambition " .. name
                end
                accepted.Ambitions[name] = copied
            end
        end
    end
    if incoming.LSHiddenSkills ~= nil then
        if not plain(incoming.LSHiddenSkills) then
            return nil, "hidden skills"
        end
        accepted.LSHiddenSkills = {}
        for _, name in ipairs({ "Inventing", "PingPong" }) do
            local data = incoming.LSHiddenSkills[name]
            if data ~= nil then
                if
                    not plain(data)
                    or not number(data[1], 0, 10, true)
                    or not number(data[2], 0, thresholds[data[1]], true)
                then
                    return nil, "hidden " .. name
                end
                accepted.LSHiddenSkills[name] = { data[1], data[2], thresholds[data[1]] }
            end
        end
    end
    if incoming.LSMoodles ~= nil then
        if not plain(incoming.LSMoodles) then
            return nil, "moodles"
        end
        accepted.LSMoodles = {}
        for name, definition in pairs(moodles) do
            local data = incoming.LSMoodles[name]
            if data ~= nil then
                if not plain(data) or not number(data.Value, 0, 1.000001) then
                    return nil, "moodle " .. name
                end
                local value = math.min(1, data.Value)
                accepted.LSMoodles[name] = {
                    name = name,
                    Value = value,
                    Level = level(value),
                    Tiers = definition[1],
                    Icon = definition[2],
                    Alignment = definition[3],
                }
            end
        end
    end
    if incoming.WasTaughtLast ~= nil then
        local value = incoming.WasTaughtLast
        if
            value ~= false
            and not (
                string(value, 48)
                and (
                    value == "Yoga"
                    or value == "Inventing"
                    or value == "PingPong"
                    or (Perks and Perks[value] ~= nil)
                )
            )
        then
            return nil, "taught skill"
        end
        accepted.WasTaughtLast = value
    end
    if incoming.LSCooldowns ~= nil then
        if not plain(incoming.LSCooldowns) then
            return nil, "cooldowns"
        end
        accepted.LSCooldowns = {}
        for name in pairs(cooldowns) do
            local value = incoming.LSCooldowns[name]
            if value ~= nil then
                if value ~= false and not number(value, 0, 1000000) then
                    return nil, "cooldown"
                end
                accepted.LSCooldowns[name] = value == false and 0 or value
            end
        end
    end
    if incoming.invData ~= nil then
        if not plain(incoming.invData) then
            return nil, "inventions"
        end
        accepted.invData = {}
        for name in pairs(inventions) do
            local value = incoming.invData[name]
            if value ~= nil then
                if value ~= false and not plain(value) then
                    return nil, "invention"
                end
                local copied, ok = boundedTree(value, budget, {}, 1)
                if not ok then
                    return nil, "invention bounds"
                end
                accepted.invData[name] = copied
            end
        end
        for _, name in ipairs({ "specialMax", "specialMax_lvl10", "lsWkID" }) do
            local value = incoming.invData[name]
            if value ~= nil and name == "specialMax" then
                if not number(value, 0, 100, true) then
                    return nil, "invention limit"
                end
                accepted.invData[name] = value
            elseif value ~= nil and name == "specialMax_lvl10" then
                if type(value) ~= "boolean" then
                    return nil, "invention unlock"
                end
                accepted.invData[name] = value
            elseif value ~= nil and name == "lsWkID" then
                if
                    not (value == false or string(value, 128) or number(value, 0, 1000000000, true))
                then
                    return nil, "workbench id"
                end
                accepted.invData[name] = value
            end
        end
    end
    for name in pairs(learnedTracks) do
        if incoming[name] ~= nil then
            local copied = copyTracks(incoming[name])
            if not copied then
                return nil, "learned tracks"
            end
            accepted[name] = copied
        end
    end
    for name, maximum in pairs({
        hygieneNeed = 100,
        bathroomNeed = 100,
        hygieneNeedLimit = 1000,
        BeautyNeed = 100,
        ComfortNeed = 1,
        ComfortVal = 1,
        lastBrushTeeth = 1000000,
        lastCheckYourself = 1000000,
    }) do
        if incoming[name] ~= nil then
            local value = incoming[name]
            if value == false then
                local defaults = {
                    hygieneNeed = 50,
                    bathroomNeed = 0,
                    hygieneNeedLimit = 100,
                    BeautyNeed = 50,
                    ComfortNeed = 0.5,
                    ComfortVal = 0.35,
                    lastBrushTeeth = 0,
                    lastCheckYourself = 0,
                }
                value = defaults[name]
            end
            -- Bladder need is clamped by the stock tracker on its following tick.
            local allowedMaximum = name == "bathroomNeed" and 1000000 or maximum
            if not number(value, 0, allowedMaximum) then
                return nil, "need " .. name
            end
            accepted[name] = name == "bathroomNeed" and math.min(100, value) or value
        end
    end
    for _, field in ipairs({ "PlayerMusicLike", "PlayerMusicDislike" }) do
        if incoming[field] ~= nil then
            local genre = incoming[field]
            if
                not string(genre, 24)
                or not genres[field == "PlayerMusicDislike" and genre:gsub("no$", "") or genre]
                or (field == "PlayerMusicDislike" and genre:sub(-2) ~= "no")
            then
                return nil, "music taste"
            end
            accepted[field] = genre
        end
    end
    -- Apply a shared bound even to otherwise valid large ambition/music records.
    local copied, ok = boundedTree(accepted, { entries = 0, bytes = 0 }, {}, 1)
    if not ok then
        return nil, "legacy bounds"
    end
    return copied
end

function Legacy.apply(current, accepted)
    -- Caller validates all other saved preferences before reaching this point.
    for name, value in pairs(accepted) do
        if
            name == "Ambitions"
            or name == "LSHiddenSkills"
            or name == "LSMoodles"
            or name == "LSCooldowns"
            or name == "invData"
        then
            if type(current[name]) ~= "table" then
                current[name] = {}
            end
            for key, child in pairs(value) do
                current[name][key] = child
                if name == "LSMoodles" and key == "Dunce" then
                    -- Separate legacy failure penalties from native bad-hat mode.
                    current.ATFLegacyDunce = child.Value
                end
            end
        else
            current[name] = value
        end
    end
end
