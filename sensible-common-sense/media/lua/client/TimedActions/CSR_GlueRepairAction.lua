require "TimedActions/ISBaseTimedAction"
require "CSR_FeatureFlags"
require "CSR_Utils"

CSR_GlueRepairAction = ISBaseTimedAction:derive("CSR_GlueRepairAction")

local function performLocal(action)
    action.item = CSR_Utils.findInventoryItemById(action.character, action.itemId, action.expectedType) or action.item
    action.glue = CSR_Utils.findInventoryItemById(action.character, action.glueId, action.glueType) or action.glue
    if not action.item or not action.glue then
        return
    end

    local repairAmount = math.min(20, action.item:getConditionMax() - action.item:getCondition())
    action.item:setCondition(action.item:getCondition() + repairAmount)
    if action.glue.Use then
        action.glue:Use()
    else
        action.character:getInventory():Remove(action.glue)
    end
    action.character:Say("Repaired with glue")
end

function CSR_GlueRepairAction:new(character, item, glue)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.item = item
    o.glue = glue
    o.itemId = item and item.getID and item:getID() or nil
    o.expectedType = item and item.getFullType and item:getFullType() or nil
    o.glueId = glue and glue.getID and glue:getID() or nil
    o.glueType = glue and glue.getFullType and glue:getFullType() or nil
    o.maxTime = 180
    o.stopOnWalk = not CSR_FeatureFlags.isWalkingActionsEnabled()
    o.stopOnRun = true
    return o
end

function CSR_GlueRepairAction:isValid()
    self.item = CSR_Utils.findInventoryItemById(self.character, self.itemId, self.expectedType) or self.item
    self.glue = CSR_Utils.findInventoryItemById(self.character, self.glueId, self.glueType) or self.glue
    return self.item and self.glue and self.item:getCondition() < self.item:getConditionMax()
end

function CSR_GlueRepairAction:update()
    self.character:setMetabolicTarget(Metabolics.LightDomestic)
end

function CSR_GlueRepairAction:start()
    self.item = CSR_Utils.findInventoryItemById(self.character, self.itemId, self.expectedType) or self.item
    self.glue = CSR_Utils.findInventoryItemById(self.character, self.glueId, self.glueType) or self.glue
    self:setActionAnim("Craft")
    self:setOverrideHandModels(self.glue, self.item)
end

function CSR_GlueRepairAction:perform()
    if isClient() then
        sendClientCommand(self.character, "CommonSenseReborn", "GlueRepair", {
            itemId = self.item:getID(),
            materialId = self.glue:getID(),
            requestId = CSR_Utils.makeRequestId(self.character, "GlueRepair")
        })
    else
        performLocal(self)
    end

    ISBaseTimedAction.perform(self)
end

return CSR_GlueRepairAction
