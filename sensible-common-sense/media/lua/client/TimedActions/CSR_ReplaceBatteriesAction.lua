require "TimedActions/ISBaseTimedAction"
require "CSR_Config"
require "CSR_FeatureFlags"
require "CSR_Utils"

CSR_ReplaceBatteriesAction = ISBaseTimedAction:derive("CSR_ReplaceBatteriesAction")

local function performLocal(action)
    action.item = CSR_Utils.findInventoryItemById(action.character, action.itemId, action.expectedType) or action.item
    action.battery = CSR_Utils.findInventoryItemById(action.character, action.batteryId, action.batteryType) or action.battery
    if not action.item or not action.battery then
        return
    end

    action.item:setDelta(1.0)
    action.character:getInventory():Remove(action.battery)
    action.character:Say("Battery replaced")
end

function CSR_ReplaceBatteriesAction:new(character, item, battery)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.item = item
    o.battery = battery
    o.itemId = item and item.getID and item:getID() or nil
    o.expectedType = item and item.getFullType and item:getFullType() or nil
    o.batteryId = battery and battery.getID and battery:getID() or nil
    o.batteryType = battery and battery.getFullType and battery:getFullType() or nil
    o.maxTime = CSR_Config.BATTERY_SWAP_TIME
    o.stopOnWalk = not CSR_FeatureFlags.isWalkingActionsEnabled()
    o.stopOnRun = true
    return o
end

function CSR_ReplaceBatteriesAction:isValid()
    self.item = CSR_Utils.findInventoryItemById(self.character, self.itemId, self.expectedType) or self.item
    self.battery = CSR_Utils.findInventoryItemById(self.character, self.batteryId, self.batteryType) or self.battery
    return self.item and self.battery and self.item.getDelta and self.item:getDelta() < 1.0
end

function CSR_ReplaceBatteriesAction:update()
    self.character:setMetabolicTarget(Metabolics.LightDomestic)
end

function CSR_ReplaceBatteriesAction:start()
    self.item = CSR_Utils.findInventoryItemById(self.character, self.itemId, self.expectedType) or self.item
    self.battery = CSR_Utils.findInventoryItemById(self.character, self.batteryId, self.batteryType) or self.battery
    self:setActionAnim("Craft")
    self:setOverrideHandModels(self.battery, self.item)
end

function CSR_ReplaceBatteriesAction:perform()
    if isClient() then
        sendClientCommand(self.character, "CommonSenseReborn", "ReplaceBattery", {
            itemId = self.item:getID(),
            batteryId = self.battery:getID(),
            requestId = CSR_Utils.makeRequestId(self.character, "ReplaceBattery")
        })
    else
        performLocal(self)
    end

    ISBaseTimedAction.perform(self)
end

return CSR_ReplaceBatteriesAction

