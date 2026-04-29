require "CSR_FeatureFlags"

--[[
    CSR_ExerciseWithGear.lua
    Overrides ISFitnessUI:equipItems() to skip unequipping bags and clothing
    when exercising. Hand items are still swapped as needed by the exercise.
]]

if not ISFitnessUI then return end

local origEquipItems = ISFitnessUI.equipItems

function ISFitnessUI:equipItems()
    if not CSR_FeatureFlags.isExerciseWithGearEnabled() then
        return origEquipItems(self)
    end

    -- Check required item availability (same as vanilla)
    if self.exeData.item and not self.player:getInventory():contains(self.exeData.item, true) then
        return false
    end

    -- Handle hand items (same as vanilla)
    if not self.exeData.prop then
        ISInventoryPaneContextMenu.unequipItem(self.player:getPrimaryHandItem(), self.player:getPlayerNum())
        if not self.player:isItemInBothHands(self.player:getPrimaryHandItem()) then
            ISInventoryPaneContextMenu.unequipItem(self.player:getSecondaryHandItem(), self.player:getPlayerNum())
        end
    end
    if self.exeData.prop == "twohands" then
        ISWorldObjectContextMenu.equip(self.player, self.player:getPrimaryHandItem(), self.exeData.item, true, true)
    end
    if self.exeData.prop == "primary" then
        ISWorldObjectContextMenu.equip(self.player, self.player:getPrimaryHandItem(), self.exeData.item, true, false)
        self.player:setSecondaryHandItem(nil)
    end
    if self.exeData.prop == "switch" then
        ISWorldObjectContextMenu.equip(self.player, self.player:getPrimaryHandItem(), self.exeData.item, true, false)
        self.player:setSecondaryHandItem(nil)
    end

    -- SKIP the vanilla bag/clothing unequip loop — that's the whole point of this feature

    return true
end
