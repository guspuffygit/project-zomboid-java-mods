CSR_TransferAmount = {}


local function newTransferAction(playerObj, item, src, dest)
    if not playerObj or not item or not src or not dest then
        return nil
    end

    if ISInventoryTransferUtil and ISInventoryTransferUtil.newInventoryTransferAction then
        return ISInventoryTransferUtil.newInventoryTransferAction(playerObj, item, src, dest)
    end

    if ISInventoryTransferAction then
        return ISInventoryTransferAction:new(playerObj, item, src, dest)
    end

    return nil
end

local function getActualItems(items)
    if ISInventoryPane and ISInventoryPane.getActualItems then
        return ISInventoryPane.getActualItems(items)
    end
    return items or {}
end

local function countTransferableToInventory(items, player)
    local actualItems = getActualItems(items)
    local playerInv = getPlayerInventory(player) and getPlayerInventory(player).inventory or nil
    local count = 0
    if not playerInv then
        return 0
    end

    for _, item in ipairs(actualItems) do
        if item and item.getContainer and item:getContainer() ~= playerInv and not isForceDropHeavyItem(item) then
            count = count + 1
        end
    end

    return count
end

local function countTransferableToLoot(items, player)
    local actualItems = getActualItems(items)
    local loot = getPlayerLoot(player)
    local lootInv = loot and loot.inventory or nil
    local playerObj = getSpecificPlayer(player)
    local count = 0
    if not lootInv or not playerObj then
        return 0
    end

    for _, item in ipairs(actualItems) do
        if item and item.getContainer and item:getContainer() and item:getContainer():isInCharacterInventory(playerObj) and lootInv:isItemAllowed(item) and not item:isFavorite() then
            count = count + 1
        end
    end

    return count
end

local function queueGrabAmount(items, player, amount)
    local actualItems = getActualItems(items)
    local playerObj = getSpecificPlayer(player)
    local playerInv = getPlayerInventory(player) and getPlayerInventory(player).inventory or nil
    if not playerObj or not playerInv then
        return
    end

    local queued = 0
    local didWalk = false
    for _, item in ipairs(actualItems) do
        if item and item.getContainer and item:getContainer() ~= playerInv and not isForceDropHeavyItem(item) then
            if not didWalk then
                if not luautils.walkToContainer(item:getContainer(), player) then
                    return
                end
                didWalk = true
            end
            local action = newTransferAction(playerObj, item, item:getContainer(), playerInv)
            if action then
                ISTimedActionQueue.add(action)
            end
            queued = queued + 1
            if queued >= amount then
                break
            end
        end
    end
end

local function queuePutAmount(items, player, amount)
    local actualItems = getActualItems(items)
    local playerObj = getSpecificPlayer(player)
    local loot = getPlayerLoot(player)
    local lootInv = loot and loot.inventory or nil
    if not playerObj or not lootInv then
        return
    end

    local queued = 0
    local didWalk = false
    for _, item in ipairs(actualItems) do
        if item and item.getContainer and item:getContainer() and item:getContainer():isInCharacterInventory(playerObj) and lootInv:isItemAllowed(item) and not item:isFavorite() then
            if not didWalk then
                if not luautils.walkToContainer(lootInv, player) then
                    return
                end
                didWalk = true
            end
            local action = newTransferAction(playerObj, item, item:getContainer(), lootInv)
            if action then
                ISTimedActionQueue.add(action)
            end
            queued = queued + 1
            if queued >= amount then
                break
            end
        end
    end
end

local function openAmountPrompt(player, maxAmount, actionLabel, onAccept)
    local width = 320
    local height = 180
    local prompt = string.format("%s (1-%d)", actionLabel, maxAmount)

    local function onClickCallback(target, button)
        if button.internal == "OK" then
            local text = button.parent.entry:getText()
            local value = tonumber(text or "")
            if value then
                value = math.floor(value)
                if value < 1 then
                    value = 1
                end
                if value > maxAmount then
                    value = maxAmount
                end
                onAccept(value)
            end
        end
    end

    local modal = ISTextBox:new((getCore():getScreenWidth() - width) / 2, (getCore():getScreenHeight() - height) / 2, width, height, prompt, tostring(maxAmount), nil, onClickCallback)
    modal:initialise()
    modal:addToUIManager()

    if modal.entry then
        modal.entry:setOnlyNumbers(true)
    end

    if JoypadState.players[player + 1] then
        setJoypadFocus(player, modal)
    end
end

function CSR_TransferAmount.addContextOptions(player, context, items)
    if not context or not items then
        return
    end

    local loot = getPlayerLoot(player)
    local lootInv = loot and loot.inventory or nil
    local playerObj = getSpecificPlayer(player)
    if not playerObj then
        return
    end

    local grabCount = countTransferableToInventory(items, player)
    if grabCount > 1 then
        local option = context:addOptionOnTop(string.format("Grab Amount (%d)", grabCount), items, function(selectedItems, playerNum)
            openAmountPrompt(playerNum, grabCount, "Grab how many?", function(amount)
                queueGrabAmount(selectedItems, playerNum, amount)
            end)
        end, player)
        option.toolTip = ISInventoryPaneContextMenu.addToolTip and ISInventoryPaneContextMenu.addToolTip() or nil
        if option.toolTip then
            option.toolTip.description = string.format("Transfer a chosen number of the %d selected items into your inventory.", grabCount)
        end
    end

    local putCount = countTransferableToLoot(items, player)
    if lootInv and putCount > 1 and ISInventoryPaneContextMenu.isAnyAllowed(lootInv, items) and not ISInventoryPaneContextMenu.isAllFav(getActualItems(items)) then
        local label = loot.title and string.format("Put Amount (%s, %d)", loot.title, putCount) or string.format("Put Amount (%d)", putCount)
        local option = context:addOption(label, items, function(selectedItems, playerNum)
            openAmountPrompt(playerNum, putCount, "Put how many?", function(amount)
                queuePutAmount(selectedItems, playerNum, amount)
            end)
        end, player)
        option.toolTip = ISInventoryPaneContextMenu.addToolTip and ISInventoryPaneContextMenu.addToolTip() or nil
        if option.toolTip then
            option.toolTip.description = string.format("Transfer a chosen number of the %d selected items into the open container.", putCount)
        end
    end
end

Events.OnFillInventoryObjectContextMenu.Add(CSR_TransferAmount.addContextOptions)

return CSR_TransferAmount
