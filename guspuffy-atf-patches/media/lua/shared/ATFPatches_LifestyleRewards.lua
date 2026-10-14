-- Reward values come from server action lifecycles and existing Lifestyle formulas.
ATFPatches_LifestyleRewards = ATFPatches_LifestyleRewards or {}
local Rewards = ATFPatches_LifestyleRewards
local active = Rewards._active or setmetatable({}, { __mode = "k" })
local finished = Rewards._finished or setmetatable({}, { __mode = "k" })
Rewards._active, Rewards._finished = active, finished
local pending = Rewards._pending or {}
Rewards._pending = pending
local capture
local hiddenThresholds = { [0] = 100, 250, 500, 750, 1000, 1250, 1750, 3000, 4000, 9000, 9000 }
local moodNames = {
    "MindfulState",
    "Zen",
    "Dunce",
    "NeuralHat",
    "WasTaughtSkill",
    "PartyGood",
    "PartyBad",
    "Embarrassed",
    "DJAudience",
}

function Rewards.serverRoutesEnabled()
    return isServer() and Rewards._serverEnabled == true
end
function Rewards.enableServerRoutes()
    if not isServer() then
        return false
    end
    Rewards._serverEnabled = true
    HiddenSkills = HiddenSkills or {}
    HiddenSkills.getLevel = Rewards.getHiddenLevel
    HiddenSkills.addXP = Rewards.addHiddenXP
    HiddenSkills.removeXP = function(player, skill, amount)
        Rewards.addHiddenXP(player, skill, -math.abs(amount))
    end
    return true
end

local function finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end
function Rewards.localActor(id)
    if not finite(id) or id < 0 or id % 1 ~= 0 then
        return nil
    end
    local function matches(actor)
        return actor
            and actor.getOnlineID
            and actor:getOnlineID() == id
            and (not actor.isDead or not actor:isDead())
    end
    if type(getSpecificPlayer) == "function" then
        for index = 0, 3 do
            local actor = getSpecificPlayer(index)
            if matches(actor) then
                return actor
            end
        end
        return nil
    end
    local actor = getPlayer and getPlayer()
    return matches(actor) and actor or nil
end
function Rewards.clock()
    local hours = getGameTime():getWorldAgeHours()
    local dayLength = getSandboxOptions():getDayLengthMinutes()
    local real = getTimestampMs()
    local value = Rewards._clock
    if not value then
        value = { hours = hours, dayLength = dayLength, real = real, total = 0, epoch = 0 }
        Rewards._clock = value
    end
    local delta = (hours - value.hours) * 3600 * value.dayLength / 120
    local realDelta = math.max(0, real - value.real) / 1000
    if dayLength ~= value.dayLength or delta < 0 or delta > realDelta * 24 + 2 then
        value.epoch = value.epoch + 1
    else
        value.total = value.total + delta
    end
    value.hours, value.dayLength, value.real = hours, dayLength, real
    return value.total
end
function Rewards.ensureData(player)
    local data = player:getModData()
    data.LSMoodles = data.LSMoodles or {}
    for _, name in ipairs(moodNames) do
        data.LSMoodles[name] = data.LSMoodles[name] or { Value = 0, Level = 0 }
    end
    data.LSHiddenSkills = data.LSHiddenSkills or {}
    data.Ambitions = data.Ambitions or {}
    return data
end
function Rewards.isCapturing(player)
    return capture and capture.player == player
end
function Rewards.recordXP(player, perk, amount)
    if not Rewards.isCapturing(player) then
        return false
    end
    if Perks[perk] and finite(amount) and amount > 0 then
        capture.xp[perk] = (capture.xp[perk] or 0) + amount
    end
    return true
end
function Rewards.syncData(player)
    if not isServer() then
        return
    end
    local data = Rewards.ensureData(player)
    sendServerCommand(player, "LS", "ATF_RewardData", {
        actorOnlineID = player:getOnlineID(),
        LSHiddenSkills = { Yoga = data.LSHiddenSkills.Yoga },
        MindfulState = data.LSMoodles.MindfulState,
        IsMeditating = data.IsMeditating,
        MindfulnessMinutes = data.MindfulnessMinutes,
        MindfulnessLast = data.MindfulnessLast,
    })
