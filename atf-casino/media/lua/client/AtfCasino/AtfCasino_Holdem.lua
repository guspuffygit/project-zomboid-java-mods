---Client side of the Creepy Spiffo Poker Dealer's Texas Hold'em table. Pure view: every button
---sends an action to the server and the window redraws whatever `hdState` the server pushes back.
---Nothing here decides cards, pots, or money; other players' hole cards arrive as "??" until the
---showdown.
require("ISUI/ISCollapsableWindow")
require("ISUI/ISButton")
require("ISUI/ISTextEntryBox")

local MODULE = "AtfCasino"
local COMMAND = "holdem"
local ECONOMY_MODULE = "AfterTheFallEconomy"
local CURRENCY = "Scraps"

local DEALER_DEFAULT = { x = 614, y = 9418, z = -1 }
local PICK_RADIUS = 2.5

-- Read at call time: the server rebroadcasts SandboxVars on live admin edits, so the
-- poker dealer (and this menu) can be moved without a relog.
local function dealerPos()
    local sv = SandboxVars and SandboxVars.AtfCasino
    return {
        x = (sv and sv.PokerDealerX) or DEALER_DEFAULT.x,
        y = (sv and sv.PokerDealerY) or DEALER_DEFAULT.y,
        z = (sv and sv.FloorZ) or DEALER_DEFAULT.z,
    }
end

local FONT_SMALL = UIFont.Small
local FONT_MEDIUM = UIFont.Medium
local FONT_LARGE = UIFont.Large
local HGT_SMALL = getTextManager():getFontHeight(FONT_SMALL)
local HGT_MEDIUM = getTextManager():getFontHeight(FONT_MEDIUM)
local HGT_LARGE = getTextManager():getFontHeight(FONT_LARGE)

local CARD_W, CARD_H = 100, 135
local CARD_STEP = CARD_W + 12
local FAN_STEP = 56
local PAD = 16
local SEAT_W, SEAT_GAP, SEAT_PAD = 244, 12, 12
local SEAT_H = SEAT_PAD
    + HGT_MEDIUM
    + HGT_SMALL
    + HGT_SMALL
    + 8
    + CARD_H
    + 8
    + HGT_MEDIUM
    + HGT_SMALL
    + SEAT_PAD
local BOARD_H = 10 + HGT_MEDIUM + 10 + CARD_H + 14
local LOG_LINES = 6
local LOG_H = LOG_LINES * HGT_SMALL + 14
local BTN_W, BTN_H, BTN_GAP, GROUP_GAP = 104, 36, 8, 32
local CALL_W = 150
local QUICK_W, ENTRY_W = 70, 150

local CARD_TEXTURE_DIR = "media/textures/AtfCasino/Cards/"
local BACK_TEXTURE = "back"

AtfCasinoHoldem = AtfCasinoHoldem or {}
AtfCasinoHoldem.window = nil

local function fmt(n)
    n = math.floor((tonumber(n) or 0) + 0.5)
    local s = tostring(n)
    local out = ""
    while #s > 3 do
        out = "," .. string.sub(s, -3) .. out
        s = string.sub(s, 1, -4)
    end
    return s .. out
end

local function txt(key, fallback, ...)
    local s = getText(key, ...)
    if s == nil or s == key then
        return fallback
    end
    return s
end

local function send(action, extra)
    local player = getSpecificPlayer(0)
    if player == nil then
        return
    end
    local args = extra or {}
    args.action = action
    sendClientCommand(player, MODULE, COMMAND, args)
end

local function balance()
    if ATFEconomy and ATFEconomy.getBalance then
        return ATFEconomy.getBalance(CURRENCY) or 0
    end
    return 0
end

-- Deferred and memoised: getTexture() before the mod's media/ dir is registered returns nil and
-- poisons PZ's shared nullTextures cache, so the first lookup has to happen at render time.
local cardTextures = {}

local function cardTexture(name)
    local tex = cardTextures[name]
    if tex == nil then
        tex = getTexture(CARD_TEXTURE_DIR .. name .. ".png") or false
        cardTextures[name] = tex
    end
    return tex or nil
end

