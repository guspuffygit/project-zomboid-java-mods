local OnISEquippedItemInitialize = ISEquippedItem.initialise

local moneyIcon = getTexture("media/ui/Money_Icon_Off.png")
local moneyIconOn = getTexture("media/ui/Money_Icon_On.png")
local moneyButton
local moneyWindow

ISSurvivorEconomyUI = ISPanel:derive("ISSurvivorEconomyUI")

local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)

local LIST_WIDTH = 280
local SIDE_MARGIN = 10
local WINDOW_WIDTH = LIST_WIDTH + (SIDE_MARGIN * 2)
local WINDOW_HEIGHT = 220

function ISSurvivorEconomyUI:initialise()
    ISPanel.initialise(self)
    local btnWid = 80
    local btnHgt = FONT_HGT_SMALL + 2

    local headerY = 10
    local listY = headerY + FONT_HGT_SMALL + 6
    local listHeight = self.height - (5 + btnHgt + 5) - listY

    self.balanceList = ISScrollingListBox:new(SIDE_MARGIN, listY, LIST_WIDTH, listHeight)
    self.balanceList:initialise()
    self.balanceList:instantiate()
    self.balanceList.itemheight = FONT_HGT_SMALL + 2 * 2
    self.balanceList.selected = 0
    self.balanceList.joypadParent = self
    self.balanceList.font = UIFont.NewSmall
    self.balanceList.doDrawItem = self.drawBalanceEntry
    self.balanceList.drawBorder = true
    self.balanceList:addColumn(getText("IGUI_SurvivorEconomy_Currency"), 0)
    self.balanceList:addColumn(getText("IGUI_SurvivorEconomy_Balance"), LIST_WIDTH - 120)
    self:addChild(self.balanceList)

    self.no = ISButton:new(
        self.width - SIDE_MARGIN - btnWid,
        listY + listHeight + 5,
        btnWid,
        btnHgt,
        getText("UI_btn_close"),
        self,
        ISSurvivorEconomyUI.onClick
    )
    self.no.internal = "CLOSE"
    self.no.anchorTop = false
    self.no.anchorBottom = true
    self.no:initialise()
    self.no:instantiate()
    self.no.borderColor = { r = 0.4, g = 0.4, b = 0.4, a = 0.9 }
    self:addChild(self.no)
end

function ISSurvivorEconomyUI:populateList()
    if not moneyWindow then
        return
    end
    self.balanceList:clear()

    local balances = SurvivorEconomy and SurvivorEconomy.balances or {}
    local sorted = {}
    for currency, balance in pairs(balances) do
        sorted[#sorted + 1] = { currency = currency, balance = balance }
    end
    table.sort(sorted, function(a, b)
        return tostring(a.currency) < tostring(b.currency)
    end)

    if #sorted == 0 then
        local entry = { currency = getText("IGUI_SurvivorEconomy_NoBalance"), balance = nil }
        self.balanceList:addItem(entry.currency, entry)
        return
    end

    for _, entry in ipairs(sorted) do
        self.balanceList:addItem(entry.currency, entry)
    end
end

function ISSurvivorEconomyUI:drawBalanceEntry(y, entry, alt)
    local list = self
    local a = 0.9
    list:drawRectBorder(
        0,
        y,
        list:getWidth(),
        list.itemheight - 1,
        a,
        list.borderColor.r,
        list.borderColor.g,
        list.borderColor.b
    )

    if list.selected == entry.index then
        list:drawRect(0, y, list:getWidth(), list.itemheight - 1, 0.3, 0.7, 0.35, 0.15)
    end

    local item = entry.item
    local balanceText = ""
    if item.balance ~= nil then
        balanceText = "$" .. tostring(math.floor((item.balance or 0) + 0.5))
    end
    list:drawText(tostring(item.currency or ""), 3, y + 2, 1, 1, 1, a, list.font)
    list:drawText(balanceText, list.columns[2].size + 3, y + 2, 1, 1, 1, a, list.font)

    return y + list.itemheight
end

function ISSurvivorEconomyUI:prerender()
    local headerY = 10
    self:drawRect(
        0,
        0,
        self.width,
        self.height,
        self.backgroundColor.a,
        self.backgroundColor.r,
        self.backgroundColor.g,
        self.backgroundColor.b
    )
    self:drawRectBorder(
        0,
        0,
        self.width,
        self.height,
        self.borderColor.a,
        self.borderColor.r,
        self.borderColor.g,
        self.borderColor.b
    )

    local titleText = getText("IGUI_SurvivorEconomy_Title")
    self:drawText(
        titleText,
        self.width / 2 - (getTextManager():MeasureStringX(UIFont.Small, titleText) / 2),
        headerY,
        1,
        1,
        1,
        1,
        UIFont.Small
    )
end

function ISSurvivorEconomyUI:onClick(button)
    if button.internal == "CLOSE" then
        self:close()
        moneyWindow = nil
        if moneyButton then
            moneyButton:setImage(moneyIcon)
        end
    end
end

function ISSurvivorEconomyUI:close()
    self:setVisible(false)
    self:removeFromUIManager()
    ISSurvivorEconomyUI.instance = nil
end

function ISSurvivorEconomyUI:new(x, y, width, height)
    local o = ISPanel:new(x, y, width, height)
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

    o.borderColor = { r = 0.4, g = 0.4, b = 0.4, a = 1 }
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.8 }
    o.width = width
    o.height = height
    o.moveWithMouse = true
    ISSurvivorEconomyUI.instance = o

    return o
end

local function onPressMoneyBtn()
    if not moneyWindow then
        moneyWindow = ISSurvivorEconomyUI:new(200, 50, WINDOW_WIDTH, WINDOW_HEIGHT)
        moneyWindow:initialise()
        moneyWindow:addToUIManager()
        moneyWindow:populateList()
        moneyButton:setImage(moneyIconOn)
    else
        moneyWindow:close()
        moneyWindow = nil
        moneyButton:setImage(moneyIcon)
    end
end

function ISEquippedItem:initialise()
    local menu = OnISEquippedItemInitialize(self)

    if getWorld():getGameMode() == "Multiplayer" then
        local texWid = moneyIcon:getWidthOrig()
        local texHgt = moneyIcon:getHeightOrig()
        -- Sit just above the leaderboard icon, which itself is at +270 below the map button.
        local leaderboardY = self.mapBtn:getY() + self.mapIconOff:getHeightOrig() + 270
        local y = leaderboardY - texHgt - 5

        moneyButton = ISButton:new(5, y, texWid, texHgt, "", self, onPressMoneyBtn)
        moneyButton:setImage(moneyIcon)
        moneyButton.internal = "SurvivorEconomy"
        moneyButton:initialise()
        moneyButton:instantiate()
        moneyButton:setDisplayBackground(false)
        moneyButton.borderColor = { r = 1, g = 1, b = 1, a = 0.1 }
        moneyButton:ignoreWidthChange()
        moneyButton:ignoreHeightChange()

        self:addChild(moneyButton)
        if moneyButton:getBottom() > self:getHeight() then
            self:setHeight(moneyButton:getBottom())
        end
    end

    return menu
end

local function onBalanceUpdated()
    if moneyWindow then
        moneyWindow:populateList()
    end
end

local function onServerCommand(module, command, arguments)
    if module ~= "SurvivorEconomy" then
        return
    end
    if command ~= "balanceUpdated" then
        return
    end
    if not isClient() then
        return
    end
    onBalanceUpdated()
end

Events.OnServerCommand.Add(onServerCommand)
