--[[
Talis New Music's EveryOneMinute vehicle power tick loops over EVERY loaded
vehicle (1,792 on ATF, profiled 2026-08-27) making 3-5 Lua->Java reflection
calls each (getPartById/getDeviceData/getInventoryItem/getModData) just to
discover which vehicles have an NM radio state. That discovery is the burst
where server Lua eats 30-60% of the main thread for ~1s every in-game minute.
The real work only applies to radios the mod already tracks in
NMServerRegistryState.worldRegistry.

This patch replaces NMServerVehiclePowerTick.onEveryOneMinute with a
registry-driven sweep: iterate worldRegistry vehicle entries and resolve each
to its live vehicle through the mod's own chain
(entry.vehicleSqlId -> vehicleRuntimeIdBySqlId -> getVehicleById), verifying
the sqlId round-trips before touching the vehicle. Per-vehicle power/drain
semantics are copied verbatim from the original (same public APIs, same
shared lastDrainMs table, delta-time drain math unchanged).

Safety net: every 10th minute (and the first minute after boot) the ORIGINAL
full sweep runs instead, catching radios that have saved state but no
registry entry yet (e.g. right after a restart) and any entry the index
failed to resolve. Worst-case a dead-battery force-off is delayed 10 game
minutes (~1 real minute at ATF's clock); drain amounts stay correct because
the math is elapsed-time based.

The sqlId index is fresh whenever it matters: NMServerSourceRefreshTick calls
NMServerVehicleSqlIndexCache.refresh() every 10 scheduler ticks while any
registry entry exists (rate-limited to 1.5s), and a playing vehicle radio is
by definition a registry entry.

NMServerMainRuntime.onEveryOneMinute looks up
NMServerVehiclePowerTick.onEveryOneMinute on the global table at every call,
so swapping the function member is sufficient. Applied on the first server
tick so every Talis module is guaranteed loaded.

Re-check this file whenever Talis New Music updates: the per-vehicle block
below must stay behaviorally identical to theirs
(server/runtime/NMServerVehiclePowerTick.lua).

Live stats for eval inspection:
  ATFPatchesTalisNMVehicleSweep.stats = { registrySweeps, fullSweeps,
  entriesSeen, entriesResolved, entriesUnresolved }
]]

if isClient() and not isServer() then
    return
end

ATFPatchesTalisNMVehicleSweep = ATFPatchesTalisNMVehicleSweep or {}
ATFPatchesTalisNMVehicleSweep.stats = {
    registrySweeps = 0,
    fullSweeps = 0,
    entriesSeen = 0,
    entriesResolved = 0,
    entriesUnresolved = 0,
}

local FULL_SWEEP_EVERY_N_MINUTES = 10

local function nowRealMs()
    if getTimestampMs then
        local ms = tonumber(getTimestampMs())
        if ms then
            return ms
        end
    end
    if getTimestamp then
        local ts = tonumber(getTimestamp())
        if ts then
            return ts * 1000
        end
    end
    return 0
end

local function markAuthoritativeMutation(state)
    if not state then
        return
    end
    NMDeviceState.bumpRevision(state)
    state.sourceGeneration = (tonumber(state.sourceGeneration) or 0) + 1
end

local function drainVehicleBattery(vehicle, drainSeconds, deltaSeconds)
    if not vehicle then
        return 0.0
    end
    local batteryPart = vehicle.getBattery and vehicle:getBattery() or nil
    local batteryItem = batteryPart
            and batteryPart.getInventoryItem
            and batteryPart:getInventoryItem()
        or nil
    if not batteryItem then
        return 0.0
    end

    local current = NMCore.readDrainableFraction(batteryItem, 0.0)
    local nextValue =
        NMServerBatteryAuthority.computeNextCharge(current, deltaSeconds, drainSeconds)
    if nextValue ~= current then
        if batteryItem.setUsedDelta then
            batteryItem:setUsedDelta(nextValue)
        end
        if vehicle.transmitPartUsedDelta and batteryPart then
            vehicle:transmitPartUsedDelta(batteryPart)
        end
    end
    return nextValue
end

local function forceVehicleStateOff(vehicle, part, state, reason)
    if not vehicle or not part or not state then
        return false
    end
    local changed = NMServerBatteryAuthority.forceStateOff(state, reason or "vehicle_battery_empty")
    if not changed then
        return false
    end
    markAuthoritativeMutation(state)

    if vehicle.transmitPartModData then
        vehicle:transmitPartModData(part)
        vehicle:updateParts()
    end
    return true
end

-- Behavioral copy of the original sweep's per-vehicle body
-- (NMServerVehiclePowerTick.lua lines 79-128), minus the discovery scan.
local function tickOneVehicle(vehicle)
    local part = vehicle.getPartById and vehicle:getPartById("Radio") or nil
    local profile = part and NMDeviceProfiles.getVehicleProfile(part) or nil
    local state = part and profile and NMDeviceState.peek and NMDeviceState.peek(part) or nil
    if not (profile and state and profile.vehicleUsesCarBattery) then
        return
    end

    local uuid = tostring(state.deviceUUID or "")
    local nowMsValue = nowRealMs()
    if not NMVehicleHelpers.vehicleHasPower(vehicle, part) then
        if forceVehicleStateOff(vehicle, part, state, "vehicle_battery_empty") then
            local token = string.format(
                "%s:%s",
                tostring(tonumber(state.playbackEpoch) or -1),
                tostring(tonumber(state.trackIndex) or -1)
            )
            NMServerBatteryAuthority.logEmptyStop("vehicle", uuid, "vehicle_battery_empty", token)
        end
        NMServerVehiclePowerTick.lastDrainMs[uuid] = nowMsValue
    elseif state.isOn and (vehicle.isEngineRunning and (not vehicle:isEngineRunning())) then
        if
            not (
                NMRuntimeConfig.getVehicleCustomDrainEnabled
                and NMRuntimeConfig.getVehicleCustomDrainEnabled()
            )
        then
            NMServerVehiclePowerTick.lastDrainMs[uuid] = nowMsValue
        else
            local prevMs = tonumber(NMServerVehiclePowerTick.lastDrainMs[uuid])
            if not prevMs then
                NMServerVehiclePowerTick.lastDrainMs[uuid] = nowMsValue
            else
                local deltaSeconds = math.max(0, (nowMsValue - prevMs) / 1000.0)
                NMServerVehiclePowerTick.lastDrainMs[uuid] = nowMsValue
                local drainSeconds = tonumber(
                    NMRuntimeConfig.getBatteryDrainSecondsVehicleEngineOff
                            and NMRuntimeConfig.getBatteryDrainSecondsVehicleEngineOff()
                        or 300
                ) or 300
                local batteryPart = vehicle.getBattery and vehicle:getBattery() or nil
                local batteryItem = batteryPart
                        and batteryPart.getInventoryItem
                        and batteryPart:getInventoryItem()
                    or nil
                local currentCharge = NMCore.readDrainableFraction(batteryItem, 0.0)
                local nextCharge = drainVehicleBattery(vehicle, drainSeconds, deltaSeconds)
                NMServerBatteryAuthority.logBatteryTick(
                    "vehicle",
                    uuid,
                    nowMsValue,
                    prevMs,
                    currentCharge,
                    nextCharge,
                    drainSeconds,
                    "engineOn=false"
                )
                if nextCharge <= 0 then
                    if forceVehicleStateOff(vehicle, part, state, "vehicle_battery_empty") then
                        local token = string.format(
                            "%s:%s",
                            tostring(tonumber(state.playbackEpoch) or -1),
                            tostring(tonumber(state.trackIndex) or -1)
                        )
                        NMServerBatteryAuthority.logEmptyStop(
                            "vehicle",
                            uuid,
                            "vehicle_battery_empty",
                            token
                        )
                    end
                end
            end
        end
    else
        NMServerVehiclePowerTick.lastDrainMs[uuid] = nowMsValue
    end

    local entry = NMServerRegistryState.worldRegistry[uuid]
    if entry then
        entry.x = tonumber(vehicle:getX()) or entry.x
        entry.y = tonumber(vehicle:getY()) or entry.y
        entry.z = tonumber(vehicle:getZ()) or entry.z
        entry.windowsOpen = NMVehicleHelpers.vehicleWindowsOpen(vehicle)
        entry.stateSnapshot = NMDeviceState.export(state)
        NMServerRegistryState.worldRegistry[uuid] = entry
    end
end

local function resolveEntryVehicle(entry)
    local sqlId = tostring(entry.vehicleSqlId or "")
    if sqlId == "" then
        return nil
    end
    local indexMap = NMServerRegistryState and NMServerRegistryState.vehicleRuntimeIdBySqlId or nil
    local runtimeId = tonumber(indexMap and indexMap[sqlId] or nil)
    if not runtimeId or not getVehicleById then
        return nil
    end
    local vehicle = getVehicleById(runtimeId)
    if not vehicle then
        return nil
    end
    local observedSql = NMVehicleHelpers
            and NMVehicleHelpers.getVehicleSqlIdString
            and NMVehicleHelpers.getVehicleSqlIdString(vehicle)
        or ""
    if tostring(observedSql) ~= sqlId then
        return nil
    end
    return vehicle
end

local function registrySweep(stats)
    stats.registrySweeps = stats.registrySweeps + 1
    local world = NMServerRegistryState and NMServerRegistryState.worldRegistry or nil
    if type(world) ~= "table" then
        return
    end
    for _, entry in pairs(world) do
        if entry and tostring(entry.vehicleSqlId or "") ~= "" then
            stats.entriesSeen = stats.entriesSeen + 1
            local vehicle = resolveEntryVehicle(entry)
            if vehicle then
                stats.entriesResolved = stats.entriesResolved + 1
                tickOneVehicle(vehicle)
            else
                -- Unresolvable now (index stale / vehicle unloaded); the
                -- periodic full sweep catches it if it is actually live.
                stats.entriesUnresolved = stats.entriesUnresolved + 1
            end
        end
    end
end

local function applyPatch()
    if
        not (
            NMServerVehiclePowerTick
            and NMServerVehiclePowerTick.onEveryOneMinute
            and NMServerRegistryState
            and NMDeviceProfiles
            and NMDeviceState
            and NMVehicleHelpers
            and NMServerBatteryAuthority
            and NMRuntimeConfig
            and NMCore
        )
    then
        print(
            "[ATFPatches] Talis New Music not loaded (or shape changed); vehicle power registry sweep skipped."
        )
        return false
    end

    local originalFullSweep = NMServerVehiclePowerTick.onEveryOneMinute
    local minuteCounter = 0

    NMServerVehiclePowerTick.onEveryOneMinute = function()
        local stats = ATFPatchesTalisNMVehicleSweep.stats
        if minuteCounter % FULL_SWEEP_EVERY_N_MINUTES == 0 then
            stats.fullSweeps = stats.fullSweeps + 1
            minuteCounter = minuteCounter + 1
            originalFullSweep()
            return
        end
        minuteCounter = minuteCounter + 1
        registrySweep(stats)
    end

    print(
        "[ATFPatches] Talis New Music vehicle power tick now registry-driven (full sweep every "
            .. FULL_SWEEP_EVERY_N_MINUTES
            .. " minutes)."
    )
    return true
end

local function onFirstTick()
    Events.OnTick.Remove(onFirstTick)
    applyPatch()
end

Events.OnTick.Add(onFirstTick)
