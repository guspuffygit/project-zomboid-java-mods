require "TimedActions/ISBaseTimedAction"
require "CSR_FeatureFlags"
require "CSR_Utils"

CSR_TowelDryAction = ISBaseTimedAction:derive("CSR_TowelDryAction")

local DRY_TIME = 200

local TOWEL_DATA = {
    BathTowel       = { dryAmount = 60, label = "Bath Towel" },
    Sheet           = { dryAmount = 45, label = "Sheet" },
    DishCloth       = { dryAmount = 25, label = "Dish Cloth" },
    RippedSheets    = { dryAmount = 15, label = "Ripped Sheets" },
}

local function getTowelData(item)
    if not item then return nil end
    return TOWEL_DATA[item:getType()]
end

function CSR_TowelDryAction:new(character, towel)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.towel = towel
    o.towelId = towel and towel.getID and towel:getID() or nil
    o.towelType = towel and towel.getFullType and towel:getFullType() or nil
    o.maxTime = DRY_TIME
    o.stopOnWalk = true
    o.stopOnRun = true
    return o
end

function CSR_TowelDryAction:isValid()
    self.towel = CSR_Utils.findInventoryItemById(self.character, self.towelId, self.towelType) or self.towel
    if not self.towel then return false end
    return self.character:getStats():get(CharacterStat.WETNESS) > 0
end

function CSR_TowelDryAction:update()
    self.character:setMetabolicTarget(Metabolics.LightDomestic)
end

function CSR_TowelDryAction:start()
    self.towel = CSR_Utils.findInventoryItemById(self.character, self.towelId, self.towelType) or self.towel
    self:setActionAnim("Loot")
    self:setOverrideHandModels(self.towel, nil)
end

function CSR_TowelDryAction:stop()
    ISBaseTimedAction.stop(self)
end

function CSR_TowelDryAction:perform()
    self.towel = CSR_Utils.findInventoryItemById(self.character, self.towelId, self.towelType) or self.towel
    local data = getTowelData(self.towel)
    if not data then
        ISBaseTimedAction.perform(self)
        return
    end

    local wetness = self.character:getStats():get(CharacterStat.WETNESS)
    local dryFraction = data.dryAmount / 100
    -- Use flat reduction (percentage of max wetness) so drying is effective at all wetness levels
    local reduction = math.max(dryFraction, wetness * dryFraction)
    self.character:getBodyDamage():decreaseBodyWetness(reduction)
    local dried = math.floor(dryFraction * 100)
    self.character:Say("Dried off with " .. data.label .. " (-" .. dried .. "% wetness)")

    ISBaseTimedAction.perform(self)
end

-- Context menu hook
local function onInventoryContext(playerNum, context, items)
    if not CSR_FeatureFlags.isTowelDryingEnabled() then return end

    local player = getSpecificPlayer(playerNum)
    if not player or player:isDead() then return end

    local wetness = player:getStats():get(CharacterStat.WETNESS)
    if wetness <= 0 then return end

    local inventoryItems = CSR_Utils.resolveInventorySelection(items)

    for _, item in ipairs(inventoryItems) do
        local data = getTowelData(item)
        if data then
            local wetPercent = math.floor(wetness * 100)
            local text = string.format("Dry Off (%s, -%d%%)", data.label, math.min(data.dryAmount, wetPercent))
            local option = context:addOption(text, items, function()
                ISInventoryPaneContextMenu.transferIfNeeded(player, item)
                ISTimedActionQueue.add(CSR_TowelDryAction:new(player, item))
            end)
            option.iconTexture = item:getTexture()
            break -- Only show one towel option at a time
        end
    end
end

Events.OnFillInventoryObjectContextMenu.Add(onInventoryContext)

return CSR_TowelDryAction
