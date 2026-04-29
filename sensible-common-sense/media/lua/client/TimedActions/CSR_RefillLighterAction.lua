require "TimedActions/ISBaseTimedAction"
require "CSR_Config"
require "CSR_FeatureFlags"
require "CSR_Utils"

CSR_RefillLighterAction = ISBaseTimedAction:derive("CSR_RefillLighterAction")

local function performLocal(action)
    action.lighter = CSR_Utils.findInventoryItemById(action.character, action.lighterId, action.lighterType) or action.lighter
    action.fluid = CSR_Utils.findInventoryItemById(action.character, action.fluidId, action.fluidType) or action.fluid
    if not action.lighter or not action.fluid then
        return
    end

    local current = action.lighter:getDelta()
    local available = action.fluid:getDelta()
    local needed = 1.0 - current
    local transfer = math.min(needed, available)

    action.lighter:setDelta(math.min(1.0, current + transfer))
    action.fluid:setDelta(math.max(0.0, available - transfer))
    if action.fluid:getDelta() <= 0 then
        action.character:getInventory():Remove(action.fluid)
    end

    action.character:Say("Lighter refilled")
end

function CSR_RefillLighterAction:new(character, lighter, fluid)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.lighter = lighter
    o.fluid = fluid
    o.lighterId = lighter and lighter.getID and lighter:getID() or nil
    o.lighterType = lighter and lighter.getFullType and lighter:getFullType() or nil
    o.fluidId = fluid and fluid.getID and fluid:getID() or nil
    o.fluidType = fluid and fluid.getFullType and fluid:getFullType() or nil
    o.maxTime = CSR_Config.LIGHTER_REFILL_TIME
    o.stopOnWalk = not CSR_FeatureFlags.isWalkingActionsEnabled()
    o.stopOnRun = true
    return o
end

function CSR_RefillLighterAction:isValid()
    self.lighter = CSR_Utils.findInventoryItemById(self.character, self.lighterId, self.lighterType) or self.lighter
    self.fluid = CSR_Utils.findInventoryItemById(self.character, self.fluidId, self.fluidType) or self.fluid
    return self.lighter and self.fluid and CSR_Utils.canRefillLighter(self.lighter) and self.fluid.getDelta and self.fluid:getDelta() > 0
end

function CSR_RefillLighterAction:update()
    self.character:setMetabolicTarget(Metabolics.LightDomestic)
end

function CSR_RefillLighterAction:start()
    self.lighter = CSR_Utils.findInventoryItemById(self.character, self.lighterId, self.lighterType) or self.lighter
    self.fluid = CSR_Utils.findInventoryItemById(self.character, self.fluidId, self.fluidType) or self.fluid
    self:setActionAnim("Craft")
    self:setOverrideHandModels(self.fluid, self.lighter)
end

function CSR_RefillLighterAction:perform()
    if isClient() then
        sendClientCommand(self.character, "CommonSenseReborn", "RefillLighter", {
            itemId = self.lighter:getID(),
            fluidId = self.fluid:getID(),
            requestId = CSR_Utils.makeRequestId(self.character, "RefillLighter")
        })
    else
        performLocal(self)
    end

    ISBaseTimedAction.perform(self)
end

return CSR_RefillLighterAction

