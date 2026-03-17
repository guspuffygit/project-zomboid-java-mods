if isServer() then return end

require "ISUI/ISCollapsableWindow"
require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISTextEntryBox"
require "ISUI/ISScrollingListBox"
require "ISUI/ISLabel"
require "ZoneMarkerClient"
require "ZoneMarkerShared"

---@class ZoneMarkerUI : ISCollapsableWindow
---@field catList ISScrollingListBox Category list widget
---@field catNameEntry ISTextEntryBox Category name input
---@field catR ISTextEntryBox Red color input
---@field catG ISTextEntryBox Green color input
---@field catB ISTextEntryBox Blue color input
---@field catA ISTextEntryBox Alpha color input
---@field addCatBtn ISButton Add category button
---@field delCatBtn ISButton Delete category button
---@field zoneLabel ISLabel Zone section heading
---@field zoneList ISScrollingListBox Zone list widget
---@field zoneNameEntry ISTextEntryBox Zone name input
---@field zoneX1 ISTextEntryBox Zone X1 coordinate input
---@field zoneY1 ISTextEntryBox Zone Y1 coordinate input
---@field zoneX2 ISTextEntryBox Zone X2 coordinate input
---@field zoneY2 ISTextEntryBox Zone Y2 coordinate input
---@field addZoneBtn ISButton Add zone button
---@field delZoneBtn ISButton Delete zone button
---@field dividerY number Y position of the section divider line
---@field lastVersion integer Last seen ZoneMarkerCache.version
---@field selectedCategory string|nil Currently selected category name
---@field instance ZoneMarkerUI|nil Singleton instance (class-level)
ZoneMarkerUI = ISCollapsableWindow:derive("ZoneMarkerUI")

---@type string
local MODULE = ZoneMarkerShared.MODULE
---@type integer
local PAD = 10
---@type integer
local ROW_H = 24
---@type integer
local BTN_H = 28
---@type integer
local LIST_H = 120

---@param x number
---@param y number
---@param width number
---@param height number
---@return ZoneMarkerUI
function ZoneMarkerUI:new(x, y, width, height)
    local o = ISCollapsableWindow:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o.title = "Zone Marker"
    o.resizable = false
    o.lastVersion = -1
    o.selectedCategory = nil
    return o
end

