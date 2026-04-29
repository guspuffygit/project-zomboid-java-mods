require "CSR_FeatureFlags"
require "CSR_Theme"
require "CSR_Utils"
require "Hotbar/CSR_HotbarFlashlightIndicator"

CSR_Debug = CSR_Debug or false

local function getConditionColor(ratio)
    if ratio > 0.75 then
        return CSR_Theme.getColor("accentGreen")
    elseif ratio > 0.40 then
        return CSR_Theme.getColor("accentAmber")
    elseif ratio > 0.15 then
        return CSR_Theme.getColor("accentRed")
    else
        return CSR_Theme.getColor("accentViolet")
    end
end

local function getAmmoInfo(item)
    if not item then return nil end
    if item.getCurrentAmmoCount and item.getMaxAmmo then
        local current = item:getCurrentAmmoCount()
        local max = item:getMaxAmmo()
        if type(current) == "number" and type(max) == "number" and max > 0 then
            return current, max
        end
    end
    return nil
end

local function getBatteryColor(ratio)
    if ratio > 0.75 then
        return { r = 0.2, g = 0.7, b = 1.0 }
    elseif ratio > 0.40 then
        return { r = 0.3, g = 0.55, b = 0.9 }
    elseif ratio > 0.15 then
        return CSR_Theme.getColor("accentAmber")
    else
        return CSR_Theme.getColor("accentRed")
    end
end

local function isDrainableItem(item)
    if not item then return false end
    if instanceof(item, "DrainableComboItem") then return true end
    if item.IsDrainable and item:IsDrainable() then return true end
    return false
end

local function getItemHealthRatio(item)
    if not item then return nil end

    if isDrainableItem(item) then
        if item.getCurrentUsesFloat then
            return item:getCurrentUsesFloat()
        elseif item.getDelta then
            return item:getDelta()
        end
    end

    if item.getCondition and item.getConditionMax then
        local cond = item:getCondition()
        local maxCond = item:getConditionMax()
        if type(cond) == "number" and type(maxCond) == "number" and maxCond > 0 then
            return cond / maxCond
        end
    end

    return nil
end

local function drawConditionTint(hotbar, slotX, item)
    local ratio = getItemHealthRatio(item)
    if not ratio then return end

    local isDrainable = isDrainableItem(item)
    local color = isDrainable and getBatteryColor(ratio) or getConditionColor(ratio)
    if not color then return end

    local y = hotbar.margins + 1
    local w = hotbar.slotWidth
    local h = hotbar.slotHeight

    hotbar:drawRect(slotX, y, w, h, 0.18, color.r, color.g, color.b)

    local barH = 3
    local barW = math.max(1, math.floor(w * ratio))
    local barY = y + h - barH
    hotbar:drawRect(slotX, barY, barW, barH, 0.80, color.r, color.g, color.b)
end

local function drawPill(hotbar, slotX, text, color)
    local font = UIFont.Medium
    local textW = getTextManager():MeasureStringX(font, text)
    local textH = getTextManager():getFontHeight(font)

    local pillW = textW + 8
    local pillH = textH + 4
    local pillX = slotX + math.floor((hotbar.slotWidth - pillW) / 2)
    local pillY = hotbar.margins + hotbar.slotWidth - pillH - 2

    local bg = CSR_Theme.getColor("panelBg")
    hotbar:drawRect(pillX, pillY, pillW, pillH, 0.92, bg.r, bg.g, bg.b)
    hotbar:drawText(text, pillX + 4, pillY + 2, color.r, color.g, color.b, 0.95, font)
end

local function drawAmmoPill(hotbar, slotX, item)
    local current, max = getAmmoInfo(item)
    if not current then return end

    local ratio = current / max
    local color = getConditionColor(ratio)
    if not color then return end

    drawPill(hotbar, slotX, tostring(current) .. "/" .. tostring(max), color)
end

local function drawBatteryPill(hotbar, slotX, item)
    if not isDrainableItem(item) then return end

    local delta = nil
    if item.getCurrentUsesFloat then
        delta = item:getCurrentUsesFloat()
    elseif item.getDelta then
        delta = item:getDelta()
    end
    if type(delta) ~= "number" then return end

    local pct = math.floor(delta * 100)
    local color = getBatteryColor(delta)
    if not color then return end

    local label = tostring(pct) .. "%"

    local font = UIFont.NewSmall
    local textW = getTextManager():MeasureStringX(font, label)
    local textH = getTextManager():getFontHeight(font)

    local pillW = textW + 4
    local pillH = textH + 2
    local pillX = slotX + math.floor((hotbar.slotWidth - pillW) / 2)
    local pillY = hotbar.margins + 2

    local bg = CSR_Theme.getColor("panelBg")
    hotbar:drawRect(pillX, pillY, pillW, pillH, 0.90, bg.r, bg.g, bg.b)
    hotbar:drawRectBorder(pillX, pillY, pillW, pillH, 0.5, color.r, color.g, color.b)
    hotbar:drawText(label, pillX + 2, pillY + 1, color.r, color.g, color.b, 1.0, font)
