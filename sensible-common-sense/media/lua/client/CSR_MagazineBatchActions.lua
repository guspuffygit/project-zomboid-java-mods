
require "CSR_FeatureFlags"

CSR_MagazineBatchActions = {}

local vanillaDoMagazineMenu = nil

local function getMagazineKey(magazine)
    if not magazine then
        return nil
    end
    if magazine.getFullType then
        return magazine:getFullType()
    end
    return magazine.getType and magazine:getType() or nil
end

local function collectMagazinesRecursive(inventory, magazineKey, results)
    if not inventory or not magazineKey or not results then
        return
    end

    local items = inventory:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if getMagazineKey(item) == magazineKey then
            results[#results + 1] = item
        elseif instanceof(item, "InventoryContainer") and item:getInventory() then
            collectMagazinesRecursive(item:getInventory(), magazineKey, results)
        end
    end
end

local function getMagazineCandidates(playerObj, magazine)
    local results = {}
    if not playerObj or not playerObj:getInventory() then
        return results
    end

    collectMagazinesRecursive(playerObj:getInventory(), getMagazineKey(magazine), results)

    table.sort(results, function(a, b)
        local aAmmo = a and a.getCurrentAmmoCount and a:getCurrentAmmoCount() or 0
        local bAmmo = b and b.getCurrentAmmoCount and b:getCurrentAmmoCount() or 0
        if aAmmo == bAmmo then
            local aName = a and a.getName and a:getName() or ""
            local bName = b and b.getName and b:getName() or ""
            return aName < bName
        end
        return aAmmo > bAmmo
    end)

    return results
end

local function getRemainingAmmoCount(playerObj, ammoKey, reserved)
    if not playerObj or not playerObj:getInventory() or not ammoKey then
        return 0
    end
    local total = playerObj:getInventory():getItemCountRecurse(ammoKey)
    return math.max(0, total - (reserved or 0))
end

local function getAmmoSlice(allAmmoItems, startIndex, amount)
    local ammoItems = ArrayList.new()
    if not allAmmoItems or amount <= 0 then
        return ammoItems
    end

    for i = startIndex, startIndex + amount - 1 do
        if i >= allAmmoItems:size() then
            break
        end
        ammoItems:add(allAmmoItems:get(i))
    end

    return ammoItems
end

local function countLoadableMagazines(magazines)
    local count = 0
    for i = 1, #magazines do
        local magazine = magazines[i]
        if magazine and magazine:getCurrentAmmoCount() < magazine:getMaxAmmo() then
            count = count + 1
        end
    end
    return count
end

local function countUnloadableMagazines(magazines)
    local count = 0
    for i = 1, #magazines do
        local magazine = magazines[i]
        if magazine and magazine:getCurrentAmmoCount() > 0 then
            count = count + 1
        end
    end
    return count
end

function CSR_MagazineBatchActions.onLoadAllMagazines(playerObj, magazine)
    if not playerObj or not magazine or not playerObj:getInventory() then
        return
    end

    local ammoType = magazine.getAmmoType and magazine:getAmmoType() or nil
    local ammoKey = ammoType and ammoType:getItemKey() or nil
    if not ammoKey then
        return
    end

    local magazines = getMagazineCandidates(playerObj, magazine)
    if #magazines <= 1 then
        return
    end

    local allAmmoCount = playerObj:getInventory():getItemCountRecurse(ammoKey)
    if allAmmoCount <= 0 then
        return
    end

    local allAmmoItems = playerObj:getInventory():getSomeTypeRecurse(ammoKey, allAmmoCount)
    local reservedAmmo = 0

    for i = 1, #magazines do
        local candidate = magazines[i]
        local missing = candidate:getMaxAmmo() - candidate:getCurrentAmmoCount()
        if missing > 0 then
            local available = getRemainingAmmoCount(playerObj, ammoKey, reservedAmmo)
            local ammoCount = math.min(missing, available)
            if ammoCount > 0 then
                ISInventoryPaneContextMenu.transferIfNeeded(playerObj, candidate)
                local ammoItems = getAmmoSlice(allAmmoItems, reservedAmmo, ammoCount)
                ISInventoryPaneContextMenu.transferIfNeeded(playerObj, ammoItems)
                ISTimedActionQueue.add(ISLoadBulletsInMagazine:new(playerObj, candidate, ammoCount))
                reservedAmmo = reservedAmmo + ammoCount
            end
        end
    end
end

function CSR_MagazineBatchActions.onUnloadAllMagazines(playerObj, magazine)
    if not playerObj or not magazine or not playerObj:getInventory() then
        return
    end

    local magazines = getMagazineCandidates(playerObj, magazine)
    if #magazines <= 1 then
        return
    end

    for i = 1, #magazines do
        local candidate = magazines[i]
        if candidate:getCurrentAmmoCount() > 0 then
            ISInventoryPaneContextMenu.transferIfNeeded(playerObj, candidate)
            ISTimedActionQueue.add(ISUnloadBulletsFromMagazine:new(playerObj, candidate))
        end
    end
end

local function buildLoadTooltip(playerObj, magazines, ammoKey)
    local tooltip = ISInventoryPaneContextMenu.addToolTip and ISInventoryPaneContextMenu.addToolTip() or nil
    if not tooltip then
        return nil
    end

    local loadable = countLoadableMagazines(magazines)
    local ammoCount = playerObj:getInventory():getItemCountRecurse(ammoKey)
    tooltip.description = string.format(
        "Queue vanilla reload actions for %d matching magazines using %d available rounds.",
        loadable,
        ammoCount
    )
    return tooltip
end

local function buildUnloadTooltip(magazines)
    local tooltip = ISInventoryPaneContextMenu.addToolTip and ISInventoryPaneContextMenu.addToolTip() or nil
    if not tooltip then
        return nil
    end

    local unloadable = countUnloadableMagazines(magazines)
    tooltip.description = string.format(
        "Queue vanilla unload actions for %d matching magazines in your inventory and bags.",
        unloadable
    )
    return tooltip
end

local function initMagazinePatch()
    if not ISInventoryPaneContextMenu or not ISInventoryPaneContextMenu.doMagazineMenu or ISInventoryPaneContextMenu.__csr_magazine_patched then
        return
    end
    ISInventoryPaneContextMenu.__csr_magazine_patched = true
    vanillaDoMagazineMenu = ISInventoryPaneContextMenu.doMagazineMenu

    ISInventoryPaneContextMenu.doMagazineMenu = function(playerObj, magazine, context)
        vanillaDoMagazineMenu(playerObj, magazine, context)

    if not CSR_FeatureFlags.isMagazineBatchActionsEnabled() then
        return
    end

    if not playerObj or not magazine or not context then
        return
    end

    local magazines = getMagazineCandidates(playerObj, magazine)
    if #magazines <= 1 then
        return
    end

    local ammoType = magazine.getAmmoType and magazine:getAmmoType() or nil
    local ammoKey = ammoType and ammoType:getItemKey() or nil
    local loadable = countLoadableMagazines(magazines)
    local unloadable = countUnloadableMagazines(magazines)

    if ammoKey and loadable > 0 and playerObj:getInventory():getItemCountRecurse(ammoKey) > 0 then
        local loadOption = context:addOption(
            string.format("Load All Magazines (%d)", loadable),
            playerObj,
            CSR_MagazineBatchActions.onLoadAllMagazines,
            magazine
        )
        loadOption.toolTip = buildLoadTooltip(playerObj, magazines, ammoKey)
    end

    if unloadable > 1 then
        local unloadOption = context:addOption(
            string.format("Unload All Magazines (%d)", unloadable),
            playerObj,
            CSR_MagazineBatchActions.onUnloadAllMagazines,
            magazine
        )
        unloadOption.toolTip = buildUnloadTooltip(magazines)
    end
end
end

if Events and Events.OnGameStart then
    Events.OnGameStart.Add(initMagazinePatch)
end

return CSR_MagazineBatchActions
