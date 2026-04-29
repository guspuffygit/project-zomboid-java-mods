
require "CSR_Theme"
require "CSR_Utils"
require "CSR_FeatureFlags"
require "CSR_RoomScanner"

CSR_Clipboard = CSR_Clipboard or {}

local HEADER_HGT = 24
local ROWS_PER_PAGE = 6
local PANEL_W = 500
local PANEL_H = 345
local ROW_H = 34

local function getPlayerItemById(player, itemId)
    if not player or not itemId then
        return nil
    end

    local items = player:getInventory() and player:getInventory():getItems() or nil
    if not items then
        return nil
    end

    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item and item.getID and item:getID() == itemId then
            return item
        end
    end

    return nil
end

local function buildTooltip(text)
    local tooltip = ISToolTip:new()
    tooltip:initialise()
    tooltip.description = text
    return tooltip
end

local function cloneEntries(entries, maxEntries)
    local cloned = {}
    for i = 1, math.min(maxEntries, entries and #entries or 0) do
        local entry = entries[i] or {}
        cloned[i] = {
            text = tostring(entry.text or ""):sub(1, 64),
            checked = entry.checked == true,
        }
    end
    return cloned
end

CSR_Clipboard.Panel = ISPanel:derive("CSR_ClipboardPanel")

function CSR_Clipboard.Panel:initialise()
    ISPanel.initialise(self)
end

function CSR_Clipboard.Panel:createChildren()
    self.closeButton = ISButton:new(self.width - 72, 3, 62, 18, "Close", self, self.onCloseButton)
    self:addChild(self.closeButton)
    CSR_Theme.applyButtonStyle(self.closeButton, "accentSlate", false)

    self.prevButton = ISButton:new(12, self.height - 38, 96, 24, "Previous", self, self.onPrevPage)
    self:addChild(self.prevButton)
    CSR_Theme.applyButtonStyle(self.prevButton, "accentSlate", false)

    self.nextButton = ISButton:new(116, self.height - 38, 96, 24, "Next", self, self.onNextPage)
    self:addChild(self.nextButton)
    CSR_Theme.applyButtonStyle(self.nextButton, "accentBlue", false)

    self.saveButton = ISButton:new(self.width - 112, self.height - 38, 96, 24, "Save", self, self.onSaveButton)
    self:addChild(self.saveButton)
    CSR_Theme.applyButtonStyle(self.saveButton, "accentGreen", not self.readOnly)
    self.saveButton:setVisible(not self.readOnly)

    if not self.readOnly and CSR_FeatureFlags.isRoomScannerEnabled() then
        self.scanButton = ISButton:new(220, self.height - 38, 96, 24, "Scan Room", self, self.onScanRoom)
        self:addChild(self.scanButton)
        CSR_Theme.applyButtonStyle(self.scanButton, "accentAmber", false)
        self.scanButton.tooltip = "Scan the enclosed room you are standing in and fill the clipboard with an item inventory. Requires a pen."
    end

    self.titleEntry = ISTextEntryBox:new(self.data.title or "Clipboard", 12, 38, self.width - 24, 24)
    self:addChild(self.titleEntry)

    self.entryButtons = {}
    self.entryBoxes = {}
    local startY = 80
    for i = 1, ROWS_PER_PAGE do
        local y = startY + ((i - 1) * ROW_H)
        local toggle = ISButton:new(12, y, 28, 24, "[ ]", self, self.onToggleEntry)
        toggle.internal = i
        self:addChild(toggle)
        CSR_Theme.applyButtonStyle(toggle, "accentSlate", false)
        self.entryButtons[i] = toggle

        local box = ISTextEntryBox:new("", 48, y, self.width - 60, 24)
        self:addChild(box)
        self.entryBoxes[i] = box
    end
end

--- Called after addToUIManager so all javaObjects exist.
function CSR_Clipboard.Panel:postCreateChildren()
    if self.titleEntry and self.titleEntry.javaObject then
        self.titleEntry:setEditable(not self.readOnly)
    end
    for i = 1, ROWS_PER_PAGE do
        local box = self.entryBoxes[i]
        if box and box.javaObject then
            box:setEditable(not self.readOnly)
        end
    end
    self:refreshPage()
end

function CSR_Clipboard.Panel:prerender()
    CSR_Theme.drawPanelChrome(self, self.readOnly and "Clipboard Reader" or "Clipboard", HEADER_HGT)
    self:drawText(self.readOnly and "Read-only world clipboard" or "Checklist backed by inserted paper", 12, 16, 0.67, 0.73, 0.80, 1.0, UIFont.Small)
    self:drawText(string.format("Paper: %d / 5", self.data.paperAmount or 0), 12, 64, 0.94, 0.96, 0.98, 1.0, UIFont.Small)
    self:drawText(self:getPageText(), 230, self.height - 34, 0.94, 0.96, 0.98, 1.0, UIFont.Small)
    ISPanel.prerender(self)
end

function CSR_Clipboard.Panel:getPageCount()
    return math.max(1, math.ceil(math.max(1, self.data.paperAmount or 0) * ROWS_PER_PAGE / ROWS_PER_PAGE))
end

function CSR_Clipboard.Panel:getPageText()
    return string.format("Page %d / %d", self.page, self:getPageCount())
end

function CSR_Clipboard.Panel:getEntryIndex(row)
    return ((self.page - 1) * ROWS_PER_PAGE) + row
end

function CSR_Clipboard.Panel:storeVisiblePage()
    if self.readOnly then
        return
    end

    self.data.title = self.titleEntry:getText()
    for i = 1, ROWS_PER_PAGE do
        local index = self:getEntryIndex(i)
        if index <= self.maxEntries then
            self.data.entries[index] = self.data.entries[index] or { text = "", checked = false }
            self.data.entries[index].text = self.entryBoxes[i]:getText()
        end
    end
end

function CSR_Clipboard.Panel:refreshPage()
    self.maxEntries = math.max(0, (self.data.paperAmount or 0) * ROWS_PER_PAGE)
    self.page = math.max(1, math.min(self.page, self:getPageCount()))
    self.titleEntry:setText(self.data.title or "Clipboard")

    for i = 1, ROWS_PER_PAGE do
        local index = self:getEntryIndex(i)
        local active = index <= self.maxEntries
        local entry = self.data.entries[index] or { text = "", checked = false }
        self.entryButtons[i]:setVisible(active)
        self.entryBoxes[i]:setVisible(active)
        self.entryButtons[i].enable = active
        self.entryBoxes[i]:setEditable(active and not self.readOnly)
        if active then
            self.entryButtons[i]:setTitle(entry.checked and "[X]" or "[ ]")
            CSR_Theme.applyButtonStyle(self.entryButtons[i], entry.checked and "accentGreen" or "accentSlate", entry.checked)
            self.entryButtons[i].toolTip = buildTooltip(self.readOnly and "Pick up the clipboard to edit checklist items." or "Toggle this checklist item.")
            self.entryBoxes[i]:setText(entry.text or "")
        end
    end

    self.prevButton.enable = self.page > 1
    self.nextButton.enable = self.page < self:getPageCount()
end

function CSR_Clipboard.Panel:onToggleEntry(button)
    if self.readOnly then
        return
    end

    local row = button.internal
    local index = self:getEntryIndex(row)
    if index > self.maxEntries then
        return
    end

    self.data.entries[index] = self.data.entries[index] or { text = "", checked = false }
    self.data.entries[index].checked = not self.data.entries[index].checked
    self:refreshPage()
end

function CSR_Clipboard.Panel:onPrevPage()
    self:storeVisiblePage()
    self.page = math.max(1, self.page - 1)
    self:refreshPage()
end

function CSR_Clipboard.Panel:onNextPage()
    self:storeVisiblePage()
    self.page = math.min(self:getPageCount(), self.page + 1)
    self:refreshPage()
end

function CSR_Clipboard.Panel:pushSave()
    if self.readOnly then
        return
    end

    self:storeVisiblePage()
    self.data.title = (self.titleEntry:getText() or ""):gsub("[%c]", ""):sub(1, 48)
    if self.data.title == "" then
        self.data.title = "Clipboard"
    end

    local payload = {
        title = self.data.title,
        entries = cloneEntries(self.data.entries, self.maxEntries),
    }

    local liveItem = getPlayerItemById(self.player, self.itemId)
    if liveItem then
        local liveData = CSR_Utils.getClipboardData(liveItem)
        liveData.title = payload.title
        liveData.entries = cloneEntries(payload.entries, self.maxEntries)
        if liveItem.setCustomName then
            liveItem:setCustomName(true)
        end
        liveItem:setName("Clipboard: " .. payload.title)
    end

    if isClient() then
        local texts = {}
        local checkedIndices = {}
        for i, entry in ipairs(payload.entries) do
            texts[i] = entry.text or ""
            if entry.checked then
                checkedIndices[#checkedIndices + 1] = tostring(i)
            end
        end
        sendClientCommand(self.player, "CommonSenseReborn", "ClipboardSave", {
            itemId = self.itemId,
            title = payload.title,
            entryTextsStr = table.concat(texts, "\n"),
            entryCheckedStr = table.concat(checkedIndices, ","),
            requestId = CSR_Utils.makeRequestId(self.player, "ClipboardSave"),
            requestTimestamp = getTimestampMs and getTimestampMs() or os.time() * 1000,
        })
    end
end

function CSR_Clipboard.Panel:onSaveButton()
    self:pushSave()
end

function CSR_Clipboard.Panel:onCloseButton()
    self:pushSave()
    self:close()
end

function CSR_Clipboard.Panel:onScanRoom()
    if self.readOnly or not self.player then
        return
    end

    if self.data.paperAmount <= 0 then
        self.player:Say("I need to add paper to the clipboard first.")
        return
    end

    local hasPen = self.player:getInventory():containsTypeRecurse("Pen")
        or self.player:getInventory():containsTypeRecurse("RedPen")
        or self.player:getInventory():containsTypeRecurse("BluePen")
    if not hasPen then
        self.player:Say("I need a pen to write with.")
        return
    end

    local result, err = CSR_RoomScanner.scanRoom(self.player)
    if not result then
        self.player:Say(err or "Scan failed.")
        return
    end

    local maxEntries = self.data.paperAmount * ROWS_PER_PAGE
    local items = result.items or {}

    if #items == 0 then
        self.player:Say("This room is empty.")
        return
    end

    self.data.entries = {}
    for i = 1, math.min(maxEntries, #items) do
        local entry = items[i]
        local text = entry.name
        if entry.count > 1 then
            text = entry.name .. " x" .. tostring(entry.count)
        end
        self.data.entries[i] = { text = text:sub(1, 64), checked = false }
    end

    if result.roomName then
        self.data.title = result.roomName .. " Inventory"
    end

    self.page = 1
    self:refreshPage()

    local scanned = math.min(maxEntries, #items)
    local overflow = #items - scanned
    if overflow > 0 then
        self.player:Say("Scanned " .. tostring(result.squareCount) .. " tiles. " .. tostring(overflow) .. " item types didn't fit — add more paper.")
    else
        self.player:Say("Scanned " .. tostring(result.squareCount) .. " tiles, " .. tostring(scanned) .. " item types found.")
    end
end

function CSR_Clipboard.Panel:onRightMouseDown(x, y)
    return true
end

function CSR_Clipboard.Panel:close()
    self:removeFromUIManager()
    if CSR_Clipboard.instance == self then
        CSR_Clipboard.instance = nil
    end
end

function CSR_Clipboard.Panel:new(player, item, readOnly)
    local x = math.floor((getCore():getScreenWidth() - PANEL_W) / 2)
    local y = math.floor((getCore():getScreenHeight() - PANEL_H) / 2)
    local o = ISPanel:new(x, y, PANEL_W, PANEL_H)
    setmetatable(o, self)
    self.__index = self
    o.player = player
    o.itemId = item and item.getID and item:getID() or nil
    o.item = item
    o.readOnly = readOnly == true
    o.data = {
        title = "Clipboard",
        paperAmount = 0,
        entries = {},
    }
    local sourceData = CSR_Utils.getClipboardData(item)
    if sourceData then
        o.data.title = sourceData.title or "Clipboard"
        o.data.paperAmount = sourceData.paperAmount or 0
        o.data.entries = cloneEntries(sourceData.entries, (sourceData.paperAmount or 0) * ROWS_PER_PAGE)
    end
    o.page = 1
    o.moveWithMouse = true
    o.anchorRight = false
    o.anchorBottom = false
    return o
end

function CSR_Clipboard.show(player, item, readOnly)
    if not CSR_FeatureFlags.isClipboardEnabled() or not player or not item or not CSR_Utils.isClipboard(item) then
        return
    end

    if CSR_Clipboard.instance then
        CSR_Clipboard.instance:close()
    end

    local panel = CSR_Clipboard.Panel:new(player, item, readOnly)
    panel:initialise()
    panel:addToUIManager()
    panel:postCreateChildren()
    CSR_Clipboard.instance = panel
end

function CSR_Clipboard.addPaper(player, item)
    if not player or not item or not CSR_Utils.isClipboard(item) then
        return
    end

    local data = CSR_Utils.getClipboardData(item)
    if not data or data.paperAmount >= 5 then
        return
    end

    local paper = player:getInventory():FindAndReturn("SheetPaper2")
    if not paper then
        return
    end

    data.paperAmount = data.paperAmount + 1
    if isClient() then
        sendClientCommand(player, "CommonSenseReborn", "ClipboardAddPaper", {
            itemId = item:getID(),
            requestId = CSR_Utils.makeRequestId(player, "ClipboardAddPaper"),
            requestTimestamp = getTimestampMs and getTimestampMs() or os.time() * 1000,
        })
    else
        player:getInventory():DoRemoveItem(paper)
    end
end

function CSR_Clipboard.removePaper(player, item)
    if not player or not item or not CSR_Utils.isClipboard(item) then
        return
    end

    local data = CSR_Utils.getClipboardData(item)
    if not data or data.paperAmount <= 0 then
        return
    end

    data.paperAmount = data.paperAmount - 1
    local maxEntries = data.paperAmount * ROWS_PER_PAGE
    for i = #data.entries, maxEntries + 1, -1 do
        data.entries[i] = nil
    end

    if isClient() then
        sendClientCommand(player, "CommonSenseReborn", "ClipboardRemovePaper", {
            itemId = item:getID(),
            requestId = CSR_Utils.makeRequestId(player, "ClipboardRemovePaper"),
            requestTimestamp = getTimestampMs and getTimestampMs() or os.time() * 1000,
        })
    else
        player:getInventory():AddItem("Base.SheetPaper2")
    end
end

return CSR_Clipboard
