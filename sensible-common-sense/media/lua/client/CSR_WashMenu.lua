require "CSR_FeatureFlags"

local originalDoWashClothingMenu = nil

local function getRequiredWater(item)
    if ISWashClothing and ISWashClothing.GetRequiredWater then
        return ISWashClothing.GetRequiredWater(item) or 0
    end
    return 0
end

local function getRequiredSoap(item)
    if ISWashClothing and ISWashClothing.GetRequiredSoap then
        return ISWashClothing.GetRequiredSoap(item) or 0
    end
    return 0
end

local function compareRequiredWater(itemA, itemB)
    local waterA = getRequiredWater(itemA)
    local waterB = getRequiredWater(itemB)
    if waterA == waterB then
        return (itemA:getDisplayName() or "") < (itemB:getDisplayName() or "")
    end
    return waterA < waterB
end

local function defineWashLists(playerObj, playerInv)
    local data = {
        all = {},
        equipped = {},
        unequipped = {},
        weapons = {},
    }

    local function pushItem(item, isWeapon)
        table.insert(data.all, item)
        if isWeapon then
            table.insert(data.weapons, item)
        end
        if playerObj:isEquipped(item) then
            table.insert(data.equipped, item)
        else
            table.insert(data.unequipped, item)
        end
    end

    local clothing = playerInv:getItemsFromCategory("Clothing")
    for i = 0, clothing:size() - 1 do
        local item = clothing:get(i)
        if not item:isHidden() and (item:hasBlood() or item:hasDirt()) then
            pushItem(item, false)
        end
    end

    local containers = playerInv:getItemsFromCategory("Container")
    for i = 0, containers:size() - 1 do
        local item = containers:get(i)
        if not item:isHidden() and (item:hasBlood() or item:hasDirt()) then
            pushItem(item, false)
        end
    end

    local weapons = playerInv:getItemsFromCategory("Weapon")
    for i = 0, weapons:size() - 1 do
        local item = weapons:get(i)
        if item:hasBlood() then
            pushItem(item, true)
        end
    end

    return data
end

local function onWashAndClose(playerObj, sink, soapList, washList, noSoap, context)
    ISWorldObjectContextMenu.onWashClothing(playerObj, sink, soapList, washList, nil, noSoap)
    context:closeAll()
end

