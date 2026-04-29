require "CSR_FeatureFlags"

--[[
    CSR_WearableSlotFix.lua
    Runtime script parameter overrides applied at load time via DoParam.

    Moves ear protection items from the Hat body location to the Ears slot
    so they can be worn simultaneously with hats and helmets.
    Inspired by WearEarProtectorswithHat (Workshop 3439298478).
]]

local SLOT_OVERRIDES = {
    { item = "Hat_EarMuffs",           param = "BodyLocation = Ears" },
    { item = "Hat_EarMuff_Protectors", param = "BodyLocation = Ears" },
}

local function applySlotOverrides()
    if not CSR_FeatureFlags.isWearableSlotFixEnabled() then return end
    for _, entry in ipairs(SLOT_OVERRIDES) do
        local scriptItem = ScriptManager.instance:getItem(entry.item)
        if scriptItem then
            scriptItem:DoParam(entry.param)
        end
    end
end

Events.OnGameTimeLoaded.Add(applySlotOverrides)
Events.OnNewGame.Add(applySlotOverrides)
