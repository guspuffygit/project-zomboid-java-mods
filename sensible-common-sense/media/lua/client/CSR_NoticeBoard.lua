require "CSR_Theme"
require "CSR_FeatureFlags"

--[[
    CSR_NoticeBoard.lua
    Adds "Read/Write Notice" to paper notice tiles and "View/Edit Whiteboard" to
    whiteboard tiles. Writing requires a pen or marker in inventory.

    Paper notice modData  : { text=string, author=string, timestamp=number }
    Whiteboard modData    : { lines={[1..6]=string}, lastEditor=string }

    In SP  : modData written directly + transmitModData.
    In MP  : server command sent; server validates and writes modData.
]]

CSR_NoticeBoard = CSR_NoticeBoard or {}

local MODULE = "CommonSenseReborn"

-- Max character lengths enforced client-side (server re-validates).
local NOTICE_MAX_LEN     = 80
local WHITEBOARD_LINES   = 6
local WHITEBOARD_MAX_LEN = 80

-- Paper notice sprite prefix  (papernotices_01_4 through papernotices_01_9)
local NOTICE_PREFIX = "papernotices_01_"
-- Whiteboard sprite prefix: location_business_office_generic_01_50 through _55
local WHITEBOARD_PREFIX = "location_business_office_generic_01_"
local WHITEBOARD_SPRITE_MIN = 50
local WHITEBOARD_SPRITE_MAX = 55

-- =============================================
-- HELPERS
-- =============================================

local function hasPenOrMarker(player)
    local inv = player:getInventory()
    return inv:containsTypeRecurse("Pen")
        or inv:containsTypeRecurse("RedPen")
        or inv:containsTypeRecurse("BluePen")
        or inv:containsTypeRecurse("Pencil")
        or inv:containsTypeRecurse("MarkerBlack")
        or inv:containsTypeRecurse("MarkerBlue")
        or inv:containsTypeRecurse("MarkerRed")
        or inv:containsTypeRecurse("MarkerGreen")
end

local function notify(playerObj, text)
    if not playerObj then return end
    if HaloTextHelper and HaloTextHelper.addTextWithArrow then
        HaloTextHelper.addTextWithArrow(playerObj, text, true, HaloTextHelper.getColorGreen())
    elseif playerObj.Say then
        playerObj:Say(text)
    end
end

local function getObjCoords(obj)
    return obj:getX(), obj:getY(), obj:getZ()
end

-- =============================================
-- NOTICE WRITE PANEL (single text entry)
-- =============================================

CSR_NoticeBoard.WritePanel = ISPanel:derive("CSR_NoticeBoardWritePanel")

function CSR_NoticeBoard.WritePanel:initialise()
    ISPanel.initialise(self)
end

function CSR_NoticeBoard.WritePanel:createChildren()
    local bW = 80
    self.cancelButton = ISButton:new(self.width - bW - 8, self.height - 32, bW, 24, "Cancel", self, self.onCancel)
    self:addChild(self.cancelButton)
    CSR_Theme.applyButtonStyle(self.cancelButton, "accentSlate", false)

    self.saveButton = ISButton:new(self.width - (bW * 2) - 16, self.height - 32, bW, 24, "Post", self, self.onSave)
    self:addChild(self.saveButton)
    CSR_Theme.applyButtonStyle(self.saveButton, "accentGreen", false)

    self.textEntry = ISTextEntryBox:new("", 12, 44, self.width - 24, 28)
    self:addChild(self.textEntry)
end

function CSR_NoticeBoard.WritePanel:postCreateChildren()
    if self.textEntry and self.textEntry.javaObject then
        local existing = (self.existingText or "")
        self.textEntry:setText(existing)
        self.textEntry:focus()
    end
end

function CSR_NoticeBoard.WritePanel:prerender()
    CSR_Theme.drawPanelChrome(self, "Write Notice", 24)
    self:drawText("What do you want to write? (max " .. NOTICE_MAX_LEN .. " characters)", 12, 16, 0.67, 0.73, 0.80, 1, UIFont.Small)
    ISPanel.prerender(self)
end

