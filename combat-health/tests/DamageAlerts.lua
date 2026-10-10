local root = arg[1] or arg[0]:match("^(.*)[/\\]tests[/\\][^/\\]+$") or "."
local path = root .. "/media/lua/client/ATFCombatHealth/DamageAlerts.lua"
local D
if readTestSource then
    D = assert(loadstring(readTestSource(path), "@" .. path))()
else
    D = dofile(path)
end
local checks = 0
local function check(value, why)
    assert(value, why)
    checks = checks + 1
end
local function near(first, second)
    return math.abs(first - second) < 0.000001
end
local prefs = { damageAlertMode = "flash", damageAlertThreshold = 25, focusFade = true }
local function active(state, now, options)
    return D.presentation(state, now, options or prefs)
end

local state = D.new()
check(not D.update(state, 75, 0, prefs), "first sample is a baseline, not damage")
check(not active(state, 0).reveal, "baseline has no attention")
check(D.update(state, 50, 200, prefs), "exact single 25-point loss alerts")
check(active(state, 200).reveal, "alert immediately reveals the faded HUD")
check(near(active(state, 200 + 2000 / 6).glowAlpha, 1), "first glow reaches full alpha")
check(near(active(state, 1200).glowAlpha, 1), "second glow reaches full alpha")
check(near(active(state, 200 + 2000 * 5 / 6).glowAlpha, 1), "third glow reaches full alpha")
check(
    active(state, 2199).reveal and not active(state, 2200).reveal,
    "attention ends exactly after two seconds"
)
local rising, lit = 0, false
for now = 200, 2200, 10 do
    local view = active(state, now)
    check(view.glowAlpha >= 0 and view.glowAlpha <= 1, "glow alpha stays bounded")
    local current = view.glowAlpha > 0.5
    if current and not lit then
        rising = rising + 1
    end
    lit = current
end
check(rising == 3, "one alert produces exactly three separate glows")
check(
    prefs.focusFade == true and prefs.damageAlertMode == "flash",
    "alert never mutates saved preferences"
)
check(
    active(state, 300) == active(state, 301),
    "presentation result is reused without per-frame allocations"
)

state = D.new()
D.update(state, 100, 0, prefs)
for i = 1, 4 do
    check(
        not D.update(state, 100 - i * 5, i * 200, prefs),
        "partial rapid loss stays below threshold"
    )
end
check(D.update(state, 75, 1000, prefs), "five rapid hits accumulate within the window")
local started, cooldown = state.startedAt, state.nextAlertAt
check(not D.update(state, 45, 1200, prefs), "large hit during an active alert does not restart it")
check(
    state.startedAt == started and state.nextAlertAt == cooldown,
    "repeated damage cannot extend pulse or cooldown"
)
check(not D.update(state, 15, 1400, prefs), "further active hits remain suppressed")
for now = 1600, 6000, 200 do
    check(not D.update(state, 15, now, prefs), "old suppressed damage never replays after cooldown")
end
check(not active(state, 6000).reveal, "continued sampling cannot blink forever")
D.update(state, 100, 6200, prefs)
check(D.update(state, 75, 6400, prefs), "fresh rapid damage after cooldown can alert again")

