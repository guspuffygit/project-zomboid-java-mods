if not isServer() then
    return
end

require "CSR_FeatureFlags"

--[[
    CSR_InfectionResilience.lua
    Server-side infection survival system.

    When a zombie-infected player's infection reaches a random threshold,
    the system rolls for survival. On success the real infection converts
    to a fake infection (fever) that the player can recover from.

    Formula:  successChance = chanceToHeal / (penalty ^ infectedParts)
    Roll:     ZombRand(0, 100) < successChance  →  survive

    Sandbox options control every tunable.
    ModData keys:
        CSR_IR_Threshold  – randomly chosen % of mortality time to trigger roll
        CSR_IR_Doomed     – true after a failed roll (no retries)
]]

CSR_InfectionResilience = {}

-- =========================================================================
-- Helpers
-- =========================================================================

local function sb()
    return SandboxVars and SandboxVars.CommonSenseReborn or {}
end

local function getChanceToHeal()
    return tonumber(sb().InfResChanceToHeal) or 10
end

local function getPenalty()
    return tonumber(sb().InfResPenaltyMultiplier) or 1.5
end

local function getThresholdMin()
    return tonumber(sb().InfResThresholdMin) or 70
end

local function getThresholdMax()
    return tonumber(sb().InfResThresholdMax) or 95
end

--- Count body parts with an infected wound.
local function countInfectedParts(player)
    local bd = player:getBodyDamage()
    if not bd then return 0 end
    local parts = bd:getBodyParts()
    if not parts then return 0 end
    local count = 0
    for i = 0, parts:size() - 1 do
        local bp = parts:get(i)
        if bp and bp:IsInfected() then
            count = count + 1
        end
    end
    return count
end

--- Assign a random threshold percentage the first time we see this infection.
local function getOrAssignThreshold(player)
    local md = player:getModData()
    if md.CSR_IR_Threshold then
        return md.CSR_IR_Threshold
    end
    local lo = getThresholdMin()
    local hi = getThresholdMax()
    if hi <= lo then hi = lo + 1 end
    local threshold = ZombRand(lo, hi + 1)
    md.CSR_IR_Threshold = threshold
    return threshold
end

--- Convert a real zombie infection into a fake infection (fever).
local function convertToFever(player)
    local bd = player:getBodyDamage()
    if not bd then return end

    -- Copy real infection stat into fever stat
    local stats = player:getStats()
    local realVal = stats:get(CharacterStat.ZOMBIE_INFECTION)
    stats:set(CharacterStat.ZOMBIE_FEVER, realVal)
    stats:set(CharacterStat.ZOMBIE_INFECTION, 0)

    -- Flip the overall flags
    bd:setInfected(false)
    bd:setIsFakeInfected(true)

    -- Clear infected-wound flag on each body part so they can heal
    local parts = bd:getBodyParts()
    if parts then
        for i = 0, parts:size() - 1 do
            local bp = parts:get(i)
            if bp and bp:IsInfected() then
                bp:setInfectedWound(false)
            end
        end
    end

    player:setHaloNote(getText("IGUI_CSR_InfRes_Survived"), 0.4, 1.0, 0.4, 300)
end

--- Clean up moddata when the player is no longer infected.
local function clearModData(player)
    local md = player:getModData()
    md.CSR_IR_Threshold = nil
    md.CSR_IR_Doomed = nil
end

-- =========================================================================
-- Per-minute tick
-- =========================================================================

local function onEveryOneMinute()
    if not CSR_FeatureFlags.isInfectionResilienceEnabled() then return end

    local players = getOnlinePlayers()
    if not players then return end

    for p = 0, players:size() - 1 do
        local player = players:get(p)
        if player and not player:isDead() then
            local bd = player:getBodyDamage()
            if bd and bd:IsInfected() then
                local md = player:getModData()

                -- Already failed the roll — no second chances
                if md.CSR_IR_Doomed then
                    -- keep going, nothing to do
                else
                    local threshold = getOrAssignThreshold(player)
                    -- B42: getInfectionMortalityTime/getInfectionLevel removed; use CharacterStat
                    local infLevel = player:getStats():get(CharacterStat.ZOMBIE_INFECTION)
                    local pct = infLevel * 100

                    if pct >= threshold then
                        local infectedParts = countInfectedParts(player)
                        if infectedParts < 1 then infectedParts = 1 end

                        local chance = getChanceToHeal() / (getPenalty() ^ infectedParts)
                        local roll = ZombRand(0, 100)

                        if roll < chance then
                            convertToFever(player)
                            clearModData(player)
                        else
                            -- Mark doomed — the infection will run its course
                            md.CSR_IR_Doomed = true
                        end
                    end
                end
            else
                -- Not infected (or recovered) — clear leftover moddata
                clearModData(player)
            end
        end
    end
end

if not _G.__CSR_InfectionResilience_evRegistered then
    _G.__CSR_InfectionResilience_evRegistered = true
    Events.EveryOneMinute.Add(onEveryOneMinute)
end
