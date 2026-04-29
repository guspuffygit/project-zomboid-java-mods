
require "CSR_Utils"
require "CSR_FeatureFlags"
require "TimedActions/CSR_UnHotwireAction"

CSR_VehicleHotwire = CSR_VehicleHotwire or {}

local function canAddImprovisedHotwire(playerObj, vehicle)
    return CSR_FeatureFlags.isImprovisedHotwireEnabled()
        and vehicle ~= nil
        and CSR_Utils.canAttemptImprovisedHotwire(playerObj, vehicle)
end

local function canAddUnHotwire(playerObj, vehicle)
    if not CSR_FeatureFlags.isUnHotwireEnabled() then return false end
    if not vehicle then return false end
    if not vehicle:isDriver(playerObj) then return false end
    if vehicle:isEngineRunning() or vehicle:isEngineStarted() then return false end
    return vehicle:isHotwired() == true
end

local function addImprovisedHotwireSlice(playerObj)
    local vehicle = playerObj and playerObj:getVehicle() or nil
    local menu = getPlayerRadialMenu(playerObj:getPlayerNum())
    if not menu then
        return
    end

    if not canAddImprovisedHotwire(playerObj, vehicle) then
        return
    end

    local screwdriver = CSR_Utils.hasScrewdriver(playerObj)
    if not screwdriver then
        return
    end

    menu:addSlice("Attempt Hotwire", getTexture("media/ui/vehicles/vehicle_ignitionON.png"), CSR_VehicleHotwire.onImprovisedHotwire, playerObj, screwdriver)
end

local function addUnHotwireSlice(playerObj)
    local vehicle = playerObj and playerObj:getVehicle() or nil
    local menu = getPlayerRadialMenu(playerObj:getPlayerNum())
    if not menu then return end
    if not canAddUnHotwire(playerObj, vehicle) then return end

    local screwdriver = CSR_Utils.hasScrewdriver(playerObj)
    if not screwdriver then return end

    menu:addSlice("Remove Hotwire", getTexture("media/ui/vehicles/vehicle_ignitionOFF.png"), CSR_VehicleHotwire.onUnHotwire, playerObj, screwdriver)
end

function CSR_VehicleHotwire.onImprovisedHotwire(playerObj, screwdriver)
    if not playerObj then
        return
    end

    if CSR_ImprovisedHotwireAction then
        ISTimedActionQueue.add(CSR_ImprovisedHotwireAction:new(playerObj, screwdriver))
    end
end

function CSR_VehicleHotwire.onUnHotwire(playerObj, screwdriver)
    if not playerObj then return end
    if CSR_UnHotwireAction then
        ISTimedActionQueue.add(CSR_UnHotwireAction:new(playerObj, screwdriver))
    end
end

local function hookShowRadialMenu()
    if not ISVehicleMenu or not ISVehicleMenu.showRadialMenu or ISVehicleMenu.__csr_hotwire_patched then
        return
    end
    ISVehicleMenu.__csr_hotwire_patched = true
    local original_showRadialMenu = ISVehicleMenu.showRadialMenu
    function ISVehicleMenu.showRadialMenu(playerObj)
        original_showRadialMenu(playerObj)

        -- Only inject when player is inside a vehicle (radial was built, not toggled off)
        local vehicle = playerObj and playerObj:getVehicle() or nil
        if vehicle then
            addImprovisedHotwireSlice(playerObj)
            addUnHotwireSlice(playerObj)
        end
    end
end

if Events and Events.OnGameStart then
    Events.OnGameStart.Add(hookShowRadialMenu)
end

return CSR_VehicleHotwire