state = D.new()
D.update(state, 100, 0, prefs)
for i = 1, 600 do
    check(
        not D.update(state, 100 - i * 0.1, i * 200, prefs),
        "slow 0.1-point ticks never trigger rapid damage"
    )
    check(#state.samples <= 11, "sample history remains bounded to eleven entries")
end
check(not active(state, 120000).reveal, "large lifetime damage alone is not a rapid-damage alert")

state = D.new()
D.update(state, 100, 0, prefs)
D.update(state, 85, 200, prefs)
D.update(state, 95, 400, prefs)
check(not D.update(state, 80, 600, prefs), "healing clears earlier accumulated damage")
check(D.update(state, 70, 800, prefs), "damage after healing uses the recovered baseline")
D.update(state, 100, 1000, prefs)
check(active(state, 1200).reveal, "healing does not prematurely cancel an already bounded alert")

state = D.new()
D.update(state, 100, 0, prefs)
for now = 200, 1800, 200 do
    D.update(state, 100, now, prefs)
end
check(D.update(state, 75, 2000, prefs), "damage at the two-second window edge is included")
state = D.new()
D.update(state, 100, 0, prefs)
check(not D.update(state, 60, 2200, prefs), "long sampling gaps establish a fresh baseline")
check(D.update(state, 35, 2400, prefs), "fresh loss after a gap is still detected")

state = D.new()
D.update(state, 100, 0, prefs)
check(
    not D.update(state, 75, 100, prefs),
    "samples closer than 200ms do not bypass the bounded sampling path"
)
check(
    D.update(state, 75, 200, prefs),
    "ignored intermediate sample does not hide a lasting health loss"
)
check(
    not D.update(state, 50, 100, prefs),
    "backward clock clears history and establishes a new baseline"
)
check(not active(state, 100).reveal, "clock reversal cannot retain an old pulse")

local reveal = { damageAlertMode = "reveal", damageAlertThreshold = 10 }
state = D.new()
D.update(state, 100, 0, reveal)
check(D.update(state, 90, 200, reveal), "configured ten-point threshold is honored")
check(
    active(state, 500, reveal).reveal and active(state, 500, reveal).glowAlpha == 0,
    "reveal mode never flashes"
)
local off = { damageAlertMode = "off", damageAlertThreshold = 25 }
check(not active(state, 500, off).reveal, "off immediately clears active attention")
check(not D.update(state, 25, 600, off), "off cannot start attention even for a large hit")
check(not D.update(state, 25, 800, prefs), "re-enabling uses a new baseline")
check(not active(state, 800).reveal, "off-to-on cannot resurrect old attention")

state = D.new()
D.update(state, 100, 0, prefs)
D.update(state, 80, 200, prefs)
check(
    not D.update(state, 79.9, 400, reveal),
    "lowering the threshold cannot turn a tiny tick into a retroactive alert"
)
check(
    not active(state, 400, reveal).reveal,
    "preference changes establish a fresh detection baseline"
)
for _, now in ipairs({ -1, math.huge, 0 / 0, "600" }) do
    state = D.new()
    D.update(state, 100, 0, prefs)
    D.update(state, 75, 200, prefs)
    check(
        not D.update(state, 50, now, prefs),
        "invalid timestamps cannot start or extend attention"
    )
    check(not active(state, 300).reveal, "invalid timestamps clear existing attention")
end

state = D.new()
D.update(state, 100, 0)
check(D.update(state, 75, 200), "missing preferences use flash and25-point defaults")
check(active(state, 500).reveal, "default preferences produce temporary attention")

for _, threshold in ipairs({ 15, 40 }) do
    local custom = { damageAlertMode = "flash", damageAlertThreshold = threshold }
    state = D.new()
    D.update(state, 100, 0, custom)
    check(
        D.update(state, 100 - threshold, 200, custom),
        "supported custom threshold triggers at its exact boundary"
    )
end
local invalid = { damageAlertMode = "always", damageAlertThreshold = 0, focusFade = false }
state = D.new()
D.update(state, 100, 0, invalid)
check(
    not D.update(state, 90, 200, invalid),
    "invalid threshold defaults to 25 rather than hypersensitive alerts"
)
check(D.update(state, 75, 400, invalid), "invalid mode safely falls back to the default")
check(
    active(state, 733, invalid).glowAlpha > 0.9,
    "invalid mode produces the documented flash default"
)
check(
    invalid.damageAlertMode == "always"
        and invalid.damageAlertThreshold == 0
        and not invalid.focusFade,
    "normalization does not rewrite user preferences"
)

for _, health in ipairs({ 0, -1, 101, math.huge, 0 / 0, "75" }) do
    state = D.new()
    D.update(state, 100, 0, prefs)
    D.update(state, 75, 200, prefs)
    check(not D.update(state, health, 300, prefs), "dead or invalid health cannot alert")
    check(
        not active(state, 300).reveal and #state.samples == 0,
        "dead or invalid sample clears alert and history immediately"
    )
end
state = D.new()
D.update(state, 100, 0, prefs)
D.update(state, 75, 200, prefs)
check(
    not D.update(state, nil, 300, prefs) and not active(state, 300).reveal,
    "missing character sample clears attention"
)
D.update(state, 100, 400, prefs)
check(not active(state, 400).reveal, "revival begins from a clean baseline")
local other = D.new()
D.update(other, 40, 400, prefs)
check(
    not active(other, 400).reveal,
    "replacement character state never inherits the previous identity's damage"
)
D.update(state, 75, 600, prefs)
D.clear(state)
check(
    not active(state, 600).reveal and #state.samples == 0,
    "explicit HUD close/release clears attention"
)
print("DamageAlerts: " .. checks .. " checks passed")
