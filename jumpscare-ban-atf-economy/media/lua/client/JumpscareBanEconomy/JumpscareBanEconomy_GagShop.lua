-- "Buy Jumpscare Gags" shop. Adds a button to the ATF Economy balance window
-- (via the ATFEconomySidebar registry, the mod's supported extension seam) that
-- opens a window where players spend Scraps to play a global Fart / Cry / Kachow
-- for everyone on the server. The charge and the broadcast happen server-side in
-- the addon's Java handler; this file only sends the purchase request and shows
-- the result.

require("ISUI/ISCollapsableWindow")
pcall(require, "ISUI/AfterTheFallEconomy/AfterTheFallEconomy_BalanceSidebar")

local MODULE = "JumpscareBanEconomy"
local DEFAULT_PRICE = 1000000
local SIDEBAR_BUTTON_ID = "jumpscareBanEconomy:openGagShop"

local GAGS = {
    {
        id = "fart",
        nameKey = "IGUI_JumpscareBanEconomy_GagFart",
        descKey = "IGUI_JumpscareBanEconomy_GagFartDesc",
        priceOption = "FartPrice",
    },
    {
        id = "cry",
        nameKey = "IGUI_JumpscareBanEconomy_GagCry",
        descKey = "IGUI_JumpscareBanEconomy_GagCryDesc",
        priceOption = "CryPrice",
    },
    {
        id = "kachow",
        nameKey = "IGUI_JumpscareBanEconomy_GagKachow",
        descKey = "IGUI_JumpscareBanEconomy_GagKachowDesc",
        priceOption = "KachowPrice",
    },
}

local function getGagById(id)
    for _, gag in ipairs(GAGS) do
        if gag.id == id then
            return gag
        end
    end
    return nil
end

-- Master switch, off unless the server turns it on. Unset means the option has not
-- synced yet (file scope runs before the world's SandboxVars arrive) and stays off
-- until the OnGameStart refresh below re-reads it.
local function isModEnabled()
    local opts = SandboxVars.JumpscareBanEconomy
    return opts ~= nil and opts.Enabled == true
end

-- SandboxVars are synced to the client, so the displayed price matches the
-- server's; the server re-reads its own value on purchase regardless.
local function getPrice(gag)
    local opts = SandboxVars.JumpscareBanEconomy
    local price = opts and opts[gag.priceOption]
    if type(price) ~= "number" then
        return DEFAULT_PRICE
    end
    return math.floor(price)
end

-- Same thousands-separator format the economy mod uses in its own UI files.
local function formatAmount(n)
    local s = tostring(math.floor((n or 0) + 0.5))
    local sign, digits = s:match("^(%-?)(%d+)$")
    if digits == nil then
        return s
    end
    digits = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    return sign .. digits
end

local function formatScraps(n)
    return "$" .. formatAmount(n) .. " Scraps"
end

local function describeResult(args)
    local gag = getGagById(args.gag)
    local name = gag and getText(gag.nameKey) or tostring(args.gag)
    if args.ok then
        return getText("IGUI_JumpscareBanEconomy_Success", name), { r = 0.5, g = 0.9, b = 0.5 }
    end
    local failColor = { r = 0.9, g = 0.35, b = 0.35 }
    if args.reason == "INSUFFICIENT_BALANCE" then
        local price = args.price or (gag and getPrice(gag)) or 0
        return getText("IGUI_JumpscareBanEconomy_InsufficientBalance", name, formatScraps(price)),
            failColor
    end
    if args.reason == "ECONOMY_UNAVAILABLE" then
        return getText("IGUI_JumpscareBanEconomy_EconomyUnavailable"), failColor
    end
    if args.reason == "DISABLED" then
        return getText("IGUI_JumpscareBanEconomy_Disabled"), failColor
    end
    return getText("IGUI_JumpscareBanEconomy_Failed", tostring(args.reason or "UNKNOWN")), failColor
end

ISJumpscareGagShopUI = ISCollapsableWindow:derive("ISJumpscareGagShopUI")
ISJumpscareGagShopUI.instance = nil

local WINDOW_WIDTH = 560
local MARGIN = 12
local BALANCE_H = 26
local ROW_HEIGHT = 66
local STATUS_H = 30
local NOTE_H = 16
local BUTTON_W = 72
local BUTTON_H = 28

function ISJumpscareGagShopUI.open(playerNum)
    if not isModEnabled() then
        return
    end
    playerNum = playerNum or 0
    if ISJumpscareGagShopUI.instance then
        ISJumpscareGagShopUI.instance:close()
    end

    local height = 24 + MARGIN + BALANCE_H + #GAGS * ROW_HEIGHT + STATUS_H + NOTE_H + MARGIN
    local x = (getCore():getScreenWidth() - WINDOW_WIDTH) / 2
    local y = (getCore():getScreenHeight() - height) / 2
    local ui = ISJumpscareGagShopUI:new(x, y, WINDOW_WIDTH, height, playerNum)
    ui:initialise()
    ui:addToUIManager()
    ISJumpscareGagShopUI.instance = ui

    -- Refresh the economy mod's client balance cache so the balance line is live.
    local player = getSpecificPlayer(playerNum)
    if player then
        sendClientCommand(player, "AfterTheFallEconomy", "requestBalance", {})
    end
end

function ISJumpscareGagShopUI:new(x, y, width, height, playerNum)
    local o = ISCollapsableWindow.new(self, x, y, width, height)
    o.playerNum = playerNum
    o.title = getText("IGUI_JumpscareBanEconomy_WindowTitle")
    o.resizable = false
    o.statusText = nil
    o.statusColor = { r = 1, g = 1, b = 1 }
    return o
end

function ISJumpscareGagShopUI:createChildren()
    ISCollapsableWindow.createChildren(self)
    self.buyButtons = {}
    for i, gag in ipairs(GAGS) do
        local rowY = self:rowTop(i)
        local button = ISButton:new(
            self.width - MARGIN - BUTTON_W,
            rowY + (ROW_HEIGHT - BUTTON_H) / 2,
            BUTTON_W,
            BUTTON_H,
            getText("IGUI_JumpscareBanEconomy_Buy"),
            self,
            ISJumpscareGagShopUI.onBuy
        )
        button.internal = gag.id
        button:initialise()
        self:addChild(button)
        self.buyButtons[gag.id] = button
    end
end

function ISJumpscareGagShopUI:rowTop(index)
    return self:titleBarHeight() + MARGIN + BALANCE_H + (index - 1) * ROW_HEIGHT
end

function ISJumpscareGagShopUI:onBuy(button)
    local player = getSpecificPlayer(self.playerNum)
    if not player then
        return
    end
    self.statusText = getText("IGUI_JumpscareBanEconomy_Purchasing")
    self.statusColor = { r = 1, g = 1, b = 1 }
    sendClientCommand(player, MODULE, "purchaseGag", { gag = button.internal })
end

function ISJumpscareGagShopUI:getScrapsBalance()
    if ATFEconomy and ATFEconomy.balances and type(ATFEconomy.balances.Scraps) == "number" then
        return ATFEconomy.balances.Scraps
    end
    return nil
end

function ISJumpscareGagShopUI:setResult(args)
    self.statusText, self.statusColor = describeResult(args)
end

function ISJumpscareGagShopUI:render()
    ISCollapsableWindow.render(self)

    local balance = self:getScrapsBalance()
    local balanceText
    if balance ~= nil then
        balanceText = getText("IGUI_JumpscareBanEconomy_Balance", formatScraps(balance))
    else
        balanceText = getText("IGUI_JumpscareBanEconomy_BalanceUnknown")
    end
    self:drawText(
        balanceText,
        MARGIN,
        self:titleBarHeight() + MARGIN,
        0.9,
        0.9,
        0.9,
        1,
        UIFont.Small
    )

    for i, gag in ipairs(GAGS) do
        local rowY = self:rowTop(i)
        self:drawRectBorder(MARGIN / 2, rowY, self.width - MARGIN, ROW_HEIGHT - 6, 0.4, 1, 1, 1)
        self:drawText(getText(gag.nameKey), MARGIN, rowY + 4, 1, 1, 1, 1, UIFont.Medium)
        self:drawText(getText(gag.descKey), MARGIN, rowY + 26, 0.75, 0.75, 0.75, 1, UIFont.Small)
        self:drawText(
            formatScraps(getPrice(gag)),
            MARGIN,
            rowY + 42,
            0.55,
            0.85,
            0.55,
            1,
            UIFont.Small
        )
    end

    if self.statusText then
        local statusY = self:rowTop(#GAGS) + ROW_HEIGHT + 4
        self:drawText(
            self.statusText,
            MARGIN,
            statusY,
            self.statusColor.r,
            self.statusColor.g,
            self.statusColor.b,
            1,
            UIFont.Small
        )
    end

    self:drawText(
        getText("IGUI_JumpscareBanEconomy_CommissionNote"),
        MARGIN,
        self:rowTop(#GAGS) + ROW_HEIGHT + STATUS_H,
        0.55,
        0.55,
        0.55,
        1,
        UIFont.Small
    )
end

function ISJumpscareGagShopUI:close()
    ISCollapsableWindow.close(self)
    self:removeFromUIManager()
    if ISJumpscareGagShopUI.instance == self then
        ISJumpscareGagShopUI.instance = nil
    end
end

local function onServerCommand(module, command, args)
    if module ~= MODULE or command ~= "purchaseResult" then
        return
    end
    args = args or {}
    local ui = ISJumpscareGagShopUI.instance
    if ui and ui:isVisible() then
        ui:setResult(args)
    elseif not args.ok then
        -- Window already closed: surface the failure as a halo note instead.
        local player = getSpecificPlayer(0)
        if player then
            local text = describeResult(args)
            player:setHaloNote(text, 220, 80, 80, 300)
        end
    end
end

Events.OnServerCommand.Add(onServerCommand)

-- File-scope registration is the supported pattern: it works before the balance
-- window has ever opened and refreshes it live if it is already open. Order 40
-- lands directly below the built-in "View Deposit Items" button (order 30).
local function refreshSidebarButton()
    if not (ATFEconomySidebar and ATFEconomySidebar.registerButton) then
        return
    end
    if not isModEnabled() then
        ATFEconomySidebar.unregisterButton(SIDEBAR_BUTTON_ID)
        return
    end
    ATFEconomySidebar.registerButton({
        id = SIDEBAR_BUTTON_ID,
        label = getText("IGUI_JumpscareBanEconomy_BuyGags"),
        order = 40,
        tooltip = getText("IGUI_JumpscareBanEconomy_BuyGagsTooltip"),
        onClick = function(playerNum)
            ISJumpscareGagShopUI.open(playerNum)
        end,
    })
end

refreshSidebarButton()

-- Re-run once SandboxVars have synced: at file scope the option table is not yet
-- populated, so the pass above always reads "off". OnGameStart lands well before the
-- balance window can be opened, so an enabled server still gets the button in time.
Events.OnGameStart.Add(refreshSidebarButton)