end

local function getFluidInfo(item)
    if not item or not item.getFluidContainer then return nil end
    local ok, fc = pcall(function() return item:getFluidContainer() end)
    if not ok or not fc then return nil end
    local okAmt, amount = pcall(function() return fc:getAmount() end)
    local okCap, capacity = pcall(function() return fc:getCapacity() end)
    if not okAmt or not okCap or type(amount) ~= "number" or type(capacity) ~= "number" or capacity <= 0 then return nil end
    local ratio = amount / capacity
    -- Get fluid color from the container
    local r, g, b = 0.2, 0.7, 1.0 -- default blue
    pcall(function()
        local col = fc:getColor()
        if col then
            r = col:getRedFloat()
            g = col:getGreenFloat()
            b = col:getBlueFloat()
        end
    end)
    -- Format amount text
    local label = nil
    pcall(function()
        if FluidUtil and FluidUtil.getAmountFormatted then
            label = FluidUtil.getAmountFormatted(amount)
        end
    end)
    if not label then
        label = tostring(math.floor(amount * 1000)) .. " mL"
    end
    return { amount = amount, capacity = capacity, ratio = ratio, r = r, g = g, b = b, label = label }
end

local function drawFluidPill(hotbar, slotX, item)
    local info = getFluidInfo(item)
    if not info then return end

    local color = { r = info.r, g = info.g, b = info.b }
    local label = info.label

    local font = UIFont.NewSmall
    local textW = getTextManager():MeasureStringX(font, label)
    local textH = getTextManager():getFontHeight(font)

    local pillW = textW + 6
    local pillH = textH + 2
    local pillX = slotX + math.floor((hotbar.slotWidth - pillW) / 2)
    local pillY = hotbar.margins + 2

    local bg = CSR_Theme.getColor("panelBg")
    hotbar:drawRect(pillX, pillY, pillW, pillH, 0.92, bg.r, bg.g, bg.b)
    hotbar:drawRectBorder(pillX, pillY, pillW, pillH, 0.5, color.r, color.g, color.b)
    hotbar:drawText(label, pillX + 3, pillY + 1, color.r, color.g, color.b, 1.0, font)
end

local function drawFluidTint(hotbar, slotX, item)
    local info = getFluidInfo(item)
    if not info then return end

    local y = hotbar.margins + 1
    local w = hotbar.slotWidth
    local h = hotbar.slotHeight

    hotbar:drawRect(slotX, y, w, h, 0.15, info.r, info.g, info.b)

    local barH = 3
    local barW = math.max(1, math.floor(w * info.ratio))
    local barY = y + h - barH
    hotbar:drawRect(slotX, barY, barW, barH, 0.80, info.r, info.g, info.b)
end

local function drawSlotOverlay(hotbar, slotX, item)
    if not item then return end

    -- Check if this item is a fluid container
    local fluidInfo = getFluidInfo(item)
    local current = getAmmoInfo(item)

    if fluidInfo and not current and not isDrainableItem(item) then
        -- Fluid container (water bottle, canteen, etc.)
        drawFluidTint(hotbar, slotX, item)
        drawFluidPill(hotbar, slotX, item)
    else
        -- Standard weapon/drainable overlay
        drawConditionTint(hotbar, slotX, item)
        if current then
            drawAmmoPill(hotbar, slotX, item)
        elseif isDrainableItem(item) then
            drawBatteryPill(hotbar, slotX, item)
        end
    end
end

