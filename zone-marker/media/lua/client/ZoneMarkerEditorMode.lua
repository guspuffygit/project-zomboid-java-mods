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

    -- Zone list
    local zoneY = comboY + BUTTON_HGT + UI_BORDER_SPACING
    local zoneLabel = ISLabel:new(UI_BORDER_SPACING, zoneY, BUTTON_HGT, "Zones:", 1, 1, 1, 1, UIFont.Small, true)
    self:addChild(zoneLabel)
    zoneY = zoneY + BUTTON_HGT + 4

    local listH = (FONT_HGT_SMALL + 4) * 6
    self.zoneList = ISScrollingListBox:new(UI_BORDER_SPACING, zoneY, 300, listH)
    self.zoneList:initialise()
    self.zoneList:instantiate()
    self.zoneList.itemheight = FONT_HGT_SMALL + 4
    self.zoneList.font = UIFont.Small
    self.zoneList.drawBorder = true
    self.zoneList.backgroundColor = {r = 0, g = 0, b = 0, a = 0.5}
    self:addChild(self.zoneList)
    zoneY = zoneY + listH + 4

    -- Zone buttons
    self.addZoneBtn = ISButton:new(UI_BORDER_SPACING, zoneY, 80, BUTTON_HGT, "+ Add Zone", self, self.onAddZone)
    self:addChild(self.addZoneBtn)

    self.removeZoneBtn = ISButton:new(self.addZoneBtn:getRight() + 4, zoneY, 90, BUTTON_HGT, "- Remove Zone", self, self.onRemoveZone)
    self:addChild(self.removeZoneBtn)
end

