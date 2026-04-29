
require "CSR_Utils"


local function csrRoundAmount(value)
    if not value then
        return nil
    end

    local rounded = round(value, 1)
    if math.abs(rounded - math.floor(rounded)) < 0.05 then
        return tostring(math.floor(rounded))
    end

    return tostring(rounded)
end

local function csrGetRemainingLabel(item, recipe, cookingLvl)
    if not item or not recipe then
        return ""
    end

    local parts = {}
    local remaining = nil
    local okRemaining, rem = pcall(CSR_Utils.getRemainingConsumableAmount, item)
    if okRemaining then
        remaining = rem
    end
    if remaining then
        parts[#parts + 1] = "Remaining: " .. csrRoundAmount(remaining)
    end

    -- Build 42.17 compatibility: vanilla getRealEvolvedItemUse can throw
    -- uncaught Java runtime errors on stale item refs in MP context menus.
    -- Keep the remaining amount label and skip volatile "Use" probing.

    return table.concat(parts, ", ")
end

local function csrIsSelectableItem(evoItem, recipe)
    if instanceof(evoItem, "Food") and evoItem:isFrozen() and not recipe:isAllowFrozenItem() then
        return false
    end

    if not recipe:needToBeCooked(evoItem) then
        return false
    end

    return true
end

local function csrChooseDefaultEntry(group, recipe)
    for i = 1, #group.items do
        if csrIsSelectableItem(group.items[i].item, recipe) then
            return group.items[i]
        end
    end

    return group.items[1]
end

local function csrActionText(baseItem, sampleItem, recipe)
    local isSpice = instanceof(sampleItem, "Food") and sampleItem.isSpice and sampleItem:isSpice()
    if recipe:isResultItem(baseItem) then
        return isSpice and ("Add Seasoning: " .. sampleItem:getName()) or ("Add Ingredient: " .. sampleItem:getName())
    end

    return isSpice and ("Create From Seasoning: " .. sampleItem:getName()) or ("Create From Ingredient: " .. sampleItem:getName())
end

local function csrMakeParentText(baseItem, sampleItem, recipe, count)
    local txt = csrActionText(baseItem, sampleItem, recipe)
    if count and count > 1 then
        txt = txt .. " (" .. tostring(count) .. ")"
    end
    return txt
end

local function csrAddSpecificItemOption(subMenuRecipe, baseItem, evoItem, label, recipe, player)
    local option = subMenuRecipe:addOption(label, recipe, ISInventoryPaneContextMenu.onAddItemInEvoRecipe, baseItem, evoItem, player)
    local tooltip = ISInventoryPaneContextMenu.addToolTip()

    if instanceof(evoItem, "Food") and evoItem:isFrozen() and not recipe:isAllowFrozenItem() then
        option.notAvailable = true
        tooltip.description = getText("ContextMenu_CantAddFrozenFood")
        option.toolTip = tooltip
    end

    if not recipe:needToBeCooked(evoItem) then
        option.notAvailable = true
        if string.len(tooltip.description) > 0 then
            tooltip.description = tooltip.description .. " <BR> "
        end
        tooltip.description = tooltip.description .. getText("ContextMenu_NeedCooked")
        option.toolTip = tooltip
    end

    option.itemForTexture = evoItem
    return option
end

local function csrSortEntries(a, b)
    if instanceof(a.item, "Food") and instanceof(b.item, "Food") and a.item:isCooked() ~= b.item:isCooked() then
        return a.item:isCooked()
    end

    if CSR_Utils.compareConsumablePriority(a.item, b.item) then
        return true
    end

    if CSR_Utils.compareConsumablePriority(b.item, a.item) then
        return false
    end

    return (a.index or 0) < (b.index or 0)
end

local function initEvolvedRecipePatch()
    if not ISInventoryPaneContextMenu or ISInventoryPaneContextMenu.__csr_evorecipe_patched then
        return
    end
    ISInventoryPaneContextMenu.__csr_evorecipe_patched = true

    function ISInventoryPaneContextMenu.doEvorecipeMenu(context, items, player, evorecipe, baseItem, containerList)
    for i = 0, evorecipe:size() - 1 do
        local recipe = evorecipe:get(i)
        local availableItems = recipe:getItemsCanBeUse(getSpecificPlayer(player), baseItem, containerList)
        if availableItems:size() == 0 then
            break
        end

        local catList = ISInventoryPaneContextMenu.getEvoItemCategories(availableItems, recipe)
        local cookingLvl = getSpecificPlayer(player):getPerkLevel(Perks.Cooking)
        local fromName = getText("ContextMenu_EvolvedRecipe_" .. recipe:getUntranslatedName())
        local subOption
        if recipe:isResultItem(baseItem) then
            subOption = context:addOption(fromName, nil)
        else
            subOption = context:addOption(getText("ContextMenu_Create_From_Ingredient", fromName), nil)
        end

        local subMenuRecipe = context:getNew(context)
        context:addSubMenu(subOption, subMenuRecipe)

        for category, categoryItems in pairs(catList) do
            if getText("ContextMenu_FoodType_" .. category) ~= "ContextMenu_FoodType_" .. category then
                local txt = getText("ContextMenu_FromRandom", getText("ContextMenu_FoodType_" .. category))
                if recipe:isResultItem(baseItem) then
                    txt = getText("ContextMenu_AddRandom", getText("ContextMenu_FoodType_" .. category))
                end
                subMenuRecipe:addOption(txt, recipe, ISInventoryPaneContextMenu.onAddItemInEvoRecipe, baseItem, categoryItems[ZombRand(1, #categoryItems + 1)], player)
            end
        end

        local groupedEntries = {}
        local groupedOrder = {}
        for itemIndex = 0, availableItems:size() - 1 do
            local evoItem = availableItems:get(itemIndex)
            if evoItem and evoItem ~= baseItem then
                local groupKey = evoItem:getFullType() or evoItem:getType() or evoItem:getName()
                if not groupedEntries[groupKey] then
                    groupedEntries[groupKey] = {
                        displayItem = evoItem,
                        items = {},
                    }
                    groupedOrder[#groupedOrder + 1] = groupKey
                end

                groupedEntries[groupKey].items[#groupedEntries[groupKey].items + 1] = {
                    item = evoItem,
                    index = itemIndex,
                }
            end
        end

        for orderIndex = 1, #groupedOrder do
            local group = groupedEntries[groupedOrder[orderIndex]]
            table.sort(group.items, csrSortEntries)

            if #group.items == 1 then
                local entry = group.items[1]
                local label = csrMakeParentText(baseItem, entry.item, recipe, nil)
                local remainingText = csrGetRemainingLabel(entry.item, recipe, cookingLvl)
                if remainingText ~= "" then
                    label = label .. " (" .. remainingText .. ")"
                end
                csrAddSpecificItemOption(subMenuRecipe, baseItem, entry.item, label, recipe, player)
            else
                local parentText = csrMakeParentText(baseItem, group.displayItem, recipe, #group.items)
                local leastEntry = csrChooseDefaultEntry(group, recipe)
                local groupOption = subMenuRecipe:addOption(parentText, recipe, ISInventoryPaneContextMenu.onAddItemInEvoRecipe, baseItem, leastEntry.item, player)
                groupOption.itemForTexture = group.displayItem

                local groupMenu = ISContextMenu:getNew(subMenuRecipe)
                subMenuRecipe:addSubMenu(groupOption, groupMenu)

                for entryIndex = 1, #group.items do
                    local entry = group.items[entryIndex]
                    local childLabel = csrGetRemainingLabel(entry.item, recipe, cookingLvl)
                    if childLabel == "" then
                        childLabel = entry.item:getName()
                    end
                    csrAddSpecificItemOption(groupMenu, baseItem, entry.item, childLabel, recipe, player)
                end
            end
        end
    end
end
end

if Events and Events.OnGameStart then
    Events.OnGameStart.Add(initEvolvedRecipePatch)
end
