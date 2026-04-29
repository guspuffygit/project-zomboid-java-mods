require "TimedActions/ISBaseTimedAction"
require "CSR_FeatureFlags"
require "CSR_Utils"

CSR_PatchClothingAction = ISBaseTimedAction:derive("CSR_PatchClothingAction")

local function performLocal(action)
    action.item = CSR_Utils.findInventoryItemById(action.character, action.itemId, action.expectedType) or action.item
    action.thread = CSR_Utils.findInventoryItemById(action.character, action.threadId, action.threadType) or action.thread
    action.needle = CSR_Utils.findInventoryItemById(action.character, action.needleId, action.needleType) or action.needle
    action.fabric = CSR_Utils.findInventoryItemById(action.character, action.fabricId, action.fabricType) or action.fabric
    if not action.item or not action.thread or not action.needle or not action.fabric then
        return
    end

    local repairAmount = math.min(15, action.item:getConditionMax() - action.item:getCondition())
    action.item:setCondition(action.item:getCondition() + repairAmount)

    if action.thread.Use then
        action.thread:Use()
    else
        action.character:getInventory():Remove(action.thread)
    end

    action.needle:setCondition(math.max(0, action.needle:getCondition() - 1))

    action.character:getInventory():Remove(action.fabric)

    action.character:Say("Patched it up")

    addXp(action.character, Perks.Tailoring, 3)
end

function CSR_PatchClothingAction:new(character, item, thread, needle, fabric)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.item = item
    o.thread = thread
    o.needle = needle
    o.fabric = fabric
    o.itemId = item and item.getID and item:getID() or nil
    o.expectedType = item and item.getFullType and item:getFullType() or nil
    o.threadId = thread and thread.getID and thread:getID() or nil
    o.threadType = thread and thread.getFullType and thread:getFullType() or nil
    o.needleId = needle and needle.getID and needle:getID() or nil
    o.needleType = needle and needle.getFullType and needle:getFullType() or nil
    o.fabricId = fabric and fabric.getID and fabric:getID() or nil
    o.fabricType = fabric and fabric.getFullType and fabric:getFullType() or nil
    o.maxTime = 200
    o.stopOnWalk = not CSR_FeatureFlags.isWalkingActionsEnabled()
    o.stopOnRun = true
    return o
end

function CSR_PatchClothingAction:isValid()
    self.item = CSR_Utils.findInventoryItemById(self.character, self.itemId, self.expectedType) or self.item
    self.thread = CSR_Utils.findInventoryItemById(self.character, self.threadId, self.threadType) or self.thread
    self.needle = CSR_Utils.findInventoryItemById(self.character, self.needleId, self.needleType) or self.needle
    self.fabric = CSR_Utils.findInventoryItemById(self.character, self.fabricId, self.fabricType) or self.fabric
    return self.item and self.thread and self.needle and self.fabric
        and self.item:getCondition() < self.item:getConditionMax()
end

function CSR_PatchClothingAction:update()
    self.character:setMetabolicTarget(Metabolics.LightDomestic)
end

function CSR_PatchClothingAction:start()
    self.item = CSR_Utils.findInventoryItemById(self.character, self.itemId, self.expectedType) or self.item
    self.needle = CSR_Utils.findInventoryItemById(self.character, self.needleId, self.needleType) or self.needle
    self:setActionAnim("Craft")
    self:setOverrideHandModels(self.needle, self.item)
end

function CSR_PatchClothingAction:perform()
    if isClient() then
        sendClientCommand(self.character, "CommonSenseReborn", "PatchClothing", {
            itemId = self.item:getID(),
            threadId = self.thread:getID(),
            needleId = self.needle:getID(),
            fabricId = self.fabric:getID(),
            requestId = CSR_Utils.makeRequestId(self.character, "PatchClothing")
        })
    else
        performLocal(self)
    end

    ISBaseTimedAction.perform(self)
end

return CSR_PatchClothingAction