function CSR_NoticeBoard.WritePanel:onSave()
    local text = (self.textEntry:getText() or ""):gsub("[%c]", " "):sub(1, NOTICE_MAX_LEN)
    if text == "" then
        self:close()
        return
    end

    local playerObj = getSpecificPlayer(self.playerIndex)
    if not playerObj then self:close() return end

    local x, y, z = getObjCoords(self.obj)

    if isClient() then
        sendClientCommand(playerObj, MODULE, "NoticeBoardWrite", {
            x = x, y = y, z = z,
            spriteName = self.obj:getSpriteName(),
            text = text,
        })
    else
        -- SP: write directly
        local md = self.obj:getModData()
        md.csrNotice = {
            text = text,
            author = playerObj:getUsername(),
            timestamp = getTimestamp and getTimestamp() or 0,
        }
        if self.obj.transmitModData then self.obj:transmitModData() end
        notify(playerObj, "Notice posted.")
    end

    self:close()
end

function CSR_NoticeBoard.WritePanel:onCancel()
    self:close()
end

function CSR_NoticeBoard.WritePanel:onRightMouseDown(x, y)
    return true
end

function CSR_NoticeBoard.WritePanel:close()
    self:removeFromUIManager()
    CSR_NoticeBoard._writePanel = nil
end

function CSR_NoticeBoard.WritePanel:new(playerIndex, obj)
    local W, H = 400, 120
    local x = math.floor((getCore():getScreenWidth()  - W) / 2)
    local y = math.floor((getCore():getScreenHeight() - H) / 2)
    local o = ISPanel:new(x, y, W, H)
    setmetatable(o, self)
    self.__index = self
    o.playerIndex = playerIndex
    o.obj = obj
    local md = obj:getModData()
    local nd = md and md.csrNotice
    o.existingText = nd and nd.text or ""
    o.moveWithMouse = true
    o.anchorRight  = false
    o.anchorBottom = false
    return o
end

-- =============================================
-- NOTICE READ PANEL
-- =============================================

CSR_NoticeBoard.ReadPanel = ISPanel:derive("CSR_NoticeBoardReadPanel")

function CSR_NoticeBoard.ReadPanel:initialise()
    ISPanel.initialise(self)
end

function CSR_NoticeBoard.ReadPanel:createChildren()
    self.closeButton = ISButton:new(self.width - 88, self.height - 32, 80, 24, "Close", self, self.onClose)
    self:addChild(self.closeButton)
    CSR_Theme.applyButtonStyle(self.closeButton, "accentSlate", false)
end

function CSR_NoticeBoard.ReadPanel:prerender()
    CSR_Theme.drawPanelChrome(self, "Paper Notice", 24)

    local md = self.obj:getModData()
    local nd = md and md.csrNotice

    if not nd or not nd.text or nd.text == "" then
        self:drawText("(This notice is blank.)", 14, 50, 0.67, 0.73, 0.80, 1, UIFont.Medium)
    else
        -- Author line
        local author = nd.author or "Unknown"
        self:drawText("Left by: " .. author, 14, 32, 0.67, 0.73, 0.80, 1, UIFont.Small)
        -- Wrapped message
        self:drawTextureScaledAspect(nil, 0, 0, 0, 0)
        local wrapped = self:wrapText(nd.text, UIFont.Medium, self.width - 28)
        local ty = 52
        if type(wrapped) == "table" then
            for _, line in ipairs(wrapped) do
                self:drawText(line, 14, ty, 0.94, 0.96, 0.98, 1, UIFont.Medium)
                ty = ty + 22
            end
        else
            self:drawText(nd.text, 14, ty, 0.94, 0.96, 0.98, 1, UIFont.Medium)
        end
    end

    ISPanel.prerender(self)
end

function CSR_NoticeBoard.ReadPanel:onClose()
    self:close()
end

function CSR_NoticeBoard.ReadPanel:onRightMouseDown(x, y)
    return true
end

function CSR_NoticeBoard.ReadPanel:close()
    self:removeFromUIManager()
    CSR_NoticeBoard._readPanel = nil
end

function CSR_NoticeBoard.ReadPanel:new(obj)
    local W, H = 380, 160
    local x = math.floor((getCore():getScreenWidth()  - W) / 2)
    local y = math.floor((getCore():getScreenHeight() - H) / 2)
    local o = ISPanel:new(x, y, W, H)
    setmetatable(o, self)
    self.__index = self
    o.obj = obj
    o.moveWithMouse = true
    o.anchorRight  = false
    o.anchorBottom = false
    return o
end

-- =============================================
-- WHITEBOARD PANEL (6 editable lines)
-- =============================================

CSR_NoticeBoard.WhiteboardPanel = ISPanel:derive("CSR_NoticeBoardWhiteboardPanel")

