require "ISUI/AdminPanel/ZoneEditor/MultiplayerZoneEditorMode"
require "ZoneMarkerShared"
require "ZoneMarkerClient"

local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local UI_BORDER_SPACING = 10
local BUTTON_HGT = FONT_HGT_SMALL + 6

---@type string
local MODULE = ZoneMarkerShared.MODULE

MultiplayerZoneEditorMode_ZoneMarker = MultiplayerZoneEditorMode:derive("MultiplayerZoneEditorMode_ZoneMarker")

function MultiplayerZoneEditorMode_ZoneMarker:createChildren()
    -- Category combo box
    local comboY = self.editor.modeCombo:getBottom() + UI_BORDER_SPACING
    local label = ISLabel:new(UI_BORDER_SPACING, comboY, BUTTON_HGT, "Category:", 1, 1, 1, 1, UIFont.Small, true)
    self:addChild(label)

    self.categoryCombo = ISComboBox:new(label:getRight() + 4, comboY, 200, FONT_HGT_SMALL + 4, self, self.onCategoryChanged)
    self:addChild(self.categoryCombo)

    local btnX = self.categoryCombo:getRight() + UI_BORDER_SPACING
    local addCatBtn = ISButton:new(btnX, comboY, 20, BUTTON_HGT, "+", self, self.onAddCategory)
    self:addChild(addCatBtn)

    local removeCatBtn = ISButton:new(addCatBtn:getRight() + 4, comboY, 20, BUTTON_HGT, "-", self, self.onRemoveCategory)
    self:addChild(removeCatBtn)
    self.removeCatBtn = removeCatBtn
end

function MultiplayerZoneEditorMode_ZoneMarker:prerender()
    self:fillCategoryCombo()
    local hasCats = #ZoneMarkerCache.categories > 0
    self.removeCatBtn:setEnable(hasCats)
end

function MultiplayerZoneEditorMode_ZoneMarker:render()
    -- Render all zones from all visible categories on the map
    for _, cat in ipairs(ZoneMarkerCache.categories) do
        local zones = ZoneMarkerCache.zones[cat.name]
        if zones then
            for _, zone in ipairs(zones) do
                self:renderZoneRect(zone, cat.r, cat.g, cat.b, cat.a)
            end
        end
    end
end

function MultiplayerZoneEditorMode_ZoneMarker:renderZoneRect(zone, r, g, b, a)
    local x1 = self.mapAPI:worldToUIX(zone.xStart, zone.yStart)
    local y1 = self.mapAPI:worldToUIY(zone.xStart, zone.yStart)
    local x2 = self.mapAPI:worldToUIX(zone.xEnd, zone.yEnd)
    local y2 = self.mapAPI:worldToUIY(zone.xEnd, zone.yEnd)
    self.mapUI.javaObject:DrawTextureScaledColor(nil, PZMath.floor(x1), PZMath.floor(y1), x2 - x1, y2 - y1, r, g, b, a)
    local midX = (zone.xStart + zone.xEnd) / 2
    local midY = (zone.yStart + zone.yEnd) / 2
    local sx = PZMath.floor(self.mapAPI:worldToUIX(midX, midY))
    local sy = PZMath.floor(self.mapAPI:worldToUIY(midX, midY))
    self:drawText(zone.region, sx + 4, sy + 2, 0, 0, 0, 1, UIFont.Small)
end

function MultiplayerZoneEditorMode_ZoneMarker:fillCategoryCombo()
    local categories = ZoneMarkerCache.categories
    local currentCount = self.categoryCombo:getOptionCount()
    if currentCount == #categories then return end

    local selectedName = nil
    if currentCount > 0 then
        selectedName = self.categoryCombo:getOptionData(self.categoryCombo:getSelected())
    end

    self.categoryCombo:clear()
    for i, cat in ipairs(categories) do
        self.categoryCombo:addOptionWithData(cat.name, cat.name)
        if cat.name == selectedName then
            self.categoryCombo:setSelected(i)
        end
    end
end

function MultiplayerZoneEditorMode_ZoneMarker:getSelectedCategoryName()
    if self.categoryCombo:getOptionCount() == 0 then return nil end
    return self.categoryCombo:getOptionData(self.categoryCombo:getSelected())
end

function MultiplayerZoneEditorMode_ZoneMarker:onCategoryChanged()
    -- Future: update zone listbox for selected category
end

-- Add Category: opens a custom modal for name + color
function MultiplayerZoneEditorMode_ZoneMarker:onAddCategory()
    if self.modalUI then
        self.modalUI:close()
        self.modalUI:setVisible(false)
        self.modalUI:removeFromUIManager()
        self.modalUI = nil
    end
    local modal = ZoneMarkerAddCategoryDialog:new(self)
    modal:initialise()
    modal:addToUIManager()
    modal:setAlwaysOnTop(true)
    self.modalUI = modal
end

-- Remove Category: confirmation dialog
function MultiplayerZoneEditorMode_ZoneMarker:onRemoveCategory()
    local name = self:getSelectedCategoryName()
    if not name then return end
    if self.modalUI then
        self.modalUI:close()
        self.modalUI:setVisible(false)
        self.modalUI:removeFromUIManager()
        self.modalUI = nil
    end
    local modal = ISModalDialog:new(
        self.removeCatBtn:getRight() + 20, self.removeCatBtn:getY(),
        350, 150,
        "Remove category '" .. name .. "'? All zones in this category will be deleted.",
        true, self, self.onConfirmRemoveCategory
    )
    modal:initialise()
    modal:addToUIManager()
    modal:setAlwaysOnTop(true)
    modal.moveWithMouse = true
    modal.categoryName = name
    self.modalUI = modal
end

