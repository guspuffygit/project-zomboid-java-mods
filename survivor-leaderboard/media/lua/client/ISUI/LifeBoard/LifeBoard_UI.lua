local OnISEquippedItemInitialize = ISEquippedItem.initialise

local lifeboardIcon = getTexture("media/ui/Lifeboard_Icon_Off.png")
local lifeboardIconOn = getTexture("media/ui/Lifeboard_Icon_On.png")
local lifeboardButton
local lifeboardWindow

local function getTableLength(table)
    local count = 0
    for _ in pairs(table) do count = count + 1 end
    return count
end

ISLifeboardUI = ISPanel:derive("ISLifeboardUI")
ISLifeboardUI.messages = {}

local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)

local LIST_WIDTH = 260
local LIST_GAP = 20
local SIDE_MARGIN = 10
local WINDOW_WIDTH = SIDE_MARGIN + (LIST_WIDTH * 3) + (LIST_GAP * 2) + SIDE_MARGIN

function ISLifeboardUI:initialise()
    ISPanel.initialise(self)
    local btnWid = 80
    local btnHgt = FONT_HGT_SMALL + 2

    local headerY = 10
    local sectionTitleY = headerY + FONT_HGT_SMALL + 6
    local listY = sectionTitleY + FONT_HGT_SMALL + 6
    local listHeight = self.height - (5 + btnHgt + 5) - listY

    self.daysList = ISScrollingListBox:new(SIDE_MARGIN, listY, LIST_WIDTH, listHeight)
    self.daysList:initialise()
    self.daysList:instantiate()
    self.daysList.itemheight = FONT_HGT_SMALL + 2 * 2
    self.daysList.selected = 0
    self.daysList.joypadParent = self
    self.daysList.font = UIFont.NewSmall
    self.daysList.doDrawItem = self.drawDaysEntry
    self.daysList.drawBorder = true
    self.daysList:addColumn(getText("IGUI_Lifeboard_Ranking"), 0)
    self.daysList:addColumn(getText("IGUI_Lifeboard_DisplayName"), 42)
    self.daysList:addColumn(getText("IGUI_Lifeboard_Days"), LIST_WIDTH - 60)
    self:addChild(self.daysList)

    local killsX = SIDE_MARGIN + LIST_WIDTH + LIST_GAP
    self.killsList = ISScrollingListBox:new(killsX, listY, LIST_WIDTH, listHeight)
    self.killsList:initialise()
    self.killsList:instantiate()
    self.killsList.itemheight = FONT_HGT_SMALL + 2 * 2
    self.killsList.selected = 0
    self.killsList.joypadParent = self
    self.killsList.font = UIFont.NewSmall
    self.killsList.doDrawItem = self.drawKillsEntry
    self.killsList.drawBorder = true
    self.killsList:addColumn(getText("IGUI_Lifeboard_Ranking"), 0)
    self.killsList:addColumn(getText("IGUI_Lifeboard_DisplayName"), 42)
    self.killsList:addColumn(getText("IGUI_Killboard_Kills"), LIST_WIDTH - 60)
    self:addChild(self.killsList)

    local zombieKillsX = SIDE_MARGIN + (LIST_WIDTH + LIST_GAP) * 2
    self.zombieKillsList = ISScrollingListBox:new(zombieKillsX, listY, LIST_WIDTH, listHeight)
    self.zombieKillsList:initialise()
    self.zombieKillsList:instantiate()
    self.zombieKillsList.itemheight = FONT_HGT_SMALL + 2 * 2
    self.zombieKillsList.selected = 0
    self.zombieKillsList.joypadParent = self
    self.zombieKillsList.font = UIFont.NewSmall
    self.zombieKillsList.doDrawItem = self.drawZombieKillsEntry
    self.zombieKillsList.drawBorder = true
    self.zombieKillsList:addColumn(getText("IGUI_Lifeboard_Ranking"), 0)
    self.zombieKillsList:addColumn(getText("IGUI_Lifeboard_DisplayName"), 42)
    self.zombieKillsList:addColumn(getText("IGUI_Lifeboard_ZombieKills"), LIST_WIDTH - 60)
    self:addChild(self.zombieKillsList)

    self.no = ISButton:new(self.width - SIDE_MARGIN - btnWid, listY + listHeight + 5, btnWid, btnHgt, getText("UI_btn_close"), self, ISLifeboardUI.onClick)
    self.no.internal = "CLOSE"
    self.no.anchorTop = false
    self.no.anchorBottom = true
    self.no:initialise()
    self.no:instantiate()
    self.no.borderColor = {r=0.4, g=0.4, b=0.4, a=0.9}
    self:addChild(self.no)
