require "CSR_FeatureFlags"

CSR_EatAllStack = {}

local function getActualSelection(items)
    if ISInventoryPane and ISInventoryPane.getActualItems then
        return ISInventoryPane.getActualItems(items)
    end
    return items or {}
end

local function isFoodSafeForStack(item, playerObj)
    if not item or not instanceof(item, "Food") then
        return false
    end

    local scriptItem = item.getScriptItem and item:getScriptItem() or nil
    if scriptItem and scriptItem.isCantEat and scriptItem:isCantEat() then
        return false
    end

    if item.getHungChange and item:getHungChange() >= 0 then
        return false
    end

    if item.isBurnt and item:isBurnt() then
        return false
    end

    if item.isRotten and item:isRotten() then
        return false
    end

    if playerObj and playerObj.isKnownPoison and playerObj:isKnownPoison(item) then
        return false
    end

    local dangerousRaw = false
    if item.isbDangerousUncooked and item:isbDangerousUncooked() then
        dangerousRaw = true
    elseif item.isDangerousUncooked and item:isDangerousUncooked() then
        dangerousRaw = true
    end
    if dangerousRaw and item.isCooked and not item:isCooked() then
        return false
    end

    if item.isSpice and item:isSpice() then
        return false
    end

    return true
end

local function getValidFoods(items, playerObj)
    local actualItems = getActualSelection(items)
    local valid = {}

    for i = 1, #actualItems do
        local item = actualItems[i]
        if isFoodSafeForStack(item, playerObj) then
            valid[#valid + 1] = item
        end
    end

    return valid
end

local function findEatSubMenu(context)
    if not context or not context.options then
        return nil
    end

    -- Try vanilla API first
    local eatName = getText("ContextMenu_Eat")
    local openEatName = getText("ContextMenu_OpenAndEat")
    local names = { eatName, openEatName, "Open and eat", "Open and Eat" }

    for _, name in ipairs(names) do
        local option = context:getOptionFromName(name)
        if option and option.subOption then
            return context:getSubMenu(option.subOption)
        end
    end

    -- Fallback: scan for any food-related option with a submenu
    -- (covers custom menu options like "Drink")
    for i = 1, #context.options do
        local option = context.options[i]
        if option and option.subOption and not option.notAvailable then
            local sub = context:getSubMenu(option.subOption)
            if sub then
                -- Check if this submenu has an "All" option (vanilla eat submenu always does)
                local allName = getText("ContextMenu_Eat_All")
                if sub:getOptionFromName(allName) then
                    return sub
                end
            end
        end
    end

    return nil
end

local function queueEatAll(playerObj, validFoods)
    if not playerObj or not validFoods then
        return
    end

    for i = 1, #validFoods do
        local item = validFoods[i]
        if item then
            ISInventoryPaneContextMenu.transferIfNeeded(playerObj, item)
            ISTimedActionQueue.add(ISEatFoodAction:new(playerObj, item, 1.0))
        end
    end
end

function CSR_EatAllStack.addContextOption(player, context, items)
    if not CSR_FeatureFlags.isEatAllStackEnabled() then
        return
    end

    local playerObj = getSpecificPlayer(player)
    if not playerObj or not context or not items then
        return
    end

    local validFoods = getValidFoods(items, playerObj)
    if #validFoods <= 1 then
        return
    end

    local subMenu = findEatSubMenu(context)
    if not subMenu then
        return
    end

    local option = subMenu:addOption("All (Stack)", playerObj, queueEatAll, validFoods)
    option.toolTip = ISInventoryPaneContextMenu.addToolTip and ISInventoryPaneContextMenu.addToolTip() or nil
    if option.toolTip then
        option.toolTip.description = string.format("Queue eating all %d safe items in this selected stack.", #validFoods)
    end
end

Events.OnFillInventoryObjectContextMenu.Add(CSR_EatAllStack.addContextOption)

return CSR_EatAllStack
