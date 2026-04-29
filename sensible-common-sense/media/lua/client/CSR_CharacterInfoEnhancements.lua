require "CSR_Utils"
require "CSR_Theme"
require "CSR_FeatureFlags"

local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local FONT_HGT_MEDIUM = getTextManager():getFontHeight(UIFont.Medium)
local UI_BORDER_SPACING = 10

local function csrDrawStatRow(self, label, value, x, y, labelWidth, valueColor)
    local labelColor = CSR_Theme.getColor("textMuted")
    valueColor = valueColor or CSR_Theme.getColor("text")
    self:drawTextRight(label, x + labelWidth, y, labelColor.r, labelColor.g, labelColor.b, 1, UIFont.Small)
    self:drawText(value, x + labelWidth + UI_BORDER_SPACING, y, valueColor.r, valueColor.g, valueColor.b, 1, UIFont.Small)
end

local function csrPatchCharacterScreen()
    if not CSR_FeatureFlags.isCharacterInfoEnhancementsEnabled() then return end
    if not ISCharacterScreen or ISCharacterScreen.CSR_renderPatched then
        return
    end

    local originalRender = ISCharacterScreen.render

    function ISCharacterScreen:render()
        originalRender(self)

        local character = self.char
        if not character then
            return
        end

        local nutrition = CSR_Utils.getCharacterNutritionSummary and CSR_Utils.getCharacterNutritionSummary(character) or nil
        if not nutrition then
            return
        end

        local sectionX = 20
        local sectionY = self.height + 6
        local sectionWidth = math.max(240, self.width - (sectionX * 2))
        local rowCount = 5
        local sectionHeight = FONT_HGT_MEDIUM + (FONT_HGT_SMALL * rowCount) + UI_BORDER_SPACING * (rowCount + 2)
        local labelWidth = math.max(
            getTextManager():MeasureStringX(UIFont.Small, getText("IGUI_char_Weight")),
            getTextManager():MeasureStringX(UIFont.Small, "Weight Trend"),
            getTextManager():MeasureStringX(UIFont.Small, "Calories"),
            getTextManager():MeasureStringX(UIFont.Small, "Protein"),
            getTextManager():MeasureStringX(UIFont.Small, "Carbs / Fats")
        )

        self:setHeightAndParentHeight(sectionY + sectionHeight + UI_BORDER_SPACING)

        local bg = CSR_Theme.withAlpha(CSR_Theme.getColor("panelBg"), 0.42)
        local border = CSR_Theme.withAlpha(CSR_Theme.getColor("panelBorder"), 0.85)
        local header = CSR_Theme.getColor("accentBlue")
        self:drawRectBorder(sectionX, sectionY, sectionWidth, sectionHeight, border.a, border.r, border.g, border.b)
        self:drawRect(sectionX, sectionY, sectionWidth, sectionHeight, bg.a, bg.r, bg.g, bg.b)

        local accentBar = CSR_Theme.getColor("accentBlue")
        self:drawRect(sectionX, sectionY, 3, sectionHeight, 0.7, accentBar.r, accentBar.g, accentBar.b)

        self:drawText("Nutrition", sectionX + UI_BORDER_SPACING, sectionY + UI_BORDER_SPACING, header.r, header.g, header.b, 1, UIFont.Medium)

        local rowY = sectionY + UI_BORDER_SPACING + FONT_HGT_MEDIUM + 4

        local weightColor = CSR_Theme.getColor("text")
        csrDrawStatRow(self, getText("IGUI_char_Weight"), nutrition.weightText, sectionX + UI_BORDER_SPACING, rowY, labelWidth, weightColor)

        rowY = rowY + FONT_HGT_SMALL + UI_BORDER_SPACING
        local trendColor
        if nutrition.trend == "Gaining fast" then
            trendColor = CSR_Theme.getColor("accentAmber")
        elseif nutrition.trend == "Gaining" then
            trendColor = { r = 0.9, g = 0.8, b = 0.3 }
        elseif nutrition.trend == "Losing" then
            trendColor = CSR_Theme.getColor("accentRed")
        else
            trendColor = CSR_Theme.getColor("accentGreen")
        end
        csrDrawStatRow(self, "Weight Trend", nutrition.trend, sectionX + UI_BORDER_SPACING, rowY, labelWidth, trendColor)

        rowY = rowY + FONT_HGT_SMALL + UI_BORDER_SPACING
        local calColor
        if nutrition.calories >= 1500 then
            calColor = CSR_Theme.getColor("accentGreen")
        elseif nutrition.calories >= 800 then
            calColor = CSR_Theme.getColor("accentAmber")
        else
            calColor = CSR_Theme.getColor("accentRed")
        end
        csrDrawStatRow(self, "Calories", nutrition.caloriesText, sectionX + UI_BORDER_SPACING, rowY, labelWidth, calColor)

        rowY = rowY + FONT_HGT_SMALL + UI_BORDER_SPACING
        local protColor
        if nutrition.proteins >= 0 then
            protColor = CSR_Theme.getColor("accentGreen")
        else
            protColor = CSR_Theme.getColor("accentRed")
        end
        csrDrawStatRow(self, "Protein", nutrition.proteinsText, sectionX + UI_BORDER_SPACING, rowY, labelWidth, protColor)

        rowY = rowY + FONT_HGT_SMALL + UI_BORDER_SPACING
        local carbFatColor = CSR_Theme.getColor("text")
        csrDrawStatRow(self, "Carbs / Fats", nutrition.carbsText .. " / " .. nutrition.fatsText, sectionX + UI_BORDER_SPACING, rowY, labelWidth, carbFatColor)
    end

    ISCharacterScreen.CSR_renderPatched = true
end

if Events and Events.OnGameStart then
    Events.OnGameStart.Add(csrPatchCharacterScreen)
end