local function buildWashSubset(list, waterRemaining)
    local subset = {}
    local soapRequired = 0
    local waterRequired = 0

    for i = 1, #list do
        local item = list[i]
        local itemWater = getRequiredWater(item)
        if waterRequired + itemWater <= waterRemaining then
            subset[#subset + 1] = item
            waterRequired = waterRequired + itemWater
            soapRequired = soapRequired + getRequiredSoap(item)
        end
    end

    return subset, soapRequired, waterRequired
end

local function addWashOption(parentMenu, label, playerObj, sink, soapList, washList, waterRemaining, soapRemaining, context)
    if #washList == 0 then
        return
    end

    local subset, soapRequired, waterRequired = buildWashSubset(washList, waterRemaining)
    if #subset == 0 then
        return
    end

    local noSoap = soapRemaining < soapRequired
    local displayLabel = label
    if #subset < #washList then
        displayLabel = string.format("%s (%d/%d)", label, #subset, #washList)
    elseif #washList > 1 then
        displayLabel = string.format("%s (%d)", label, #washList)
    end

    local option = parentMenu:addOption(displayLabel, playerObj, onWashAndClose, sink, soapList, subset, noSoap, context)
    local tooltip = ISWorldObjectContextMenu.addToolTip()
    local lines = {}

    if noSoap then
        lines[#lines + 1] = string.format("<RGB:1,0.5,0.5> %s: %s / %s", getText("IGUI_Washing_Soap"), tostring(math.floor(soapRemaining)), tostring(math.ceil(soapRequired)))
        lines[#lines + 1] = "<RGB:1,0.5,0.5> " .. getText("IGUI_Washing_WithoutSoap")
    else
        lines[#lines + 1] = string.format("<RGB:0.5,1,0.5> %s: %s / %s", getText("IGUI_Washing_Soap"), tostring(math.floor(soapRemaining)), tostring(math.ceil(soapRequired)))
    end

    lines[#lines + 1] = string.format("<RGB:0.5,1,0.5> %s: %s / %s", getText("ContextMenu_WaterName"), tostring(math.floor(waterRemaining)), tostring(math.ceil(waterRequired)))
    if #subset < #washList then
        lines[#lines + 1] = string.format("<RGB:1,1,1> Cleans %d of %d items with current water.", #subset, #washList)
    end

    local previewCount = math.min(#subset, 6)
    for i = 1, previewCount do
        lines[#lines + 1] = "<RGB:1,1,1> " .. getText("ContextMenu_WashClothing", subset[i]:getDisplayName())
    end
    if #subset > previewCount then
        lines[#lines + 1] = string.format("<RGB:1,1,1> ...and %d more", #subset - previewCount)
    end

    tooltip.description = table.concat(lines, " <LINE> ")
    option.toolTip = tooltip
end

local function initWashPatch()
    if not ISWorldObjectContextMenu or not ISWorldObjectContextMenu.doWashClothingMenu or ISWorldObjectContextMenu.__csr_wash_patched then
        return
    end
    ISWorldObjectContextMenu.__csr_wash_patched = true
    originalDoWashClothingMenu = ISWorldObjectContextMenu.doWashClothingMenu

    function ISWorldObjectContextMenu.doWashClothingMenu(sink, player, context)
        originalDoWashClothingMenu(sink, player, context)

    if not CSR_FeatureFlags.isWashMenuSplitEnabled() then
        return
    end

    local playerObj = getSpecificPlayer(player)
    if not playerObj or sink:getSquare():getBuilding() ~= playerObj:getBuilding() then
        return
    end

    local washData = defineWashLists(playerObj, playerObj:getInventory())
    if #washData.all <= 1 then
        return
    end

    local soapList = {}
    local soapBars = playerObj:getInventory():getItemsFromType("Soap2", true)
    for i = 0, soapBars:size() - 1 do
        table.insert(soapList, soapBars:get(i))
    end

    local cleaners = playerObj:getInventory():getItemsFromType("CleaningLiquid2", true)
    for i = 0, cleaners:size() - 1 do
        table.insert(soapList, cleaners:get(i))
    end

    table.sort(washData.all, compareRequiredWater)
    table.sort(washData.equipped, compareRequiredWater)
    table.sort(washData.unequipped, compareRequiredWater)
    table.sort(washData.weapons, compareRequiredWater)

    local soapRequired, waterRequired = ISWorldObjectContextMenu.calculateSoapAndWaterRequired(washData.all)
    local soapRemaining = ISWashClothing.GetSoapRemaining(soapList)
    local waterRemaining = sink:getFluidAmount()

    local mainSubMenu = nil
    local option = nil
    local submenuIndex = 1
    while option == nil do
        mainSubMenu = context:getSubMenu(submenuIndex)
        if mainSubMenu == nil then
            break
        end
        option = mainSubMenu:getOptionFromName(getText("ContextMenu_WashAllClothing"))
        submenuIndex = submenuIndex + 1
    end

    if not mainSubMenu or not option then
        return
    end

    local tooltip = ISWorldObjectContextMenu.addToolTip()
    tooltip.description = getText("IGUI_Washing_Soap") .. ": " .. tostring(math.min(math.floor(soapRemaining), math.ceil(soapRequired))) .. " / " .. tostring(math.ceil(soapRequired))
        .. " <LINE> " .. getText("ContextMenu_WaterName") .. ": " .. tostring(math.floor(waterRemaining)) .. " / " .. tostring(math.ceil(waterRequired))
        .. " <LINE> " .. "CSR splits wash targets and keeps partial options available when water is limited."
    option.toolTip = tooltip

    local splitMenu = ISContextMenu:getNew(context)
    context:addSubMenu(option, splitMenu)
    addWashOption(splitMenu, getText("ContextMenu_All"), playerObj, sink, soapList, washData.all, waterRemaining, soapRemaining, context)

    if #washData.equipped > 0 then
        addWashOption(splitMenu, getText("ContextMenu_WashEquippedOnly"), playerObj, sink, soapList, washData.equipped, waterRemaining, soapRemaining, context)
    end

    if #washData.unequipped > 0 then
        addWashOption(splitMenu, getText("ContextMenu_WashUnequippedOnly"), playerObj, sink, soapList, washData.unequipped, waterRemaining, soapRemaining, context)
    end

    if #washData.weapons > 0 then
        addWashOption(splitMenu, getText("ContextMenu_WashWeaponsOnly"), playerObj, sink, soapList, washData.weapons, waterRemaining, soapRemaining, context)
    end
end
end

if Events and Events.OnGameStart then
    Events.OnGameStart.Add(initWashPatch)
end
