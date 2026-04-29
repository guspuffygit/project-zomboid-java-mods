require "CSR_FeatureFlags"
require "CSR_Utils"
require "CSR_Theme"

CSR_ItemInsights = {}

local function fmtTime(days)
    days = math.max(0, days or 0)
    local d = math.floor(days)
    local remH = (days - d) * 24
    local h = math.floor(remH)
    local m = math.floor((remH - h) * 60)
    local parts = {}
    if d > 0 then parts[#parts + 1] = d .. "d" end
    if h > 0 then parts[#parts + 1] = h .. "h" end
    if m > 0 then parts[#parts + 1] = m .. "m" end
    return #parts > 0 and table.concat(parts, " ") or "<1m"
end

local function safeCall(obj, fnName, ...)
    if not obj or type(obj[fnName]) ~= "function" then
        return nil
    end
    return obj[fnName](obj, ...)
end

local ROT_SPEED_MAP = { 1.7, 1.4, 1.0, 0.7, 0.4 }
local FRIDGE_FACTOR_MAP = { 0.4, 0.3, 0.2, 0.1, 0.03 }

local function getRotSpeedMultiplier()
    local idx = SandboxVars and SandboxVars.FoodRotSpeed or 3
    return ROT_SPEED_MAP[idx] or 1.0
end

local function getFridgeFactorMultiplier()
    local idx = SandboxVars and SandboxVars.FridgeFactor or 3
    return FRIDGE_FACTOR_MAP[idx] or 0.2
end

local function isItemRefrigerated(item)
    if safeCall(item, "isFrozen") or safeCall(item, "isThawing") then
        return true
    end
    local container = safeCall(item, "getContainer")
    if container then
        local ctype = safeCall(container, "getType")
        if ctype == "fridge" or ctype == "freezer" then
            local heat = safeCall(item, "getHeat")
            return type(heat) == "number" and heat < 1
        end
    end
    return false
end

local function getFoodInsight(item)
    if not item or not instanceof(item, "Food") then
        return nil
    end

    local freezingTime = safeCall(item, "getFreezingTime")
    if type(freezingTime) == "number" and freezingTime > 0 then
        if safeCall(item, "isFrozen") then
            return { label = "Frozen", color = CSR_Theme.withAlpha(CSR_Theme.getColor("accentBlue"), 0.95) }
        end
        return { label = "Freezing: " .. math.floor(freezingTime) .. "%", color = CSR_Theme.withAlpha(CSR_Theme.getColor("accentBlue"), 0.95) }
    end

    local age = safeCall(item, "getAge") or 0
    local offAge = safeCall(item, "getOffAge") or 0
    local offAgeMax = safeCall(item, "getOffAgeMax") or 0
    if type(offAgeMax) ~= "number" or offAgeMax <= 0 or offAgeMax > 9999 then
        return nil
    end

    local rotSpeed = getRotSpeedMultiplier()
    local effectiveSpeed = rotSpeed
    if isItemRefrigerated(item) then
        effectiveSpeed = rotSpeed * getFridgeFactorMultiplier()
    end

    local label
    local color
    if age >= offAgeMax then
        label = "Rotten"
        color = CSR_Theme.withAlpha(CSR_Theme.getColor("accentRed"), 0.95)
    elseif offAge > 0 and age >= offAge then
        label = "Stale for: " .. fmtTime((offAgeMax - age) / math.max(0.001, effectiveSpeed))
        color = CSR_Theme.withAlpha(CSR_Theme.getColor("accentAmber"), 0.95)
    else
        label = "Fresh for: " .. fmtTime((offAge - age) / math.max(0.001, effectiveSpeed))
        color = CSR_Theme.withAlpha(CSR_Theme.getColor("accentGreen"), 0.95)
    end

    return { label = label, color = color }
end

local function getNutritionInsight(item)
    local summary = CSR_Utils.getFoodNutritionSummary and CSR_Utils.getFoodNutritionSummary(item) or nil
    if not summary then
        return nil
    end

    return {
        label = "Nutrition: " .. summary,
        color = CSR_Theme.withAlpha(CSR_Theme.getColor("text"), 0.95)
    }
end

local function getDrainableInsight(item)
    if not item then
        return nil
    end

    local fluidContainer = safeCall(item, "getFluidContainer")
    if fluidContainer then
        local amount = safeCall(fluidContainer, "getAmount")
        local capacity = safeCall(fluidContainer, "getCapacity")
        if type(amount) == "number" and type(capacity) == "number" and capacity > 0 then
            local pct = math.max(0, math.floor((amount / capacity) * 100))
            return { label = "Contents: " .. pct .. "%", color = CSR_Theme.withAlpha(CSR_Theme.getColor("accentBlue"), 0.95) }
        end
    end

    if instanceof(item, "Drainable") or instanceof(item, "DrainableComboItem") then
        local uses = safeCall(item, "getCurrentUsesFloat")
        if type(uses) == "number" then
            local pct = math.max(0, math.floor(uses * 100))
            local color = pct > 25 and CSR_Theme.withAlpha(CSR_Theme.getColor("accentBlue"), 0.95)
                or (pct > 0 and CSR_Theme.withAlpha(CSR_Theme.getColor("accentAmber"), 0.95)
                or CSR_Theme.withAlpha(CSR_Theme.getColor("accentRed"), 0.95))
            return { label = "Remaining: " .. pct .. "%", color = color }
        end
    end

    return nil
end

local function getLiteratureInsight(item)
    if not item or not instanceof(item, "Literature") then
        return nil
    end

    local totalPages = safeCall(item, "getNumberOfPages")
    if type(totalPages) ~= "number" or totalPages <= 0 then
        return nil
    end

    local readPages = 0
    local player = getPlayer and getPlayer() or nil
    if player and player.getAlreadyReadPages then
        readPages = player:getAlreadyReadPages(item:getFullType()) or 0
    end
    readPages = math.min(readPages, totalPages)

    local done = readPages >= totalPages
    return {
        label = string.format("Read pages: %d/%d", readPages, totalPages),
        color = done and CSR_Theme.withAlpha(CSR_Theme.getColor("accentGreen"), 0.95)
            or CSR_Theme.withAlpha(CSR_Theme.getColor("accentAmber"), 0.95)
    }
end

local function getBestDuplicateCondition(player, item)
    if not player or not item or not (instanceof(item, "HandWeapon") or instanceof(item, "Clothing")) then
        return nil
    end

    local inventory = player:getInventory()
    if not inventory then
        return nil
    end

    local fullType = item:getFullType()
    local current = safeCall(item, "getCondition") or 0
    local best = current
    local items = inventory:getItems()
    for i = 0, items:size() - 1 do
        local other = items:get(i)
        if other and other ~= item and other:getFullType() == fullType then
            best = math.max(best, safeCall(other, "getCondition") or 0)
        end
    end

    if best > current then
        return {
            label = string.format("Better duplicate in inventory: %d%%", best),
            color = CSR_Theme.withAlpha(CSR_Theme.getColor("accentAmber"), 0.95)
        }
    end

    return nil
end

local function collectInsights(item)
    local insights = {}
    local player = getPlayer and getPlayer() or nil

    local food = getFoodInsight(item)
    if food then insights[#insights + 1] = food end

    local nutrition = getNutritionInsight(item)
    if nutrition then insights[#insights + 1] = nutrition end

    local drain = getDrainableInsight(item)
    if drain then insights[#insights + 1] = drain end

    local lit = getLiteratureInsight(item)
    if lit then insights[#insights + 1] = lit end

    local dup = getBestDuplicateCondition(player, item)
    if dup then insights[#insights + 1] = dup end

    return insights
end

local function hookTooltip()
    if not ISToolTipInv or not ISToolTipInv.render or ISToolTipInv.__csr_item_insights then
        return
    end

    ISToolTipInv.__csr_item_insights = true
    local originalRender = ISToolTipInv.render
    function ISToolTipInv:render(...)
        originalRender(self, ...)

        if not CSR_FeatureFlags.isItemInsightTooltipsEnabled() then
            return
        end

        local item = self.item
        if not item then
            return
        end

        local insights = collectInsights(item)
        if #insights == 0 then
            return
        end

        local font = UIFont.NewSmall
        local fontHeight = getTextManager():getFontHeight(font)
        local extraHeight = (#insights * (fontHeight + 2)) + 6
        local width = self:getWidth()
        local y = self:getHeight()

        -- Expand tooltip width if any insight label is wider than current width
        local padX = 12
        for i = 1, #insights do
            local textW = getTextManager():MeasureStringX(font, "  " .. insights[i].label) + padX
            if textW > width then
                width = textW
            end
        end
        if width > self:getWidth() then
            self:setWidth(width)
        end

        local bg = CSR_Theme.withAlpha(CSR_Theme.getColor("panelBg"), 0.92)
        local border = CSR_Theme.withAlpha(CSR_Theme.getColor("panelBorder"), 0.78)
        self:drawRect(0, y, width, extraHeight, bg.a, bg.r, bg.g, bg.b)
        self:drawRectBorder(0, y, width, extraHeight, border.a, border.r, border.g, border.b)

        for i = 1, #insights do
            local insight = insights[i]
            local iy = y + 3 + ((i - 1) * (fontHeight + 2))
            self:drawText("  " .. insight.label, 4, iy, insight.color.r, insight.color.g, insight.color.b, insight.color.a, font)
        end

        self:setHeight(y + extraHeight)
    end
end

if Events and Events.OnGameStart then
    Events.OnGameStart.Add(hookTooltip)
end

return CSR_ItemInsights
