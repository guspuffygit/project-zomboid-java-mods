-- Recent XP and visible temperature checks, including the installed Lifestyle
-- HSMng implementation (recursive level-up overflow and mastered-table behavior).
local root = arg[1] or arg[0]:match("^(.*)[/\\]tests[/\\][^/\\]+$") or "."
local game = assert(
    arg[2] or (os and os.getenv and os.getenv("PZ_GAME_ROOT")),
    "Pass the game root as argument 2"
)
local lifestyle = arg[3] or (os and os.getenv and os.getenv("LIFESTYLE_MOD_ROOT"))
if lifestyle == "" then
    lifestyle = nil
end
local function load(path)
    if readTestSource then
        return assert(loadstring(readTestSource(path), "@" .. path))()
    end
    return dofile(path)
end
local checks = 0
local function check(ok, why)
    assert(ok, why)
    checks = checks + 1
end
local function close(actual, expected)
    return math.abs(actual - expected) < 0.000001
end
local function count(values)
    local n = 0
    for _ in pairs(values) do
        n = n + 1
    end
    return n
end
local function pack(...)
    return { n = select("#", ...), ... }
end
require = function() end
local now, xpReads, moodleReads = 1000, 0, 0
getTimestampMs = function()
    return now
end
local translations = {
    IGUI_XP_xp = "XP",
    IGUI_perks_Yoga = "Yoga",
    IGUI_Temp_Cold = "Cold",
    IGUI_Temp_Normal = "Normal",
    IGUI_Temp_Hot = "Hot",
    UI_ATFCombatHealth_Cool = "Cool",
    UI_ATFCombatHealth_Warm = "Warm",
}
getTextOrNull = function(key)
    return translations[key]
end
getText = function(key)
    return translations[key] or key
end
MoodleType = { HYPOTHERMIA = "Hypothermia", HYPERTHERMIA = "Hyperthermia" }
Perks = { None = "None", Lifestyle = "Lifestyle", Meditation = "Meditation" }
local players = {}
getSpecificPlayer = function(slot)
    return players[slot]
end
local function player(slot)
    local p = { slot = slot, xp = {}, data = {}, cold = 0, hot = 0 }
    function p:getPlayerNum()
        return self.slot
    end
    function p:isLocalPlayer()
        return not self.remote
    end
    function p:isDead()
        return self.dead
    end
    function p:getModData()
        return self.data
    end
    function p:getXp()
        return {
            getXP = function(_, perk)
                xpReads = xpReads + 1
                return self.xp[perk] or 0
            end,
        }
    end
    function p:getMoodles()
        if self.noMoodles then
            return nil
        end
        return {
            getMoodleLevel = function(_, kind)
                moodleReads = moodleReads + 1
                return kind == MoodleType.HYPOTHERMIA and self.cold or self.hot
            end,
            getMoodleDisplayString = function(_, kind)
                if kind == MoodleType.HYPOTHERMIA then
                    return "Native cold " .. self.cold
                end
                return "Native hot " .. self.hot
            end,
        }
    end
    return p
end
local function perk(id, parent)
    return {
        getId = function()
            return id
        end,
        getType = function()
            return id
        end,
        getParent = function()
            return parent or "Skills"
        end,
        getName = function()
            return id
        end,
    }
