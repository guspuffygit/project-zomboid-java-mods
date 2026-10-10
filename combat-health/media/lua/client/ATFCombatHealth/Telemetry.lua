-- Ordinary local-player information only. Native XP totals are sampled at 1 Hz:
-- B42 multiplayer clients do not receive the native AddXP Lua event on XP sync.
ATFPlayerMiniHUDTelemetry = ATFPlayerMiniHUDTelemetry or {}
local T = ATFPlayerMiniHUDTelemetry
T.states = T.states or {}
T.maxPerks, T.maxRemembered, T.maxRows = 256, 12, 3
T.xpInterval, T.temperatureInterval, T.expiry = 1000, 500, 30000

local function text(key, fallback)
    return getTextOrNull(key) or fallback
end

local function currentPlayer(player)
    return player
        and player.isLocalPlayer
        and player.isDead
        and player.getPlayerNum
        and player:isLocalPlayer()
        and not player:isDead()
        and getSpecificPlayer(player:getPlayerNum()) == player
end

local function number(value)
    value = tonumber(value)
    if value and value == value and value > -math.huge and value < math.huge then
        return value
    end
end

local function perkId(perk)
    if not perk then
        return nil
    end
    local id = perk.getId and perk:getId()
    if id == nil then
        id = perk:getType()
    end
    return "perk:" .. tostring(id)
end