end
function Rewards.getHiddenLevel(player, skill)
    local value = Rewards.ensureData(player).LSHiddenSkills[skill]
    return value and value[1] or 0
end
function Rewards.addHiddenXP(player, skill, amount)
    if
        not Rewards.serverRoutesEnabled()
        or not finite(amount)
        or not ({ Yoga = true, Inventing = true, PingPong = true })[skill]
    then
        return
    end
    if Rewards.isCapturing(player) then
        capture.hidden[skill] = (capture.hidden[skill] or 0) + amount
        return
    end
    local data = Rewards.ensureData(player)
    local value = data.LSHiddenSkills[skill] or { 0, 0, 100 }
    data.LSHiddenSkills[skill] = value
    if value[1] >= 10 then
        return
    end
    local total = math.max(0, math.floor(value[2] + amount))
    while value[1] < 10 and total > value[3] do
        total = total - value[3]
        value[1] = value[1] + 1
        value[3] = hiddenThresholds[value[1]]
    end
    value[2] = total
    Rewards.syncData(player)
end
function Rewards.near(player, object)
    local square = object
        and ((object.getSquare and object:getSquare()) or (object.getObjects and object))
    if not square or (object.getObjectIndex and object:getObjectIndex() < 0) then
        return false
    end
    return square:getZ() == math.floor(player:getZ())
        and math.abs(square:getX() - player:getX()) <= 2
        and math.abs(square:getY() - player:getY()) <= 2
        and getCell():getGridSquare(square:getX(), square:getY(), square:getZ()) == square
end
function Rewards.objectName(object, name)
    local sprite = object and object.getSprite and object:getSprite()
    local properties = sprite and sprite:getProperties()
    return properties and properties:has("CustomName") and properties:get("CustomName") == name
end
function Rewards.artwork(object, key)
    local data = object and object:getModData()[key]
    return type(data) == "table"
        and ({ small = true, medium = true, large = true })[data.size]
        and finite(data.level)
        and data.level >= 1
        and data.level <= 10
end
function Rewards.workItems(player, items, style)
    if type(items) ~= "table" then
        return false
    end
    local tools = {
        Hedge = { "Saw" },
        Ice = { "Saw" },
        Wood = { "Hammer", "CarpentryChisel" },
        Stone = { "Hammer", "MasonsChisel" },
        Metal = { "BlowTorch", "Hammer", "WeldingMask" },
    }
    local required = tools[style or "Wood"]
    if not required then
        return false
    end
    for index, name in ipairs(required) do
        local item = items["item" .. index]
        if not Rewards.owns(player, item) or item:getType() ~= name or item:isBroken() then
            return false
        end
    end
    local count = 0
    for index = 1, 3 do
        local item = items["item" .. index]
        if item then
            if not Rewards.owns(player, item) then
                return false
            end
            count = count + 1
        end
    end
    return count > 0
end
function Rewards.hasTool(player, name)
    return player:getInventory():getFirstEvalRecurse(function(item)
        return item:getType() == name and not item:isBroken()
    end) ~= nil
end
function Rewards.hasRequirements(player, requirements)
    if type(requirements) ~= "table" then
        return false
    end
    local entries = 0
    for name, required in pairs(requirements) do
        if
            type(name) ~= "string"
            or not finite(required)
            or required <= 0
            or required ~= math.floor(required)
        then
            return false
        end
        local list = player:getInventory():getItemsFromType(name, true)
        local amount = 0
        for index = 0, list:size() - 1 do
            local item = list:get(index)
            local container = item:getContainer()
            if container and container:isExistYet() and container:isRemoveItemAllowed(item) then
                amount = amount + (item:IsDrainable() and item:getCurrentUses() or 1)
            end
        end
        if amount < required then
            return false
        end
        entries = entries + 1
    end
    return entries > 0