local function patchHotbarRender()
    if not ISHotbar or not ISHotbar.render or ISHotbar.__csr_weapon_hud_overlay then
        return
    end
    if CSR_FeatureFlags.isCleanHotBarActive() then
        print("[CSR] CleanHotBar detected — skipping CSR weapon HUD overlay patch")
        return
    end
    ISHotbar.__csr_weapon_hud_overlay = true

    -- Also claim the flashlight indicator guard so its old code doesn't re-patch
    ISHotbar.__csr_flashlight_indicator = true

    local originalRender = ISHotbar.render
    local _errorLogged = {}

    function ISHotbar:render()
        originalRender(self)

        local slotX = self.margins + 1
        for i, _ in pairs(self.availableSlot) do
            local item = self.attachedItems[i]
            if item then
                -- Weapon/battery overlay
                if CSR_FeatureFlags.isWeaponHudOverlayEnabled() then
                    local ok, err = pcall(drawSlotOverlay, self, slotX, item)
                    if not ok and not _errorLogged["overlay"] then
                        _errorLogged["overlay"] = true
                        print("[CSR] drawSlotOverlay error: " .. tostring(err))
                    end
                end

                -- Flashlight on/off indicator
                if CSR_HotbarFlashlightIndicator and CSR_HotbarFlashlightIndicator.drawFlashlightIndicator then
                    local ok, err = pcall(CSR_HotbarFlashlightIndicator.drawFlashlightIndicator, self, slotX, item)
                    if not ok and not _errorLogged["flashlight"] then
                        _errorLogged["flashlight"] = true
                        print("[CSR] drawFlashlightIndicator error: " .. tostring(err))
                    end
                end
            end
            slotX = slotX + self.slotWidth + self.slotPad
        end
    end
end

local function drawEquippedWeaponAmmo()
    if not CSR_FeatureFlags.isWeaponHudOverlayEnabled() then
        return
    end

    local player = getSpecificPlayer(0)
    if not player then return end

    local weapon = player:getPrimaryHandItem()
    if not weapon then return end

    local current, max = getAmmoInfo(weapon)
    if not current then return end

    local ratio = current / max
    local color = getConditionColor(ratio)
    if not color then return end

    local text = tostring(current) .. " / " .. tostring(max)
    local font = UIFont.Medium
    local tm = getTextManager()
    local textW = tm:MeasureStringX(font, text)
    local textH = tm:getFontHeight(font)

    local padX = 10
    local padY = 8
    local pillW = textW + padX * 2
    local pillH = textH + padY * 2

    -- Position next to the equipped item panel (top-left sidebar)
    local x, y
    local playerData = getPlayerData and getPlayerData(0) or nil
    local equippedPanel = playerData and playerData.equipped or nil
    if equippedPanel and equippedPanel.mainHand and equippedPanel:getIsVisible() then
        -- Place to the right of the mainHand circle
        x = equippedPanel:getAbsoluteX() + equippedPanel:getWidth() + 6
        y = equippedPanel:getAbsoluteY() + (equippedPanel.mainHand:getY() or 0)
            + math.floor(((equippedPanel.mainHand:getHeight() or 48) - pillH) / 2)
    else
        -- Fallback: top-left corner
        x = 20
        y = 20
    end

    -- Draw translucent rounded background (like CSR radial menu)
    local bg = CSR_Theme.getColor("panelBg")
    local border = CSR_Theme.getColor("panelBorder")
    if ISUIElement and ISUIElement.drawRectStatic then
        -- Main fill
        ISUIElement.drawRectStatic(x + 2, y, pillW - 4, pillH, 0.88, bg.r, bg.g, bg.b)
        ISUIElement.drawRectStatic(x, y + 2, pillW, pillH - 4, 0.88, bg.r, bg.g, bg.b)
        -- Corner fills for rounded look
        ISUIElement.drawRectStatic(x + 1, y + 1, pillW - 2, pillH - 2, 0.88, bg.r, bg.g, bg.b)
        -- Accent stripe on left
        ISUIElement.drawRectStatic(x + 1, y + 2, 3, pillH - 4, 0.90, color.r, color.g, color.b)
        -- Border
        if ISUIElement.drawRectBorderStatic then
            ISUIElement.drawRectBorderStatic(x + 1, y + 1, pillW - 2, pillH - 2, 0.55, border.r, border.g, border.b)
        end
    end

    -- Draw text centered
    tm:DrawString(font, x + padX, y + padY, text, color.r, color.g, color.b, 1.0)
end

-- Controller-active gate. JoypadState.players[N+1] is non-nil only
-- when player N is using a controller as the active input. KB&M
-- players have nil here, so this short-circuit never fires for them.
-- Aim-cursor pills anchor to getMouseX/Y which is meaningless on
-- controller, so we suppress them entirely in that mode.
local function isControllerActive(playerNum)
    if not JoypadState or not JoypadState.players then return false end
    return JoypadState.players[(playerNum or 0) + 1] ~= nil
end