local WB_W         = 500
local WB_H         = 280
local WB_HEADER    = 24
local WB_ROW_H     = 28
local WB_ROWS      = WHITEBOARD_LINES

function CSR_NoticeBoard.WhiteboardPanel:initialise()
    ISPanel.initialise(self)
end

function CSR_NoticeBoard.WhiteboardPanel:createChildren()
    local bW = 80
    self.closeButton = ISButton:new(self.width - bW - 8, self.height - 32, bW, 24, "Close", self, self.onClose)
    self:addChild(self.closeButton)
    CSR_Theme.applyButtonStyle(self.closeButton, "accentSlate", false)

    if not self.readOnly then
        self.saveButton = ISButton:new(self.width - (bW * 2) - 16, self.height - 32, bW, 24, "Save", self, self.onSave)
        self:addChild(self.saveButton)
        CSR_Theme.applyButtonStyle(self.saveButton, "accentGreen", false)
    end

    self.lineBoxes = {}
    local startY = WB_HEADER + 16
    for i = 1, WB_ROWS do
        local box = ISTextEntryBox:new("", 12, startY + ((i - 1) * WB_ROW_H), self.width - 24, 24)
        self:addChild(box)
        self.lineBoxes[i] = box
    end
end

function CSR_NoticeBoard.WhiteboardPanel:postCreateChildren()
    -- Lines are loaded in prerender() once Java widgets are guaranteed to exist.
    for i = 1, WB_ROWS do
        if self.lineBoxes[i] then
            self.lineBoxes[i]:setEditable(not self.readOnly)
        end
    end
end

function CSR_NoticeBoard.WhiteboardPanel:prerender()
    -- Populate text boxes on the first render pass, after Java objects exist.
    if not self._linesLoaded then
        self._linesLoaded = true
        local md = self.obj:getModData()
        for i = 1, WB_ROWS do
            if self.lineBoxes[i] then
                self.lineBoxes[i]:setText(md and md["csrWbLine" .. i] or "")
            end
        end
    end
    CSR_Theme.drawPanelChrome(self, "Whiteboard", WB_HEADER)
    local md = self.obj:getModData()
    local editor = md and md.csrWbEditor or ""
    if editor ~= "" then
        self:drawText("Last edited by: " .. editor, 12, 14, 0.67, 0.73, 0.80, 1, UIFont.Small)
    end
    ISPanel.prerender(self)
end

function CSR_NoticeBoard.WhiteboardPanel:onSave()
    local playerObj = getSpecificPlayer(self.playerIndex)
    if not playerObj then self:close() return end

    -- Require a marker to write on a whiteboard
    local wbInv = playerObj:getInventory()
    local hasMarker = wbInv:containsTypeRecurse("MarkerBlack")
        or wbInv:containsTypeRecurse("MarkerBlue")
        or wbInv:containsTypeRecurse("MarkerRed")
        or wbInv:containsTypeRecurse("MarkerGreen")
    if not hasMarker then
        notify(playerObj, "Need a marker to write on the whiteboard.")
        return
    end

    local lines = {}
    for i = 1, WB_ROWS do
        local t = (self.lineBoxes[i]:getText() or ""):gsub("[%c]", " "):sub(1, WHITEBOARD_MAX_LEN)
        lines[i] = t
    end

    local x, y, z = getObjCoords(self.obj)

    if isClient() then
        sendClientCommand(playerObj, MODULE, "WhiteboardWrite", {
            x = x, y = y, z = z,
            spriteName = self.obj:getSpriteName(),
            linesStr = table.concat(lines, "\n"),
        })
    else
        -- SP: write each line as its own flat key (no delimiter) so values
        -- survive the Java modData serialization round-trip without issues.
        local md = self.obj:getModData()
        for i = 1, WB_ROWS do
            md["csrWbLine" .. i] = lines[i]
        end
        md.csrWbEditor = playerObj:getUsername()
        if self.obj.transmitModData then self.obj:transmitModData() end
        notify(playerObj, "Whiteboard saved.")
    end

    self:close()
end

function CSR_NoticeBoard.WhiteboardPanel:onClose()
    self:close()
end

function CSR_NoticeBoard.WhiteboardPanel:onRightMouseDown(x, y)
    return true
end

function CSR_NoticeBoard.WhiteboardPanel:close()
    self:removeFromUIManager()
    CSR_NoticeBoard._wbPanel = nil
