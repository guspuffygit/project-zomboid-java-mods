require "CSR_FeatureFlags"
require "CSR_Theme"
require "CSR_Utils"

local texOn = nil
local texOff = nil

local function drawFlashlightIndicator(hotbar, slotX, item)
    if not item or not CSR_FeatureFlags.isEquipmentQoLEnabled() or not CSR_Utils.isFlashlight(item) then
        return
    end

    if not texOn then texOn = getTexture("media/ui/flashlight_on.png") end
    if not texOff then texOff = getTexture("media/ui/flashlight_off.png") end

    local isOn = CSR_Utils.isFlashlightActive(item)
    local tex = isOn and texOn or texOff
    local iconSize = 16
    local x = slotX + hotbar.slotWidth - iconSize - 2
    local y = hotbar.margins + 2

    if tex then
        local alpha = isOn and 1.0 or 0.7
        hotbar:drawTexture(tex, x + 1, y + 1, 0.6, 0, 0, 0)
        hotbar:drawTexture(tex, x, y, alpha, 1.0, 1.0, 1.0)
    end
end

-- Render hook moved to CSR_WeaponHudOverlay.lua (single consolidated patch)
-- Expose the draw function for the consolidated hook
CSR_HotbarFlashlightIndicator = CSR_HotbarFlashlightIndicator or {}
CSR_HotbarFlashlightIndicator.drawFlashlightIndicator = drawFlashlightIndicator