function MultiplayerZoneEditorMode_ZoneMarker:onConfirmRemoveCategory(button)
    if button.internal == "YES" then
        local name = button.parent.categoryName
        sendClientCommand(getPlayer(), MODULE, "removeCategory", {name = name})
    end
end

function MultiplayerZoneEditorMode_ZoneMarker:undisplay()
    if self.modalUI then
        self.modalUI:close()
        self.modalUI:setVisible(false)
        self.modalUI:removeFromUIManager()
        self.modalUI = nil
    end
    MultiplayerZoneEditorMode.undisplay(self)
end

function MultiplayerZoneEditorMode_ZoneMarker:new(editor)
    local o = MultiplayerZoneEditorMode.new(self, editor)
    return o
end

--
-- Add Category Dialog
--
ZoneMarkerAddCategoryDialog = ISPanel:derive("ZoneMarkerAddCategoryDialog")

function ZoneMarkerAddCategoryDialog:initialise()
    ISPanel.initialise(self)
    self:createChildren()
end

function ZoneMarkerAddCategoryDialog:createChildren()
    local x = UI_BORDER_SPACING
    local y = UI_BORDER_SPACING
    local labelW = 60
    local entryW = 160
    local rowH = FONT_HGT_SMALL + 8

    -- Title bar
    local title = ISLabel:new(x, y, BUTTON_HGT, "Add Category", 1, 1, 1, 1, UIFont.Small, true)
    self:addChild(title)
    y = y + BUTTON_HGT + UI_BORDER_SPACING

    -- Name
    local nameLabel = ISLabel:new(x, y, rowH, "Name:", 1, 1, 1, 1, UIFont.Small, true)
    self:addChild(nameLabel)
    self.nameEntry = ISTextEntryBox:new("", labelW + x, y, entryW, rowH)
    self.nameEntry:initialise()
    self.nameEntry:instantiate()
    self:addChild(self.nameEntry)
    y = y + rowH + 4

    -- R
    local rLabel = ISLabel:new(x, y, rowH, "R:", 1, 1, 1, 1, UIFont.Small, true)
    self:addChild(rLabel)
    self.rEntry = ISTextEntryBox:new("0.5", labelW + x, y, 60, rowH)
    self.rEntry:initialise()
    self.rEntry:instantiate()
    self:addChild(self.rEntry)
    y = y + rowH + 4

    -- G
    local gLabel = ISLabel:new(x, y, rowH, "G:", 1, 1, 1, 1, UIFont.Small, true)
    self:addChild(gLabel)
    self.gEntry = ISTextEntryBox:new("0.5", labelW + x, y, 60, rowH)
    self.gEntry:initialise()
    self.gEntry:instantiate()
    self:addChild(self.gEntry)
    y = y + rowH + 4

    -- B
    local bLabel = ISLabel:new(x, y, rowH, "B:", 1, 1, 1, 1, UIFont.Small, true)
    self:addChild(bLabel)
    self.bEntry = ISTextEntryBox:new("0.5", labelW + x, y, 60, rowH)
    self.bEntry:initialise()
    self.bEntry:instantiate()
    self:addChild(self.bEntry)
    y = y + rowH + 4

    -- A
    local aLabel = ISLabel:new(x, y, rowH, "A:", 1, 1, 1, 1, UIFont.Small, true)
    self:addChild(aLabel)
    self.aEntry = ISTextEntryBox:new("0.5", labelW + x, y, 60, rowH)
    self.aEntry:initialise()
    self.aEntry:instantiate()
    self:addChild(self.aEntry)
    y = y + rowH + UI_BORDER_SPACING

    -- Error label
    self.errorLabel = ISLabel:new(x, y, BUTTON_HGT, "", 1, 0, 0, 1, UIFont.Small, true)
    self:addChild(self.errorLabel)
    y = y + BUTTON_HGT + 4

    -- Buttons
    local okBtn = ISButton:new(x, y, 80, BUTTON_HGT, "OK", self, self.onOK)
    self:addChild(okBtn)

    local cancelBtn = ISButton:new(okBtn:getRight() + UI_BORDER_SPACING, y, 80, BUTTON_HGT, "Cancel", self, self.onCancel)
    self:addChild(cancelBtn)
end

function ZoneMarkerAddCategoryDialog:onOK()
    local name = self.nameEntry:getText()
    if not name or name == "" then
        self.errorLabel:setName("Name cannot be empty")
        return
    end

    local r = tonumber(self.rEntry:getText())
    local g = tonumber(self.gEntry:getText())
    local b = tonumber(self.bEntry:getText())
    local a = tonumber(self.aEntry:getText())

    if not r or not g or not b or not a then
        self.errorLabel:setName("R, G, B, A must be numbers")
        return
    end

    sendClientCommand(getPlayer(), MODULE, "addCategory", {name = name, r = r, g = g, b = b, a = a})
    self:close()
end

function ZoneMarkerAddCategoryDialog:onCancel()
    self:close()
end

function ZoneMarkerAddCategoryDialog:close()
    self:setVisible(false)
    self:removeFromUIManager()
    if self.mode then
        self.mode.modalUI = nil
    end
end

function ZoneMarkerAddCategoryDialog:new(mode)
    local w = 250
    local h = 280
    local screenW = getCore():getScreenWidth()
    local screenH = getCore():getScreenHeight()
    local x = (screenW - w) / 2
    local y = (screenH - h) / 2
    local o = ISPanel.new(self, x, y, w, h)
    o:setVisible(true)
    o.moveWithMouse = true
    o.mode = mode
    o.backgroundColor = {r = 0, g = 0, b = 0, a = 0.8}
    o.borderColor = {r = 0.4, g = 0.4, b = 0.4, a = 1}
    return o
end
