-- Passive rewards use accepted native player/item state on the server.
-- The legacy Lifestyle packets never supply an XP or health amount here.
require("ATFPatches_LifestyleRewards")
ATFPatches_LifestylePassiveRewards = ATFPatches_LifestylePassiveRewards or {}
local Passive = ATFPatches_LifestylePassiveRewards
local Rewards = ATFPatches_LifestyleRewards
Passive.players = Passive.players or {}
local players = Passive.players
local function enabled()
    return isServer() and Rewards.serverRoutesEnabled and Rewards.serverRoutesEnabled()
end
local function finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end
local function alive(player)
    return player and instanceof(player, "IsoPlayer") and not player:isDead()
end
local function stateFor(player)
    local state = players[player]
    if not state then
        state = { skills = {} }
        players[player] = state
    end
    return state
end
local function syncData(player)
    local data = Rewards.ensureData(player)
    local actorOnlineID = player:getOnlineID()
    local terminator = data.Ambitions.LSTerminator
    local signature = table.concat({
        tostring(actorOnlineID),
        tostring(data.LSMoodles.MindfulState.Value),
        tostring(data.LSMoodles.Dunce.Value),
        tostring(data.LSMoodles.NeuralHat.Value),
        tostring(data.MindfulnessMinutes),
        tostring(data.MindfulnessLast),
        tostring(type(terminator) == "table" and terminator.isActive),
        tostring(type(terminator) == "table" and terminator.completed),
        tostring(type(terminator) == "table" and terminator.goal1progress),
    }, ":")
    local cache = stateFor(player)
    if cache.signature == signature then
        return
    end
    cache.signature = signature
    sendServerCommand(player, "LS", "ATF_PassiveData", {
        actorOnlineID = actorOnlineID,
        MindfulState = data.LSMoodles.MindfulState,
        Dunce = data.LSMoodles.Dunce,
        NeuralHat = data.LSMoodles.NeuralHat,
        MindfulnessMinutes = data.MindfulnessMinutes,
        MindfulnessLast = data.MindfulnessLast,
        Terminator = data.Ambitions.LSTerminator,
    })
end
if Passive.clientHandler then
    Events.OnServerCommand.Remove(Passive.clientHandler)
end
Passive.clientHandler = function(module, command, args)
    if module ~= "LS" or command ~= "ATF_PassiveData" or type(args) ~= "table" then
        return
    end
    local player = Rewards.localActor(args.actorOnlineID)
    if not player then
        return
    end
    local data = Rewards.ensureData(player)
    for _, name in ipairs({ "MindfulState", "Dunce", "NeuralHat" }) do
        if type(args[name]) == "table" and finite(args[name].Value) then
            data.LSMoodles[name].Value = args[name].Value
        end
    end
    if args.MindfulnessMinutes == false or finite(args.MindfulnessMinutes) then
        data.MindfulnessMinutes = args.MindfulnessMinutes
    end
    if finite(args.MindfulnessLast) then
        data.MindfulnessLast = args.MindfulnessLast
    end
    if type(args.Terminator) == "table" and args.Terminator.name == "LSTerminator" then
        local previous = data.Ambitions.LSTerminator
        data.Ambitions.LSTerminator = args.Terminator
        if
            args.Terminator.completed
            and (not previous or not previous.completed)
            and LSAmbtMng
            and LSAmbtMng.doComplete
        then
            LSAmbtMng.doComplete(player, args.Terminator)
        end
    end
end
if isClient() and not isServer() then
    Events.OnServerCommand.Add(Passive.clientHandler)
end
if not isServer() then
    return
end

