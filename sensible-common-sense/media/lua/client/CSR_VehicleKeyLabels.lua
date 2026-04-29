require "CSR_FeatureFlags"

CSR_VehicleKeyLabels = {}

local function safeCall(obj, fnName, ...)
    if not obj or type(obj[fnName]) ~= "function" then
        return nil
    end
    return obj[fnName](obj, ...)
end

local function getVehicleStats(vehicle)
    if not vehicle then
        return nil
    end

    local script = safeCall(vehicle, "getScript")
    if not script then
        return nil
    end

    local model = safeCall(script, "getCarModelName") or safeCall(script, "getName") or safeCall(vehicle, "getScriptName")
    if not model or model == "" then
        return nil
    end
    model = tostring(model):gsub("^Base%.", "")

    local totalCond = 0
    local partCount = 0
    local count = safeCall(vehicle, "getPartCount") or 0
    for i = 1, count do
        local part = vehicle:getPartByIndex(i - 1)
        if part and (safeCall(part, "getCategory") or "") ~= "nodisplay" then
            totalCond = totalCond + (safeCall(part, "getCondition") or 0)
            partCount = partCount + 1
        end
    end

    local avgCond = partCount > 0 and math.floor(totalCond / partCount) or 0
    local fuelPct = 0
    local gasTank = safeCall(vehicle, "getPartById", "GasTank")
    if gasTank then
        local cap = safeCall(gasTank, "getContainerCapacity") or 0
        local amount = safeCall(gasTank, "getContainerContentAmount") or 0
        if cap > 0 then
            fuelPct = math.floor((amount / cap) * 100)
        end
    end

    return { model = model, condition = avgCond, fuel = fuelPct }
end

local function findKeyById(playerObj, keyId)
    if not playerObj or not keyId then
        return nil
    end

    local inv = playerObj:getInventory()
    if not inv then
        return nil
    end

    local items = inv:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item and safeCall(item, "getKeyId") == keyId then
            return item
        end
    end
    return nil
end

local function updateVehicleKeyLabel(playerObj, vehicle)
    if not CSR_FeatureFlags.isSmartVehicleKeyLabelsEnabled() or not playerObj or not vehicle then
        return
    end

    local keyId = safeCall(vehicle, "getKeyId")
    if not keyId or keyId == -1 then
        return
    end

    local key = findKeyById(playerObj, keyId)
    if not key then
        return
    end

    local stats = getVehicleStats(vehicle)
    if not stats then
        return
    end

    local label = string.format("%s (C:%d%%|F:%d%%)", stats.model, stats.condition, stats.fuel)
    local modData = key:getModData()
    modData.CSR_OriginalKeyName = modData.CSR_OriginalKeyName or key:getName()

    if modData.CSR_KeyLabel == label then
        return
    end

    modData.CSR_KeyLabel = label
    key:setName(label)
end

local function onEnterVehicle(character)
    if character and instanceof(character, "IsoPlayer") then
        updateVehicleKeyLabel(character, character:getVehicle())
    end
end

local function hookVehicleMenus()
    if not ISVehicleMenu then
        return
    end

    if ISVehicleMenu.showRadialMenu and not ISVehicleMenu.__csr_keylabel_inside then
        ISVehicleMenu.__csr_keylabel_inside = true
        local original = ISVehicleMenu.showRadialMenu
        ISVehicleMenu.showRadialMenu = function(playerObj, ...)
            updateVehicleKeyLabel(playerObj, playerObj and playerObj:getVehicle() or nil)
            return original(playerObj, ...)
        end
    end

    if ISVehicleMenu.showRadialMenuOutside and not ISVehicleMenu.__csr_keylabel_outside then
        ISVehicleMenu.__csr_keylabel_outside = true
        local original = ISVehicleMenu.showRadialMenuOutside
        ISVehicleMenu.showRadialMenuOutside = function(playerObj, ...)
            local vehicle = ISVehicleMenu.getVehicleToInteractWith and ISVehicleMenu.getVehicleToInteractWith(playerObj) or nil
            updateVehicleKeyLabel(playerObj, vehicle)
            return original(playerObj, ...)
        end
    end
end

if Events then
    if Events.OnEnterVehicle then Events.OnEnterVehicle.Add(onEnterVehicle) end
    if Events.OnGameStart then Events.OnGameStart.Add(hookVehicleMenus) end
end

return CSR_VehicleKeyLabels
