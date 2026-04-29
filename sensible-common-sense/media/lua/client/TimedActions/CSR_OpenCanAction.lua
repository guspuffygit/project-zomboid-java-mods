require "TimedActions/ISBaseTimedAction"
require "CSR_Config"
require "CSR_FeatureFlags"
require "CSR_Utils"

CSR_OpenCanAction = ISBaseTimedAction:derive("CSR_OpenCanAction")

local function performLocal(action)
    action.item = CSR_Utils.findInventoryItemById(action.character, action.itemId, action.expectedType) or action.item
    action.tool = CSR_Utils.findInventoryItemById(action.character, action.toolId, action.toolType) or action.tool
    if not action.item or not action.tool then
        return
    end

    local newType = CSR_Utils.getOpenCanResult(action.item)
    if newType then
        local oldCondition = action.item:getCondition()
        action.item:Use()
        local openedItem = action.character:getInventory():AddItem(newType)
        if openedItem then
            openedItem:setCondition(oldCondition)
        end
    end

    action.tool:setCondition(math.max(0, action.tool:getCondition() - 1))

    local canInjuryChance = (SandboxVars and SandboxVars.CommonSenseReborn and SandboxVars.CommonSenseReborn.CanInjuryChance) or 0.05
    if CSR_Utils.isKnifeItem(action.tool) and ZombRandFloat(0, 1) < canInjuryChance then
        local bodyDamage = action.character:getBodyDamage()
        local hand = ZombRand(2) == 0 and BodyPartType.Hand_L or BodyPartType.Hand_R
        bodyDamage:AddDamage(hand, 5)
        action.character:Say("Ouch! Cut myself opening the can")
    end
end

function CSR_OpenCanAction:new(character, item, tool)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.item = item
    o.tool = tool
    o.itemId = item and item.getID and item:getID() or nil
    o.expectedType = item and item.getFullType and item:getFullType() or nil
    o.toolId = tool and tool.getID and tool:getID() or nil
    o.toolType = tool and tool.getFullType and tool:getFullType() or nil
    o.maxTime = CSR_Config.OPEN_CAN_TIME
    o.stopOnWalk = not CSR_FeatureFlags.isWalkingActionsEnabled()
    o.stopOnRun = true
    return o
end

function CSR_OpenCanAction:isValid()
    self.item = CSR_Utils.findInventoryItemById(self.character, self.itemId, self.expectedType) or self.item
    self.tool = CSR_Utils.findInventoryItemById(self.character, self.toolId, self.toolType) or self.tool
    return self.item and self.tool and self.tool:getCondition() > 0 and CSR_Utils.getOpenCanResult(self.item) ~= nil
end

function CSR_OpenCanAction:update()
    self.character:setMetabolicTarget(Metabolics.LightDomestic)
end

function CSR_OpenCanAction:start()
    self.item = CSR_Utils.findInventoryItemById(self.character, self.itemId, self.expectedType) or self.item
    self.tool = CSR_Utils.findInventoryItemById(self.character, self.toolId, self.toolType) or self.tool
    self:setActionAnim("Eat")
    self:setOverrideHandModels(self.tool, self.item)
end

function CSR_OpenCanAction:perform()
    if isClient() then
        sendClientCommand(self.character, "CommonSenseReborn", "OpenCan", {
            itemId = self.item:getID(),
            toolId = self.tool:getID(),
            requestId = CSR_Utils.makeRequestId(self.character, "OpenCan")
        })
    else
        performLocal(self)
    end

    ISBaseTimedAction.perform(self)
end

return CSR_OpenCanAction