local function neural(player)
    local hat = ItemBodyLocation and player:getWornItems():getItem(ItemBodyLocation.HAT)
    if
        not hat
        or hat:getType() ~= "NeuralHat"
        or hat:isBroken()
        or not player:getInventory():getFirstEvalRecurse(function(item)
            return item == hat
        end)
    then
        return
    end
    local data = hat:getModData()
    local movable = data and data.movableData
    local inv = type(movable) == "table" and movable.inventionData
    local state = hat:getVisual():getTextureChoice()
    if
        type(inv) ~= "table"
        or inv.enabled ~= true
        or inv.isBroken
        or not finite(inv.fuelUses)
        or inv.fuelUses <= 0
        or not finite(state)
        or state % 1 ~= 0
        or state < 1
        or state > 5
    then
        return
    end
    if state >= 3 then
        local overdrive = inv.overdrive
        if
            type(overdrive) ~= "table"
            or not finite(overdrive[1])
            or overdrive[1] % 1 ~= 0
            or overdrive[1] < state - 2
            or overdrive[1] > 3
        then
            return
        end
    end
    local efficiency = inv.efficiencyMult
    if
        type(efficiency) ~= "table"
        or not finite(efficiency[1])
        or efficiency[1] < 0
        or efficiency[1] > 1
        or not finite(efficiency[3])
        or efficiency[3] < 0
        or efficiency[3] > 0.5
    then
        return
    end
    return state, inv
end
local function eligible(player, perk)
    local parent = perk and perk:getParent()
    return parent and parent:getId() ~= "None" and player:getPerkLevel(perk) < 10
end
local function adjustXP(player, perk, amount, state)
    if not finite(amount) or amount == 0 then
        return
    end
    state.applying = true
    local ok, err = pcall(function()
        if amount > 0 then
            addXp(player, perk, amount)
        else
            addXpNoMultiplier(player, perk, amount)
        end
        SyncXp(player)
    end)
    state.applying = false
    if not ok then
        error(err, 0)
    end
end
local function neuralMinute(player, data, cache)
    local mode, inv = neural(player)
    if not finite(data.ATFLegacyDunce) then
        -- Retain the trusted persisted penalty at first activation/reconnect.
        local existing = data.LSMoodles.Dunce.Value
        data.ATFLegacyDunce = finite(existing) and math.max(0, math.min(1, existing)) or 0
    end
    local dunce = math.max(data.ATFLegacyDunce, mode == 2 and 1 or 0)
    data.LSMoodles.Dunce.Value = dunce
    if not mode and (not finite(dunce) or dunce <= 0) then
        data.LSMoodles.NeuralHat.Value = 0
        cache.skills = {}
        cache.delay = 0
        return
    end
    local bad = finite(dunce) and dunce > 0
    data.LSMoodles.NeuralHat.Value = bad and 0 or 1
    if not bad then
        data.LSMoodles.Dunce.Value = 0
    end
    if cache.delay and cache.delay > 0 then
        cache.delay = cache.delay - 1
        return
    end
    cache.delay = 5
    local xp = player:getXp()
    for i = 1, Perks.getMaxIndex() - 1 do
        local perk = Perks.fromIndex(i)
        if eligible(player, perk) then
            local name, current = perk:getId(), xp:getXP(perk)
            if finite(current) and current > 0 then
                local previous = cache.skills[name]
                local level = player:getPerkLevel(perk)
                if
                    previous
                    and previous.level == level
                    and finite(previous.xp)
                    and current > previous.xp
                then
                    local difference = current - previous.xp
                    local amount
                    if bad then
                        if previous.xp > 0 then
                            amount = -difference * math.min(0.8, dunce)
                        end
                    else
                        amount = difference * inv.efficiencyMult[1] * mode + (previous.residue or 0)
                        previous.round = (previous.round or 0) + 1
                        if amount >= 1 or previous.round >= 2 then
                            if ZombRand(3) == 1 then
                                amount = amount + amount * inv.efficiencyMult[3]
                            end
                            previous.residue, previous.round = 0, 0
                        else
                            previous.residue = amount
                            amount = nil
                        end
                    end
                    if amount then
                        adjustXP(player, perk, amount, cache)
                    end
                end
                previous = previous or { residue = 0, round = 0 }
                -- Read actual post-award XP, including native multipliers.
                -- Our bonus cannot become another earning on the next poll.
                previous.xp = xp:getXP(perk)
                previous.level = player:getPerkLevel(perk)
                cache.skills[name] = previous
            else
                cache.skills[perk:getId()] = nil
            end
        end
    end
