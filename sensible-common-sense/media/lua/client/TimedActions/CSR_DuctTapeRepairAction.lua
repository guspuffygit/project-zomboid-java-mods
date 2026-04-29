require "TimedActions/ISBaseTimedAction"
require "CSR_FeatureFlags"
require "CSR_Utils"

CSR_DuctTapeRepairAction = ISBaseTimedAction:derive("CSR_DuctTapeRepairAction")

local function performLocal(action)
    action.item = CSR_Utils.findInventoryItemById(action.character, action.itemId, action.expectedType) or action.item
    action.tape = CSR_Utils.findInventoryItemById(action.character, action.tapeId, action.tapeType) or action.tape
    if not action.item or not action.tape then
        return
    end

    local repairAmount = math.min(25, action.item:getConditionMax() - action.item:getCondition())
    action.item:setCondition(action.item:getCondition() + repairAmount)
    if action.tape.Use then
        action.tape:Use()
    else
        action.character:getInventory():Remove(action.tape)
    end
    action.character:Say("Repaired with duct tape")
end

function CSR_DuctTapeRepairAction:new(character, item, tape)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.item = item
    o.tape = tape
    o.itemId = item and item.getID and item:getID() or nil
    o.expectedType = item and item.getFullType and item:getFullType() or nil
    o.tapeId = tape and tape.getID and tape:getID() or nil
    o.tapeType = tape and tape.getFullType and tape:getFullType() or nil
    o.maxTime = 150
    o.stopOnWalk = not CSR_FeatureFlags.isWalkingActionsEnabled()
    o.stopOnRun = true
    return o
end

function CSR_DuctTapeRepairAction:isValid()
    self.item = CSR_Utils.findInventoryItemById(self.character, self.itemId, self.expectedType) or self.item
    self.tape = CSR_Utils.findInventoryItemById(self.character, self.tapeId, self.tapeType) or self.tape
    return self.item and self.tape and self.item:getCondition() < self.item:getConditionMax()
end

function CSR_DuctTapeRepairAction:update()
    self.character:setMetabolicTarget(Metabolics.LightDomestic)
end

function CSR_DuctTapeRepairAction:start()
    self.item = CSR_Utils.findInventoryItemById(self.character, self.itemId, self.expectedType) or self.item
    self.tape = CSR_Utils.findInventoryItemById(self.character, self.tapeId, self.tapeType) or self.tape
    self:setActionAnim("Craft")
    self:setOverrideHandModels(self.tape, self.item)
end

function CSR_DuctTapeRepairAction:perform()
    if isClient() then
        sendClientCommand(self.character, "CommonSenseReborn", "DuctTapeRepair", {
            itemId = self.item:getID(),
            materialId = self.tape:getID(),
            requestId = CSR_Utils.makeRequestId(self.character, "DuctTapeRepair")
        })
    else
        performLocal(self)
    end

    ISBaseTimedAction.perform(self)
end

return CSR_DuctTapeRepairAction
