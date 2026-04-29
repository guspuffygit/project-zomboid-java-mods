require "CSR_FeatureFlags"

--[[
    CSR_TowAssist.lua
    Adds a forward impulse to vehicles towing another vehicle, compensating
    for the sluggishness when hauling. Force scales with towing vehicle mass,
    towed vehicle mass, and sandbox-configurable factor per vehicle type.
    Inspired by Effortless Towing (Workshop 3442862183).
    Fixes: correct impulse position (center, not offset), towed mass factor,
    uses OnPlayerUpdate instead of OnTick for efficiency.

    Compatibility: auto-disabled when Realistic Car Physics (RealisticCarPhysics)
    is active. RCP replaces the Java-level CarController and rebalances all engine
    torque curves from scratch; CSR's raw addImpulse() calls are calibrated for
    vanilla physics and stack destructively on top of RCP's already-boosted torque.
]]

-- Cached at load time; getActivatedMods() is safe to call here.
-- RCP: replaces Java vehicle physics, our impulse stacks destructively.
-- PSC: same author as RCP and uses similar physics rebalancing on engine swaps;
--      treat as incompatible to avoid stacking impulses on tuned engines.
local RCP_ACTIVE = getActivatedMods and getActivatedMods():contains("RealisticCarPhysics")
local PSC_ACTIVE = getActivatedMods and getActivatedMods():contains("ProjectSummerCar")

local ZERO_VEC = nil

local function getTowFactor(vehicle)
    local sb = SandboxVars and SandboxVars.CommonSenseReborn or nil
    if not sb then return 5.0 end
    local script = vehicle:getScript()
    if not script then return sb.TowAssistStandardFactor or 5.0 end
    local mechType = script:getMechanicType()
    if mechType == 1 then
        return sb.TowAssistStandardFactor or 5.0
    elseif mechType == 2 then
        return sb.TowAssistHeavyDutyFactor or 7.0
    elseif mechType == 3 then
        return sb.TowAssistSportFactor or 4.0
    end
    return sb.TowAssistStandardFactor or 5.0
end

local function onPlayerUpdate(player)
    if not CSR_FeatureFlags.isTowAssistEnabled() then return end
    -- Disabled when Realistic Car Physics or Project Summer Car is active:
    -- those mods replace/rebalance the Java vehicle physics layer, and our
    -- impulse is calibrated for vanilla and stacks destructively on top.
    if RCP_ACTIVE or PSC_ACTIVE then return end
    -- In MP, server handles tow assist to avoid double impulse
    if isClient() then return end
    if not player:isDriving() then return end
    local vehicle = player:getVehicle()
    if not vehicle then return end
    local towed = vehicle:getVehicleTowing()
    if not towed then return end
    local gear = vehicle:getTransmissionNumber()
    if gear <= 0 then return end

    local factor = getTowFactor(vehicle)
    if not factor or factor == 0 then return end

    -- Speed-based taper: begins tapering at 5 km/h, reaches zero at 55 km/h.
    -- Gentler onset removes the lurchy flat-top that made low-speed towing feel rough.
    local speed = vehicle.getCurrentSpeedKmHour and vehicle:getCurrentSpeedKmHour() or 0
    local speedFactor = math.max(0, 1 - (math.max(0, speed - 5) / 50))
    if speedFactor <= 0 then return end

    local mass = vehicle:getMass()
    local towedMass = towed:getMass()
    -- Scale force: more towed weight = more impulse needed, but diminishing
    local loadRatio = math.min(towedMass / math.max(mass, 1), 3.0)
    local dir = Vector3f.new()
    vehicle:getForwardVector(dir)
    local delta = getGameTime():getMultiplier()
    -- Cap delta to prevent physics explosion at high game speeds
    delta = math.min(delta, 5.0)
    local forceMag = mass * factor * loadRatio * delta * speedFactor
    local force = Vector3f.new(dir:x() * forceMag, dir:y() * forceMag, dir:z() * forceMag)
    -- Apply impulse at vehicle center (zero offset) to avoid torque
    if not ZERO_VEC then ZERO_VEC = Vector3f.new() end
    ZERO_VEC:set(0, 0, 0)
    vehicle:addImpulse(force, ZERO_VEC)
end

if not _G.__CSR_TowAssist_evRegistered then
    _G.__CSR_TowAssist_evRegistered = true
    Events.OnPlayerUpdate.Add(onPlayerUpdate)
end
