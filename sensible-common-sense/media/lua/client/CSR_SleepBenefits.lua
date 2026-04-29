require "CSR_FeatureFlags"

-- Track per-player sleep state to detect the asleep→awake transition for "Sleep On It".
local sleepState = {}

-- EveryTenMinutes: gradual mood and stamina recovery while the player is asleep.
local function onSleepBenefits()
    if not CSR_FeatureFlags.isSleepBenefitsEnabled() then return end

    local player = getPlayer()
    if not player or not player:isAsleep() then return end

    local stats = player:getStats()
    if not stats then return end

    -- Boredom
    local boredom = stats:get(CharacterStat.BOREDOM)
    if boredom and boredom > 0 then
        stats:remove(CharacterStat.BOREDOM, math.min(1.5, boredom))
    end

    -- Unhappiness
    local unhappiness = stats:get(CharacterStat.UNHAPPINESS)
    if unhappiness and unhappiness > 0 then
        stats:remove(CharacterStat.UNHAPPINESS, math.min(0.5, unhappiness))
    end

    -- Stress (on-edge moodle source) -- fades slowly during restful sleep
    local stress = stats:get(CharacterStat.STRESS)
    if stress and stress > 0 then
        stats:remove(CharacterStat.STRESS, math.min(2.0, stress))
    end

    -- Panic (anxiety moodle source) -- fades slowly during sleep
    local panic = stats:get(CharacterStat.PANIC)
    if panic and panic > 0 then
        stats:remove(CharacterStat.PANIC, math.min(1.5, panic))
    end

    -- Anger -- fades during sleep
    local anger = stats:get(CharacterStat.ANGER)
    if anger and anger > 0 then
        stats:remove(CharacterStat.ANGER, math.min(1.0, anger))
    end

    -- Endurance (sprint stamina) -- vanilla does not restore this during sleep;
    -- resting should recover stamina so the exhausted moodle clears after a full sleep.
    local endurance = stats:get(CharacterStat.ENDURANCE)
    if endurance and endurance ~= nil and endurance < 1.0 then
        stats:add(CharacterStat.ENDURANCE, math.min(0.1, 1.0 - endurance))
    end
end

-- "Sleep On It": one-time burst of mood improvement at the moment the player wakes.
-- Applied once per sleep cycle when the isAsleep() state transitions true → false.
local function applySleptOnIt(player)
    if not CSR_FeatureFlags.isSleepBenefitsEnabled() then return end
    if not player or player:isDead() then return end

    local stats = player:getStats()
    if not stats then return end

    -- Stress: significant reduction on wake-up (0-100 scale)
    local stress = stats:get(CharacterStat.STRESS)
    if stress and stress > 0 then
        stats:remove(CharacterStat.STRESS, math.min(25, stress))
    end

    -- Panic: meaningful reduction (0-100 scale; 50 is one wound-clean worth)
    local panic = stats:get(CharacterStat.PANIC)
    if panic and panic > 0 then
        stats:remove(CharacterStat.PANIC, math.min(20, panic))
    end

    -- Anger
    local anger = stats:get(CharacterStat.ANGER)
    if anger and anger > 0 then
        stats:remove(CharacterStat.ANGER, math.min(20, anger))
    end

    -- Boredom: wake-up bonus on top of the gradual per-10-min reduction
    local boredom = stats:get(CharacterStat.BOREDOM)
    if boredom and boredom > 0 then
        stats:remove(CharacterStat.BOREDOM, math.min(20, boredom))
    end

    -- Unhappiness: small wake-up bonus
    local unhappiness = stats:get(CharacterStat.UNHAPPINESS)
    if unhappiness and unhappiness > 0 then
        stats:remove(CharacterStat.UNHAPPINESS, math.min(5, unhappiness))
    end
end

-- OnPlayerUpdate: detect asleep → awake transition for the "Sleep On It" burst.
local function onPlayerUpdate(player)
    if not player then return end
    local pNum   = player:getPlayerNum()
    local asleep = player:isAsleep()
    if sleepState[pNum] == true and not asleep then
        applySleptOnIt(player)
    end
    sleepState[pNum] = asleep
end

if not _G.__CSR_SleepBenefits_evRegistered then
    _G.__CSR_SleepBenefits_evRegistered = true
    if Events and Events.EveryTenMinutes then
        Events.EveryTenMinutes.Add(onSleepBenefits)
    end
    if Events and Events.OnPlayerUpdate then
        Events.OnPlayerUpdate.Add(onPlayerUpdate)
    end
end

