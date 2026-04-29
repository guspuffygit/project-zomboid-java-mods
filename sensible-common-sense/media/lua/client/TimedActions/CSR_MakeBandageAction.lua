require "TimedActions/ISBaseTimedAction"
require "CSR_Config"
require "CSR_FeatureFlags"
require "CSR_Utils"

CSR_MakeBandageAction = ISBaseTimedAction:derive("CSR_MakeBandageAction")

local function removeItem(item, fallbackContainer)
    local container = item and item.getContainer and item:getContainer() or fallbackContainer
    if not container or not item then
        return
    end

    if container.DoRemoveItem then
        container:DoRemoveItem(item)
    else
        container:Remove(item)
    end
end

local function wearNeedle(needle)
    if needle and needle.getCondition and needle.setCondition and needle:getCondition() > 0 then
        needle:setCondition(math.max(0, needle:getCondition() - 1))
    end
end

local function performLocal(action)
    action.material = CSR_Utils.findInventoryItemById(action.character, action.materialId, action.materialType) or action.material
    action.thread = CSR_Utils.findInventoryItemById(action.character, action.threadId, action.threadType) or action.thread
    action.needle = CSR_Utils.findInventoryItemById(action.character, action.needleId, action.needleType) or action.needle
    if not action.character or not action.material or not action.thread or not action.needle then
        return
    end

    removeItem(action.material, action.character:getInventory())
    if action.thread.Use then
        action.thread:Use()
    end
    wearNeedle(action.needle)
    action.character:getInventory():AddItem("Base.Bandage")
end

function CSR_MakeBandageAction:new(character, material, thread, needle)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.material = material
    o.thread = thread
    o.needle = needle
    o.materialId = material and material.getID and material:getID() or nil
    o.materialType = material and material.getFullType and material:getFullType() or nil
    o.threadId = thread and thread.getID and thread:getID() or nil
    o.threadType = thread and thread.getFullType and thread:getFullType() or nil
    o.needleId = needle and needle.getID and needle:getID() or nil
    o.needleType = needle and needle.getFullType and needle:getFullType() or nil
    o.maxTime = CSR_Config.MAKE_BANDAGE_TIME
    o.stopOnWalk = not CSR_FeatureFlags.isWalkingActionsEnabled()
    o.stopOnRun = true
    return o
end

function CSR_MakeBandageAction:isValid()
    self.material = CSR_Utils.findInventoryItemById(self.character, self.materialId, self.materialType) or self.material
    self.thread = CSR_Utils.findInventoryItemById(self.character, self.threadId, self.threadType) or self.thread
    self.needle = CSR_Utils.findInventoryItemById(self.character, self.needleId, self.needleType) or self.needle
    return self.material and self.thread and self.needle and CSR_Utils.canMakeBandage(self.material, self.character)
end

function CSR_MakeBandageAction:update()
    self.character:setMetabolicTarget(Metabolics.LightDomestic)
end

function CSR_MakeBandageAction:start()
    self.material = CSR_Utils.findInventoryItemById(self.character, self.materialId, self.materialType) or self.material
    self.thread = CSR_Utils.findInventoryItemById(self.character, self.threadId, self.threadType) or self.thread
    self.needle = CSR_Utils.findInventoryItemById(self.character, self.needleId, self.needleType) or self.needle
    self:setActionAnim("Craft")
    self:setOverrideHandModels(self.needle, self.material)
end

function CSR_MakeBandageAction:perform()
    if isClient() then
        sendClientCommand(self.character, "CommonSenseReborn", "MakeBandage", {
            itemId = self.material:getID(),
            threadId = self.thread:getID(),
            needleId = self.needle:getID(),
            requestId = CSR_Utils.makeRequestId(self.character, "MakeBandage"),
            requestTimestamp = getTimestampMs and getTimestampMs() or os.time() * 1000,
        })
    else
        performLocal(self)
    end

    ISBaseTimedAction.perform(self)
end

return CSR_MakeBandageAction
