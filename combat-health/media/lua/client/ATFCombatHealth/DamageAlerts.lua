-- Presentation-only rapid damage attention. Each HUD/character owns a fresh state;
-- this module never changes health, saved preferences, or native player state.
ATFCombatHealthDamageAlerts = ATFCombatHealthDamageAlerts or {}
local D = ATFCombatHealthDamageAlerts
local INTERVAL, WINDOW, DURATION, COOLDOWN = 200, 2000, 2000, 5000
local thresholds = { [10] = true, [15] = true, [25] = true, [40] = true }

local function finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function settings(prefs)
    prefs = type(prefs) == "table" and prefs or {}
    local mode = prefs.damageAlertMode
    if mode ~= "flash" and mode ~= "reveal" and mode ~= "off" then
        mode = "flash"
    end
    local threshold = prefs.damageAlertThreshold
    if not thresholds[threshold] then
        threshold = 25
    end
    return mode, threshold
end

function D.new()
    return { samples = {}, view = { reveal = false, glowAlpha = 0 } }
end

function D.clear(state)
    state.samples = {}
    state.lastSample, state.lastHealth, state.startedAt, state.nextAlertAt = nil, nil, nil, nil
    state.mode, state.threshold = nil, nil
    local view = state.view or {}
    view.reveal, view.glowAlpha = false, 0
    state.view = view
end

local function baseline(state, health, now)
    state.samples = { { at = now, health = health } }
    state.lastSample, state.lastHealth = now, health
end

-- Returns true only when a new alert starts. Time is milliseconds, health is the
-- unrounded native 0..100 value. Missing/dead samples must clear an old alert.
function D.update(state, health, now, prefs)
    if not finite(now) or now < 0 or not finite(health) or health <= 0 or health > 100 then
        D.clear(state)
        return false
    end
    local mode, threshold = settings(prefs)
    if state.mode ~= mode or state.threshold ~= threshold then
        D.clear(state)
        state.mode, state.threshold = mode, threshold
    end
    if mode == "off" then
        return false
    end
    if state.lastSample and now < state.lastSample then
        D.clear(state)
        state.mode, state.threshold = mode, threshold
    end
    if not state.lastSample or now - state.lastSample > WINDOW then
        -- A hidden HUD or stalled sample loop cannot date damage across its gap.
        baseline(state, health, now)
        return false
    end
    if now - state.lastSample < INTERVAL then
        return false
    end
    if health > state.lastHealth or now < (state.nextAlertAt or 0) then
        -- Healing resets accumulated loss. Suppressed hits cannot queue another
        -- alert or prolong the existing one; its original expiry stays fixed.
        baseline(state, health, now)
        return false
    end

    local samples, count, highest = state.samples, 0, health
    for i = 1, #samples do
        local sample = samples[i]
        if now - sample.at <= WINDOW then
            count = count + 1
            samples[count] = sample
            highest = math.max(highest, sample.health)
        end
    end
    for i = #samples, count + 1, -1 do
        samples[i] = nil
    end
    samples[count + 1] = { at = now, health = health }
    state.lastSample, state.lastHealth = now, health
    if highest - health + 0.000001 < threshold then
        return false
    end
    state.startedAt, state.nextAlertAt = now, now + COOLDOWN
    baseline(state, health, now)
    return true
end

-- Reuses one tiny result per state, so per-frame presentation allocates nothing.
-- Three complete smooth pulses fit inside the fixed two-second reveal window.
function D.presentation(state, now, prefs)
    local mode = settings(prefs)
    local view = state.view
    view.reveal, view.glowAlpha = false, 0
    if mode == "off" or not finite(now) then
        D.clear(state)
        return view
    end
    local elapsed = state.startedAt and now - state.startedAt
    if not elapsed or elapsed < 0 or elapsed >= DURATION then
        return view
    end
    view.reveal = true
    if mode == "flash" then
        local phase = (elapsed * 3 / DURATION) % 1
        local glow = math.sin(phase * math.pi)
        view.glowAlpha = math.max(0, math.min(1, glow * glow))
    end
    return view
end

return D
