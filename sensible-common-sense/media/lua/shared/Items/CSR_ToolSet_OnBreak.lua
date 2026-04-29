--[[
    CSR Tool Set -- OnBreak handlers
    When a combined tool item breaks from use, drop the original container
    (toolbox/tool roll) on the ground so the player doesn't lose it entirely.
    Individual tools are consumed -- only the container survives.
]]

require "CSR_FeatureFlags"
OnBreak = OnBreak or {}

function OnBreak.CSR_RollLeather(item, player)
    if CSR_FeatureFlags.isToolSetEnabled() then
        OnBreak.GroundHandler(item, player, "Base.ToolRoll_Leather")
    end
end

function OnBreak.CSR_RollFabric(item, player)
    if CSR_FeatureFlags.isToolSetEnabled() then
        OnBreak.GroundHandler(item, player, "Base.ToolRoll_Fabric")
    end
end

function OnBreak.CSR_Toolbox(item, player)
    if CSR_FeatureFlags.isToolSetEnabled() then
        OnBreak.GroundHandler(item, player, "Base.Toolbox")
    end
end

function OnBreak.CSR_FullToolbox(item, player)
    if CSR_FeatureFlags.isToolSetEnabled() then
        OnBreak.GroundHandler(item, player, "Base.Toolbox")
    end
end
