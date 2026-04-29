require "TimedActions/ISBaseTimedAction"
require "CSR_Config"
require "CSR_FeatureFlags"
require "CSR_Utils"

CSR_OpenJarAction = ISBaseTimedAction:derive("CSR_OpenJarAction")

local function addLidIfAvailable(character)
    local lidType = CSR_Utils.getJarLidType()
    if lidType then
        character:getInventory():AddItem(lidType)
    end
end

local function performLocal(action)
    action.item = CSR_Utils.findInventoryItemById(action.character, action.itemId, action.expectedType) or action.item
    if not action.item then
        return
    end

    local newType = CSR_Utils.getOpenJarResult(action.item)
    if not newType then
        return
    end

    local oldCondition = action.item.getCondition and action.item:getCondition() or nil
    action.item:Use()
    local openedItem = action.character:getInventory():AddItem(newType)
    if openedItem and oldCondition and openedItem.setCondition then
        openedItem:setCondition(oldCondition)
    end

    addLidIfAvailable(action.character)
end

function CSR_OpenJarAction:new(character, item)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.item = item
    o.itemId = item and item.getID and item:getID() or nil
    o.expectedType = item and item.getFullType and item:getFullType() or nil
    o.maxTime = CSR_Config.OPEN_JAR_TIME
    o.stopOnWalk = not CSR_FeatureFlags.isWalkingActionsEnabled()
    o.stopOnRun = true
    return o
end

function CSR_OpenJarAction:isValid()
    self.item = CSR_Utils.findInventoryItemById(self.character, self.itemId, self.expectedType) or self.item
    return self.item and CSR_Utils.getOpenJarResult(self.item) ~= nil
end

function CSR_OpenJarAction:update()
    self.character:setMetabolicTarget(Metabolics.LightDomestic)
end

function CSR_OpenJarAction:start()
    self.item = CSR_Utils.findInventoryItemById(self.character, self.itemId, self.expectedType) or self.item
    self:setActionAnim("Loot")
    self:setOverrideHandModels(nil, self.item)
end

function CSR_OpenJarAction:perform()
    if isClient() then
        sendClientCommand(self.character, "CommonSenseReborn", "OpenJar", {
            itemId = self.item:getID(),
            requestId = CSR_Utils.makeRequestId(self.character, "OpenJar")
        })
    else
        performLocal(self)
    end

    ISBaseTimedAction.perform(self)
end

return CSR_OpenJarAction