local function drawAimingAmmoCounter()
    if not CSR_FeatureFlags.isAimingAmmoCursorEnabled() then
        return
    end
    if isControllerActive(0) then return end

    local player = getSpecificPlayer(0)
    if not player then return end
    if not player:isAiming() then return end

    local weapon = player:getPrimaryHandItem()
    if not weapon then return end

    local current, max = getAmmoInfo(weapon)
    if not current then return end

    local ratio = current / max
    local color = getConditionColor(ratio)
    if not color then return end

    local text = tostring(current) .. " / " .. tostring(max)
    local font = UIFont.Medium
    local tm = getTextManager()
    local textW = tm:MeasureStringX(font, text)
    local textH = tm:getFontHeight(font)

    local padX = 6
    local padY = 4
    local pillW = textW + padX * 2
    local pillH = textH + padY * 2

    -- Position below and to the right of the mouse cursor
    local mx = getMouseX()
    local my = getMouseY()
    local x = mx + 24
    local y = my + 24

    -- Keep on screen
    local sw = getCore():getScreenWidth()
    local sh = getCore():getScreenHeight()
    if x + pillW > sw then x = mx - pillW - 8 end
    if y + pillH > sh then y = my - pillH - 8 end

    local bg = CSR_Theme.getColor("panelBg")
    if ISUIElement and ISUIElement.drawRectStatic then
        ISUIElement.drawRectStatic(x, y, pillW, pillH, 0.88, bg.r, bg.g, bg.b)
        if ISUIElement.drawRectBorderStatic then
            ISUIElement.drawRectBorderStatic(x, y, pillW, pillH, 0.50, color.r, color.g, color.b)
        end
    end

    tm:DrawString(font, x + padX, y + padY, text, color.r, color.g, color.b, 1.0)
end

-- Shared cursor-pill renderer for the small HP / Density pills that flank the
-- ammo counter while aiming. slotOffset: -1 = above ammo, +1 = below.
local function drawCursorAuxPill(text, color, slotOffset)
    local font = UIFont.Small
    local tm = getTextManager()
    local textW = tm:MeasureStringX(font, text)
    local textH = tm:getFontHeight(font)

    local padX = 5
    local padY = 3
    local pillW = textW + padX * 2
    local pillH = textH + padY * 2

    local mx = getMouseX()
    local my = getMouseY()
    local x = mx + 24
    -- Vertically stack relative to the ammo pill anchor (my + 24).
    -- Ammo pill (UIFont.Medium, padY=4) is roughly textH+8 tall (~30px in B42).
    -- Reserve a 38px slot per pill (pill height + ~6px gap) so HP sits cleanly
    -- above and Density sits below without overlapping the ammo counter.
    local SLOT_H = 38
    local y = my + 24 + (slotOffset * SLOT_H)

    local sw = getCore():getScreenWidth()
    local sh = getCore():getScreenHeight()
    if x + pillW > sw then x = mx - pillW - 8 end
    if y + pillH > sh then y = my - pillH - 8 end
    if y < 0 then y = 0 end

    local bg = CSR_Theme.getColor("panelBg")
    if ISUIElement and ISUIElement.drawRectStatic then
        ISUIElement.drawRectStatic(x, y, pillW, pillH, 0.85, bg.r, bg.g, bg.b)
        if ISUIElement.drawRectBorderStatic then
            ISUIElement.drawRectBorderStatic(x, y, pillW, pillH, 0.45, color.r, color.g, color.b)
        end
    end

    tm:DrawString(font, x + padX, y + padY, text, color.r, color.g, color.b, 1.0)
end

local function drawAimingHealthCursor()
    if not CSR_FeatureFlags.isAimingHealthCursorEnabled() then
        return
    end
    if isControllerActive(0) then return end

    local player = getSpecificPlayer(0)
    if not player then return end
    if not player:isAiming() then return end

    local bd = player.getBodyDamage and player:getBodyDamage()
    if not bd then return end

    local hp = bd.getOverallBodyHealth and bd:getOverallBodyHealth()
    if type(hp) ~= "number" then return end

    local ratio = math.max(0, math.min(1, hp / 100))
    local color = getConditionColor(ratio)
    if not color then return end

    -- Concise label: "HP 78"
    local text = "HP " .. tostring(math.floor(hp + 0.5))
    drawCursorAuxPill(text, color, -1)
end

local function drawAimingDensityCursor()
    if not CSR_FeatureFlags.isAimingDensityCursorEnabled() then
        return
    end
    if not CSR_NearbyDensityHUD or not CSR_NearbyDensityHUD.getCachedCount then
        return
    end
    if isControllerActive(0) then return end

    local player = getSpecificPlayer(0)
    if not player then return end
    if not player:isAiming() then return end

    local count = CSR_NearbyDensityHUD.getCachedCount() or 0
    local tier = CSR_NearbyDensityHUD.getCachedTier() or 0
    local colorKey = CSR_NearbyDensityHUD.getTierColorKey(tier) or "accentSlate"
    local color = CSR_Theme.getColor(colorKey)
    if not color then return end

    local text = "Zeds " .. tostring(count)
    drawCursorAuxPill(text, color, 1)