end
local duration = {
    [3] = { 10, 20 },
    [4] = { 14, 28 },
    [5] = { 20, 40 },
    [6] = { 30, 60 },
    [7] = { 60, 90 },
    [8] = { 90, 120 },
    [9] = { 120, 180 },
    [10] = { 180, 260 },
}
local function mindfulMinute(player, data)
    if
        not SandboxVars.Text
        or not SandboxVars.Text.DividerMeditationNew
        or not Perks.Meditation
    then
        return false
    end
    local value, minutes = data.LSMoodles.MindfulState.Value, data.MindfulnessMinutes
    if not finite(value) or (value <= 0 and (not finite(minutes) or minutes <= 0)) then
        return false
    end
    local level = player:getPerkLevel(Perks.Meditation)
    if level < 3 then
        data.LSMoodles.MindfulState.Value = 0
        return false
    end
    local disciplined = player:hasTrait(CharacterTrait.DISCIPLINED)
    local meditation = SandboxVars.Meditation or {}
    local options = meditation.MindfulnessDuration or 2
    local scale = options == 1 and 0.5 or options == 3 and 2 or 1
    local total = (duration[level] and duration[level][disciplined and 2 or 1] or 5) * scale
    local healed = false
    if value >= 0.6 then
        local amount = meditation.HealFactor or 2
        if finite(amount) and amount >= 0 and amount <= 10 then
            if level == 10 then
                amount = amount * (disciplined and 6 or 4)
            end
            if amount > 0 then
                player:getBodyDamage():AddGeneralHealth(amount)
                healed = true
            end
        end
    end
    if data.IsMeditating == true then
        data.MindfulnessMinutes = false
        return healed
    end
    if not finite(minutes) then
        data.MindfulnessMinutes = total
        return healed
    end
    if minutes <= 0 then
        value = math.max(0, math.floor((value - 0.2) * 10 + 0.5) / 10)
        if value < 0.2 then
            value = 0
        end
        data.LSMoodles.MindfulState.Value = value
        minutes = value > 0 and total or 0
        data.MindfulnessLast = value
    elseif value <= 0 and finite(data.MindfulnessLast) then
        data.LSMoodles.MindfulState.Value = data.MindfulnessLast
    end
    data.MindfulnessMinutes = math.max(0, minutes - 1)
    return healed
end
local function terminatorRecord()
    return {
        name = "LSTerminator",
        cat = "Combat",
        texture = "LSTerminator",
        goal1 = 5000,
        goal2 = "pain",
        goal3 = 0,
        goal4 = 0,
        goal5 = 0,
        goal6 = 0,
        isHidden = false,
        isPassive = false,
        disable = false,
        resetF = false,
        completed = false,
        isActive = false,
    }
end
function Passive.selectAmbition(player, name, active)
    if
        not enabled()
        or not alive(player)
        or name ~= "LSTerminator"
        or type(active) ~= "boolean"
        or not SandboxVars.LSAmbt
        or not SandboxVars.LSAmbt.Toggle
    then
        return false
    end
    local data = Rewards.ensureData(player)
    local record = data.Ambitions.LSTerminator
    if type(record) ~= "table" then
        record = terminatorRecord()
        data.Ambitions.LSTerminator = record
    end
    if record.disable then
        return false
    end
    if active and not record.isActive then
        local inProgress, total = 0, 0
        for _, ambition in pairs(data.Ambitions) do
            if type(ambition) == "table" and ambition.isActive and not ambition.disable then
                total = total + 1
                if not ambition.completed then
                    inProgress = inProgress + 1
                end
            end
        end
        local maxProgress = SandboxVars.LSAmbt.MaxInProgress or 1
        local maxTotal = math.max(maxProgress, SandboxVars.LSAmbt.MaxTotal or 3)
        if total >= maxTotal or (not record.completed and inProgress >= maxProgress) then
            return false
        end
        if not record.completed then
            record.ogKills = player:getZombieKills()
            record.goal1, record.goal1progress, record.goal2progress, record.reset =
                5000, 0, true, true
        end
    elseif not active and not record.completed then
        record = terminatorRecord()
        data.Ambitions.LSTerminator = record
    end
    record.isActive = active
    syncData(player)
    return true
end
local function setEndurance(player, value)
    player:getStats():set(CharacterStat.ENDURANCE, math.max(0, math.min(1, value)))
    sendPlayerStat(player, CharacterStat.ENDURANCE)
