require "CSR_FeatureFlags"

--[[
    CSR_ItemRename.lua
    Adds "Rename" to the right-click context menu of any inventory item.
    Uses setCustomName(true) + setName() to persist the custom name across saves.
    Includes "Reset Name" to revert to the original script-defined name.
]]

CSR_ItemRename = CSR_ItemRename or {}

local function getFirstItem(items)
    if ISInventoryPane and ISInventoryPane.getActualItems then
        items = ISInventoryPane.getActualItems(items)
    end
    if items and #items > 0 then
        return items[1]
    end
    return nil
end

local function getOriginalName(item)
    if not item then return "Item" end
    local scriptItem = item:getScriptItem()
    if scriptItem and scriptItem.getDisplayName then
        return scriptItem:getDisplayName()
    end
    return item:getName() or "Item"
end

local function onRenameItem(player, item)
    if not player or not item then return end

    local currentName = item:getName() or ""
    local modal = ISTextBox:new(0, 0, 280, 180, "Enter new name:", currentName, nil,
        function(target, button, obj)
            if button.internal == "OK" then
                local newName = button.parent:getText()
                if newName and newName ~= "" then
                    -- Sanitize: strip leading/trailing whitespace, limit length
                    newName = string.match(newName, "^%s*(.-)%s*$") or newName
                    if #newName > 80 then
                        newName = string.sub(newName, 1, 80)
                    end
                    if #newName > 0 then
                        -- Store original name for reset
                        local modData = obj:getModData()
                        if not modData["CSR_OriginalItemName"] then
                            modData["CSR_OriginalItemName"] = getOriginalName(obj)
                        end
                        if obj.setCustomName then
                            obj:setCustomName(true)
                        end
                        obj:setName(newName)

                        -- MP sync
                        if isClient() then
                            sendClientCommand(player, "CSR_ItemRename", "rename", {
                                itemId = obj:getID(),
                                newName = newName,
                            })
                        end
                    end
                end
            end
        end)
    modal:setValidateFunction(nil, function(str)
        return str and #str > 0 and #str <= 80
    end)
    modal.obj = item
    modal:initialise()
    modal:addToUIManager()
end

local function onResetName(player, item)
    if not player or not item then return end

    local modData = item:getModData()
    local origName = modData["CSR_OriginalItemName"]
    if not origName then
        origName = getOriginalName(item)
    end

    item:setName(origName)
    if item.setCustomName then
        item:setCustomName(false)
    end
    modData["CSR_OriginalItemName"] = nil

    -- MP sync
    if isClient() then
        sendClientCommand(player, "CSR_ItemRename", "reset", {
            itemId = item:getID(),
        })
    end
end

function CSR_ItemRename.addContextOption(playerNum, context, items)
    if not CSR_FeatureFlags or not CSR_FeatureFlags.isItemRenameEnabled then return end
    if not CSR_FeatureFlags.isItemRenameEnabled() then return end

    local item = getFirstItem(items)
    if not item then return end

    local player = getSpecificPlayer(playerNum)
    if not player then return end

    context:addOption("Rename Item", player, onRenameItem, item)

    -- Show "Reset Name" if item has a custom name
    local modData = item:getModData()
    if modData["CSR_OriginalItemName"] then
        context:addOption("Reset Item Name", player, onResetName, item)
    end
end

if Events and Events.OnFillInventoryObjectContextMenu then
    Events.OnFillInventoryObjectContextMenu.Add(CSR_ItemRename.addContextOption)
end

return CSR_ItemRename