function ZoneMarkerUI:createChildren()
    ISCollapsableWindow.createChildren(self)

    local x = PAD
    local y = 28
    local w = self.width - PAD * 2
    local gap = 8
    local halfW = (w - gap) / 2

    -- === CATEGORIES SECTION ===

    local lbl = ISLabel:new(x, y, ROW_H, "Categories", 1, 1, 1, 1, UIFont.Medium, true)
    lbl:initialise()
    self:addChild(lbl)
    y = y + ROW_H + 4

    self.catList = ISScrollingListBox:new(x, y, w, LIST_H)
    self.catList:initialise()
    self.catList:instantiate()
    self.catList.itemheight = 22
    self.catList.backgroundColor = {r = 0, g = 0, b = 0, a = 0.5}
    self.catList.borderColor = {r = 0.4, g = 0.4, b = 0.4, a = 0.9}
    self.catList:setOnMouseDownFunction(self, ZoneMarkerUI.onSelectCategory)
    self:addChild(self.catList)
    y = y + LIST_H + 10

    -- Name input
    lbl = ISLabel:new(x, y + 2, ROW_H, "Name:", 1, 1, 1, 1, UIFont.Small, true)
    lbl:initialise()
    self:addChild(lbl)
    self.catNameEntry = ISTextEntryBox:new("", x + 50, y + 2, w - 50, ROW_H - 4)
    self.catNameEntry:initialise()
    self.catNameEntry:instantiate()
    self:addChild(self.catNameEntry)
    y = y + ROW_H + 8

    -- RGBA color inputs
    local colorW = 50
    local cx = x

    lbl = ISLabel:new(cx, y + 2, ROW_H, "R:", 1, 0.4, 0.4, 1, UIFont.Small, true)
    lbl:initialise()
    self:addChild(lbl)
    self.catR = ISTextEntryBox:new("1.0", cx + 20, y + 2, colorW, ROW_H - 4)
    self.catR:initialise()
    self.catR:instantiate()
    self:addChild(self.catR)
    cx = cx + 20 + colorW + gap

    lbl = ISLabel:new(cx, y + 2, ROW_H, "G:", 0.4, 1, 0.4, 1, UIFont.Small, true)
    lbl:initialise()
    self:addChild(lbl)
    self.catG = ISTextEntryBox:new("0.0", cx + 20, y + 2, colorW, ROW_H - 4)
    self.catG:initialise()
    self.catG:instantiate()
    self:addChild(self.catG)
    cx = cx + 20 + colorW + gap

    lbl = ISLabel:new(cx, y + 2, ROW_H, "B:", 0.4, 0.4, 1, 1, UIFont.Small, true)
    lbl:initialise()
    self:addChild(lbl)
    self.catB = ISTextEntryBox:new("0.0", cx + 20, y + 2, colorW, ROW_H - 4)
    self.catB:initialise()
    self.catB:instantiate()
    self:addChild(self.catB)
    cx = cx + 20 + colorW + gap

    lbl = ISLabel:new(cx, y + 2, ROW_H, "A:", 1, 1, 1, 1, UIFont.Small, true)
    lbl:initialise()
    self:addChild(lbl)
    self.catA = ISTextEntryBox:new("0.5", cx + 20, y + 2, colorW, ROW_H - 4)
    self.catA:initialise()
    self.catA:instantiate()
    self:addChild(self.catA)
    y = y + ROW_H + 10

    -- Category buttons
    self.addCatBtn = ISButton:new(x, y, halfW, BTN_H, "Add Category", self, ZoneMarkerUI.onAddCategory)
    self.addCatBtn:initialise()
    self.addCatBtn:instantiate()
    self:addChild(self.addCatBtn)

    self.delCatBtn = ISButton:new(x + halfW + gap, y, halfW, BTN_H, "Delete Category", self, ZoneMarkerUI.onDeleteCategory)
    self.delCatBtn:initialise()
    self.delCatBtn:instantiate()
    self:addChild(self.delCatBtn)
    y = y + BTN_H + 16

    -- Divider position
    self.dividerY = y - 8

    -- === ZONES SECTION ===

    self.zoneLabel = ISLabel:new(x, y, ROW_H, "Zones", 1, 1, 1, 1, UIFont.Medium, true)
    self.zoneLabel:initialise()
    self:addChild(self.zoneLabel)
    y = y + ROW_H + 4

    self.zoneList = ISScrollingListBox:new(x, y, w, LIST_H)
    self.zoneList:initialise()
    self.zoneList:instantiate()
    self.zoneList.itemheight = 22
    self.zoneList.backgroundColor = {r = 0, g = 0, b = 0, a = 0.5}
    self.zoneList.borderColor = {r = 0.4, g = 0.4, b = 0.4, a = 0.9}
    self:addChild(self.zoneList)
    y = y + LIST_H + 10

    -- Zone name input
    lbl = ISLabel:new(x, y + 2, ROW_H, "Name:", 1, 1, 1, 1, UIFont.Small, true)
    lbl:initialise()
    self:addChild(lbl)
    self.zoneNameEntry = ISTextEntryBox:new("", x + 50, y + 2, w - 50, ROW_H - 4)
    self.zoneNameEntry:initialise()
    self.zoneNameEntry:instantiate()
    self:addChild(self.zoneNameEntry)
    y = y + ROW_H + 8

    -- Coordinate inputs: X1, Y1, X2 on first row
    local coordW = 65
    cx = x

    lbl = ISLabel:new(cx, y + 2, ROW_H, "X1:", 1, 1, 1, 1, UIFont.Small, true)
    lbl:initialise()
    self:addChild(lbl)
    self.zoneX1 = ISTextEntryBox:new("", cx + 28, y + 2, coordW, ROW_H - 4)
    self.zoneX1:initialise()
    self.zoneX1:instantiate()
    self:addChild(self.zoneX1)
    cx = cx + 28 + coordW + gap

    lbl = ISLabel:new(cx, y + 2, ROW_H, "Y1:", 1, 1, 1, 1, UIFont.Small, true)
    lbl:initialise()
    self:addChild(lbl)
    self.zoneY1 = ISTextEntryBox:new("", cx + 28, y + 2, coordW, ROW_H - 4)
    self.zoneY1:initialise()
    self.zoneY1:instantiate()
    self:addChild(self.zoneY1)
    cx = cx + 28 + coordW + gap

    lbl = ISLabel:new(cx, y + 2, ROW_H, "X2:", 1, 1, 1, 1, UIFont.Small, true)
    lbl:initialise()
    self:addChild(lbl)
    self.zoneX2 = ISTextEntryBox:new("", cx + 28, y + 2, coordW, ROW_H - 4)
    self.zoneX2:initialise()
    self.zoneX2:instantiate()
    self:addChild(self.zoneX2)
    y = y + ROW_H + 8

    -- Y2 on second row
    cx = x
    lbl = ISLabel:new(cx, y + 2, ROW_H, "Y2:", 1, 1, 1, 1, UIFont.Small, true)
    lbl:initialise()
    self:addChild(lbl)
    self.zoneY2 = ISTextEntryBox:new("", cx + 28, y + 2, coordW, ROW_H - 4)
    self.zoneY2:initialise()
    self.zoneY2:instantiate()
    self:addChild(self.zoneY2)
    y = y + ROW_H + 10

    -- Zone buttons
    self.addZoneBtn = ISButton:new(x, y, halfW, BTN_H, "Add Zone", self, ZoneMarkerUI.onAddZone)
    self.addZoneBtn:initialise()
    self.addZoneBtn:instantiate()
    self:addChild(self.addZoneBtn)

    self.delZoneBtn = ISButton:new(x + halfW + gap, y, halfW, BTN_H, "Delete Zone", self, ZoneMarkerUI.onDeleteZone)
    self.delZoneBtn:initialise()
    self.delZoneBtn:instantiate()
    self:addChild(self.delZoneBtn)
