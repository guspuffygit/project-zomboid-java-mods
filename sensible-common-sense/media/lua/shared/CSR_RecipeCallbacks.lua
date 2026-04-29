--[[
    CSR_RecipeCallbacks.lua
    OnCreate / OnGiveXP callbacks for CSR craftRecipes.
    Referenced by script name in CSR_CommonSenseRecipes.txt.
]]

CSR_RecipeCallbacks = {}

--- Teach the player the pumpkin growing season recipe so that the
--- extracted seeds can actually be planted via the farming menu.
--- The farming menu requires either Farming >= 6 or knowledge of
--- the season recipe (normally learned by opening a seed packet).
function CSR_RecipeCallbacks.onExtractPumpkinSeeds(craftRecipeData, character)
    if character and character.learnRecipe then
        character:learnRecipe("base:pumpkin growing season")
    end
end
