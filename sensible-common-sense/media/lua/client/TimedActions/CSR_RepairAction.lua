require "TimedActions/ISBaseTimedAction"
require "CSR_Config"
require "CSR_FeatureFlags"
require "CSR_Utils"

CSR_RepairAction = ISBaseTimedAction:derive("CSR_RepairAction")

local function performLocal(action)
    action.item = CSR_Utils.findInventoryItemById(action.character, action.itemId, action.expectedType) or action.item
    action.tool = CSR_Utils.findInventoryItemById(action.character, action.toolId, action.toolType) or action.tool
    if not action.item or not action.tool then
        return
    end

    local repairAmount = math.min(10, action.item:getConditionMax() - action.item:getCondition())
    local wearMult = (SandboxVars and SandboxVars.CommonSenseReborn and SandboxVars.CommonSenseReborn.ToolWearMultiplier) or 1.0
    local wear = math.max(1, math.floor(2 * wearMult))
    action.item:setCondition(action.item:getCondition() + repairAmount)
    action.tool:setCondition(math.max(0, action.tool:getCondition() - wear))
end

function CSR_RepairAction:new(character, item, tool)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.item = item
    o.tool = tool
    o.itemId = item and item.getID and item:getID() or nil
    o.expectedType = item and item.getFullType and item:getFullType() or nil
    o.toolId = tool and tool.getID and tool:getID() or nil
    o.toolType = tool and tool.getFullType and tool:getFullType() or nil
    o.maxTime = CSR_Config.REPAIR_TIME
    o.stopOnWalk = not CSR_FeatureFlags.isWalkingActionsEnabled()
    o.stopOnRun = true
    return o
end

function CSR_RepairAction:isValid()
    self.item = CSR_Utils.findInventoryItemById(self.character, self.itemId, self.expectedType) or self.item
    self.tool = CSR_Utils.findInventoryItemById(self.character, self.toolId, self.toolType) or self.tool
    return self.item and self.tool and self.item:getCondition() < self.item:getConditionMax() and self.tool:getCondition() > 0
end

function CSR_RepairAction:update()
    self.character:setMetabolicTarget(Metabolics.LightDomestic)
end

function CSR_RepairAction:start()
    self.item = CSR_Utils.findInventoryItemById(self.character, self.itemId, self.expectedType) or self.item
    self.tool = CSR_Utils.findInventoryItemById(self.character, self.toolId, self.toolType) or self.tool
    self:setActionAnim("Craft")
    self:setOverrideHandModels(self.tool, self.item)
end

function CSR_RepairAction:perform()
    print("[CSR] RepairAction:perform() isClient=" .. tostring(isClient()) .. " itemId=" .. tostring(self.item and self.item:getID()) .. " toolId=" .. tostring(self.tool and self.tool:getID()))
    if isClient() then
        sendClientCommand(self.character, "CommonSenseReborn", "QuickRepair", {
            itemId = self.item:getID(),
            toolId = self.tool:getID(),
            requestId = CSR_Utils.makeRequestId(self.character, "QuickRepair")
        })
    else
        performLocal(self)
    end

    ISBaseTimedAction.perform(self)
end

return CSR_RepairAction