end

--
-- Rendering
--

function ZoneMarkerUI:prerender()
    ISCollapsableWindow.prerender(self)
    if self.dividerY then
        self:drawRectStatic(PAD, self.dividerY, self.width - PAD * 2, 1, 0.5, 0.4, 0.4, 0.4)
    end
end

--
-- Data refresh
--

function ZoneMarkerUI:update()
    ISCollapsableWindow.update(self)
    if self.lastVersion ~= ZoneMarkerCache.version then
        self.lastVersion = ZoneMarkerCache.version
        self:refreshCategoryList()
        self:refreshZoneList()
    end
end

function ZoneMarkerUI:refreshCategoryList()
    local prevSelected = self.selectedCategory
    self.catList:clear()
    local newSelectedIdx = nil
    for i, cat in ipairs(ZoneMarkerCache.categories) do
        local display = cat.name .. string.format("  (%.1f, %.1f, %.1f, %.1f)", cat.r, cat.g, cat.b, cat.a)
        self.catList:addItem(display, cat)
        if cat.name == prevSelected then
            newSelectedIdx = i
        end
    end
    if newSelectedIdx then
        self.catList.selected = newSelectedIdx
    else
        self.selectedCategory = nil
    end
end

function ZoneMarkerUI:refreshZoneList()
    self.zoneList:clear()
    if not self.selectedCategory then
        self.zoneLabel.name = "Zones"
        return
    end
    self.zoneLabel.name = "Zones: " .. self.selectedCategory
    local zones = ZoneMarkerCache.zones[self.selectedCategory]
    if zones then
        for _, zone in ipairs(zones) do
            local display = zone.region .. string.format("  (%d,%d - %d,%d)",
                zone.xStart, zone.yStart, zone.xEnd, zone.yEnd)
            self.zoneList:addItem(display, zone)
        end
    end
end

--
-- Event handlers
--

---@param item {text: string, item: ZoneMarkerCategory}
function ZoneMarkerUI:onSelectCategory(item)
    if item and item.item then
        self.selectedCategory = item.item.name
        self:refreshZoneList()
    end
end

---@param button ISButton
function ZoneMarkerUI:onAddCategory(button)
    local name = self.catNameEntry:getText()
    if not name or name == "" then return end
    local r = tonumber(self.catR:getText())
    local g = tonumber(self.catG:getText())
    local b = tonumber(self.catB:getText())
    local a = tonumber(self.catA:getText())
    if not r or not g or not b then return end
    sendClientCommand(getPlayer(), MODULE, "addCategory", {
        name = name,
        r = r,
        g = g,
        b = b,
        a = a or 1.0,
    })
    self.catNameEntry:setText("")
