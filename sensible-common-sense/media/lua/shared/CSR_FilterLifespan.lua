require "CSR_FeatureFlags"

--[[
    CSR_FilterLifespan.lua
    Applies a sandbox multiplier to all mask filter drain rates.
    Higher multiplier = filters last longer.
    Inspired by Wolf's Mask Filter Redux (Workshop 3708819784).
]]

local BASELINE_DELTAS = {
    RespiratorFilters          = 0.02,
    RespiratorFiltersRecharged = 0.04,
    GasmaskFilter              = 0.01,
    GasmaskFilterCrafted       = 0.02,
    CSR_FieldRespirator        = 0.04,
    CSR_FieldGasMask           = 0.03,
}

local function applyFilterMultiplier()
    if not CSR_FeatureFlags.isFieldFiltersEnabled() then return end
    local sb = SandboxVars and SandboxVars.CommonSenseReborn or nil
    local multiplier = sb and sb.FilterLifespanMultiplier or 1
    if type(multiplier) ~= "number" or multiplier < 1 then multiplier = 1 end
    if multiplier == 1 then return end
    for itemName, baseline in pairs(BASELINE_DELTAS) do
        local scriptItem = ScriptManager.instance:getItem(itemName)
        if scriptItem then
            scriptItem:DoParam("UseDelta = " .. tostring(baseline / multiplier))
        end
    end
end

Events.OnGameTimeLoaded.Add(applyFilterMultiplier)
Events.OnNewGame.Add(applyFilterMultiplier)