end
local alpha, beta, meditation = perk("Alpha"), perk("Beta"), perk("Meditation", Perks.Lifestyle)
local list, listReads = { perk("Category", Perks.None), alpha, beta, meditation, alpha }, 0
PerkFactory = {
    PerkList = {
        size = function()
            listReads = listReads + 1
            return #list
        end,
        get = function(_, i)
            listReads = listReads + 1
            return list[i + 1]
        end,
    },
}
local source = root .. "/media/lua/client/ATFCombatHealth/Telemetry.lua"
local T = load(source)
local p = player(0)
players[0] = p
p.xp.Alpha, p.xp.Beta, p.xp.Meditation = 10, 20, 30
check(T.new(nil) == nil, "absent player has no telemetry")
local remote = player(1)
remote.remote = true
players[1] = remote
check(T.new(remote) == nil, "remote character cannot get local telemetry")
check(T.new(player(0)) == nil, "stale survivor reference cannot get telemetry")
local state = T.new(p)
check(state and #state.xpRows == 0 and state.temperature == nil, "new state starts empty")
check(not T.installYoga(), "missing optional Lifestyle API is inert")
local reads = xpReads
for i = 1, 100 do
    T.update(state, now + i, false, false)
end
check(xpReads == reads and moodleReads == 0, "disabled sections read no XP or temperature")
check(T.update(state, now, true, false), "XP enable marks a layout change")
check(
    #state.xpRows == 0 and state.scanReads == 3 and state.polls == 1,
    "initial XP scan baselines children once, excluding parent/duplicate perks"
)
local cachedReads = listReads
for i = 1, 999 do
    T.update(state, now + i, true, false)
end
check(
    state.scanReads == 3 and state.polls == 1 and listReads == cachedReads,
    "hundreds of updates never rescan perks before one second"
)

-- Multipliers, caps and resets are represented by actual stored totals. Raw
-- event amounts are deliberately unrelated to those totals and never summed.
p.xp.Alpha = 16
check(T.onXP(state, p, alpha, 2, now + 10), "candidate event observes the current total promptly")
check(
    #state.xpRows == 1 and state.xpRows[1].amount == 6 and state.xpRows[1].text == "Alpha +6 XP",
    "cached full text shows the actual multiplied delta of six, not raw requested two"
)
T.onXP(state, p, alpha, 2, now + 11)
check(state.xpRows[1].amount == 6, "duplicate native events do not duplicate gains")
check(
    T.update(state, now + 12, true, false) and not T.update(state, now + 13, true, false),
    "event dirty state triggers one following layout refresh"
)
local beforeForeign = state.scanReads
T.onXP(state, remote, alpha, 100, now + 14)
T.onXP(state, p, perk("Unregistered"), 100, now + 14)
check(state.scanReads == beforeForeign, "foreign and uncached candidates perform no XP reads")
p.xp.Beta, p.xp.Meditation = 27, 35
now = 2000
T.update(state, now, true, false)
check(
    state.polls == 2 and state.scanReads == 8,
    "one second fallback reads each cached child once plus two event candidates"
)
check(
    #state.xpRows == 3 and state.xpRows[1].id == "perk:Meditation",
    "native Meditation arrives through ordinary XP totals"
)
local function row(id)
    for _, value in ipairs(state.xpRows) do
        if value.id == id then
            return value
        end
    end
end
check(
    row("perk:Alpha").amount == 6 and row("perk:Beta").amount == 7,
    "polling preserves event gains without duplicating them"
)
p.xp.Alpha = 0
now = 3000
T.update(state, now, true, false)
check(row("perk:Alpha").amount == 6, "XP losses and reset totals create no positive gain")
p.xp.Alpha = 0.25
now = 4000
T.update(state, now, true, false)
check(close(row("perk:Alpha").amount, 6.25), "gain after a reset uses the new baseline")
T.update(state, now, false, false)
check(#state.xpRows == 0 and count(state.entries) == 0, "turning XP off clears history and totals")
p.xp.Alpha = 200
T.update(state, now + 100, true, false)
check(#state.xpRows == 0, "re-enable baselines XP gained while hidden without a fake gain")
p.xp.Alpha = 202
now = 5100
T.update(state, now, true, false)
check(row("perk:Alpha").amount == 2, "new gain after re-enable starts fresh")

-- Native finite set is cached with a hard read cap; old state does not rebuild
-- when another player's new state captures a larger installed perk collection.
list = { perk("Category", Perks.None) }
for i = 1, 300 do
    list[#list + 1] = perk("Skill" .. i)
end
local q = player(2)
players[2] = q
local large = T.new(q)
local oldListReads = listReads
T.update(large, now, true, false)
check(large.scanReads == 256 and large.polls == 1, "per-player scan has a hard 256 child cap")
local capListReads = listReads
for i = 1, 999 do
    T.update(large, now + i, true, false)
end
check(
    large.scanReads == 256 and listReads == capListReads and capListReads > oldListReads,
    "capped native perk list is cached rather than read every frame"
)
T.onXP(large, q, list[258], 999, now + 500)
check(
    large.scanReads == 256 and #large.xpRows == 0,
    "perk beyond the cap cannot bypass bounded read behavior"
)
for i = 1, 15 do
    q.xp["Skill" .. i] = i
    T.onXP(large, q, list[i + 1], 0.001, now + i)
end
check(
    #large.xpRows == 3 and count(large.entries) == 12,
    "recent gains remember at most twelve and display only three"
)
check(
    large.xpRows[1].id == "perk:Skill15" and large.xpRows[3].id == "perk:Skill13",
    "most recently gained skills are shown first"
)
q.xp.Skill13 = 14
T.onXP(large, q, list[14], 100, now + 20)
check(
    large.xpRows[1].id == "perk:Skill13" and large.xpRows[1].amount == 14,
    "repeat gain aggregates and moves that skill to the front"
)
now = now + 30020
T.update(large, now, true, false)
check(
    #large.xpRows == 0 and count(large.entries) == 0,
    "thirty seconds since each final gain expires rows and remembered history"
)
check(large.polls == 2, "long delay runs one scan rather than catch-up loops")
local qReads = large.scanReads
T.update(large, now, false, false)
for i = 1, 2000 do
    T.update(large, now + i, false, false)
end
check(large.scanReads == qReads, "disabled XP stops native reads even after a due poll")

-- Five text states group the ordinary native hypo/hyperthermia moodles. No
-- BodyDamage, thermoregulator, ambient temperature or debug value is consulted.
now = 50000
check(
    T.update(state, now, false, true) and state.temperature.key == "normal",
    "no visible temperature moodle means Normal"
)
local firstMoodleReads = moodleReads
p.hot = 1
T.update(state, now + 499, false, true)
check(
    state.temperature.key == "normal" and moodleReads == firstMoodleReads,
    "temperature remains cached until half a second"
)
for _, value in ipairs({
    { 0, 1, "warm", "Warm" },
    { 0, 2, "hot", "Hot" },
    { 0, 4, "hot", "Hot" },
    { 1, 0, "cool", "Cool" },
    { 2, 0, "cold", "Cold" },
    { 4, 0, "cold", "Cold" },
    { 0, 0, "normal", "Normal" },
}) do
    p.cold, p.hot = value[1], value[2]
    now = now + 500
    T.update(state, now, false, true)
    check(
        state.temperature.key == value[3] and state.temperature.text == value[4],
        "visible moodle state " .. value[3]
    )
    if p.cold > 0 then
        check(
            state.temperature.tooltip == "Native cold " .. p.cold,
            "native cold tooltip remains exact"
        )
    end
    if p.hot > 0 then
        check(
            state.temperature.tooltip == "Native hot " .. p.hot,
            "native hot tooltip remains exact"
        )
    end
end
now = now + 500
check(not T.update(state, now, false, true), "unchanged temperature does not rebuild layout")
p.noMoodles = true
now = now + 500
T.update(state, now, false, true)
check(state.temperature == nil, "unsupported/missing native moodles omit temperature")
p.noMoodles, p.cold = false, 1.5
now = now + 500
T.update(state, now, false, true)
check(state.temperature == nil, "invalid native moodle levels cannot invent a temperature state")
p.cold = 0
T.update(state, now, false, false)
check(state.temperature == nil, "temperature section off releases displayed state")
local getMoodles = p.getMoodles
p.getMoodles = nil
now = now + 500
T.update(state, now, false, true)
check(state.temperature == nil, "absent native moodle API omits temperature without an error")
p.getMoodles = getMoodles

-- Optional mod integration loads the actual installed helper, not a copy of its
-- thresholds or addXP algorithm. Its Halo/sound effects still execute unchanged.
if lifestyle then
    local halos, sounds = 0, 0
    HaloTextHelper = {
        addTextWithArrow = function()
            halos = halos + 1
        end,
    }
    getSoundManager = function()
        return {
            playUISound = function()
                sounds = sounds + 1
            end,
        }
    end
    isClient = function()
        return false
    end
    load(lifestyle .. "/common/media/lua/client/Helper/HSMng.lua")
    local original = HiddenSkills.addXP
    check(
        T.installYoga() and HiddenSkills.addXP ~= original,
        "late Lifestyle load installs only the optional addXP observer"
    )
    local installed = HiddenSkills.addXP
    T.installYoga()
    load(source)
    T.installYoga()
    check(HiddenSkills.addXP == installed, "reload never adds another Yoga wrapper")
    local skillTable = HiddenSkills
    load(lifestyle .. "/common/media/lua/client/Helper/HSMng.lua")
    check(
        HiddenSkills == skillTable and HiddenSkills.addXP ~= installed,
        "actual helper reload replaces addXP while retaining its table"
    )
    local reloaded = HiddenSkills.addXP
    T.installYoga()
    check(
        HiddenSkills.addXP ~= reloaded,
        "observer reinstalls after actual same-table helper reload"
    )
    installed = HiddenSkills.addXP
    T.installYoga()
    check(HiddenSkills.addXP == installed, "repaired same-table observer remains idempotent")
    translations.UI_LSHS_Yoga = "Localized Yoga"
    T.update(state, now, true, false)
    HiddenSkills.addXP(p, "Yoga", 5)
    check(
        row("hidden:Yoga").amount == 5
            and row("hidden:Yoga").name == "Localized Yoga"
            and p.data.LSHiddenSkills.Yoga[2] == 5,
        "actual helper creates and awards localized Yoga without native perk registration"
    )
    HiddenSkills.addXP(p, "Yoga", 5.8)
    check(
        row("hidden:Yoga").amount == 10 and p.data.LSHiddenSkills.Yoga[2] == 10,
        "fractional request follows Lifestyle floor instead of inflating reported gain"
    )
    local oldGainTime = state.entries["hidden:Yoga"].lastGain
    now = now + 100
    HiddenSkills.addXP(p, "Yoga", 0.1)
    check(
        row("hidden:Yoga").amount == 10 and state.entries["hidden:Yoga"].lastGain == oldGainTime,
        "rounded-to-zero Yoga gain neither adds nor renews history"
    )
    check(halos == 3 and sounds == 0, "original Lifestyle Halo/sound semantics remain intact")
    T.update(state, now, false, false)
    T.update(state, now, true, false)
    p.data.LSHiddenSkills.Yoga = { 0, 95, 100 }
    HiddenSkills.addXP(p, "Yoga", 500)
    check(
        p.data.LSHiddenSkills.Yoga[1] == 2 and p.data.LSHiddenSkills.Yoga[2] == 245,
        "native helper crosses levels and replaces skill tables"
    )
    check(
        row("hidden:Yoga").amount == 500,
        "recursive overflow creates one Yoga gain, not duplicated nested awards"
    )
    T.update(state, now, false, false)
    T.update(state, now, true, false)
    p.data.LSHiddenSkills.Yoga = { 9, 8990, 9000 }
    HiddenSkills.addXP(p, "Yoga", 1000)
    check(
        p.data.LSHiddenSkills.Yoga[1] == 10 and p.data.LSHiddenSkills.Yoga[2] == 8990,
        "installed helper retains old XP on mastering"
    )
    check(row("hidden:Yoga").amount == 10, "mastered Yoga reports only accepted XP up to the cap")
    HiddenSkills.addXP(p, "Yoga", 1000)
    check(row("hidden:Yoga").amount == 10, "mastered Yoga ignores further requests")
    T.update(state, now, false, false)
    T.update(state, now, true, false)
    p.data.LSHiddenSkills.Yoga = { 0, 99, 100 }
    HiddenSkills.addXP(p, "Yoga", 1)
    check(
        p.data.LSHiddenSkills.Yoga[1] == 0 and row("hidden:Yoga").amount == 1,
        "Lifestyle equal-threshold XP is accepted without early level-up"
    )
    HiddenSkills.addXP(p, "Yoga", 1)
    check(
        p.data.LSHiddenSkills.Yoga[1] == 1 and row("hidden:Yoga").amount == 2,
        "strict greater-than native threshold counts the next point exactly once"
    )
    HiddenSkills.removeXP(p, "Yoga", 20)
    check(
        row("hidden:Yoga").amount == 2,
        "Yoga cancellation loss never creates a recent positive gain"
    )
    T.update(state, now, false, false)
    HiddenSkills.addXP(p, "Yoga", 3)
    check(#state.xpRows == 0, "disabled Yoga observer preserves the helper without tracking")
else
    print(
        "SKIP installed Lifestyle helper: pass -PlifestyleModDir or LIFESTYLE_MOD_ROOT to include it"
    )
end

-- Another valid API implementation can return arbitrary Lua values or errors.
-- Observe before/after only, preserving nil positions, trailing nils and errors.
T.update(state, now, false, false)
p.data.LSHiddenSkills = p.data.LSHiddenSkills or {}
p.data.LSHiddenSkills.Yoga = { 0, 0, 100 }
local fail, calls = false, 0
local function replacementXP(actor, skill, amount, extra)
    calls = calls + 1
    if fail then
        error("original sentinel")
    end
    if actor.data then
        actor.data.LSHiddenSkills.Yoga[2] = actor.data.LSHiddenSkills.Yoga[2] + amount
    end
    return "first", nil, extra, nil
end
HiddenSkills = { addXP = replacementXP }
check(T.installYoga(), "replacement optional API table gets its own observer")
T.update(state, now, true, false)
local result = pack(HiddenSkills.addXP(p, "Yoga", 4, "third"))
check(
    result.n == 4
        and result[1] == "first"
        and result[2] == nil
        and result[3] == "third"
        and result[4] == nil,
    "wrapper preserves all return values including trailing nil"
)
check(
    row("hidden:Yoga").amount == 4 and calls == 1,
    "replacement API contributes its actual gain once"
)
fail = true
local ok, reason = pcall(HiddenSkills.addXP, p, "Yoga", 4)
check(
    not ok and tostring(reason):find("original sentinel", 1, true),
    "original API error is propagated"
)
fail = false
HiddenSkills.addXP(p, "Yoga", 1)
check(
    row("hidden:Yoga").amount == 5 and calls == 3,
    "error cleanup restores observation for subsequent calls"
)
local generic = {}
result = pack(HiddenSkills.addXP(generic, "Yoga", 4, "generic"))
check(
    result.n == 4 and result[3] == "generic",
    "generic non-player characters keep original API behavior"
)

-- Death, replacement and explicit cleanup remove all retained survivor/perk
-- references. A respawn starts from loaded totals, not an apparent XP windfall.
T.update(state, now, true, true)
p.dead = true
local deathReads = state.scanReads
T.onXP(state, p, alpha, 999, now)
check(state.scanReads == deathReads, "dead player event performs no XP read")
check(
    T.update(state, now, true, true)
        and state.player == nil
        and state.perks == nil
        and #state.xpRows == 0
        and state.temperature == nil,
    "death clears all displayed and cached character/perk references"
)
check(T.states[0] == nil, "dead state is removed from optional callback registry")
local fresh = player(0)
players[0] = fresh
fresh.xp.Alpha = 5000
list = { alpha, beta, meditation }
local revived = T.new(fresh)
T.update(revived, now, true, false)
check(#revived.xpRows == 0 and revived.player == fresh, "respawn loaded XP is only a baseline")
local replacement = player(0)
players[0] = replacement
check(
    T.update(revived, now, true, true) and revived.player == nil,
    "stale player identity is cleared on replacement"
)
T.clear(large)
check(
    large.player == nil and large.perks == nil and count(large.entries) == 0 and T.states[2] == nil,
    "explicit disconnect cleanup releases references and remembered XP"
)
print(
    "PASS Telemetry "
        .. checks
        .. " checks (bounded XP reads, visible moodles; installed Lifestyle "
        .. (lifestyle and "included" or "skipped")
        .. ")"
)