end
local function terminatorMinute(player, data)
    local ambt = data.Ambitions.LSTerminator
    if
        not SandboxVars.LSAmbt
        or not SandboxVars.LSAmbt.Toggle
        or type(ambt) ~= "table"
        or ambt.disable
    then
        return false
    end
    if not ambt.completed then
        if not ambt.isActive or player:isAsleep() then
            return false
        end
        if not finite(ambt.ogKills) then
            ambt.ogKills = player:getZombieKills()
        end
        local kills = player:getZombieKills()
        if kills < ambt.ogKills then
            ambt.ogKills = kills
        end
        ambt.goal1, ambt.goal1progress, ambt.goal2progress, ambt.reset =
            5000, math.floor(kills - ambt.ogKills), true, true
        if player:getStats():get(CharacterStat.ENDURANCE) > 0.35 then
            setEndurance(player, 0.35)
        end
        if ambt.goal1progress >= 5000 then
            ambt.completed, ambt.reset, ambt.isHidden = true, false, false
        end
        return false
    end
    local changed = false
    local body, gain = player:getBodyDamage(), 0.05
    local parts = body:getBodyParts()
    for i = 0, parts:size() - 1 do
        local part = parts:get(i)
        if part:bleeding() and not part:IsBleedingStemmed() then
            if part:getType() == BodyPartType.Neck then
                gain = gain * 5
            end
            part:AddHealth(gain)
            changed = true
        end
    end
    if not finite(ambt.ogFireKR) then
        ambt.ogFireKR = player:getFireKillRate()
    end
    if ambt.isActive then
        local roll = ZombRand(20) + 1
        local endurance = player:getStats():get(CharacterStat.ENDURANCE)
        if finite(ambt.ogEnd) and endurance ~= ambt.ogEnd then
            endurance = math.min(1, endurance + math.abs(endurance - ambt.ogEnd) * 0.2)
            setEndurance(player, endurance)
        end
        ambt.ogEnd = endurance
        local health = player:getHealth()
        if finite(ambt.ogHth) and health < ambt.ogHth and roll > 18 then
            body:AddGeneralHealth(ambt.ogHth - health)
            changed = true
        end
        ambt.ogHth = player:getHealth()
        player:setFireKillRate(ambt.ogFireKR / 3)
        if player:isOnFire() and roll > 16 then
            player:StopBurning()
        end
    else
        player:setFireKillRate(ambt.ogFireKR)
    end
    return changed
end
if Passive.xpHandler then
    Events.AddXP.Remove(Passive.xpHandler)
end
Passive.xpHandler = function(player, perk, amount)
    if
        not enabled()
        or not alive(player)
        or not eligible(player, perk)
        or not finite(amount)
        or amount <= 0
    then
        return
    end
    local mode = neural(player)
    if not mode then
        return
    end
    local cache = stateFor(player)
    if cache.applying then
        return
    end
    local name, current = perk:getId(), player:getXp():getXP(perk)
    if finite(current) and not cache.skills[name] then
        cache.skills[name] = {
            xp = math.max(0, current - amount),
            level = player:getPerkLevel(perk),
            residue = 0,
            round = 0,
        }
    end
end
Events.AddXP.Add(Passive.xpHandler)
if Passive.minuteHandler then
    Events.EveryOneMinute.Remove(Passive.minuteHandler)
end
Passive.minuteHandler = function()
    if not enabled() or not Perks.Meditation then
        return
    end
    local online, seen = getOnlinePlayers(), {}
    if not online then
        return
    end
    for i = 0, online:size() - 1 do
        local player = online:get(i)
        if alive(player) then
            seen[player] = true
            Rewards.settle(player)
            local data, cache = Rewards.ensureData(player), stateFor(player)
            neuralMinute(player, data, cache)
            local changed = mindfulMinute(player, data)
            if terminatorMinute(player, data) then
                changed = true
            end
            if changed then
                sendDamage(player)
            end
            syncData(player)
        end
    end
    for player in pairs(players) do
        if not seen[player] then
            players[player] = nil
        end
    end
end
Events.EveryOneMinute.Add(Passive.minuteHandler)
