local function canSafelyOverrideAttachmentType(item, targetValue)
    if not item then
        return false
    end

    local existing = item.getAttachmentType and item:getAttachmentType() or nil
    if not existing or existing == "" then
        return true
    end

    return existing == targetValue
end

local function adjustItem(fullType, property, value)
    local manager = ScriptManager and ScriptManager.instance or nil
    if not manager then
        return
    end

    local item = manager:getItem(fullType)
    if item and property == "AttachmentType" and canSafelyOverrideAttachmentType(item, value) then
        item:DoParam(property .. " = " .. value)
    elseif item and property ~= "AttachmentType" then
        item:DoParam(property .. " = " .. value)
    end
end

Events.OnInitWorld.Add(function()
    adjustItem("Base.Torch", "AttachmentType", "HandTorchSmall")
    adjustItem("Base.HandTorch", "AttachmentType", "HandTorchSmall")
    adjustItem("Base.FlashLight_AngleHead", "AttachmentType", "TorchAngled")
    adjustItem("Base.FlashLight_AngleHead_Army", "AttachmentType", "TorchAngled")
    adjustItem("Base.PenLight", "AttachmentType", "HandTorchSmall")
    adjustItem("Base.Lantern_Hurricane", "AttachmentType", "HandTorchBig")
    adjustItem("Base.Lantern_HurricaneLit", "AttachmentType", "HandTorchBig")
    adjustItem("Base.Lantern_Hurricane_Copper", "AttachmentType", "HandTorchBig")
    adjustItem("Base.Lantern_Hurricane_CopperLit", "AttachmentType", "HandTorchBig")
    adjustItem("Base.Lantern_Hurricane_Forged", "AttachmentType", "HandTorchBig")
    adjustItem("Base.Lantern_Hurricane_ForgedLit", "AttachmentType", "HandTorchBig")
    adjustItem("Base.Lantern_Hurricane_Gold", "AttachmentType", "HandTorchBig")
    adjustItem("Base.Lantern_Hurricane_GoldLit", "AttachmentType", "HandTorchBig")
    adjustItem("Base.Lantern_Hurricane_Silver", "AttachmentType", "HandTorchBig")
    adjustItem("Base.Lantern_Hurricane_SilverLit", "AttachmentType", "HandTorchBig")
    adjustItem("Base.Lantern_Propane", "AttachmentType", "HandTorchBig")
    adjustItem("Base.Lantern_CraftedElectric", "AttachmentType", "HandTorchBig")
end)