local function cachePerks(state)
    state.perks, state.perkById = {}, {}
    local list = PerkFactory and PerkFactory.PerkList
    if not list then
        return
    end
    for i = 0, list:size() - 1 do
        if #state.perks >= T.maxPerks then
            break
        end
        local perk = list:get(i)
        if perk and perk:getParent() ~= Perks.None then
            local id = perkId(perk)
            if not state.perkById[id] then
                local entry = { id = id, perk = perk, name = perk:getName() }
                state.perks[#state.perks + 1] = entry
                state.perkById[id] = entry
            end
        end
    end
end

local function amountText(amount)
    local display = math.floor(amount * 100 + 0.5) / 100
    return "+" .. string.format("%g", display) .. " " .. text("IGUI_XP_xp", "XP")
end

local function sameRows(first, second)
    if #first ~= #second then
        return false
    end
    for i, row in ipairs(first) do
        local other = second[i]
        if
            row.id ~= other.id
            or row.name ~= other.name
            or row.amount ~= other.amount
            or row.text ~= other.text
        then
            return false
        end
    end
    return true
end

local function rebuildRows(state, now)
    local active = {}
    for id, entry in pairs(state.entries) do
        if now - entry.lastGain >= T.expiry then
            state.entries[id] = nil
        else
            active[#active + 1] = entry
        end
    end
    table.sort(active, function(a, b)
        return a.sequence > b.sequence
    end)
    state.nextExpiry = nil
    for i, entry in ipairs(active) do
        if i > T.maxRemembered then
            state.entries[entry.id] = nil
        else
            local expiry = entry.lastGain + T.expiry
            state.nextExpiry = state.nextExpiry and math.min(state.nextExpiry, expiry) or expiry
        end
    end
    local rows = {}
    for i = 1, math.min(T.maxRows, #active) do
        local entry = active[i]
        rows[i] = {
            id = entry.id,
            name = entry.name,
            amount = entry.amount,
            text = entry.name .. " " .. amountText(entry.amount),
        }
    end
    if not sameRows(state.xpRows, rows) then
        state.xpRows = rows
        state.dirty = true
    end
end

local function gain(state, id, name, amount, now)
    if not amount or amount <= 0 then
        return
    end
    local entry = state.entries[id]
    if not entry or now - entry.lastGain >= T.expiry then
        entry = { id = id, name = name, amount = 0 }
        state.entries[id] = entry
    end
    state.sequence = state.sequence + 1
    entry.name, entry.amount = name, entry.amount + amount
    entry.lastGain, entry.sequence = now, state.sequence
    rebuildRows(state, now)
end

local function readXP(state, entry, now, baseline)
    state.scanReads = state.scanReads + 1
    local total = number(state.player:getXp():getXP(entry.perk:getType()))
    if not total then
        state.totals[entry.id] = nil
        return
    end
    total = math.max(0, total)
    local previous = state.totals[entry.id]
    state.totals[entry.id] = total
    if not baseline and previous and total > previous then
        gain(state, entry.id, entry.name, total - previous, now)
    end
end

local function scanXP(state, now, baseline)
    state.polls = state.polls + 1
    for _, entry in ipairs(state.perks) do
        readXP(state, entry, now, baseline)
    end
    state.lastScan = now
end

local function resetXP(state)
    state.entries, state.totals, state.xpRows = {}, {}, {}
    state.sequence, state.nextExpiry, state.lastScan = 0, nil, nil
end

function T.new(player)
    if not currentPlayer(player) then
        return nil
    end
    local num = player:getPlayerNum()
    if T.states[num] then
        T.clear(T.states[num])
    end
    local state = {
        player = player,
        playerNum = num,
        xpRows = {},
        temperature = nil,
        showXP = false,
        showTemperature = false,
        scanReads = 0,
        polls = 0,
        dirty = false,
    }
    resetXP(state)
    T.states[num] = state
    return state
end

function T.clear(state)
    if not state then
        return
    end
    if T.states[state.playerNum] == state then
        T.states[state.playerNum] = nil
    end
    state.player, state.perks, state.perkById = nil, nil, nil
    state.temperature, state.lastTemperature, state.yogaDepth = nil, nil, nil
    state.showXP, state.showTemperature, state.dirty = false, false, false
    resetXP(state)
end

local function sampleTemperature(player)
    if not player.getMoodles then
        return nil
    end
    local moodles = player:getMoodles()
    if
        not moodles
        or not moodles.getMoodleLevel
        or not MoodleType
        or not MoodleType.HYPOTHERMIA
        or not MoodleType.HYPERTHERMIA
    then
        return nil
    end
    local cold = number(moodles:getMoodleLevel(MoodleType.HYPOTHERMIA))
    local hot = number(moodles:getMoodleLevel(MoodleType.HYPERTHERMIA))
    if
        not cold
        or not hot
        or cold < 0
        or hot < 0
        or cold > 4
        or hot > 4
        or cold ~= math.floor(cold)
        or hot ~= math.floor(hot)
    then
        return nil
    end
    -- These are presentation groups of visible vanilla moodles, not invented
    -- Celsius thresholds. Native Clothing UI hides raw core numbers outside debug.
    local key, label, kind = "normal", text("IGUI_Temp_Normal", "Normal"), nil
    if cold >= 2 then
        key, label, kind = "cold", text("IGUI_Temp_Cold", "Cold"), MoodleType.HYPOTHERMIA
    elseif cold == 1 then
        key, label, kind = "cool", text("UI_ATFCombatHealth_Cool", "Cool"), MoodleType.HYPOTHERMIA
    elseif hot >= 2 then
        key, label, kind = "hot", text("IGUI_Temp_Hot", "Hot"), MoodleType.HYPERTHERMIA
    elseif hot == 1 then
        key, label, kind = "warm", text("UI_ATFCombatHealth_Warm", "Warm"), MoodleType.HYPERTHERMIA
    end
    local tooltip = kind and moodles.getMoodleDisplayString and moodles:getMoodleDisplayString(kind)
        or label
    return { key = key, text = label, tooltip = tooltip }
end

local function sameTemperature(first, second)
    if not first or not second then
        return first == second
    end
    return first.key == second.key and first.text == second.text and first.tooltip == second.tooltip
end

function T.update(state, now, showXP, showTemperature)
    if not state then
        return false
    end
    if not currentPlayer(state.player) then
        local changed = state.player ~= nil or #state.xpRows > 0 or state.temperature ~= nil
        T.clear(state)
        return changed
    end
    now = now or getTimestampMs()
    showXP, showTemperature = not not showXP, not not showTemperature
    local changed = state.dirty
    state.dirty = false
    if state.showXP ~= showXP then
        state.showXP = showXP
        resetXP(state)
        changed = true
        if showXP then
            if not state.perks then
                cachePerks(state)
            end
            scanXP(state, now, true)
        end
    elseif showXP and now - state.lastScan >= T.xpInterval then
        scanXP(state, now, false)
    end
    if showXP and state.nextExpiry and now >= state.nextExpiry then
        rebuildRows(state, now)
    end
    if state.showTemperature ~= showTemperature then
        state.showTemperature, state.lastTemperature = showTemperature, nil
        changed = true
    end
    if
        showTemperature
        and (not state.lastTemperature or now - state.lastTemperature >= T.temperatureInterval)
    then
        local value = sampleTemperature(state.player)
        if not sameTemperature(state.temperature, value) then
            state.temperature, changed = value, true
        end
        state.lastTemperature = now
    elseif not showTemperature and state.temperature then
        state.temperature, changed = nil, true
    end
    changed = changed or state.dirty
    state.dirty = false
    return not not changed
end

function T.onXP(state, player, perk, amount, now)
    -- The event's requested/modified amount is only a hint. Reading the same
    -- baseline used by polling prevents multipliers and duplicate events adding XP.
    if not state or not state.showXP or state.player ~= player or not currentPlayer(player) then
        return false
    end
    local entry = state.perkById and state.perkById[perkId(perk)]
    if not entry then
        return false
    end
    readXP(state, entry, now or getTimestampMs(), false)
    return state.dirty == true
end

-- Installed Lifestyle HSMng uses these level thresholds. At level 10 it retains
-- the previous table's XP, so that field must not be added to mastered total XP.
local yogaThresholds = { 100, 250, 500, 750, 1000, 1250, 1750, 3000, 4000, 9000 }
local function yogaTotal(player)
    local values = player:getModData().LSHiddenSkills
    values = values and values.Yoga
    if not values then
        return 0
    end
    local level = math.max(0, math.min(10, math.floor(number(values[1]) or 0)))
    local total = 0
    for i = 1, level do
        total = total + yogaThresholds[i]
    end
    if level < 10 then
        total = total + math.max(0, number(values[2]) or 0)
    end
    return total
end

local function pack(...)
    return { n = select("#", ...), ... }
end
function T.installYoga()
    local skills = HiddenSkills
    if not skills or type(skills.addXP) ~= "function" then
        return false
    end
    if T.yogaHookTable == skills and T.yogaHookFunction == skills.addXP then
        return true
    end
    local original = skills.addXP
    local function yogaXP(player, skill, amount, ...)
        local state = player and player.getPlayerNum and T.states[player:getPlayerNum()]
        if
            skill ~= "Yoga"
            or not state
            or not state.showXP
            or state.player ~= player
            or not currentPlayer(player)
            or (state.yogaDepth or 0) > 0
        then
            return original(player, skill, amount, ...)
        end
        -- Copy the cumulative value before the callback mutates/replaces tables.
        local previous = yogaTotal(player)
        state.yogaDepth = 1
        local result = pack(pcall(original, player, skill, amount, ...))
        state.yogaDepth = nil
        if not result[1] then
            error(result[2])
        end
        if state.showXP and state.player == player and currentPlayer(player) then
            gain(
                state,
                "hidden:Yoga",
                text("UI_LSHS_Yoga", text("IGUI_perks_Yoga", "Yoga")),
                yogaTotal(player) - previous,
                getTimestampMs()
            )
        end
        return unpack(result, 2, result.n)
    end
    skills.addXP = yogaXP
    T.yogaHookTable = skills
    T.yogaHookFunction = skills.addXP
    return true
end

return T