function MultiplayerZoneEditorMode_ZoneMarker:prerender()
    self:fillCategoryCombo()
    self:refreshZoneList()
    local hasCats = #ZoneMarkerCache.categories > 0
    self.removeCatBtn:setEnable(hasCats)
    self.addZoneBtn:setEnable(hasCats)
    self.removeZoneBtn:setEnable(hasCats and self.zoneList.selected > 0 and self.zoneList.selected <= #self.zoneList.items)
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

    -- Highlight selected zone
    local sel = self.zoneList.selected
    if sel > 0 and sel <= #self.zoneList.items then
        local zone = self.zoneList.items[sel].item
        if zone then
            self:renderZoneOutline(zone, 1, 1, 0, 1)
        end
    end

    -- Drawing feedback
    if self.drawState == "waiting" then
        local mx = self:getMouseX()
        local my = self:getMouseY()
        self:drawRect(mx - 10, my, 20, 1, 1, 1, 1, 0)
        self:drawRect(mx, my - 10, 1, 20, 1, 1, 1, 0)
    elseif self.drawState == "drawing" and self.drawStart and self.drawEnd then
        local x1 = self.mapAPI:worldToUIX(self.drawStart.x, self.drawStart.y)
        local y1 = self.mapAPI:worldToUIY(self.drawStart.x, self.drawStart.y)
        local x2 = self.mapAPI:worldToUIX(self.drawEnd.x, self.drawEnd.y)
        local y2 = self.mapAPI:worldToUIY(self.drawEnd.x, self.drawEnd.y)
        local rx = PZMath.min(x1, x2)
        local ry = PZMath.min(y1, y2)
        local rw = PZMath.abs(x2 - x1)
        local rh = PZMath.abs(y2 - y1)
        self:drawRectBorder(rx, ry, rw, rh, 1, 1, 1, 1)
        self.mapUI.javaObject:DrawTextureScaledColor(nil, PZMath.floor(rx), PZMath.floor(ry), rw, rh, 1, 1, 1, 0.2)
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

function MultiplayerZoneEditorMode_ZoneMarker:renderZoneOutline(zone, r, g, b, a)
    local x1 = self.mapAPI:worldToUIX(zone.xStart, zone.yStart)
    local y1 = self.mapAPI:worldToUIY(zone.xStart, zone.yStart)
    local x2 = self.mapAPI:worldToUIX(zone.xEnd, zone.yEnd)
    local y2 = self.mapAPI:worldToUIY(zone.xEnd, zone.yEnd)
    local rx = PZMath.min(x1, x2)
    local ry = PZMath.min(y1, y2)
    local rw = PZMath.abs(x2 - x1)
    local rh = PZMath.abs(y2 - y1)
    self:drawRectBorder(rx, ry, rw, rh, a, r, g, b)
    self:drawRectBorder(rx - 1, ry - 1, rw + 2, rh + 2, a, r, g, b)
end

function MultiplayerZoneEditorMode_ZoneMarker:refreshZoneList()
    local catName = self:getSelectedCategoryName()
    local zones = catName and ZoneMarkerCache.zones[catName] or {}
    local zoneCount = zones and #zones or 0

    -- Avoid rebuilding if nothing changed
    if catName == self.lastZoneListCategory and zoneCount == self.lastZoneListCount then
        return
    end
    self.lastZoneListCategory = catName
    self.lastZoneListCount = zoneCount

    local prevRegion = nil
    if self.zoneList.selected > 0 and self.zoneList.selected <= #self.zoneList.items then
        prevRegion = self.zoneList.items[self.zoneList.selected].item and self.zoneList.items[self.zoneList.selected].item.region
    end

    self.zoneList:clear()
    if zones then
        for i, zone in ipairs(zones) do
            local label = zone.region .. "  (" .. PZMath.floor(zone.xStart) .. "," .. PZMath.floor(zone.yStart) .. " -> " .. PZMath.floor(zone.xEnd) .. "," .. PZMath.floor(zone.yEnd) .. ")"
            self.zoneList:addItem(label, zone)
            if prevRegion and zone.region == prevRegion then
                self.zoneList.selected = i
            end
        end
    end
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
    self:cancelDrawing()
    self.lastZoneListCategory = nil
    self.lastZoneListCount = nil
end

-- Add Category: opens a custom modal for name + color
function MultiplayerZoneEditorMode_ZoneMarker:onAddCategory()
    self:closeModal()
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
    self:closeModal()
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

-- Zone addition: enter draw mode
function MultiplayerZoneEditorMode_ZoneMarker:onAddZone()
    local catName = self:getSelectedCategoryName()
    if not catName then return end
    if self.drawState then
        self:cancelDrawing()
        return
    end
    self.drawState = "waiting"
    self.addZoneBtn:setTitle("Cancel")
end

-- Zone removal: confirmation dialog
function MultiplayerZoneEditorMode_ZoneMarker:onRemoveZone()
    local catName = self:getSelectedCategoryName()
    if not catName then return end
    local sel = self.zoneList.selected
    if sel <= 0 or sel > #self.zoneList.items then return end
    local zone = self.zoneList.items[sel].item
    if not zone then return end

    self:closeModal()
    local modal = ISModalDialog:new(
        self.removeZoneBtn:getRight() + 20, self.removeZoneBtn:getY(),
        350, 150,
        "Remove zone '" .. zone.region .. "' from '" .. catName .. "'?",
        true, self, self.onConfirmRemoveZone
    )
    modal:initialise()
    modal:addToUIManager()
    modal:setAlwaysOnTop(true)
    modal.moveWithMouse = true
    modal.categoryName = catName
    modal.region = zone.region
    self.modalUI = modal
end

function MultiplayerZoneEditorMode_ZoneMarker:onConfirmRemoveZone(button)
    if button.internal == "YES" then
        sendClientCommand(getPlayer(), MODULE, "removeZone", {
            categoryName = button.parent.categoryName,
            region = button.parent.region,
        })
        self.lastZoneListCategory = nil
        self.lastZoneListCount = nil
    end
end

-- Drawing state machine: mouse overrides
function MultiplayerZoneEditorMode_ZoneMarker:onMouseDown(x, y)
    if self.drawState == "waiting" then
        local worldX = self.mapAPI:uiToWorldX(x, y)
        local worldY = self.mapAPI:uiToWorldY(x, y)
        self.drawStart = {x = worldX, y = worldY}
        self.drawEnd = {x = worldX, y = worldY}
        self.drawState = "drawing"
        return true
    end
    return false
end

function MultiplayerZoneEditorMode_ZoneMarker:onMouseUp(x, y)
    if self.drawState == "drawing" and self.drawStart then
        local worldX = self.mapAPI:uiToWorldX(x, y)
        local worldY = self.mapAPI:uiToWorldY(x, y)
        self.drawEnd = {x = worldX, y = worldY}

        local xStart = PZMath.min(self.drawStart.x, self.drawEnd.x)
        local yStart = PZMath.min(self.drawStart.y, self.drawEnd.y)
        local xEnd = PZMath.max(self.drawStart.x, self.drawEnd.x)
        local yEnd = PZMath.max(self.drawStart.y, self.drawEnd.y)

        if PZMath.abs(xEnd - xStart) < 1 or PZMath.abs(yEnd - yStart) < 1 then
            self:cancelDrawing()
            return true
        end

        self.drawState = nil
        self.addZoneBtn:setTitle("+ Add Zone")

        -- Open name dialog
        self:closeModal()
        local screenW = getCore():getScreenWidth()
        local screenH = getCore():getScreenHeight()
        local modal = ISTextBox:new((screenW - 280) / 2, (screenH - 100) / 2, 280, 100, "Zone name:", "", self, self.onZoneNameEntered)
        modal:initialise()
        modal:addToUIManager()
        modal:setAlwaysOnTop(true)
        modal.moveWithMouse = true
        modal.drawnXStart = PZMath.floor(xStart)
        modal.drawnYStart = PZMath.floor(yStart)
        modal.drawnXEnd = PZMath.floor(xEnd)
        modal.drawnYEnd = PZMath.floor(yEnd)
        self.modalUI = modal
        return true
    end
    return false
end

function MultiplayerZoneEditorMode_ZoneMarker:onMouseMove(dx, dy)
    if self.drawState == "drawing" then
        local mx = self:getMouseX()
        local my = self:getMouseY()
        local worldX = self.mapAPI:uiToWorldX(mx, my)
        local worldY = self.mapAPI:uiToWorldY(mx, my)
        self.drawEnd = {x = worldX, y = worldY}
        return true
    end
    return false
end

function MultiplayerZoneEditorMode_ZoneMarker:onRightMouseDown(x, y)
    if self.drawState then
        self:cancelDrawing()
        return true
    end
    return false
end

function MultiplayerZoneEditorMode_ZoneMarker:onKeyRelease(key)
    if key == Keyboard.KEY_ESCAPE and self.drawState then
        self:cancelDrawing()
        return true
    end
    return false
end

function MultiplayerZoneEditorMode_ZoneMarker:onZoneNameEntered(button)
    if button.internal == "OK" then
        local region = button.parent.entry:getText()
        if region and region ~= "" then
            local catName = self:getSelectedCategoryName()
            if catName then
                sendClientCommand(getPlayer(), MODULE, "addZone", {
                    categoryName = catName,
                    xStart = button.parent.drawnXStart,
                    yStart = button.parent.drawnYStart,
                    xEnd = button.parent.drawnXEnd,
                    yEnd = button.parent.drawnYEnd,
                    region = region,
                })
                self.lastZoneListCategory = nil
                self.lastZoneListCount = nil
            end
        end
    end
    self.drawStart = nil
    self.drawEnd = nil
end

function MultiplayerZoneEditorMode_ZoneMarker:cancelDrawing()
    self.drawState = nil
    self.drawStart = nil
    self.drawEnd = nil
    if self.addZoneBtn then
        self.addZoneBtn:setTitle("+ Add Zone")
    end
end

function MultiplayerZoneEditorMode_ZoneMarker:closeModal()
    if self.modalUI then
        local modal = self.modalUI
        self.modalUI = nil
        modal:setVisible(false)
        modal:removeFromUIManager()
    end
end

function MultiplayerZoneEditorMode_ZoneMarker:undisplay()
    self:cancelDrawing()
    self:closeModal()
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

function ZoneMarkerAddCategoryDialog:onMouseDown(x, y)
    ISPanel.onMouseDown(self, x, y)
    return true
end

function ZoneMarkerAddCategoryDialog:onMouseUp(x, y)
    ISPanel.onMouseUp(self, x, y)
    return true
end

function ZoneMarkerAddCategoryDialog:onMouseMove(dx, dy)
    ISPanel.onMouseMove(self, dx, dy)
    return true
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
