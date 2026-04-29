require "CSR_FeatureFlags"

--[[
    CSR_TowAssistServer.lua
    Server-side tow assist for MP. Applies the same impulse logic
    to all online players who are towing vehicles.

    Compatibility: auto-disabled when Realistic Car Physics (RealisticCarPhysics)
    is active -- same reason as the client file; RCP's Java engine rebalances all
    torque and our vanilla-calibrated impulse stacks destructively.
]]

-- Cached at load time.
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

local function processPlayer(player)
    if not player:isDriving() then return end
    local vehicle = player:getVehicle()
    if not vehicle then return end
    local towed = vehicle:getVehicleTowing()
    if not towed then return end
    local gear = vehicle:getTransmissionNumber()
    if gear <= 0 then return end

    local factor = getTowFactor(vehicle)
    if not factor or factor == 0 then return end

    -- Speed-based taper: matches client. Begins at 5 km/h, zero at 55 km/h.
    local speed = vehicle.getCurrentSpeedKmHour and vehicle:getCurrentSpeedKmHour() or 0
    local speedFactor = math.max(0, 1 - (math.max(0, speed - 5) / 50))
    if speedFactor <= 0 then return end

    local mass = vehicle:getMass()
    local towedMass = towed:getMass()
    local loadRatio = math.min(towedMass / math.max(mass, 1), 3.0)
    local dir = Vector3f.new()
    vehicle:getForwardVector(dir)
    local delta = getGameTime():getMultiplier()
    delta = math.min(delta, 5.0)
    local forceMag = mass * factor * loadRatio * delta * speedFactor
    local force = Vector3f.new(dir:x() * forceMag, dir:y() * forceMag, dir:z() * forceMag)
    if not ZERO_VEC then ZERO_VEC = Vector3f.new() end
    ZERO_VEC:set(0, 0, 0)
    vehicle:addImpulse(force, ZERO_VEC)
end

if not CSR_TowAssistServer then CSR_TowAssistServer = {} end
if isServer() and not CSR_TowAssistServer._registered then
    CSR_TowAssistServer._registered = true
    Events.OnPlayerUpdate.Add(function(player)
        if not CSR_FeatureFlags.isTowAssistEnabled() then return end
        -- Both RCP and Project Summer Car rebalance the Java vehicle physics layer;
        -- our vanilla-calibrated impulse stacks destructively on top.
        if RCP_ACTIVE or PSC_ACTIVE then return end
        processPlayer(player)
    end)
end
