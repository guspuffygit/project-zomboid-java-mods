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

function ISLifeboardUI:initialise()
    ISPanel.initialise(self)
    local btnWid = 80
    local btnHgt = FONT_HGT_SMALL + 2

    local y = 10 + FONT_HGT_SMALL + 24
    self.playerList = ISScrollingListBox:new(10, y, self.width - 20, self.height - (5 + btnHgt + 5) - y)
    self.playerList:initialise()
    self.playerList:instantiate()
    self.playerList.itemheight = FONT_HGT_SMALL + 2 * 2
    self.playerList.selected = 0
    self.playerList.joypadParent = self
    self.playerList.font = UIFont.NewSmall
    self.playerList.doDrawItem = self.drawPlayers
    self.playerList.drawBorder = true
    self.playerList:addColumn(getText("IGUI_Lifeboard_Ranking"), 0)
    self.playerList:addColumn(getText("IGUI_Lifeboard_DisplayName"), 42)
    self.playerList:addColumn(getText("IGUI_Lifeboard_Days"), 200)
    self.playerList.onRightMouseUp = ISLifeboardUI.onRightMousePlayerList
    self:addChild(self.playerList)

    self.no = ISButton:new(self.playerList.x + self.playerList.width - btnWid, self.playerList.y + self.playerList.height + 5, btnWid, btnHgt, getText("UI_btn_close"), self, ISLifeboardUI.onClick)
    self.no.internal = "CLOSE"
    self.no.anchorTop = false
    self.no.anchorBottom = true
    self.no:initialise()
    self.no:instantiate()
    self.no.borderColor = {r=0.4, g=0.4, b=0.4, a=0.9}
    self:addChild(self.no)
end

function ISLifeboardUI:onRightMousePlayerList(x, y)
    local row = self:rowAt(x, y)
    if row < 1 or row > #self.items then return end
    self.selected = row
    local lifeboard = self.parent
    lifeboard:doPlayerListContextMenu(self.items[row].item, self:getX() + x, self:getY() + y)
end

function ISLifeboardUI:doPlayerListContextMenu(selectedEntry, x,y)
    if not isAdmin() then return end
    local playerObj = getPlayer()
    local playerNum = self.admin:getPlayerNum()
    local context = ISContextMenu.get(playerNum, x + self:getAbsoluteX(), y + self:getAbsoluteY())
    context:addOption(getText("IGUI_Lifeboard_DeleteEntry"), self, ISLifeboardUI.onCommand, playerObj, selectedEntry, "DeleteEntry")
    context:addOption(getText("IGUI_Lifeboard_DeleteAllEntries"), self, ISLifeboardUI.onCommand, playerObj, selectedEntry, "DeleteAllEntries")
end

function ISLifeboardUI:onCommand(playerObj, selectedEntry, command)
    local args = { player = selectedEntry }
    sendClientCommand(playerObj, "Lifeboard", command, args)
end

function ISLifeboardUI:populateList()
    if not lifeboardWindow then return end
    self.playerList:clear()
    table.sort(LifeBoard.board, function(a, b) return a.dayCount > b.dayCount end)

    if getTableLength(LifeBoard.board) == 0 then
        local entry = {}
        entry.displayName = getText("IGUI_Lifeboard_BoardEmpty")
        entry.dayCount = 0
        self.playerList:addItem(entry.displayName, entry)
        return
    end

    for i,player in ipairs(LifeBoard.board) do
        local entry = {}
        entry.displayName = player.displayName
        entry.dayCount = player.dayCount
        self.playerList:addItem(entry.displayName, entry)
    end
end

function ISLifeboardUI:drawPlayers(y, entry, alt)

    local a = 0.9

    self:drawRectBorder(0, (y), self:getWidth(), self.itemheight - 1, a, self.borderColor.r, self.borderColor.g, self.borderColor.b)

    if self.selected == entry.index then
        self:drawRect(0, (y), self:getWidth(), self.itemheight - 1, 0.3, 0.7, 0.35, 0.15)
    end

    self:drawText(tostring(entry.index), 3, y + 2, 1, 1, 1, a, self.font)
    self:drawText(entry.item.displayName, self.columns[2].size + 3, y + 2, 1, 1, 1, a, self.font)
    self:drawText(tostring(entry.item.dayCount), self.columns[3].size + 3, y + 4, 1, 1, 1, a, self.font)

    return y + self.itemheight
end

function ISLifeboardUI:prerender()
    local z = 10
    self:drawRect(0, 0, self.width, self.height, self.backgroundColor.a, self.backgroundColor.r, self.backgroundColor.g, self.backgroundColor.b)
    self:drawRectBorder(0, 0, self.width, self.height, self.borderColor.a, self.borderColor.r, self.borderColor.g, self.borderColor.b)
    self:drawText(getText("IGUI_Lifeboard_Title"), self.width/2 - (getTextManager():MeasureStringX(UIFont.Small, getText("IGUI_Lifeboard_Title")) / 2), z, 1,1,1,1, UIFont.Small)
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

        lifeboardWindow = ISLifeboardUI:new(200, 50, 280, windowHeight, getPlayer())
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

    if ModData.exists("LifeBoard.board") then
        ModData.remove("LifeBoard.board")
    end

    LifeBoard.board = ModData.getOrCreate("LifeBoard.board")
    ModData.request("LifeBoard.board")
end

Events.OnServerCommand.Add(onServerCommand)