end

---@param button ISButton
function ZoneMarkerUI:onDeleteCategory(button)
    if not self.catList.selected or self.catList.selected < 1 then return end
    local item = self.catList.items[self.catList.selected]
    if not item then return end
    sendClientCommand(getPlayer(), MODULE, "removeCategory", {
        name = item.item.name,
    })
    self.selectedCategory = nil
    self:refreshZoneList()
end

---@param button ISButton
function ZoneMarkerUI:onAddZone(button)
    if not self.selectedCategory then return end
    local name = self.zoneNameEntry:getText()
    if not name or name == "" then return end
    local x1 = tonumber(self.zoneX1:getText())
    local y1 = tonumber(self.zoneY1:getText())
    local x2 = tonumber(self.zoneX2:getText())
    local y2 = tonumber(self.zoneY2:getText())
    if not x1 or not y1 or not x2 or not y2 then return end
    sendClientCommand(getPlayer(), MODULE, "addZone", {
        category = self.selectedCategory,
        name = name,
        xStart = x1,
        yStart = y1,
        xEnd = x2,
        yEnd = y2,
    })
    self.zoneNameEntry:setText("")
    self.zoneX1:setText("")
    self.zoneY1:setText("")
    self.zoneX2:setText("")
    self.zoneY2:setText("")
end

---@param button ISButton
function ZoneMarkerUI:onDeleteZone(button)
    if not self.selectedCategory then return end
    if not self.zoneList.selected or self.zoneList.selected < 1 then return end
    local item = self.zoneList.items[self.zoneList.selected]
    if not item then return end
    sendClientCommand(getPlayer(), MODULE, "removeZone", {
        category = self.selectedCategory,
        name = item.item.region,
    })
end

function ZoneMarkerUI:close()
    ISCollapsableWindow.close(self)
    self:removeFromUIManager()
    ZoneMarkerUI.instance = nil
end

--
-- Open / singleton
--

-- Close orphaned window from previous load
if ZoneMarkerUI.instance then
    ZoneMarkerUI.instance:close()
end
ZoneMarkerUI.instance = nil

--- Open the Zone Marker UI, pre-filling X1/Y1 with the given world coordinates.
--- If already open, closes it instead (toggle behaviour).
---@param worldX number World X coordinate to pre-fill
---@param worldY number World Y coordinate to pre-fill
function ZoneMarkerUI.open(worldX, worldY)
    if ZoneMarkerUI.instance then
        ZoneMarkerUI.instance:close()
        return
    end
    local sw = getCore():getScreenWidth()
    local sh = getCore():getScreenHeight()
    local w = 460
    local h = 590
    local ui = ZoneMarkerUI:new((sw - w) / 2, (sh - h) / 2, w, h)
    ui:initialise()
    ui:addToUIManager()
    ui:setVisible(true)
    ZoneMarkerUI.instance = ui
    -- Pre-fill X1/Y1 with the clicked map coordinates
    ui.zoneX1:setText(tostring(math.floor(worldX)))
    ui.zoneY1:setText(tostring(math.floor(worldY)))
end

--
-- Patch ISWorldMap right-click menu to add Zone Marker option
--

require "ISUI/Maps/ISWorldMap"

-- Store original only once so reloads don't capture the patched version
if not ISWorldMap._zoneMarkerOriginalOnRightMouseUp then
    ISWorldMap._zoneMarkerOriginalOnRightMouseUp = ISWorldMap.onRightMouseUp
end

---@param x number
---@param y number
function ISWorldMap:onRightMouseUp(x, y)
    ISWorldMap._zoneMarkerOriginalOnRightMouseUp(self, x, y)

    -- Same admin gate as the base game uses for the world map context menu
    if not getDebug() and not (isClient() and (getAccessLevel() == "admin")) then
        return true
    end

    local context = getPlayerContextMenu(0)
    if not context or context.numOptions <= 1 then return true end

    local worldX = self.mapAPI:uiToWorldX(x, y)
    local worldY = self.mapAPI:uiToWorldY(x, y)

    context:addOption("Zone Marker", nil, function()
        ZoneMarkerUI.open(worldX, worldY)
    end)

    return true
end
