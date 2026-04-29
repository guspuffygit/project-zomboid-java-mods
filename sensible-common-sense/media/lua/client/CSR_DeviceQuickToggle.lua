
require "CSR_FeatureFlags"

CSR_DeviceQuickToggle = CSR_DeviceQuickToggle or {}

if not CSR_FeatureFlags then
    return CSR_DeviceQuickToggle
end

local originalFillMenuOutsideVehicle = nil

local function createTooltip(name, description)
    local tooltip = ISToolTip:new()
    tooltip:initialise()
    tooltip:setVisible(false)
    tooltip:setName(name or "Device")
    tooltip.description = description or ""
    tooltip.maxLineWidth = 512
    return tooltip
end

local function getDeviceName(deviceData, fallback)
    if deviceData and deviceData.getDeviceName then
        local name = deviceData:getDeviceName()
        if name and name ~= "" then
            return name
        end
    end
    return fallback or "Device"
end

local function canUseDevice(deviceData)
    if not deviceData then
        return false
    end
    if deviceData:getIsBatteryPowered() then
        return deviceData:getPower() > 0
    end
    return deviceData:canBePoweredHere()
end

local function getToggleLabel(deviceData, prefix)
    local state = (deviceData and deviceData:getIsTurnedOn()) and "Turn Off" or "Turn On"
    if prefix and prefix ~= "" then
        return state .. " " .. prefix
    end
    return state
end

local function queueToggle(playerObj, device)
    if not playerObj or not device then
        return
    end
    ISTimedActionQueue.add(ISRadioAction:new("ToggleOnOff", playerObj, device))
end

local function addToggleOption(context, playerObj, device, prefix)
    if not context or not playerObj or not device or not device.getDeviceData then
        return nil
    end

    local deviceData = device:getDeviceData()
    if not deviceData then
        return nil
    end

    local option = context:addOption(getToggleLabel(deviceData, prefix), playerObj, queueToggle, device)
    local available = canUseDevice(deviceData)
    if not available then
        option.notAvailable = true
        option.toolTip = createTooltip(getDeviceName(deviceData, prefix), getText("IGUI_RadioRequiresPowerNearby"))
    else
        option.toolTip = createTooltip(
            getDeviceName(deviceData, prefix),
            deviceData:getIsTurnedOn() and "Quickly power this device off from the context menu."
                or "Quickly power this device on from the context menu."
        )
    end

    return option
end

local function playerCanReachWorldDevice(playerObj, object)
    return object and object.getSquare and object:getSquare() ~= nil and luautils.walkAdj(playerObj, object:getSquare(), false)
end

local function isPortableInventoryDevice(item)
    return item
        and item.getDeviceData
        and item:getDeviceData() ~= nil
        and item.isInPlayerInventory
        and item:isInPlayerInventory()
end

function CSR_DeviceQuickToggle.addWorldContext(playerNum, context, worldobjects, test)
    if test or not CSR_FeatureFlags.isQuickDeviceToggleEnabled() then
        return
    end

    local playerObj = getSpecificPlayer(playerNum)
    if not playerObj or not context or not worldobjects then
        return
    end

    local seen = {}
    for _, object in ipairs(worldobjects) do
        if object and object.getDeviceData and object:getDeviceData() and not seen[object] then
            if playerCanReachWorldDevice(playerObj, object) then
                addToggleOption(context, playerObj, object)
                seen[object] = true
            end
        end
    end
end

function CSR_DeviceQuickToggle.addInventoryContext(playerNum, context, items)
    if not CSR_FeatureFlags.isQuickDeviceToggleEnabled() then
        return
    end

    local playerObj = getSpecificPlayer(playerNum)
    if not playerObj or not context or not items then
        return
    end

    local actualItems = ISInventoryPane.getActualItems and ISInventoryPane.getActualItems(items) or items
    local seen = {}
    for i = 1, #actualItems do
        local item = actualItems[i]
        if isPortableInventoryDevice(item) and not seen[item] then
            addToggleOption(context, playerObj, item)
            seen[item] = true
        end
    end
end

local function getVehicleSignalParts(vehicle)
    local parts = {}
    if not vehicle then
        return parts
    end

    for i = 0, vehicle:getPartCount() - 1 do
        local part = vehicle:getPartByIndex(i)
        if part and part.getDeviceData and part:getDeviceData() and part:getInventoryItem() then
            parts[#parts + 1] = part
        end
    end

    return parts
end

local function addVehicleToggleOptions(context, playerObj, vehicle)
    local parts = getVehicleSignalParts(vehicle)
    if #parts == 0 then
        return
    end

    for i = 1, #parts do
        local part = parts[i]
        local deviceData = part:getDeviceData()
        local prefix = nil
        if #parts > 1 then
            prefix = getDeviceName(deviceData, part:getId())
        else
            prefix = "Vehicle Radio"
        end
        addToggleOption(context, playerObj, part, prefix)
    end
end

local function hookVehicleMenu()
    if not ISVehicleMenu or not ISVehicleMenu.FillMenuOutsideVehicle or ISVehicleMenu.__csr_device_toggle_patched then
        return
    end
    ISVehicleMenu.__csr_device_toggle_patched = true
    originalFillMenuOutsideVehicle = ISVehicleMenu.FillMenuOutsideVehicle

    ISVehicleMenu.FillMenuOutsideVehicle = function(player, context, vehicle, test)
        local result = originalFillMenuOutsideVehicle(player, context, vehicle, test)

        if not test and CSR_FeatureFlags.isQuickDeviceToggleEnabled() then
            local playerObj = getSpecificPlayer(player)
            if playerObj and context and vehicle then
                addVehicleToggleOptions(context, playerObj, vehicle)
            end
        end

        return result
    end
end

if Events then
    if Events.OnFillWorldObjectContextMenu then
        Events.OnFillWorldObjectContextMenu.Add(CSR_DeviceQuickToggle.addWorldContext)
    end
    if Events.OnFillInventoryObjectContextMenu then
        Events.OnFillInventoryObjectContextMenu.Add(CSR_DeviceQuickToggle.addInventoryContext)
    end
    if Events.OnGameStart then
        Events.OnGameStart.Add(hookVehicleMenu)
    end
end

return CSR_DeviceQuickToggle
