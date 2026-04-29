require "TimedActions/ISBaseTimedAction"
require "CSR_Config"
require "CSR_FeatureFlags"
require "CSR_Utils"

CSR_TearClothAction = ISBaseTimedAction:derive("CSR_TearClothAction")

local function resolveInventoryItem(character, itemId, expectedType)
    local inventory = character and character.getInventory and character:getInventory() or nil
    local items = inventory and inventory.getItems and inventory:getItems() or nil
    if not items then
        return nil
    end

    local fallback = nil
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item then
            if itemId ~= nil and item.getID and item:getID() == itemId then
                if not expectedType or (item.getFullType and item:getFullType() == expectedType) then
                    return item
                end
            end
            if not fallback and expectedType and item.getFullType and item:getFullType() == expectedType then
                fallback = item
            end
        end
    end

    return fallback
end

local function performLocal(action)
    local item = resolveInventoryItem(action.character, action.itemId, action.expectedType) or action.item
    local tearInfo = CSR_Utils.getTearClothInfo(item)
    if not tearInfo then
        return
    end

    local container = item and item.getContainer and item:getContainer() or action.character:getInventory()
    if container then
        if container.DoRemoveItem then
            container:DoRemoveItem(item)
        else
            container:Remove(item)
        end
    end
    for _ = 1, tearInfo.quantity do
        action.character:getInventory():AddItem(tearInfo.outputType)
    end

    if action.tool and action.tool.getCondition and action.tool.setCondition then
        action.tool:setCondition(math.max(0, action.tool:getCondition() - 1))
    end

    action.character:Say("Tore clothing into usable material")
end

function CSR_TearClothAction:new(character, item, tool)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.item = item
    o.itemId = item and item.getID and item:getID() or nil
    o.expectedType = item and item.getFullType and item:getFullType() or nil
    o.tool = tool
    o.maxTime = CSR_Config.CLOTH_TEAR_TIME
    o.stopOnWalk = not CSR_FeatureFlags.isWalkingActionsEnabled()
    o.stopOnRun = true
    return o
end

function CSR_TearClothAction:isValid()
    local item = resolveInventoryItem(self.character, self.itemId, self.expectedType) or self.item
    self.item = item
    return item ~= nil and CSR_Utils.getTearClothInfo(item) ~= nil
end

function CSR_TearClothAction:update()
    self.character:setMetabolicTarget(Metabolics.LightDomestic)
end

function CSR_TearClothAction:start()
    self.item = resolveInventoryItem(self.character, self.itemId, self.expectedType) or self.item
    if self.item and self.character and self.character.isEquippedClothing and self.character:isEquippedClothing(self.item) then
        self.character:removeWornItem(self.item)
    end
    self:setActionAnim("Loot")
    self:setOverrideHandModels(self.tool, self.item)
end

function CSR_TearClothAction:perform()
    self.item = resolveInventoryItem(self.character, self.itemId, self.expectedType) or self.item
    if isClient() then
        local tearInfo = CSR_Utils.getTearClothInfo(self.item)
        sendClientCommand(self.character, "CommonSenseReborn", "TearCloth", {
            itemId = self.item:getID(),
            expectedType = self.item:getFullType(),
            outputType = tearInfo and tearInfo.outputType or nil,
            quantity = tearInfo and tearInfo.quantity or 1,
            toolId = self.tool and self.tool:getID() or nil,
            requestId = CSR_Utils.makeRequestId(self.character, "TearCloth")
        })
    else
        performLocal(self)
    end

    ISBaseTimedAction.perform(self)
end

return CSR_TearClothAction