end

function CSR_NoticeBoard.WhiteboardPanel:new(playerIndex, obj, readOnly)
    local x = math.floor((getCore():getScreenWidth()  - WB_W) / 2)
    local y = math.floor((getCore():getScreenHeight() - WB_H) / 2)
    local o = ISPanel:new(x, y, WB_W, WB_H)
    setmetatable(o, self)
    self.__index = self
    o.playerIndex = playerIndex
    o.obj         = obj
    o.readOnly    = readOnly == true
    o.moveWithMouse = true
    o.anchorRight   = false
    o.anchorBottom  = false
    return o
end

-- =============================================
-- CONTEXT MENU HOOK
-- =============================================

local function isNoticeTile(spriteName)
    if not spriteName then return false end
    return spriteName:sub(1, #NOTICE_PREFIX) == NOTICE_PREFIX
end

local function isWhiteboardTile(spriteName)
    if not spriteName then return false end
    if spriteName:sub(1, #WHITEBOARD_PREFIX) ~= WHITEBOARD_PREFIX then return false end
    local num = tonumber(spriteName:sub(#WHITEBOARD_PREFIX + 1))
    return num and num >= WHITEBOARD_SPRITE_MIN and num <= WHITEBOARD_SPRITE_MAX
end

-- Finds the first notice or whiteboard IsoObject in worldobjects.
local function findTargetObject(worldobjects)
    for _, wo in ipairs(worldobjects) do
        if wo and wo.getSpriteName then
            local sn = wo:getSpriteName()
            if isNoticeTile(sn) or isWhiteboardTile(sn) then
                return wo, sn
            end
        end
        -- Also check all objects on the same square
        if wo and wo.getSquare then
            local sq = wo:getSquare()
            if sq then
                local objs = sq:getObjects()
                if objs then
                    for i = 0, objs:size() - 1 do
                        local o = objs:get(i)
                        if o and o.getSpriteName then
                            local sn = o:getSpriteName()
                            if isNoticeTile(sn) or isWhiteboardTile(sn) then
                                return o, sn
                            end
                        end
                    end
                end
            end
        end
    end
    return nil, nil
end

local function onFillWorldObjectContextMenu(player, context, worldobjects, test)
    if not CSR_FeatureFlags.isNoticeBoardEnabled() then return end
    if test and ISWorldObjectContextMenu and ISWorldObjectContextMenu.Test then return true end

    local playerObj = getSpecificPlayer(player)
    if not playerObj then return end

    local obj, spriteName = findTargetObject(worldobjects)
    if not obj then return end

    -- Distance guard: must be within 2 tiles
    local dist = playerObj:DistToSquared(obj:getX() + 0.5, obj:getY() + 0.5)
    if dist > 4 then return end

    if test then
        if ISWorldObjectContextMenu and ISWorldObjectContextMenu.setTest then
            return ISWorldObjectContextMenu.setTest()
        end
        return true
    end

    if isNoticeTile(spriteName) then
        -- Read Notice — always visible
        context:addOption("Read Notice", worldobjects, function()
            if CSR_NoticeBoard._readPanel then
                CSR_NoticeBoard._readPanel:close()
            end
            local p = CSR_NoticeBoard.ReadPanel:new(obj)
            p:initialise()
            p:addToUIManager()
            CSR_NoticeBoard._readPanel = p
        end)

        -- Write Notice — only when has pen/marker
        if hasPenOrMarker(playerObj) then
            context:addOption("Write Notice", worldobjects, function()
                if CSR_NoticeBoard._writePanel then
                    CSR_NoticeBoard._writePanel:close()
                end
                local p = CSR_NoticeBoard.WritePanel:new(player, obj)
                p:initialise()
                p:addToUIManager()
                CSR_NoticeBoard._writePanel = p
            end)
        end

    elseif isWhiteboardTile(spriteName) then
        -- Single option — always opens editable panel; Save button is always
        -- visible. Marker check is done at save time with a notification.
        context:addOption("View / Edit Whiteboard", worldobjects, function()
            if CSR_NoticeBoard._wbPanel then
                CSR_NoticeBoard._wbPanel:close()
            end
            local p = CSR_NoticeBoard.WhiteboardPanel:new(player, obj, false)
            p:initialise()
            p:addToUIManager()
            CSR_NoticeBoard._wbPanel = p
        end)
    end
end

Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)