end
local trackCatalog
function Rewards.trackLevel(sound, family)
    trackCatalog = trackCatalog or require("ATFPatches_LifestyleRewardTracks")
    return trackCatalog[sound] and trackCatalog[sound][family]
end
function Rewards.track(action, family)
    trackCatalog = trackCatalog or require("ATFPatches_LifestyleRewardTracks")
    local track = trackCatalog[action.soundFile]
    return track and track[family] and track[family] <= action.character:getPerkLevel(Perks.Music)
end
local instrumentTypes
local function approvedInstruments()
    if instrumentTypes then
        return instrumentTypes
    end
    instrumentTypes = {}
    local names = {
        "Banjo",
        "GuitarElectricBass",
        "GuitarAcoustic",
        "GuitarElectric",
        "Flute",
        "Trumpet",
        "Keytar",
        "Saxophone",
        "Violin",
        "Harmonica",
    }
    for _, name in ipairs(names) do
        instrumentTypes["Base." .. name] = name
    end
    instrumentTypes["Lifestyle.Harmonica"] = "Harmonica"
    -- Expand compatibility once from actual server script definitions, using
    -- the provider menus' suffix/prefix rules, then require an exact full type.
    if getAllItems then
        local scripts = getAllItems()
        for index = 0, scripts:size() - 1 do
            local item = scripts:get(index)
            local full = item and item:getFullName()
            if full then
                for _, name in ipairs(names) do
                    if full:sub(-#name) == name then
                        instrumentTypes[full] = name
                        break
                    end
                end
                for prefix, family in pairs({
                    ["HMW.H_Bass"] = "GuitarElectricBass",
                    ["HMW.H_Acoustic"] = "GuitarAcoustic",
                    ["HMW.H_Electric"] = "GuitarElectric",
                    ["HMW.H_Banjo"] = "Banjo",
                }) do
                    if full:sub(1, #prefix) == prefix then
                        instrumentTypes[full] = family
                    end
                end
            end
        end
    end
    return instrumentTypes
end
local pianoPieces = {
    recreational_01_8 = { "recreational_01_9", "E" },
    recreational_01_9 = { "recreational_01_8", "W" },
    recreational_01_12 = { "recreational_01_13", "N" },
    recreational_01_13 = { "recreational_01_12", "S" },
    recreational_01_28 = { "recreational_01_29", "E" },
    recreational_01_29 = { "recreational_01_28", "W" },
    recreational_01_30 = { "recreational_01_31", "N" },
    recreational_01_31 = { "recreational_01_30", "S" },
    recreational_01_40 = { "recreational_01_41", "E" },
    recreational_01_41 = { "recreational_01_40", "W" },
    recreational_01_48 = { "recreational_01_49", "N" },
    recreational_01_49 = { "recreational_01_48", "S" },
    recreational_01_108 = { "recreational_01_109", "E" },
    recreational_01_109 = { "recreational_01_108", "W" },
    recreational_01_99 = { "recreational_01_96", "N" },
    recreational_01_96 = { "recreational_01_99", "S" },
}
function Rewards.instrument(action)
    if action.obj then
        if action.instrumentType ~= "Piano" or not Rewards.near(action.character, action.obj) then
            return false
        end
        local name = action.obj:getSpriteName() or action.obj:getTextureName()
        local piece = pianoPieces[name]
        if not piece or action.instrument ~= name then
            return false
        end
        local adjacent = action.obj:getSquare():getAdjacentSquare(IsoDirections[piece[2]])
        if not adjacent then
            return false
        end
        local objects = adjacent:getObjects()
        for index = 0, objects:size() - 1 do
            local object = objects:get(index)
            local other = object and (object:getSpriteName() or object:getTextureName())
            if other == piece[1] and Rewards.near(action.character, object) then
                return true
            end
        end
        return false
    end
    return Rewards.owns(action.character, action.instrument)
        and not action.instrument:isBroken()
        and approvedInstruments()[action.instrument:getFullType()] == action.instrumentType
end
function Rewards.cleaningTime(player, kind, bleach)
    local base, skill = 350, 0.07
    if kind == "Unclog" then
        base, skill = 3000, 0.05
    end
    local amount = base
    if bleach then
        local fluid = LSUtil.getFluidContainer(bleach)
        if not fluid then
            return math.huge
        end
        amount = amount * 1.5
        if not fluid:isPureFluid(Fluid.Bleach) then
            local percent = LSUtil.getPercentage(
                fluid:getAmount(),
                fluid:getSpecificFluidAmount(Fluid.Bleach),
                false,
                false
            )
            if not finite(percent) or percent <= 0 then
                return math.huge
            end
            amount = math.ceil(amount + 10000 / percent)
        end
    end
    if LSAmbtMng.hasCompleted(player, "LSGrimeFighter") then
        amount = amount / 2
    end
    local multiplier = 1
    for name, change in pairs({
        CLEANFREAK = 0.5,
        TIDY = -0.2,
        SLOPPY = 0.2,
        ALL_THUMBS = 0.2,
        DEXTROUS = -0.1,
    }) do
        if player:hasTrait(CharacterTrait[name]) then
            multiplier = multiplier + change
        end
    end
    return math.max(
        1,
        math.floor(amount * multiplier - base * player:getPerkLevel(Perks.Cleaning) * skill)
    )
end
function Rewards.yogaValues(level)
    local values = {
        { "Beginner", 50, 1, 2 },
        { "Beginner", 50, 1, 2 },
        { "Beginner", 40, 1, 3 },
        { "Intermediate", 40, 2, 3 },
        { "Intermediate", 30, 2, 4 },
        { "Intermediate", 30, 2, 4 },
        { "Advanced", 30, 3, 6 },
        { "Advanced", 20, 3, 6 },
        { "Advanced", 20, 3, 8 },
        { "Master", 10, 4, 10 },
        { "Master", 0, 4, 10 },
    }
    return values[math.max(0, math.min(10, math.floor(level))) + 1]
end
function Rewards.owns(player, item)
    if not item or not item.getID then
        return false
    end
    return player:getInventory():getFirstEvalRecurse(function(candidate)
        return candidate == item
    end) ~= nil
end
local function alive(player)
    if
        not player
        or player:isDead()
        or player:getVehicle()
        or (player.isAsleep and player:isAsleep())
    then
        return false
    end
    if
        getPlayerByOnlineID
        and player.getOnlineID
        and getPlayerByOnlineID(player:getOnlineID()) ~= player
    then
        return false
    end
    return true
end
function Rewards.calculate(action, callback)
    if capture then
        error("Nested Lifestyle reward calculation")
    end
    local pending = { player = action.character, xp = {}, hidden = {} }
    capture = pending
    local ok, err = pcall(callback, action)
    capture = nil
    if not ok then
        error(err)
    end
    return pending
end
local function award(player, reward)
    local changed = false
    for name, amount in pairs(reward.xp) do
        if
            Perks[name]
            and finite(amount)
            and amount > 0
            and player:getPerkLevel(Perks[name]) < 10
        then
            addXp(player, Perks[name], amount)
            changed = true
        end
    end
    if changed then
        SyncXp(player)
    end
    for name, amount in pairs(reward.hidden) do
        Rewards.addHiddenXP(player, name, amount)
    end
end
Rewards.award = award
local function closeCredits(state, completed)
    local definition = state.definition
    state.target = Rewards.clock()
    state.completed = completed
    if definition.interval and state.target - state.cursor > definition.interval then
        pending[#pending + 1] = state
    elseif completed and definition.completion then
        award(state.action.character, Rewards.calculate(state.action, definition.completion))
    end
end
function Rewards.start(action, definition)
    if not Rewards.serverRoutesEnabled() or not action.netAction or finished[action] then
        return false
    end
    if
        not ATFLifestyleNativeAction
        or not ATFLifestyleNativeAction.ownsAction(action.netAction, action.character)
    then
        return false
    end
    if
        action.player ~= nil
        and not ATFLifestyleNativeAction.ownsAction(action.netAction, action.player)
    then
        return false
    end
    if not alive(action.character) then
        return false
    end
    if active[action.character] then
        return false
    end
    if not LSAmbtMng or not LSAmbtMng.hasCompleted then
        require("ISAmbt/AmbtMng_utils")
    end
    Rewards.ensureData(action.character)
    if definition.validate and not definition.validate(action) then
        return false
    end
    local now = Rewards.clock()
    local state = {
        action = action,
        definition = definition,
        started = now,
        cursor = now,
        last = now,
        epoch = Rewards._clock.epoch,
        resourcesCheckedAt = getTimestampMs(),
    }
    if definition.initialize then
        definition.initialize(action, state)
    end
    active[action.character] = state
    return true
end
local function resourcesValid(state, force)
    if not state.definition.validate then
        return true
    end
    local now = getTimestampMs()
    if
        force
        or not state.resourcesCheckedAt
        or now < state.resourcesCheckedAt
        or now - state.resourcesCheckedAt >= 250
    then
        state.resourcesCheckedAt = now
        return state.definition.validate(state.action)
    end
    return true
end
local function invalidate(state)
    local action = state.action
    state.pendingPose = nil
    active[action.character] = nil
    finished[action] = true
    if state.definition.cancel then
        state.definition.cancel(action, state)
    end
    if state.definition.ended then
        state.definition.ended(action, state)
    end
end
function Rewards.settle(player, forceResources)
    local state = active[player]
    if not Rewards.serverRoutesEnabled() or not state then
        return false
    end
    local action, definition = state.action, state.definition
    if
        not ATFLifestyleNativeAction
        or not ATFLifestyleNativeAction.ownsAction(action.netAction, player)
        or (action.player ~= nil and not ATFLifestyleNativeAction.ownsAction(
            action.netAction,
            action.player
        ))
        or not alive(player)
        or (action.stopOnWalk and player.isPlayerMoving and player:isPlayerMoving())
        or (action.stopOnRun and player.isRunning and player:isRunning())
        or (action.stopOnAim and player:isAiming())
        or not resourcesValid(state, forceResources)
    then
        invalidate(state)
        return false
    end
    local now = Rewards.clock()
    if now < state.last or state.epoch ~= Rewards._clock.epoch then
        invalidate(state)
        return false
    end
    if definition.advance then
        if not resourcesValid(state, true) then
            invalidate(state)
            return false
        end
        definition.advance(action, state, now - state.last)
    end
    state.last = now
    if state.pendingPose and definition.pose and now >= state.nextPose then
        if not resourcesValid(state, true) then
            invalidate(state)
            return false
        end
        local intent = state.pendingPose
        state.pendingPose = nil
        definition.pose(action, state, intent)
    end
    if definition.interval then
        -- Credit only intervals that elapsed on the server. Packet repetition cannot add intervals.
        local processed = 0
        while now - state.cursor > definition.interval and processed < 32 do
            -- Cache only between awards. A lost tool cannot earn one last interval.
            if not resourcesValid(state, true) then
                invalidate(state)
                return false
            end
            state.cursor = state.cursor + definition.interval
            award(player, Rewards.calculate(action, definition.periodic))
            processed = processed + 1
        end
    end
    return true
end
function Rewards.finish(action, completed)
    local state = active[action.character]
    if not state or state.action ~= action or finished[action] then
        return false
    end
    if not Rewards.settle(action.character, true) then
        return false
    end
    state.pendingPose = nil
    active[action.character] = nil
    finished[action] = true
    local elapsed = Rewards.clock() - state.started
    if
        completed
        and (not state.definition.minimum or elapsed >= state.definition.minimum(action, state))
    then
        closeCredits(state, true)
    elseif state.definition.cancel then
        state.definition.cancel(action, state)
    end
    if not completed then
        closeCredits(state, false)
    end
    if state.definition.ended then
        state.definition.ended(action, state)
    end
    return true
end
function Rewards.complete(action, callback)
    if not Rewards.serverRoutesEnabled() then
        return callback(action)
    end
    local state = active[action.character]
    if
        not state
        or state.action ~= action
        or finished[action]
        or not Rewards.settle(action.character, true)
    then
        return false
    end
    local elapsed = Rewards.clock() - state.started
    local minimum = state.definition.minimum and state.definition.minimum(action, state)
    -- Yoga uses a small bounded allowance for native StartAction packet skew.
    -- It cannot complete an unearned pending pose or create extra pose credit.
    local grace = state.definition.completionGrace or 0
    if
        minimum
        and (state.pendingPose or elapsed < minimum - grace)
        and not action.character:isTimedActionInstant()
    then
        Rewards.finish(action, false)
        return false
    end
    -- Close before native resource mutation or reward callbacks. A retry cannot
    -- complete an already consumed operation or claim the same final reward.
    state.pendingPose = nil
    active[action.character] = nil
    finished[action] = true
    local ok, result = pcall(callback, action)
    if ok and result == true then
        closeCredits(state, true)
    end
    if state.definition.ended then
        state.definition.ended(action, state)
    end
    if not ok then
        error(result)
    end
    return result == true
end
function Rewards.pose(player, name)
    if not Rewards.serverRoutesEnabled() then
        return false
    end
    local state = active[player]
    if not state or not state.definition.pose or not Rewards.settle(player, true) then
        return false
    end
    return state.definition.pose(state.action, state, name)
end
function Rewards.context(player)
    return active[player]
end

if Events and Events.OnServerCommand then
    if Rewards._serverCommand then
        Events.OnServerCommand.Remove(Rewards._serverCommand)
    end
    Rewards._serverCommand = function(module, command, args)
        if module ~= "LS" or command ~= "ATF_RewardData" or type(args) ~= "table" then
            return
        end
        local player = Rewards.localActor(args.actorOnlineID)
        if not player then
            return
        end
        local data = Rewards.ensureData(player)
        if type(args.LSHiddenSkills) == "table" and type(args.LSHiddenSkills.Yoga) == "table" then
            data.LSHiddenSkills.Yoga = args.LSHiddenSkills.Yoga
        end
        if type(args.MindfulState) == "table" then
            data.LSMoodles.MindfulState = args.MindfulState
        end
        data.IsMeditating = args.IsMeditating
        data.MindfulnessMinutes = args.MindfulnessMinutes
        data.MindfulnessLast = args.MindfulnessLast
    end
    Events.OnServerCommand.Add(Rewards._serverCommand)
end
if isServer() and Events and Events.OnTick then
    if Rewards._tick then
        Events.OnTick.Remove(Rewards._tick)
    end
    Rewards._tick = function()
        if not Rewards.serverRoutesEnabled() then
            return
        end
        for player in pairs(active) do
            Rewards.settle(player)
        end
        local budget = 32
        for index = #pending, 1, -1 do
            local state = pending[index]
            local player = state.action.character
            if not alive(player) then
                table.remove(pending, index)
            else
                -- These are fixed historical credits authorized before closure.
                -- Completion may already have consumed or changed its resources.
                while state.target - state.cursor > state.definition.interval and budget > 0 do
                    state.cursor = state.cursor + state.definition.interval
                    award(player, Rewards.calculate(state.action, state.definition.periodic))
                    budget = budget - 1
                end
                if state.target - state.cursor <= state.definition.interval then
                    if state.completed and state.definition.completion then
                        award(player, Rewards.calculate(state.action, state.definition.completion))
                    end
                    table.remove(pending, index)
                end
                if budget == 0 then
                    break
                end
            end
        end
    end
    Events.OnTick.Add(Rewards._tick)
end
-- Reloads keep the paired activation, but must replace closures that capture
-- the previous helper's calculation state.
if Rewards.serverRoutesEnabled() then
    Rewards.enableServerRoutes()
end
return Rewards
