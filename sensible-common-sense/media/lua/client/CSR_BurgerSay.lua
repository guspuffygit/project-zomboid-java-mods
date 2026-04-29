require "CSR_FeatureFlags"
require "TimedActions/ISEatFoodAction"

local BURGER_TYPES = {
    ["Burger"] = true,
    ["BurgerMeal"] = true,
}

local _originalEatComplete = ISEatFoodAction.complete

function ISEatFoodAction:complete()
    _originalEatComplete(self)
    if not self.character or not self.item then return end
    if not self.item.getType then return end
    local itemType = self.item:getType()
    if BURGER_TYPES[itemType] then
        self.character:Say("TheBurger!")
    end
end