end

function ISLifeboardUI:populateList()
    if not lifeboardWindow then return end
    self.daysList:clear()
    self.killsList:clear()
    self.zombieKillsList:clear()

    local daysSorted = {}
    local killsSorted = {}
    local zombieKillsSorted = {}
    for _, player in pairs(LifeBoard.board) do
        if (player.dayCount or 0) ~= 0 then
            daysSorted[#daysSorted + 1] = player
        end
        if (player.killCount or 0) ~= 0 then
            killsSorted[#killsSorted + 1] = player
        end
        if (player.zombieKillCount or 0) ~= 0 then
            zombieKillsSorted[#zombieKillsSorted + 1] = player
        end
    end
    table.sort(daysSorted, function(a, b) return (a.dayCount or 0) > (b.dayCount or 0) end)
    table.sort(killsSorted, function(a, b)
        local ak = a.killCount or 0
        local bk = b.killCount or 0
        if ak == bk then
            return (a.displayName or "") < (b.displayName or "")
        end
        return ak > bk
    end)
    table.sort(zombieKillsSorted, function(a, b)
        local ak = a.zombieKillCount or 0
        local bk = b.zombieKillCount or 0
        if ak == bk then
            return (a.displayName or "") < (b.displayName or "")
        end
        return ak > bk
    end)

    if #daysSorted == 0 and #killsSorted == 0 and #zombieKillsSorted == 0 then
        local entry = {}
        entry.displayName = getText("IGUI_Lifeboard_BoardEmpty")
        entry.dayCount = 0
        entry.killCount = 0
        entry.zombieKillCount = 0
        self.daysList:addItem(entry.displayName, entry)
        self.killsList:addItem(entry.displayName, entry)
        self.zombieKillsList:addItem(entry.displayName, entry)
        return
    end

    if #daysSorted == 0 then
        local entry = {}
        entry.displayName = getText("IGUI_Lifeboard_BoardEmpty")
        entry.dayCount = 0
        self.daysList:addItem(entry.displayName, entry)
    else
        for _, player in ipairs(daysSorted) do
            local entry = {}
            entry.displayName = player.displayName
            entry.dayCount = player.dayCount
            self.daysList:addItem(entry.displayName, entry)
        end
    end

    if #killsSorted == 0 then
        local entry = {}
        entry.displayName = getText("IGUI_Lifeboard_BoardEmpty")
        entry.killCount = 0
        self.killsList:addItem(entry.displayName, entry)
    else
        for _, player in ipairs(killsSorted) do
            local entry = {}
            entry.displayName = player.displayName
            entry.killCount = player.killCount or 0
            self.killsList:addItem(entry.displayName, entry)
        end
    end

    if #zombieKillsSorted == 0 then
        local entry = {}
        entry.displayName = getText("IGUI_Lifeboard_BoardEmpty")
        entry.zombieKillCount = 0
        self.zombieKillsList:addItem(entry.displayName, entry)
    else
        for _, player in ipairs(zombieKillsSorted) do
            local entry = {}
            entry.displayName = player.displayName
            entry.zombieKillCount = player.zombieKillCount or 0
            self.zombieKillsList:addItem(entry.displayName, entry)
        end
    end
end

local function drawRow(list, y, entry, valueText)
    local a = 0.9
    list:drawRectBorder(0, (y), list:getWidth(), list.itemheight - 1, a, list.borderColor.r, list.borderColor.g, list.borderColor.b)

    if list.selected == entry.index then
        list:drawRect(0, (y), list:getWidth(), list.itemheight - 1, 0.3, 0.7, 0.35, 0.15)
    end

    list:drawText(tostring(entry.index), 3, y + 2, 1, 1, 1, a, list.font)
    list:drawText(entry.item.displayName, list.columns[2].size + 3, y + 2, 1, 1, 1, a, list.font)
    list:drawText(valueText, list.columns[3].size + 3, y + 2, 1, 1, 1, a, list.font)

    return y + list.itemheight
end

function ISLifeboardUI:drawDaysEntry(y, entry, alt)
    return drawRow(self, y, entry, tostring(entry.item.dayCount or 0))
end

function ISLifeboardUI:drawKillsEntry(y, entry, alt)
    return drawRow(self, y, entry, tostring(entry.item.killCount or 0))
end

function ISLifeboardUI:drawZombieKillsEntry(y, entry, alt)
    return drawRow(self, y, entry, tostring(entry.item.zombieKillCount or 0))
end

function ISLifeboardUI:prerender()
    local headerY = 10
    self:drawRect(0, 0, self.width, self.height, self.backgroundColor.a, self.backgroundColor.r, self.backgroundColor.g, self.backgroundColor.b)
    self:drawRectBorder(0, 0, self.width, self.height, self.borderColor.a, self.borderColor.r, self.borderColor.g, self.borderColor.b)

    local titleText = getText("IGUI_Lifeboard_Title")
    self:drawText(titleText, self.width/2 - (getTextManager():MeasureStringX(UIFont.Small, titleText) / 2), headerY, 1,1,1,1, UIFont.Small)
end

function ISLifeboardUI:onClick(button)
    if button.internal == "CLOSE" then
        self:close()
        lifeboardWindow = nil
		lifeboardButton:setImage(lifeboardIcon)
    end
end

function ISLifeboardUI:close()
    self:setVisible(false)
    self:removeFromUIManager()
    ISLifeboardUI.instance = nil
end


function ISLifeboardUI:new(x, y, width, height, admin)

    local o = {}
    o = ISPanel:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self

    if y == 0 then
        o.y = o:getMouseY() - (height / 2)
        o:setY(o.y)
    end

    if x == 0 then
        o.x = o:getMouseX() - (width / 2)
        o:setX(o.x)
    end

    o.borderColor = {r=0.4, g=0.4, b=0.4, a=1}
    o.backgroundColor = {r=0, g=0, b=0, a=0.8}
    o.width = width
    o.height = height
    o.admin = admin
    o.moveWithMouse = true
    o.lifeboard = nil
    ISLifeboardUI.instance = o

    return o
end

local function onPressLifeboardBtn()

	if not lifeboardWindow then

        local windowHeight = 100 + (getTableLength(LifeBoard.board) * 16)

        if windowHeight > 500 then
            windowHeight = 500
        end

        lifeboardWindow = ISLifeboardUI:new(200, 50, WINDOW_WIDTH, windowHeight, getPlayer())
        lifeboardWindow:initialise()
        lifeboardWindow:addToUIManager()
        lifeboardWindow:populateList()
		lifeboardButton:setImage(lifeboardIconOn)
	else
		lifeboardWindow:close()
        lifeboardWindow = nil
		lifeboardButton:setImage(lifeboardIcon)
	end
end

function ISEquippedItem:initialise()

	local menu = OnISEquippedItemInitialize(self)

    if getWorld():getGameMode() == "Multiplayer" then
	local y = self.mapBtn:getY() + self.mapIconOff:getHeightOrig() + 270
	local texWid = lifeboardIcon:getWidthOrig()
	local texHgt = lifeboardIcon:getHeightOrig()
	lifeboardButton = ISButton:new(5, y, texWid, texHgt, "", self, onPressLifeboardBtn)

	lifeboardButton:setImage(lifeboardIcon)
	lifeboardButton.internal = "Lifeboard"
	lifeboardButton:initialise()
	lifeboardButton:instantiate()
	lifeboardButton:setDisplayBackground(false)

	lifeboardButton.borderColor = {r=1, g=1, b=1, a=0.1}
	lifeboardButton:ignoreWidthChange()
	lifeboardButton:ignoreHeightChange()

	self:addChild(lifeboardButton)
	self:setHeight(lifeboardButton:getBottom())
    end

	return menu
end

local function onServerCommand(module, command, arguments)
    if module ~= "Lifeboard" then return end
    if command ~= "UpdateBoard" then return end
    if not isClient() then return end

    -- The server now sends the full board as args.board = [{displayName, dayCount, killCount, zombieKillCount}, ...]
    -- Rebuild LifeBoard.board in place so any captured references stay valid.
    for k in pairs(LifeBoard.board) do LifeBoard.board[k] = nil end

    if arguments and arguments.board then
        for i, entry in pairs(arguments.board) do
            LifeBoard.board[i] = {
                displayName = entry.displayName,
                dayCount = entry.dayCount,
                killCount = entry.killCount,
                zombieKillCount = entry.zombieKillCount,
            }
        end
    end

    if lifeboardWindow then
        lifeboardWindow:populateList()
    end
end

Events.OnServerCommand.Add(onServerCommand)
