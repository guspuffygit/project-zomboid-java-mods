local fixtures = (arg[1] or "guspuffy-atf-patches/build/vendor-fixtures")
    .. "/mod-LifestyleHobbies/common/media/lua/"
local module = arg[2] or "guspuffy-atf-patches"
local baseline = arg[3] == "baseline"
local checks = 0
local function check(ok, why)
    assert(ok, why)
    checks = checks + 1
end
local function near(actual, expected, why)
    check(math.abs(actual - expected) < 0.00001, why .. ": " .. actual)
end
local function event()
    local result = { handlers = {} }
    result.Add = function(fn)
        result.handlers[fn] = true
    end
    result.Remove = function(fn)
        result.handlers[fn] = nil
    end
    return result
end
Events = { OnServerCommand = event(), EveryOneMinute = event(), AddXP = event() }
local function fire(name, ...)
    local callbacks = {}
    for fn in pairs(Events[name].handlers) do
        callbacks[#callbacks + 1] = fn
    end
    for _, fn in ipairs(callbacks) do
        fn(...)
    end
end
local function handlerCount(name)
    local count = 0
    for _ in pairs(Events[name].handlers) do
        count = count + 1
    end
    return count
end
local client, server = false, true
isClient = function()
    return client
end
isServer = function()
    return server
end
instanceof = function(value, kind)
    return value.kind == kind
end
ItemBodyLocation = { HAT = "Hat" }
BodyPartType = { Neck = "Neck" }
CharacterStat = { ENDURANCE = "endurance" }
CharacterTrait = { DISCIPLINED = "disciplined" }
SandboxVars = {
    Text = { DividerMeditationNew = true },
    Meditation = { MindfulnessDuration = 2, HealFactor = 2 },
    LSAmbt = { Toggle = true, MaxInProgress = 1, MaxTotal = 3 },
}
local function perk(name, parent)
    return {
        getId = function()
            return name
        end,
        getParent = function()
            return {
                getId = function()
                    return parent
                end,
            }
        end,
    }
end
Perks = {
    Meditation = perk("Meditation", "Lifestyle"),
    Axe = perk("Axe", "Combat"),
    None = perk("None", "None"),
}
local perks = { Perks.Meditation, Perks.Axe, Perks.None }
Perks.getMaxIndex = function()
    return #perks + 1
end
Perks.fromIndex = function(index)
    return perks[index]
end
local rand3, rand20 = 0, 0
ZombRand = function(limit)
    return limit == 3 and rand3 or rand20
end
local messages, damagePackets, statPackets, xpPackets, clientPackets, snapshotReads =
    {}, 0, 0, 0, 0, 0
sendServerCommand = function(player, name, command, args)
    messages[#messages + 1] = { player = player, name = name, command = command, args = args }
end
sendClientCommand = function()
    clientPackets = clientPackets + 1
end
sendDamage = function()
    damagePackets = damagePackets + 1
end
sendPlayerStat = function()
    statPackets = statPackets + 1
end
SyncXp = function()
    xpPackets = xpPackets + 1
end
getGameTime = function()
    return {
        getWorldAgeHours = function()
            return 0
        end,
    }
end
getSandboxOptions = function()
    return {
        getDayLengthMinutes = function()
            return 120
        end,
    }
end
require = function(name)
    if name == "ATFPatches_LifestyleRewards" then
        return ATFPatches_LifestyleRewards
    end
end
dofile(module .. "/media/lua/shared/ATFPatches_LifestyleRewards.lua")
local function list(values)
    return {
        size = function()
            return #values
        end,
        get = function(_, i)
            return values[i + 1]
        end,
    }
end
local nextOnlineID = 200
local function makePlayer()
    nextOnlineID = nextOnlineID + 1
    local player = {
        onlineID = nextOnlineID,
        kind = "IsoPlayer",
        data = {},
        dead = false,
        xp = { Meditation = 100, Axe = 100 },
        levels = { Meditation = 10, Axe = 0 },
        health = 100,
        endurance = 1,
        kills = 500,
        fire = 0.003,
        burning = false,
        disciplined = false,
        broken = false,
        owned = true,
        worn = true,
        state = 1,
        inv = {
            enabled = true,
            fuelUses = 100,
            efficiencyMult = { 0.1, 2, 0.5 },
            overdrive = { 3 },
        },
    }
    player.hat = {
        getType = function()
            return "NeuralHat"
        end,
        isBroken = function()
            return player.broken
        end,
        getModData = function()
            return { movableData = { inventionData = player.inv } }
        end,
        getVisual = function()
            return {
                getTextureChoice = function()
                    return player.state
                end,
            }
        end,
    }
    player.getModData = function(self)
        return self.data
    end
    player.getOnlineID = function(self)
        return self.onlineID
    end
    player.isDead = function(self)
        return self.dead
    end
    player.isAsleep = function()
        return false
    end
    player.hasTimedActions = function()
        return false
    end
    player.getVehicle = function()
        return nil
    end
    player.getWornItems = function()
        return {
            getItem = function()
                return player.worn and player.hat
            end,
        }
    end
    player.getInventory = function()
        return {
            getFirstEvalRecurse = function(_, predicate)
                return player.owned and predicate(player.hat) and player.hat or nil
            end,
        }
    end
    player.getPerkLevel = function(self, value)
        return self.levels[value:getId()] or 0
    end
    player.getXp = function()
        return {
            getXP = function(_, value)
                snapshotReads = snapshotReads + 1
                return player.xp[value:getId()] or 0
            end,
        }
    end
    player.getHealth = function(self)
        return self.health
    end
    player.getZombieKills = function(self)
        return self.kills
    end
    player.hasTrait = function(self)
        return self.disciplined
    end
    player.getFireKillRate = function(self)
        return self.fire
    end
    player.setFireKillRate = function(self, value)
        self.fire = value
    end
    player.isOnFire = function(self)
        return self.burning
    end
    player.StopBurning = function(self)
        self.burning = false
    end
    player.getStats = function()
        return {
            get = function()
                return player.endurance
            end,
            set = function(_, _, value)
                player.endurance = value
            end,
        }
    end
    player.parts = {}
    player.body = {
        AddGeneralHealth = function(_, amount)
            player.health = math.min(100, player.health + amount)
        end,
        getBodyParts = function()
            return list(player.parts)
        end,
        getNumPartsBleeding = function()
            return #player.parts
        end,
    }
    player.getBodyDamage = function()
        return player.body
    end
    ATFPatches_LifestyleRewards.ensureData(player)
    return player
end
addXp = function(player, value, amount)
    local applied = amount * (player.multiplier or 1)
    player.xp[value:getId()] = player.xp[value:getId()] + applied
    fire("AddXP", player, value, applied)
end
addXpNoMultiplier = function(player, value, amount)
    player.xp[value:getId()] = math.max(0, player.xp[value:getId()] + amount)
    fire("AddXP", player, value, amount)
end
local online = {}
getOnlinePlayers = function()
    return list(online)
end
getPlayer = function()
    return online[1]
end
dofile(module .. "/media/lua/shared/ATFPatches_LifestylePassiveRewards.lua")
local Passive = ATFPatches_LifestylePassiveRewards
local function minute(count)
    for _ = 1, count or 1 do
        fire("EveryOneMinute")
    end
end
local function fresh()
    local player = makePlayer()
    online = { player }
    Passive.players[player] = nil
    return player
end

local player = fresh()
local empty = makePlayer()
empty.data = {}
online = { empty }
minute(8)
local emptyCount = 0
for _ in pairs(empty.data) do
    emptyCount = emptyCount + 1
end
check(emptyCount == 0, "Module alone never initializes passive state")
check(Passive.players[empty] == nil, "Module alone never initializes reward caches")
check(
    not Passive.selectAmbition(empty, "LSTerminator", true),
    "Module alone never changes ambitions"
)
online = { player }
addXp(player, Perks.Axe, 10)
minute(8)
check(
    player.xp.Axe == 110 and Passive.players[player] == nil,
    "Module alone never grants NeuralHat bonus"
)
player.data.LSMoodles.MindfulState.Value = 0.6
local beforeHealth = player.health
minute(8)
check(player.health == beforeHealth, "Module alone never heals native health")
ATFPatches_LifestyleRewards.enableServerRoutes()
player = fresh()
minute()
check(player.xp.Axe == 100, "Initialization cannot reward historical XP")
check(
    messages[#messages].args.actorOnlineID == player:getOnlineID(),
    "Server passive payload identifies its actual local actor"
)
player.xp.Axe = 110 -- accepted native snapshot, with no Lifestyle amount packet
minute(5)
check(player.xp.Axe == 110, "Perk polling preserves the original five-callback cooldown")
player.multiplier = 2
minute()
near(player.xp.Axe, 112, "Native snapshot gain receives the existing formula and multiplier")
minute(6)
near(player.xp.Axe, 112, "Post-award reread prevents bonus feedback")
local priorMessages = #messages
minute()
check(#messages == priorMessages, "Unchanged passive values do not send repeat UI snapshots")

player = fresh()
addXp(player, Perks.Axe, 10)
minute()
near(player.xp.Axe, 111, "Actual server AddXP event seeds first earned gain")
minute(6)
near(player.xp.Axe, 111, "Event and snapshot paths count the earning once")
check(Passive.players[player].applying == false, "Recursive AddXP guard clears after award")
local other = makePlayer()
online = { player, other }
minute()
other.xp.Axe = 105
minute(6)
near(other.xp.Axe, 105, "Small first gain retains residue without early XP")
other.xp.Axe = 106
minute(6)
near(other.xp.Axe, 106.6, "Second earning flushes the original fractional residue")
near(player.xp.Axe, 111, "One player's residue never affects another player")

player = fresh()
rand3 = 1
minute()
player.xp.Axe = 110
minute(6)
near(player.xp.Axe, 111.5, "Existing one-in-three extra XP formula remains")
rand3 = 0
for _, invalid in ipairs({
    "off",
    "missing",
    "broken",
    "empty",
    "unknown",
    "overdrive",
    "coefficient",
}) do
    player = fresh()
    minute()
    player.xp.Axe = 110
    if invalid == "off" then
        player.state = 0
    elseif invalid == "missing" then
        player.owned = false
    elseif invalid == "broken" then
        player.broken = true
    elseif invalid == "empty" then
        player.inv.fuelUses = 0
    elseif invalid == "overdrive" then
        player.state = 5
        player.inv.overdrive = { 1 }
    elseif invalid == "coefficient" then
        player.inv.efficiencyMult[1] = 1000
    else
        player.state = 6
    end
    minute(6)
    near(player.xp.Axe, 110, "Invalid equipped invention cannot award XP: " .. invalid)
end
player = fresh()
player.state = 5
minute()
player.xp.Axe = 110
minute(6)
near(player.xp.Axe, 115, "Valid highest researched overdrive retains its existing XP formula")
player = fresh()
player.state = 2
minute()
player.xp.Axe = 110
minute(6)
near(player.xp.Axe, 102, "Bad Neural Hat retains the eighty-percent earned-XP penalty")
player.inv.fuelUses = 0
minute()
check(
    player.data.LSMoodles.Dunce.Value == 0,
    "Expired bad-hat state clears its server-derived penalty"
)
dofile(module .. "/media/lua/shared/ATFPatches_LifestyleLegacyProgress.lua")
local Legacy = ATFPatches_LifestyleLegacyProgress
player = fresh()
player.state = 2
minute()
Legacy.apply(
    player.data,
    Legacy.copy({ LSMoodles = { Dunce = { Value = 0 } }, ATFLegacyDunce = 999 })
)
player.xp.Axe = 110
minute(6)
near(player.xp.Axe, 102, "Client negative-modifier reset cannot bypass native bad-hat penalty")
Legacy.apply(player.data, Legacy.copy({ LSMoodles = { Dunce = { Value = 1 } } }))
player.inv.fuelUses = 0
minute()
check(
    player.data.LSMoodles.Dunce.Value == 1 and player.data.ATFLegacyDunce == 1,
    "New legitimate critical-failure penalty survives the broken-hat transition"
)
player.xp.Axe = 112
minute(6)
near(player.xp.Axe, 104, "Legacy lingering failure retains eighty-percent earned-XP penalty")
Legacy.apply(player.data, Legacy.copy({ LSMoodles = { Dunce = { Value = 0 } } }))
minute()
check(
    player.data.LSMoodles.Dunce.Value == 0,
    "Legacy negative-modifier cleanup preserves original lifecycle"
)
player = fresh()
minute()
player.xp.Axe = 90
minute(6)
near(player.xp.Axe, 90, "XP reductions are not positive earnings")
player.levels.Axe = 10
player.xp.Axe = 110
minute(6)
near(player.xp.Axe, 110, "Level-ten perk receives no extra XP")

player = fresh()
player.state = 0
player.health = 50
player.disciplined = true
player.data.LSMoodles.MindfulState.Value = 0.6
player.data.IsMeditating = true
local priorDamage = damagePackets
minute()
near(
    player.health,
    62,
    "Trusted perfect mindfulness uses native disciplined-level-ten heal formula"
)
check(
    player.data.MindfulnessMinutes == false,
    "Active native meditation holds earned mindfulness duration"
)
check(damagePackets == priorDamage + 1, "Server healing sends the native PlayerDamage update once")
player.data.IsMeditating = false
player.data.MindfulnessMinutes = 0
player.disciplined = false
minute()
near(player.health, 70, "Non-disciplined level-ten heal remains fourfold")
near(player.data.LSMoodles.MindfulState.Value, 0.4, "Earned mindfulness decays by one tier")
check(player.data.MindfulnessMinutes == 179, "Native tier duration and decrement preserved")
minute()
near(player.health, 70, "Lower mindfulness tier cannot heal")
player.data.LSMoodles.MindfulState.Value = 0.6
SandboxVars.Text.DividerMeditationNew = false
minute()
near(player.health, 70, "Disabled meditation sandbox prevents passive healing")
SandboxVars.Text.DividerMeditationNew = true

player = fresh()
player.state = 0
check(
    not Passive.selectAmbition(player, "Other", true),
    "Only the audited Terminator route creates a server ambition"
)
check(not Passive.selectAmbition(player, "LSTerminator", 1), "Ambition preference must be boolean")
check(
    Passive.selectAmbition(player, "LSTerminator", true),
    "Valid preference captures native kill baseline"
)
local ambition = player.data.Ambitions.LSTerminator
check(
    ambition.ogKills == 500 and ambition.goal1 == 5000 and not ambition.completed,
    "Client completion/goal amounts are not accepted"
)
player.kills = 5499
minute()
check(
    ambition.goal1progress == 4999 and not ambition.completed,
    "Previous kills cannot complete the active ambition"
)
near(player.endurance, 0.35, "In-progress Terminator retains its endurance restriction")
player.kills = 5500
minute()
check(
    ambition.completed and not ambition.reset,
    "Exactly five thousand native kills completes Terminator"
)
check(
    Passive.selectAmbition(player, "LSTerminator", false) and ambition.completed,
    "Disabling a completed ambition preserves earned completion"
)
player.parts = {
    {
        bleeding = function()
            return true
        end,
        IsBleedingStemmed = function()
            return false
        end,
        getType = function()
            return "Arm"
        end,
        AddHealth = function(_, gain)
            player.armGain = gain
        end,
    },
    {
        bleeding = function()
            return true
        end,
        IsBleedingStemmed = function()
            return false
        end,
        getType = function()
            return "Neck"
        end,
        AddHealth = function(_, gain)
            player.neckGain = gain
        end,
    },
}
minute()
near(player.armGain, 0.05, "Completed passive ambition retains bleeding-part health")
near(player.neckGain, 0.25, "Neck bleeding retains the existing multiplier")
Passive.selectAmbition(player, "LSTerminator", true)
minute()
player.health = 90
player.endurance = 0.25
player.burning = true
rand20 = 19
priorDamage = damagePackets
minute()
near(player.health, 100, "Server Terminator rolls restore observed recent damage")
near(player.endurance, 0.27, "Active Terminator retains its endurance change formula")
near(player.fire, 0.001, "Active Terminator retains reduced fire damage rate")
check(not player.burning, "Native burning stops on the existing successful roll")
check(damagePackets == priorDamage + 1, "Combined passive health effects send one native update")
Passive.selectAmbition(player, "LSTerminator", false)
minute()
near(player.fire, 0.003, "Disabling active bonus restores original fire rate")
rand20 = 0

player = fresh()
player.state = 0
Passive.selectAmbition(player, "LSTerminator", true)
player.kills = 700
minute()
Passive.selectAmbition(player, "LSTerminator", false)
check(
    not player.data.Ambitions.LSTerminator.completed
        and player.data.Ambitions.LSTerminator.ogKills == nil,
    "Disabling incomplete ambition resets progress"
)
player.data.Ambitions.Other = { isActive = true, completed = false }
check(
    not Passive.selectAmbition(player, "LSTerminator", true),
    "Server ambition selection enforces the sandbox in-progress limit"
)
player.data.Ambitions.Other.isActive = false
Passive.selectAmbition(player, "LSTerminator", true)
minute()
player.dead = true
priorDamage = damagePackets
minute()
check(
    Passive.players[player] == nil and damagePackets == priorDamage,
    "Dead player cannot receive rewards and is removed from cache"
)
online = {}
minute()
local retained = 0
for _ in pairs(Passive.players) do
    retained = retained + 1
end
check(retained == 0, "Disconnected players leave no cached XP or health state")
player = fresh()
minute()
player.xp.Axe = 110
dofile(module .. "/media/lua/shared/ATFPatches_LifestylePassiveRewards.lua")
check(
    handlerCount("EveryOneMinute") == 1 and handlerCount("AddXP") == 1,
    "Lua reload keeps one server minute and XP callback"
)
minute(6)
near(player.xp.Axe, 111, "Reload preserves the XP baseline without lost or repeated rewards")

-- Exact paired client sources retain local presentation, but send no health
-- or XP amount request and do not run a second local passive authority.
client, server = true, false
LSSync = {
    isClientOnly = function()
        return true
    end,
}
LSUtil = {
    round = function(value)
        return value
    end,
    addGeneralHealth = function(target, amount)
        if client then
            sendClientCommand()
        else
            target:getBodyDamage():AddGeneralHealth(amount)
        end
    end,
    giveXPBatch = function(target, values)
        if client then
            sendClientCommand()
        else
            for _, value in ipairs(values) do
                addXp(target, Perks[value[1]], value[2])
            end
        end
    end,
    rdm_inst = {
        random = function()
            return 0
        end,
    },
}
LSAmbtMng = {}
player = makePlayer()
online = { player }
player.data.LSMoodles.MindfulState.Value = 0.6
player.data.MindfulnessMinutes = 50
dofile(fixtures .. "client/Inventions/NeuralHat.lua")
local priorClient = clientPackets
LS_NeuralHat.check(player, player.data)
player.xp.Axe = 110
for _ = 1, 6 do
    LS_NeuralHat.check(player, player.data)
end
check(
    baseline and clientPackets > priorClient or not baseline and clientPackets == priorClient,
    baseline and "Original Neural Hat delegates client-calculated XP amounts"
        or "Patched multiplayer Neural Hat submits no XP amount"
)
dofile(fixtures .. "client/ISMeditation/Mindfulness.lua")
priorClient = clientPackets
AdjustPlayerMindfulness(player)
check(
    baseline and clientPackets > priorClient and player.data.MindfulnessMinutes == 49
        or not baseline
            and clientPackets == priorClient
            and player.data.MindfulnessMinutes == 50,
    baseline and "Original mindfulness submits client-calculated health and owns local decay"
        or "Patched multiplayer mindfulness submits no health and does not decay authoritative state"
)
dofile(fixtures .. "client/ISAmbt/LSTerminator.lua")
local before = handlerCount("EveryOneMinute")
LSAmbtMng.LSTerminator(player, { completed = true, isActive = true })
check(
    baseline and handlerCount("EveryOneMinute") == before + 1
        or not baseline and handlerCount("EveryOneMinute") == before,
    baseline and "Original Terminator creates a second client passive authority"
        or "Patched multiplayer Terminator adds no local passive reward callback"
)
-- Test startup in a separate client role with no inherited server callbacks.
Events.EveryOneMinute = event()
Events.AddXP = event()
Events.OnServerCommand = event()
ATFPatches_LifestylePassiveRewards = nil
dofile(module .. "/media/lua/shared/ATFPatches_LifestylePassiveRewards.lua")
check(
    handlerCount("EveryOneMinute") == 0 and handlerCount("AddXP") == 0,
    "Client helper registers no authoritative reward callbacks"
)
fire("OnServerCommand", "LS", "ATF_PassiveData", {
    actorOnlineID = player:getOnlineID(),
    MindfulState = { Value = 0.4 },
    NeuralHat = { Value = 1 },
})
near(
    player.data.LSMoodles.MindfulState.Value,
    0.4,
    "Trusted server passive state updates the existing client moodle"
)
local secondLocal = makePlayer()
getSpecificPlayer = function(index)
    return ({ player, secondLocal })[index + 1]
end
fire("OnServerCommand", "LS", "ATF_PassiveData", {
    actorOnlineID = secondLocal:getOnlineID(),
    MindfulState = { Value = 0.6 },
    NeuralHat = { Value = 1 },
})
check(
    secondLocal.data.LSMoodles.MindfulState.Value == 0.6
        and player.data.LSMoodles.MindfulState.Value == 0.4,
    "Second local actor receives its own passive state without overwriting primary"
)
fire("OnServerCommand", "LS", "ATF_PassiveData", {
    actorOnlineID = player:getOnlineID(),
    MindfulState = { Value = 0.2 },
})
check(
    player.data.LSMoodles.MindfulState.Value == 0.2
        and secondLocal.data.LSMoodles.MindfulState.Value == 0.6,
    "Primary actor state remains separate from second local actor"
)
for _, invalidID in ipairs({ -1, 9999, 0 / 0, 1.5 }) do
    fire(
        "OnServerCommand",
        "LS",
        "ATF_PassiveData",
        { actorOnlineID = invalidID, MindfulState = { Value = 1 } }
    )
    check(
        player.data.LSMoodles.MindfulState.Value == 0.2
            and secondLocal.data.LSMoodles.MindfulState.Value == 0.6,
        "Foreign or invalid actor ID cannot overwrite a local passive state"
    )
end
fire("OnServerCommand", "LS", "ATF_PassiveData", { MindfulState = { Value = 1 } })
check(
    player.data.LSMoodles.MindfulState.Value == 0.2
        and secondLocal.data.LSMoodles.MindfulState.Value == 0.6,
    "Missing actor ID is rejected"
)
local staleID = secondLocal:getOnlineID()
secondLocal.onlineID = staleID + 1000
fire(
    "OnServerCommand",
    "LS",
    "ATF_PassiveData",
    { actorOnlineID = staleID, MindfulState = { Value = 1 } }
)
check(
    secondLocal.data.LSMoodles.MindfulState.Value == 0.6,
    "Stale actor ID cannot update a reconnected local player"
)
secondLocal.dead = true
fire(
    "OnServerCommand",
    "LS",
    "ATF_PassiveData",
    { actorOnlineID = secondLocal:getOnlineID(), MindfulState = { Value = 1 } }
)
check(
    secondLocal.data.LSMoodles.MindfulState.Value == 0.6,
    "Dead local actor does not receive passive state"
)
getSpecificPlayer = nil
if not baseline then
    client, server = false, false
    LSSync.isClientOnly = function()
        return false
    end
    player = makePlayer()
    online = { player }
    player.health = 50
    player.data.LSMoodles.MindfulState.Value = 0.6
    player.data.MindfulnessMinutes = 50
    priorClient = clientPackets
    AdjustPlayerMindfulness(player)
    near(player.health, 58, "Singleplayer retains the original local mindfulness heal")
    check(
        player.data.MindfulnessMinutes == 49 and clientPackets == priorClient,
        "Singleplayer local decay remains without a network request"
    )
    dofile(fixtures .. "client/Inventions/NeuralHat.lua")
    LS_NeuralHat.check(player, player.data)
    player.xp.Axe = 110
    for _ = 1, 6 do
        LS_NeuralHat.check(player, player.data)
    end
    near(player.xp.Axe, 111, "Singleplayer retains the original local Neural Hat XP formula")
    check(clientPackets == priorClient, "Singleplayer XP has no multiplayer packet")
    before = handlerCount("EveryOneMinute")
    LSAmbtMng.LSTerminator(player, { completed = true, isActive = true })
    check(
        handlerCount("EveryOneMinute") == before + 1,
        "Singleplayer retains its original local Terminator callback"
    )
end
print("PASS: " .. checks .. " Lifestyle passive reward authority/progression checks")
