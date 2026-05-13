require("ISUI/SurvivorEconomy/SurvivorEconomy_LinkUI")

local OnISEquippedItemInitialize = ISEquippedItem.initialise

local moneyIcon = getTexture("media/ui/Money_Icon_Off.png")
local moneyIconOn = getTexture("media/ui/Money_Icon_On.png")
local moneyButton
local moneyWindow

ISSurvivorEconomyUI = ISPanel:derive("ISSurvivorEconomyUI")

local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local FONT_HGT_MEDIUM = getTextManager():getFontHeight(UIFont.Medium)

local SIDE_MARGIN = 10
local TOP_MARGIN = 10
local TITLE_PAD_BOTTOM = 14
local LINE_SPACING = 4
local SECTION_SPACING = 12
local WINDOW_WIDTH = 260

function ISSurvivorEconomyUI:initialise()
    ISPanel.initialise(self)
    local btnWid = 80
    local btnHgt = FONT_HGT_SMALL + 6

    self.no = ISButton:new(
        self.width - SIDE_MARGIN - btnWid,
        self.height - SIDE_MARGIN - btnHgt,
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

    self.linkBtn = ISButton:new(
        SIDE_MARGIN,
        0,
        self.width - (SIDE_MARGIN * 2),
        btnHgt,
        getText("IGUI_SurvivorEconomy_LinkDiscord"),
        self,
        ISSurvivorEconomyUI.onClick
    )
    self.linkBtn.internal = "LINK"
    self.linkBtn:initialise()
    self.linkBtn:instantiate()
    self.linkBtn.borderColor = { r = 0.4, g = 0.4, b = 0.4, a = 0.9 }
    self:addChild(self.linkBtn)

    self.entries = {}
end

function ISSurvivorEconomyUI:refresh()
    local balances = SurvivorEconomy and SurvivorEconomy.balances or {}
    local sorted = {}
    for currency, balance in pairs(balances) do
        sorted[#sorted + 1] = { currency = currency, balance = balance }
    end
    table.sort(sorted, function(a, b)
        return tostring(a.currency) < tostring(b.currency)
    end)
    self.entries = sorted

    local linked = SurvivorEconomy and SurvivorEconomy.isDiscordLinked()
    self.linkBtn:setVisible(not linked)

    local titleHgt = TOP_MARGIN + FONT_HGT_MEDIUM + TITLE_PAD_BOTTOM
    local lineCount = #sorted > 0 and #sorted or 1
    local linesHgt = lineCount * (FONT_HGT_SMALL + LINE_SPACING)
    local btnHgt = FONT_HGT_SMALL + 6
    local discordHgt = linked and (FONT_HGT_SMALL + LINE_SPACING) or btnHgt
    local totalHgt = titleHgt
        + linesHgt
        + SECTION_SPACING
        + discordHgt
        + SECTION_SPACING
        + btnHgt
        + SIDE_MARGIN
    self:setHeight(totalHgt)

    local discordY = titleHgt + linesHgt + SECTION_SPACING
    self.linkBtn:setY(discordY)
    self.discordTextY = discordY
    self.no:setY(self.height - SIDE_MARGIN - btnHgt)
end

function ISSurvivorEconomyUI:prerender()
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
        self.width / 2 - (getTextManager():MeasureStringX(UIFont.Medium, titleText) / 2),
        TOP_MARGIN,
        1,
        1,
        1,
        1,
        UIFont.Medium
    )

    local y = TOP_MARGIN + FONT_HGT_MEDIUM + TITLE_PAD_BOTTOM
    local entries = self.entries or {}

    if #entries == 0 then
        self:drawText(
            getText("IGUI_SurvivorEconomy_NoBalance"),
            SIDE_MARGIN,
            y,
            1,
            1,
            1,
            0.9,
            UIFont.Small
        )
    else
        for _, entry in ipairs(entries) do
            local rendered = math.floor((entry.balance or 0) + 0.5)
            local line = tostring(entry.currency or "") .. ": $" .. tostring(rendered)
            self:drawText(line, SIDE_MARGIN, y, 1, 1, 1, 0.9, UIFont.Small)
            y = y + FONT_HGT_SMALL + LINE_SPACING
        end
    end

    if SurvivorEconomy and SurvivorEconomy.isDiscordLinked() then
        local displayName = nil
        for _, link in pairs(SurvivorEconomy.discordLinks) do
            displayName = link.discordUsername or link.discordId
            break
        end
        local text = getText("IGUI_SurvivorEconomy_LinkedAs", tostring(displayName or ""))
        self:drawText(text, SIDE_MARGIN, self.discordTextY, 0.7, 1, 0.7, 0.9, UIFont.Small)
    end
end

function ISSurvivorEconomyUI:onClick(button)
    if button.internal == "CLOSE" then
        self:close()
        moneyWindow = nil
        if moneyButton then
            moneyButton:setImage(moneyIcon)
        end
    elseif button.internal == "LINK" then
        ISSurvivorEconomyLinkUI.open()
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
        moneyWindow = ISSurvivorEconomyUI:new(200, 50, WINDOW_WIDTH, 120)
        moneyWindow:initialise()
        moneyWindow:addToUIManager()
        moneyWindow:refresh()
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

local function refreshWindow()
    if moneyWindow then
        moneyWindow:refresh()
    end
end

local function onServerCommand(module, command, arguments)
    if module ~= "SurvivorEconomy" then
        return
    end
    if not isClient() then
        return
    end
    if command == "balanceUpdated" or command == "discordLinksUpdated" then
        refreshWindow()
    end
end

Events.OnServerCommand.Add(onServerCommand)