local function cardParts(code)
    if code == "??" then
        return "?", "?", false
    end
    local rank = string.sub(code, 1, #code - 1)
    local suit = string.sub(code, -1)
    if rank == "T" then
        rank = "10"
    end
    local red = suit == "h" or suit == "d"
    return rank, string.upper(suit), red
end

---@class AtfCasinoHoldemWindow : ISCollapsableWindow
AtfCasinoHoldemWindow = ISCollapsableWindow:derive("AtfCasinoHoldemWindow")

function AtfCasinoHoldemWindow:new(x, y)
    local width = PAD * 2 + SEAT_W * 5 + SEAT_GAP * 4
    local o = ISCollapsableWindow.new(self, x, y, width, 600)
    o.title = txt("IGUI_AtfCasino_Holdem_Title", "Texas Hold'em - Creepy Spiffo Poker Dealer")
    o.resizable = false
    o.state = nil
    o.stateAt = 0
    o.lastError = nil
    o.lastErrorAt = 0
    o.logLines = {}
    o.closing = false
    return o
end

function AtfCasinoHoldemWindow:addButton(x, y, w, label, fn)
    local b = ISButton:new(x, y, w, BTN_H, label, self, fn)
    b:initialise()
    b.font = FONT_MEDIUM
    self:addChild(b)
    return b
end

function AtfCasinoHoldemWindow:addEntry(x, y)
    local e = ISTextEntryBox:new("", x, y, ENTRY_W, BTN_H)
    e:initialise()
    e:instantiate()
    e:setOnlyNumbers(true)
    e.font = FONT_MEDIUM
    self:addChild(e)
    return e
end

function AtfCasinoHoldemWindow:createChildren()
    ISCollapsableWindow.createChildren(self)
    local th = self:titleBarHeight()
    self.headerY = th + 12
    self.boardY = self.headerY + HGT_LARGE + 14
    self.seatsY = self.boardY + BOARD_H + 18
    self.logY = self.seatsY + SEAT_H + 16
    self.buttonsY = self.logY + LOG_H + 16
    self.actionsY = self.buttonsY + BTN_H + BTN_GAP
    self:setHeight(self.actionsY + BTN_H + PAD)

    -- row 1: seat + chips
    local y = self.buttonsY
    local x = PAD
    self.sitBtn = self:addButton(x, y, BTN_W, txt("IGUI_AtfCasino_Holdem_Sit", "Sit"), self.onSit)
    x = x + BTN_W + BTN_GAP
    self.leaveBtn =
        self:addButton(x, y, BTN_W, txt("IGUI_AtfCasino_Holdem_Leave", "Cash Out"), self.onLeave)
    x = x + BTN_W + GROUP_GAP
    self.buyEntry = self:addEntry(x, y)
    x = x + ENTRY_W + BTN_GAP
    self.buyMinBtn =
        self:addButton(x, y, QUICK_W, txt("IGUI_AtfCasino_Holdem_Min", "Min"), self.onBuyMin)
    x = x + QUICK_W + BTN_GAP
    self.buyMaxBtn =
        self:addButton(x, y, QUICK_W, txt("IGUI_AtfCasino_Holdem_Max", "Max"), self.onBuyMax)
    x = x + QUICK_W + BTN_GAP
    self.buyBtn =
        self:addButton(x, y, BTN_W, txt("IGUI_AtfCasino_Holdem_BuyIn", "Buy In"), self.onBuyIn)
    self.closeBtn = self:addButton(
        self.width - BTN_W - PAD,
        y,
        BTN_W,
        txt("IGUI_AtfCasino_Holdem_Close", "Close"),
        self.close
    )
    self.closeBtn:setTooltip(
        txt(
            "IGUI_AtfCasino_Holdem_CloseTip",
            "Hides the table. Your seat and chips are kept while you stay near the dealer."
        )
    )
    local volW = 110
    self.volumeControl = AtfCasinoSounds.addVolumeControl(
        self,
        self.width - BTN_W - PAD - BTN_GAP - volW,
        y,
        volW,
        BTN_H
    )

    -- row 2: betting actions
    y = self.actionsY
    x = PAD
    self.foldBtn =
        self:addButton(x, y, BTN_W, txt("IGUI_AtfCasino_Holdem_Fold", "Fold"), self.onFold)
    x = x + BTN_W + BTN_GAP
    self.callBtn = self:addButton(
        x,
        y,
        CALL_W,
        txt("IGUI_AtfCasino_Holdem_Check", "Check"),
        self.onCheckOrCall
    )
    x = x + CALL_W + GROUP_GAP
    self.raiseEntry = self:addEntry(x, y)
    x = x + ENTRY_W + BTN_GAP
    self.raiseMinBtn =
        self:addButton(x, y, QUICK_W, txt("IGUI_AtfCasino_Holdem_Min", "Min"), self.onRaiseMin)
    x = x + QUICK_W + BTN_GAP
    self.raisePotBtn =
        self:addButton(x, y, QUICK_W, txt("IGUI_AtfCasino_Holdem_Pot", "Pot"), self.onRaisePot)
    x = x + QUICK_W + BTN_GAP
    self.raiseBtn =
        self:addButton(x, y, BTN_W, txt("IGUI_AtfCasino_Holdem_Raise", "Raise"), self.onRaise)
    x = x + BTN_W + BTN_GAP
    self.allInBtn =
        self:addButton(x, y, BTN_W, txt("IGUI_AtfCasino_Holdem_AllIn", "All-in"), self.onAllIn)
    self:refreshButtons()
end

function AtfCasinoHoldemWindow:mySeat()
    local s = self.state
    if not s or not s.seats then
        return nil
    end
    for _, seat in ipairs(s.seats) do
        if seat.isYou then
            return seat
        end
    end
    return nil
end

function AtfCasinoHoldemWindow:onBuyMin()
    local s = self.state
    if not s then
        return
    end
    local me = self:mySeat()
    local amount = s.minBuyIn or 0
    if me and (me.stack or 0) > 0 then
        amount = math.max(1, (s.minBuyIn or 0) - me.stack)
    end
    self.buyEntry:setText(tostring(math.floor(amount)))
end

function AtfCasinoHoldemWindow:onBuyMax()
    local s = self.state
    if not s then
        return
    end
    local me = self:mySeat()
    local room = (s.maxBuyIn or 0) - ((me and me.stack) or 0)
    local cap = math.max(0, math.min(room, balance()))
    self.buyEntry:setText(tostring(math.floor(cap)))
end

function AtfCasinoHoldemWindow:onRaiseMin()
    if self.state and self.state.minRaise then
        self.raiseEntry:setText(tostring(math.floor(self.state.minRaise)))
    end
end

-- Pot-sized raise: call, then raise by the pot as it stands after the call.
function AtfCasinoHoldemWindow:onRaisePot()
    local s = self.state
    local me = self:mySeat()
    if not s or not me then
        return
    end
    local call = s.callAmount or 0
    local to = (me.bet or 0) + call + (s.pot or 0) + call
    to = math.max(s.minRaise or 0, math.min(s.maxRaise or to, to))
    self.raiseEntry:setText(tostring(math.floor(to)))
end

function AtfCasinoHoldemWindow:onSit()
    send("sit")
end

function AtfCasinoHoldemWindow:onLeave()
    send("leave")
end

function AtfCasinoHoldemWindow:onBuyIn()
    local amount = tonumber(self.buyEntry:getInternalText()) or 0
    if amount <= 0 then
        self:showError(txt("IGUI_AtfCasino_Holdem_Err_EnterBuyIn", "Enter a buy-in amount first"))
        return
    end
    send("buyin", { amount = amount })
end

function AtfCasinoHoldemWindow:onFold()
    send("fold")
end

function AtfCasinoHoldemWindow:onCheckOrCall()
    if self.state and self.state.canCheck then
        send("check")
    else
        send("call")
    end
end

function AtfCasinoHoldemWindow:onRaise()
    local amount = tonumber(self.raiseEntry:getInternalText()) or 0
    if amount <= 0 then
        self:showError(
            txt("IGUI_AtfCasino_Holdem_Err_EnterRaise", "Enter the amount to raise to first")
        )
        return
    end
    send("raise", { amount = amount })
end

function AtfCasinoHoldemWindow:onAllIn()
    send("allin")
end

function AtfCasinoHoldemWindow:close()
    if not self.closing then
        self.closing = true
        send("close")
    end
    self:setVisible(false)
    self:removeFromUIManager()
    if AtfCasinoHoldem.window == self then
        AtfCasinoHoldem.window = nil
    end
end

function AtfCasinoHoldemWindow:showError(message)
    self.lastError = message
    self.lastErrorAt = getTimestampMs()
end

function AtfCasinoHoldemWindow:applyState(state)
    local oldState = self.state
    self.state = state
    self.stateAt = getTimestampMs()
    if AtfCasinoSounds then
        AtfCasinoSounds.holdem(oldState, state)
    end
    if state.resetLog then
        self.logLines = {}
    end
    if state.log then
        for _, line in ipairs(state.log) do
            table.insert(self.logLines, line)
            if #self.logLines > LOG_LINES then
                table.remove(self.logLines, 1)
            end
        end
    end
    self:refreshButtons()
end

function AtfCasinoHoldemWindow:refreshButtons()
    local s = self.state
    local seated = s ~= nil and (s.you or 0) > 0
    local canBuy = s ~= nil and s.canBuyIn == true
    local canAct = s ~= nil and s.canAct == true
    self.sitBtn:setEnable(s ~= nil and s.canSit == true)
    self.leaveBtn:setEnable(seated)
    self.buyEntry:setEditable(canBuy)
    self.buyMinBtn:setEnable(canBuy)
    self.buyMaxBtn:setEnable(canBuy)
    self.buyBtn:setEnable(canBuy)
    self.foldBtn:setEnable(canAct)
    self.callBtn:setEnable(canAct)
    if s and s.canCheck then
        self.callBtn:setTitle(txt("IGUI_AtfCasino_Holdem_Check", "Check"))
    else
        self.callBtn:setTitle(
            txt("IGUI_AtfCasino_Holdem_Call", "Call %1", fmt((s and s.callAmount) or 0))
        )
    end
    local canRaise = canAct and (s.maxRaise or 0) > (s.callAmount or 0) + (self:myBet() or 0)
    self.raiseEntry:setEditable(canRaise)
    self.raiseMinBtn:setEnable(canRaise)
    self.raisePotBtn:setEnable(canRaise)
    self.raiseBtn:setEnable(canRaise)
    self.allInBtn:setEnable(canAct)
end

function AtfCasinoHoldemWindow:myBet()
    local me = self:mySeat()
    return me and me.bet or 0
end

function AtfCasinoHoldemWindow:secondsLeft()
    if not self.state then
        return 0
    end
    local elapsed = (getTimestampMs() - self.stateAt) / 1000
    return math.max(0, math.floor((self.state.secondsLeft or 0) - elapsed + 0.999))
end

function AtfCasinoHoldemWindow:drawCard(x, y, code, dim)
    local w, h = CARD_W, CARD_H
    local hidden = code == "??"
    local alpha = dim and 0.45 or 1
    self:drawRect(x + 3, y + 3, w, h, 0.45 * alpha, 0, 0, 0)
    local tex = cardTexture(hidden and BACK_TEXTURE or code)
    if tex then
        self:drawTextureScaled(tex, x, y, w, h, alpha, 1, 1, 1)
        self:drawRectBorder(x, y, w, h, 0.6 * alpha, 0.1, 0.1, 0.12)
        return
    end
    local rank, suit, red = cardParts(code)
    if hidden then
        self:drawRect(x, y, w, h, alpha, 0.25, 0.25, 0.45)
        self:drawRectBorder(x, y, w, h, alpha, 0.8, 0.8, 0.9)
        self:drawText("?", x + w / 2 - 5, y + h / 2 - HGT_MEDIUM / 2, 1, 1, 1, alpha, FONT_MEDIUM)
        return
    end
    self:drawRect(x, y, w, h, alpha, 0.95, 0.95, 0.92)
    self:drawRectBorder(x, y, w, h, alpha, 0.2, 0.2, 0.2)
    local r, g, b = 0.1, 0.1, 0.1
    if red then
        r, g, b = 0.8, 0.1, 0.1
    end
    self:drawText(rank, x + 5, y + 3, r, g, b, alpha, FONT_MEDIUM)
    self:drawText(suit, x + 5, y + h - HGT_MEDIUM - 4, r, g, b, alpha, FONT_MEDIUM)
end

function AtfCasinoHoldemWindow:drawPanel(x, y, w, h, r, g, b, a, br, bg, bb, thick)
    self:drawRect(x, y, w, h, a, r, g, b)
    self:drawRectBorder(x, y, w, h, 1, br, bg, bb)
    if thick then
        self:drawRectBorder(x + 1, y + 1, w - 2, h - 2, 1, br, bg, bb)
    end
end

local function actingName(s)
    if not s or not s.seats then
        return "?"
    end
    for _, seat in ipairs(s.seats) do
        if seat.isTurn then
            return seat.name or "?"
        end
    end
    return "?"
end

function AtfCasinoHoldemWindow:statusLine()
    local s = self.state
    if not s then
        return txt("IGUI_AtfCasino_Holdem_Connecting", "Talking to the dealer..."), 1, 1, 1
    end
    local secs = tostring(self:secondsLeft())
    if s.phase == "WAITING" then
        if (s.playersWithChips or 0) < (s.minPlayers or 2) then
            return txt(
                "IGUI_AtfCasino_Holdem_WaitingPlayers",
                "Waiting for players - %1 of %2 needed have chips",
                tostring(math.floor(s.playersWithChips or 0)),
                tostring(math.floor(s.minPlayers or 2))
            ),
                0.8,
                0.8,
                0.8
        end
        return txt("IGUI_AtfCasino_Holdem_Starting", "Shuffling up - dealing in %1s", secs), 1, 1, 1
    elseif s.phase == "SHOWDOWN" then
        return txt("IGUI_AtfCasino_Holdem_Settle", "Hand over - next hand in %1s", secs), 1, 1, 1
    end
    if s.canAct then
        return txt("IGUI_AtfCasino_Holdem_YourTurn", "Your turn - %1s", secs), 1, 0.85, 0.2
    end
    return txt("IGUI_AtfCasino_Holdem_Waiting", "Waiting for %1 - %2s", actingName(s), secs),
        1,
        1,
        1
end

local function streetName(phase)
    if phase == "PREFLOP" then
        return txt("IGUI_AtfCasino_Holdem_Preflop", "Pre-flop")
    elseif phase == "FLOP" then
        return txt("IGUI_AtfCasino_Holdem_Flop", "Flop")
    elseif phase == "TURN" then
        return txt("IGUI_AtfCasino_Holdem_Turn", "Turn")
    elseif phase == "RIVER" then
        return txt("IGUI_AtfCasino_Holdem_River", "River")
    elseif phase == "SHOWDOWN" then
        return txt("IGUI_AtfCasino_Holdem_Showdown", "Showdown")
    end
    return ""
end

function AtfCasinoHoldemWindow:render()
    ISCollapsableWindow.render(self)
    if not self:getIsVisible() then
        return
    end
    local s = self.state
    local tm = getTextManager()

    -- header: status left, money right
    local status, sr, sg, sb = self:statusLine()
    self:drawText(status, PAD, self.headerY, sr, sg, sb, 1, FONT_LARGE)
    local balText = txt("IGUI_AtfCasino_Holdem_Balance", "Balance: %1 Scraps", fmt(balance()))
    local bw = tm:MeasureStringX(FONT_MEDIUM, balText)
    self:drawText(balText, self.width - bw - PAD, self.headerY, 0.95, 0.9, 0.55, 1, FONT_MEDIUM)
    if s then
        local lim = txt(
            "IGUI_AtfCasino_Holdem_Limits",
            "Blinds %1/%2 - buy-in %3 to %4",
            fmt(math.floor((s.bigBlind or 0) / 2)),
            fmt(s.bigBlind or 0),
            fmt(s.minBuyIn or 0),
            fmt(s.maxBuyIn or 0)
        )
        local lw = tm:MeasureStringX(FONT_SMALL, lim)
        self:drawText(
            lim,
            self.width - lw - PAD,
            self.headerY + HGT_MEDIUM + 2,
            0.7,
            0.7,
            0.7,
            1,
            FONT_SMALL
        )
    end

    -- community felt
    local by = self.boardY
    local feltW = self.width - PAD * 2
    self:drawPanel(PAD, by, feltW, BOARD_H, 0.05, 0.28, 0.12, 0.9, 0.35, 0.6, 0.35, false)
    local boardLabel
    if s and (s.hand or 0) > 0 then
        local street = streetName(s.phase)
        if street == "" then
            street = txt("IGUI_AtfCasino_Holdem_LastHand", "Last hand")
        end
        boardLabel = txt(
            "IGUI_AtfCasino_Holdem_HandPot",
            "Hand %1 - %2 - Pot %3",
            tostring(math.floor(s.hand)),
            street,
            fmt(s.pot or 0)
        )
    else
        boardLabel = txt("IGUI_AtfCasino_Holdem_Board", "Community cards")
    end
    self:drawText(boardLabel, PAD + 12, by + 10, 1, 1, 1, 1, FONT_MEDIUM)
    local cx = PAD + 12
    local cy = by + 10 + HGT_MEDIUM + 10
    local board = (s and s.board) or {}
    for i = 1, 5 do
        local code = board[i]
        if code then
            self:drawCard(cx, cy, code)
        else
            self:drawRectBorder(cx, cy, CARD_W, CARD_H, 0.35, 0.7, 0.9, 0.7)
        end
        cx = cx + CARD_STEP
    end

    -- seats
    local maxSeats = (s and s.maxSeats) or 5
    local bySeat = {}
    if s and s.seats then
        for _, seat in ipairs(s.seats) do
            bySeat[seat.index] = seat
        end
    end
    for i = 1, maxSeats do
        local sx = PAD + (i - 1) * (SEAT_W + SEAT_GAP)
        local sy = self.seatsY
        local seat = bySeat[i]
        local br, bg, bb, thick = 0.32, 0.32, 0.36, false
        local pr, pg, pb, pa = 0.07, 0.07, 0.09, 0.8
        if seat and seat.isTurn then
            br, bg, bb, thick = 1, 0.85, 0.2, true
            pr, pg, pb = 0.16, 0.13, 0.05
        elseif seat and seat.isYou then
            br, bg, bb, thick = 0.4, 0.7, 1, true
            pr, pg, pb = 0.06, 0.09, 0.16
        end
        self:drawPanel(sx, sy, SEAT_W, SEAT_H, pr, pg, pb, pa, br, bg, bb, thick)
        local tx = sx + SEAT_PAD
        local ty = sy + SEAT_PAD
        local seatTag = txt("IGUI_AtfCasino_Holdem_EmptySeat", "Seat %1", tostring(i))
        if seat then
            local name = seat.name or "?"
            local tag = seatTag
            if seat.isButton then
                tag = txt("IGUI_AtfCasino_Holdem_Button", "D") .. "  " .. tag
            end
            local tagW = tm:MeasureStringX(FONT_SMALL, tag)
            local maxNameW = SEAT_W - SEAT_PAD * 2 - tagW - 6
            while #name > 3 and tm:MeasureStringX(FONT_MEDIUM, name .. "~") > maxNameW do
                name = string.sub(name, 1, #name - 1)
            end
            if name ~= seat.name then
                name = name .. "~"
            end
            local nr, ng, nb = 1, 1, 1
            if seat.isYou then
                nr, ng, nb = 0.6, 0.85, 1
            elseif seat.folded then
                nr, ng, nb = 0.6, 0.6, 0.6
            end
            self:drawText(name, tx, ty, nr, ng, nb, 1, FONT_MEDIUM)
            self:drawText(tag, sx + SEAT_W - SEAT_PAD - tagW, ty + 2, 0.5, 0.5, 0.5, 1, FONT_SMALL)
            ty = ty + HGT_MEDIUM
            self:drawText(
                txt("IGUI_AtfCasino_Holdem_Stack", "Stack %1", fmt(seat.stack or 0)),
                tx,
                ty,
                0.95,
                0.9,
                0.55,
                1,
                FONT_SMALL
            )
            ty = ty + HGT_SMALL
            local betLine = ""
            if (seat.bet or 0) > 0 then
                betLine = txt("IGUI_AtfCasino_Holdem_SeatBet", "Bet %1", fmt(seat.bet))
            elseif (seat.totalIn or 0) > 0 and seat.inHand then
                betLine = txt("IGUI_AtfCasino_Holdem_SeatIn", "In for %1", fmt(seat.totalIn))
            elseif (seat.stack or 0) <= 0 and not seat.leaving then
                betLine = txt("IGUI_AtfCasino_Holdem_NoChips", "No chips - buy in to play")
            end
            self:drawText(betLine, tx, ty, 0.8, 0.8, 0.8, 1, FONT_SMALL)
            ty = ty + HGT_SMALL + 8

            local cards = seat.cards or {}
            for k, code in ipairs(cards) do
                self:drawCard(tx + (k - 1) * FAN_STEP, ty, code, seat.folded)
            end
            ty = ty + CARD_H + 8

            local label, r, g, b
            if (seat.won or 0) > 0 then
                label, r, g, b =
                    txt("IGUI_AtfCasino_Holdem_Won", "WON +%1", fmt(seat.won)), 0.4, 1, 0.4
            elseif seat.leaving then
                label, r, g, b = txt("IGUI_AtfCasino_Holdem_Leaving", "leaving"), 0.7, 0.7, 0.7
            elseif seat.folded then
                label, r, g, b = txt("IGUI_AtfCasino_Holdem_Folded", "folded"), 0.6, 0.6, 0.6
            elseif seat.allIn and seat.inHand then
                label, r, g, b = txt("IGUI_AtfCasino_Holdem_AllInTag", "ALL-IN"), 1, 0.6, 0.3
            elseif seat.isTurn then
                label, r, g, b = txt("IGUI_AtfCasino_Holdem_Thinking", "thinking..."), 1, 0.85, 0.2
            elseif s and s.phase ~= "WAITING" and s.phase ~= "SHOWDOWN" and not seat.inHand then
                label, r, g, b =
                    txt("IGUI_AtfCasino_Holdem_SittingOut", "sitting out"), 0.6, 0.6, 0.6
            end
            if label then
                self:drawText(label, tx, ty, r, g, b, 1, FONT_MEDIUM)
            end
            ty = ty + HGT_MEDIUM
            if seat.handName then
                self:drawText(seat.handName, tx, ty, 0.85, 0.85, 0.85, 1, FONT_SMALL)
            end
        else
            self:drawText(seatTag, tx, ty, 0.55, 0.55, 0.55, 1, FONT_MEDIUM)
            self:drawText(
                txt("IGUI_AtfCasino_Holdem_Open", "open"),
                tx,
                ty + HGT_MEDIUM,
                0.42,
                0.42,
                0.42,
                1,
                FONT_SMALL
            )
        end
    end

    -- table talk
    local ly = self.logY
    self:drawPanel(PAD, ly, feltW, LOG_H, 0.04, 0.04, 0.05, 0.75, 0.25, 0.25, 0.28, false)
    local first = math.max(1, #self.logLines - LOG_LINES + 1)
    local row = 0
    for i = first, #self.logLines do
        self:drawText(
            self.logLines[i],
            PAD + 8,
            ly + 7 + row * HGT_SMALL,
            0.85,
            0.85,
            0.85,
            1,
            FONT_SMALL
        )
        row = row + 1
    end

    -- error flash
    if self.lastError and getTimestampMs() - self.lastErrorAt < 4000 then
        local ew = tm:MeasureStringX(FONT_MEDIUM, self.lastError)
        self:drawText(
            self.lastError,
            self.width / 2 - ew / 2,
            self.buttonsY - HGT_MEDIUM - 4,
            1,
            0.4,
            0.4,
            1,
            FONT_MEDIUM
        )
    end
end

-- ---------------------------------------------------------------------------------------------

-- %1 is the server's numeric detail (a limit) where one applies.
local ERROR_TEXT = {
    DISABLED = "The casino is closed right now",
    TOO_FAR = "You are too far from the dealer",
    TABLE_FULL = "The table is full",
    ALREADY_SEATED = "You are already seated",
    NOT_SEATED = "Sit down first",
    NOT_YOUR_TURN = "It's not your turn",
    HAND_IN_PROGRESS = "Wait for the hand to finish before buying in",
    BAD_AMOUNT = "Enter a valid amount",
    BUYIN_TOO_LOW = "The minimum buy-in is %1",
    BUYIN_TOO_HIGH = "You can add at most %1 more",
    BANK_REFUSED = "The cashier refused your buy-in",
    INSUFFICIENT_BALANCE = "You don't have enough Scraps",
    CANNOT_CHECK = "You need to call %1 to stay in",
    RAISE_TOO_SMALL = "The minimum raise is to %1",
    RAISE_TOO_BIG = "You can raise to at most %1",
    PLAYER_OFFLINE = "Could not reach your account",
    DEAD = "The dealer doesn't deal to the dead",
}

local function errorText(reason, detail)
    local text = ERROR_TEXT[reason]
    if text then
        if detail and string.find(text, "%%1") then
            return (string.gsub(text, "%%1", fmt(detail)))
        end
        if detail and ERROR_TEXT[detail] then
            return ERROR_TEXT[detail]
        end
        if detail and detail ~= reason then
            return text .. " (" .. tostring(detail) .. ")"
        end
        return text
    end
    if detail and ERROR_TEXT[detail] then
        return ERROR_TEXT[detail]
    end
    return tostring(reason)
end

-- Only one table window may exist. Anything else of our Type in the UI manager (a leak from a
-- Lua hot-reload, or a window whose handle we lost) is torn down before we show the real one.
local function removeStrayWindows(keep)
    local ui = UIManager.getUI()
    local strays = {}
    for i = 0, ui:size() - 1 do
        local el = ui:get(i)
        local t = el and el.getTable and el:getTable()
        if t and t ~= keep and t.Type == "AtfCasinoHoldemWindow" then
            table.insert(strays, t)
        end
    end
    for _, t in ipairs(strays) do
        t:setVisible(false)
        t:removeFromUIManager()
    end
end

function AtfCasinoHoldem.open()
    local player = getSpecificPlayer(0)
    if player == nil then
        return
    end
    removeStrayWindows(AtfCasinoHoldem.window)
    local existing = AtfCasinoHoldem.window
    if existing then
        existing.closing = false
        if not existing:isVisible() then
            existing:setVisible(true)
        end
        if existing.removed then
            existing:addToUIManager()
            existing.removed = false
        end
        existing:bringToTop()
        send("open")
        sendClientCommand(player, ECONOMY_MODULE, "requestBalance", {})
        return
    end
    local w = AtfCasinoHoldemWindow:new(0, 0)
    w:initialise()
    w:setX(math.floor(getCore():getScreenWidth() / 2 - w.width / 2))
    w:setY(math.floor(getCore():getScreenHeight() / 2 - w.height / 2))
    w:addToUIManager()
    w:setVisible(true)
    AtfCasinoHoldem.window = w
    send("open")
    sendClientCommand(player, ECONOMY_MODULE, "requestBalance", {})
end

local function onServerCommand(module, command, args)
    if module ~= MODULE then
        return
    end
    local w = AtfCasinoHoldem.window
    if command == "hdState" then
        if w then
            w:applyState(args)
        end
    elseif command == "hdError" then
        if w then
            w:showError(errorText(args and args.reason or "ERROR", args and args.detail))
        end
    elseif command == "hdClosed" then
        if w then
            w.closing = true
            w:close()
        end
        local player = getSpecificPlayer(0)
        local reason = args and args.reason
        -- OTHER_TABLE closes silently: the player just sat down at another game.
        if player and reason ~= "DEAD" and reason ~= "OTHER_TABLE" then
            player:setHaloNote(
                txt("IGUI_AtfCasino_Holdem_WalkedAway", "You walked away from the poker table"),
                255,
                200,
                80,
                240
            )
        end
    end
end
Events.OnServerCommand.Add(onServerCommand)

local function clickedSquare(worldobjects)
    for _, o in ipairs(worldobjects) do
        if o and o.getSquare then
            local sq = o:getSquare()
            if sq then
                return sq
            end
        end
    end
    return nil
end

local function onFillWorldObjectContextMenu(playerNum, context, worldobjects, test)
    if test == true then
        return
    end
    -- Master switch off = the casino does not exist: no menu entry at all.
    local sv = SandboxVars and SandboxVars.AtfCasino
    if not (sv and sv.Enabled) then
        return
    end
    local player = getSpecificPlayer(playerNum)
    local DEALER = dealerPos()
    if not player or player:getZ() ~= DEALER.z then
        return
    end
    local sq = clickedSquare(worldobjects)
    local cx, cy
    if sq then
        cx, cy = sq:getX(), sq:getY()
    else
        cx = ISCoordConversion.ToWorldX(getMouseX(), getMouseY(), DEALER.z)
        cy = ISCoordConversion.ToWorldY(getMouseX(), getMouseY(), DEALER.z)
    end
    if math.abs(cx - DEALER.x) > PICK_RADIUS or math.abs(cy - DEALER.y) > PICK_RADIUS then
        return
    end
    local option = context:addOption(
        txt(
            "IGUI_AtfCasino_Holdem_ContextOption",
            "Play Texas Hold'em with the Creepy Spiffo Poker Dealer"
        ),
        worldobjects,
        AtfCasinoHoldem.open
    )
    if math.abs(player:getX() - DEALER.x) > 8 or math.abs(player:getY() - DEALER.y) > 8 then
        option.notAvailable = true
        local tip = ISToolTip:new()
        tip:initialise()
        tip:setVisible(false)
        tip.description =
            txt("IGUI_AtfCasino_Holdem_TooFarTip", "Walk up to the poker dealer first")
        option.toolTip = tip
    end
end
Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)

local function onPlayerDeath(player)
    if player == getSpecificPlayer(0) and AtfCasinoHoldem.window then
        AtfCasinoHoldem.window:close()
    end
end
Events.OnPlayerDeath.Add(onPlayerDeath)