end


if Events and Events.OnGameStart then
    Events.OnGameStart.Add(patchHotbarRender)
end

-- CleanHotBar compat: suppress vanilla's duplicate tooltip in ISHotbar:update.
-- Vanilla manages self.toolRender; CleanHotBar adds self.tooltipRender via updateTooltip().
-- Both show at the same time → double tooltips. Patch update() to skip vanilla tooltip when CHB active.
local function patchHotbarUpdateForCleanHotBar()
    if not ISHotbar or not ISHotbar.update or ISHotbar.__csr_chb_tooltip_fix then return end
    if not CSR_FeatureFlags.isCleanHotBarActive() then return end
    ISHotbar.__csr_chb_tooltip_fix = true

    local origUpdate = ISHotbar.update
    function ISHotbar:update()
        -- Hide vanilla toolRender if it exists (CHB manages its own tooltipRender)
        if self.toolRender then
            self.toolRender:setVisible(false)
            self.toolRender:removeFromUIManager()
            self.toolRender = nil
        end
        origUpdate(self)
        -- Suppress any toolRender that vanilla's update() just created
        if self.toolRender then
            self.toolRender:setVisible(false)
            self.toolRender:removeFromUIManager()
            self.toolRender = nil
        end
    end
end

if Events and Events.OnGameStart then
    Events.OnGameStart.Add(patchHotbarUpdateForCleanHotBar)
end

-- =============================================================
-- v1.8.11 -- Vanilla ISHotbar:update NPE guard (rewritten).
-- Earlier v1.7.5 implementation actively dropped entries whose
-- getAttachedToModel() returned null. That worked for stale-save
-- flashlights but caused a worse regression: every clothing change
-- (mask/jacket swap) briefly nulls the attached-to-model field on
-- still-valid hotbar items. The drop unequipped weapons from the
-- belt and shifted slots, producing the bug reported in v1.8.10.
--
-- New approach: prevent the bad call instead of swallowing it.
-- Vanilla ISHotbar:update iterates self.attachedItems and calls
--     self.chr:getAttachedItem(item:getAttachedToModel())
-- If getAttachedToModel() is null (transient during clothing
-- change, or persistent on a stale-save flashlight from a removed
-- mod), Java throws "locationId is null" and aborts the UI tick.
--
-- We sidecar-stash any entry whose location is null *before*
-- delegating to vanilla update, then restore it afterward. Vanilla
-- never iterates that slot this frame, so no NPE is thrown at all
-- (no pcall hiding, no PZ error-handler interference). The item
-- stays in its slot the entire time; on the next frame after the
-- model rebuilds, the location is non-null and vanilla processes
-- it normally.
-- =============================================================
local function patchHotbarUpdateForNullAttachGuard()
    if not ISHotbar or not ISHotbar.update or ISHotbar.__csr_null_attach_guard then return end
    ISHotbar.__csr_null_attach_guard = true

    local origUpdate = ISHotbar.update
    function ISHotbar:update()
        local stash = nil
        if self.attachedItems then
            for i, item in pairs(self.attachedItems) do
                local skip = false
                if not item or item.getAttachedToModel == nil then
                    skip = true
                elseif item:getAttachedToModel() == nil then
                    skip = true
                end
                if skip then
                    if not stash then stash = {} end
                    stash[i] = item
                end
            end
            if stash then
                for i, _ in pairs(stash) do
                    self.attachedItems[i] = nil
                end
            end
        end

        origUpdate(self)

        -- Restore stashed entries so they remain in their slots and
        -- get processed normally on the next frame.
        if stash and self.attachedItems then
            for i, item in pairs(stash) do
                if self.attachedItems[i] == nil then
                    self.attachedItems[i] = item
                end
            end
        end
    end
end

if Events and Events.OnGameStart then
    Events.OnGameStart.Add(patchHotbarUpdateForNullAttachGuard)
end

if Events and Events.OnPostUIDraw then
    Events.OnPostUIDraw.Add(drawEquippedWeaponAmmo)
    Events.OnPostUIDraw.Add(drawAimingAmmoCounter)
    Events.OnPostUIDraw.Add(drawAimingHealthCursor)
    Events.OnPostUIDraw.Add(drawAimingDensityCursor)
end
