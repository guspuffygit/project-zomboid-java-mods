---Client side of the Creepy Spiffo Dealer's blackjack table. Pure view: every button sends an
---action to the server and the window redraws whatever `bjState` the server pushes back. Nothing
---here decides cards, totals, or money.
require("ISUI/ISCollapsableWindow")
require("ISUI/ISButton")
require("ISUI/ISTextEntryBox")

local MODULE = "AtfCasino"
local COMMAND = "blackjack"
local ECONOMY_MODULE = "AfterTheFallEconomy"
local CURRENCY = "Scraps"

local DEALER_DEFAULT = { x = 615, y = 9422, z = -1 }
local PICK_RADIUS = 2.5

-- Read at call time: the server rebroadcasts SandboxVars on live admin edits, so the
-- dealer (and this menu) can be moved without a relog.
local function dealerPos()
	local sv = SandboxVars and SandboxVars.AtfCasino
	return {
		x = (sv and sv.DealerX) or DEALER_DEFAULT.x,
		y = (sv and sv.DealerY) or DEALER_DEFAULT.y,
		z = (sv and sv.FloorZ) or DEALER_DEFAULT.z,
	}
end

local FONT_SMALL = UIFont.Small
local FONT_MEDIUM = UIFont.Medium
local FONT_LARGE = UIFont.Large
local HGT_SMALL = getTextManager():getFontHeight(FONT_SMALL)
local HGT_MEDIUM = getTextManager():getFontHeight(FONT_MEDIUM)

local HGT_LARGE = getTextManager():getFontHeight(FONT_LARGE)

-- Card art is 136x183; drawn at ~3/4 scale so ranks and pips read at 1440p.
local CARD_W, CARD_H = 100, 135
local CARD_STEP = CARD_W + 12
local FAN_STEP = 56
local PAD = 16
local SEAT_W, SEAT_GAP, SEAT_PAD = 244, 12, 12
local SEAT_H = SEAT_PAD + HGT_MEDIUM + HGT_SMALL + 10 + CARD_H + 10 + HGT_MEDIUM + HGT_MEDIUM + SEAT_PAD
local DEALER_H = 10 + HGT_MEDIUM + 10 + CARD_H + 14
local LOG_LINES = 6
local LOG_H = LOG_LINES * HGT_SMALL + 14
local BTN_W, BTN_H, BTN_GAP, GROUP_GAP = 104, 36, 8, 32
local QUICK_W, ENTRY_W = 70, 150

local CARD_TEXTURE_DIR = "media/textures/AtfCasino/Cards/"
local BACK_TEXTURE = "back"

AtfCasinoBlackjack = AtfCasinoBlackjack or {}
AtfCasinoBlackjack.window = nil

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

---@class AtfCasinoBlackjackWindow : ISCollapsableWindow
AtfCasinoBlackjackWindow = ISCollapsableWindow:derive("AtfCasinoBlackjackWindow")

function AtfCasinoBlackjackWindow:new(x, y)
	local width = PAD * 2 + SEAT_W * 5 + SEAT_GAP * 4
	local o = ISCollapsableWindow.new(self, x, y, width, 600)
	o.title = txt("IGUI_AtfCasino_Blackjack_Title", "Blackjack - Creepy Spiffo Dealer")
	o.resizable = false
	o.state = nil
	o.stateAt = 0
	o.lastError = nil
	o.lastErrorAt = 0
	o.logLines = {}
	o.closing = false
	return o
end

function AtfCasinoBlackjackWindow:addButton(x, y, w, label, fn)
	local b = ISButton:new(x, y, w, BTN_H, label, self, fn)
	b:initialise()
	b.font = FONT_MEDIUM
	self:addChild(b)
	return b
end

function AtfCasinoBlackjackWindow:createChildren()
	ISCollapsableWindow.createChildren(self)
	local th = self:titleBarHeight()
	self.headerY = th + 12
	self.dealerY = self.headerY + HGT_LARGE + 14
	self.seatsY = self.dealerY + DEALER_H + 18
	self.logY = self.seatsY + SEAT_H + 16
	self.buttonsY = self.logY + LOG_H + 16
	self:setHeight(self.buttonsY + BTN_H + PAD)

	local y = self.buttonsY
	local x = PAD
	self.sitBtn = self:addButton(x, y, BTN_W, txt("IGUI_AtfCasino_Blackjack_Sit", "Sit"), self.onSit)
	x = x + BTN_W + BTN_GAP
	self.leaveBtn = self:addButton(x, y, BTN_W, txt("IGUI_AtfCasino_Blackjack_Leave", "Get Up"), self.onLeave)
	x = x + BTN_W + GROUP_GAP

	self.betEntry = ISTextEntryBox:new("", x, y, ENTRY_W, BTN_H)
	self.betEntry:initialise()
	self.betEntry:instantiate()
	self.betEntry:setOnlyNumbers(true)
	self.betEntry.font = FONT_MEDIUM
	self:addChild(self.betEntry)
	x = x + ENTRY_W + BTN_GAP
	self.minBtn = self:addButton(x, y, QUICK_W, txt("IGUI_AtfCasino_Blackjack_Min", "Min"), self.onMin)
	x = x + QUICK_W + BTN_GAP
	self.maxBtn = self:addButton(x, y, QUICK_W, txt("IGUI_AtfCasino_Blackjack_Max", "Max"), self.onMax)
	x = x + QUICK_W + BTN_GAP
	self.betBtn = self:addButton(x, y, BTN_W, txt("IGUI_AtfCasino_Blackjack_Bet", "Bet"), self.onBet)
	x = x + BTN_W + GROUP_GAP

	self.hitBtn = self:addButton(x, y, BTN_W, txt("IGUI_AtfCasino_Blackjack_Hit", "Hit"), self.onHit)
	x = x + BTN_W + BTN_GAP
	self.standBtn = self:addButton(x, y, BTN_W, txt("IGUI_AtfCasino_Blackjack_Stand", "Stand"), self.onStand)
	x = x + BTN_W + BTN_GAP
	self.doubleBtn = self:addButton(x, y, BTN_W, txt("IGUI_AtfCasino_Blackjack_Double", "Double"), self.onDouble)

	self.closeBtn =
		self:addButton(self.width - BTN_W - PAD, y, BTN_W, txt("IGUI_AtfCasino_Blackjack_Close", "Close"), self.close)
	self.closeBtn:setTooltip(
		txt(
			"IGUI_AtfCasino_Blackjack_CloseTip",
			"Hides the table. Your seat and hand are kept while you stay near the dealer."
		)
	)
	self:refreshButtons()
end

function AtfCasinoBlackjackWindow:onMin()
	if self.state and self.state.minBet then
		self.betEntry:setText(tostring(math.floor(self.state.minBet)))
	end
end

function AtfCasinoBlackjackWindow:onMax()
	if not self.state or not self.state.maxBet then
		return
	end
	local cap = self.state.maxBet
	if ATFEconomy and ATFEconomy.getBalance then
		cap = math.min(cap, ATFEconomy.getBalance(CURRENCY) or cap)
	end
	cap = math.max(cap, self.state.minBet or 0)
	self.betEntry:setText(tostring(math.floor(cap)))
end

function AtfCasinoBlackjackWindow:onSit()
	send("sit")
end

function AtfCasinoBlackjackWindow:onLeave()
	send("leave")
end

function AtfCasinoBlackjackWindow:onBet()
	local amount = tonumber(self.betEntry:getInternalText()) or 0
	if amount <= 0 then
		self:showError(txt("IGUI_AtfCasino_Blackjack_Err_EnterBet", "Enter a bet amount first"))
		return
	end
	send("bet", { amount = amount })
end

function AtfCasinoBlackjackWindow:onHit()
	send("hit")
end

function AtfCasinoBlackjackWindow:onStand()
	send("stand")
end

function AtfCasinoBlackjackWindow:onDouble()
	send("double")
end

function AtfCasinoBlackjackWindow:close()
	if not self.closing then
		self.closing = true
		send("close")
	end
	self:setVisible(false)
	self:removeFromUIManager()
	if AtfCasinoBlackjack.window == self then
		AtfCasinoBlackjack.window = nil
	end
end

function AtfCasinoBlackjackWindow:showError(message)
	self.lastError = message
	self.lastErrorAt = getTimestampMs()
end

function AtfCasinoBlackjackWindow:applyState(state)
	self.state = state
	self.stateAt = getTimestampMs()
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

function AtfCasinoBlackjackWindow:refreshButtons()
	local s = self.state
	local seated = s ~= nil and (s.you or 0) > 0
	self.sitBtn:setEnable(s ~= nil and s.canSit == true)
	self.leaveBtn:setEnable(seated)
	self.betBtn:setEnable(s ~= nil and s.canBet == true)
	self.minBtn:setEnable(s ~= nil and s.canBet == true)
	self.maxBtn:setEnable(s ~= nil and s.canBet == true)
	self.betEntry:setEditable(s ~= nil and s.canBet == true)
	self.hitBtn:setEnable(s ~= nil and s.canAct == true)
	self.standBtn:setEnable(s ~= nil and s.canAct == true)
	self.doubleBtn:setEnable(s ~= nil and s.canAct == true and s.canDouble == true)
end

function AtfCasinoBlackjackWindow:secondsLeft()
	if not self.state then
		return 0
	end
	local elapsed = (getTimestampMs() - self.stateAt) / 1000
	return math.max(0, math.floor((self.state.secondsLeft or 0) - elapsed + 0.999))
end

function AtfCasinoBlackjackWindow:drawCard(x, y, code)
	local w, h = CARD_W, CARD_H
	local hidden = code == "??"
	self:drawRect(x + 3, y + 3, w, h, 0.45, 0, 0, 0)
	local tex = cardTexture(hidden and BACK_TEXTURE or code)
	if tex then
		self:drawTextureScaled(tex, x, y, w, h, 1, 1, 1, 1)
		self:drawRectBorder(x, y, w, h, 0.6, 0.1, 0.1, 0.12)
		return
	end
	local rank, suit, red = cardParts(code)
	if hidden then
		self:drawRect(x, y, w, h, 1, 0.25, 0.25, 0.45)
		self:drawRectBorder(x, y, w, h, 1, 0.8, 0.8, 0.9)
		self:drawText("?", x + w / 2 - 5, y + h / 2 - HGT_MEDIUM / 2, 1, 1, 1, 1, FONT_MEDIUM)
		return
	end
	self:drawRect(x, y, w, h, 1, 0.95, 0.95, 0.92)
	self:drawRectBorder(x, y, w, h, 1, 0.2, 0.2, 0.2)
	local r, g, b = 0.1, 0.1, 0.1
	if red then
		r, g, b = 0.8, 0.1, 0.1
	end
	self:drawText(rank, x + 5, y + 3, r, g, b, 1, FONT_MEDIUM)
	self:drawText(suit, x + 5, y + h - HGT_MEDIUM - 4, r, g, b, 1, FONT_MEDIUM)
end

local function outcomeLabel(o)
	if o == "WIN" then
		return "WIN", 0.4, 1, 0.4
	elseif o == "BLACKJACK" then
		return "BLACKJACK!", 1, 0.85, 0.2
	elseif o == "PUSH" then
		return "PUSH", 0.8, 0.8, 0.8
	elseif o == "LOSE" then
		return "LOSE", 1, 0.4, 0.4
	elseif o == "BUST" then
		return "BUST", 1, 0.3, 0.3
	end
	return nil
end

function AtfCasinoBlackjackWindow:drawPanel(x, y, w, h, r, g, b, a, br, bg, bb, thick)
	self:drawRect(x, y, w, h, a, r, g, b)
	self:drawRectBorder(x, y, w, h, 1, br, bg, bb)
	if thick then
		self:drawRectBorder(x + 1, y + 1, w - 2, h - 2, 1, br, bg, bb)
	end
end

function AtfCasinoBlackjackWindow:render()
	ISCollapsableWindow.render(self)
	if not self:getIsVisible() then
		return
	end
	local s = self.state
	local tm = getTextManager()

	-- header: status left, money right
	local status
	local sr, sg, sb = 1, 1, 1
	if not s then
		status = txt("IGUI_AtfCasino_Blackjack_Connecting", "Talking to the dealer...")
	elseif s.phase == "BETTING" then
		local secs = self:secondsLeft()
		if (s.secondsLeft or 0) > 0 then
			status = txt("IGUI_AtfCasino_Blackjack_BetsClosing", "Place your bets - dealing in %1s", tostring(secs))
		else
			status = txt("IGUI_AtfCasino_Blackjack_Betting", "Place your bets")
		end
	elseif s.phase == "PLAYING" then
		if s.canAct then
			status = txt("IGUI_AtfCasino_Blackjack_YourTurn", "Your turn - %1s", tostring(self:secondsLeft()))
			sr, sg, sb = 1, 0.85, 0.2
		else
			status = txt("IGUI_AtfCasino_Blackjack_Waiting", "Seat %1 is playing", tostring(s.currentSeat or 0))
		end
	else
		status = txt("IGUI_AtfCasino_Blackjack_Settle", "Round over - next round in %1s", tostring(self:secondsLeft()))
	end
	self:drawText(status, PAD, self.headerY, sr, sg, sb, 1, FONT_LARGE)

	local bal = 0
	if ATFEconomy and ATFEconomy.getBalance then
		bal = ATFEconomy.getBalance(CURRENCY)
	end
	local balText = txt("IGUI_AtfCasino_Blackjack_Balance", "Balance: %1 Scraps", fmt(bal))
	local bw = tm:MeasureStringX(FONT_MEDIUM, balText)
	self:drawText(balText, self.width - bw - PAD, self.headerY, 0.95, 0.9, 0.55, 1, FONT_MEDIUM)
	if s then
		local lim = txt("IGUI_AtfCasino_Blackjack_Limits", "Bets %1 - %2", fmt(s.minBet or 0), fmt(s.maxBet or 0))
		local lw = tm:MeasureStringX(FONT_SMALL, lim)
		self:drawText(lim, self.width - lw - PAD, self.headerY + HGT_MEDIUM + 2, 0.7, 0.7, 0.7, 1, FONT_SMALL)
	end

	-- dealer felt
	local dy = self.dealerY
	local feltW = self.width - PAD * 2
	self:drawPanel(PAD, dy, feltW, DEALER_H, 0.05, 0.28, 0.12, 0.9, 0.35, 0.6, 0.35, false)
	local dealerLabel = txt("IGUI_AtfCasino_Blackjack_Dealer", "Dealer")
	local dr, dg, db = 1, 1, 1
	if s and s.dealer and s.dealer.total then
		local total = math.floor(s.dealer.total)
		if s.dealer.hidden then
			dealerLabel = dealerLabel
				.. "  -  "
				.. txt("IGUI_AtfCasino_Blackjack_DealerShows", "showing %1", tostring(total))
		elseif total > 21 then
			dealerLabel = dealerLabel
				.. "  -  "
				.. tostring(total)
				.. "  "
				.. txt("IGUI_AtfCasino_Blackjack_DealerBust", "BUST")
			dr, dg, db = 1, 0.45, 0.45
		else
			dealerLabel = dealerLabel .. "  -  " .. tostring(total)
		end
	end
	self:drawText(dealerLabel, PAD + 12, dy + 10, dr, dg, db, 1, FONT_MEDIUM)
	if s and s.dealer and s.dealer.cards then
		local cx = PAD + 12
		local cy = dy + 10 + HGT_MEDIUM + 10
		for _, code in ipairs(s.dealer.cards) do
			self:drawCard(cx, cy, code)
			cx = cx + CARD_STEP
		end
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
		local seatTag = txt("IGUI_AtfCasino_Blackjack_EmptySeat", "Seat %1", tostring(i))
		if seat then
			local name = seat.name or "?"
			local maxNameW = SEAT_W - SEAT_PAD * 2 - tm:MeasureStringX(FONT_SMALL, seatTag) - 6
			while #name > 3 and tm:MeasureStringX(FONT_MEDIUM, name .. "~") > maxNameW do
				name = string.sub(name, 1, #name - 1)
			end
			if name ~= seat.name then
				name = name .. "~"
			end
			local nr, ng, nb = 1, 1, 1
			if seat.isYou then
				nr, ng, nb = 0.6, 0.85, 1
			end
			self:drawText(name, tx, ty, nr, ng, nb, 1, FONT_MEDIUM)
			local tagW = tm:MeasureStringX(FONT_SMALL, seatTag)
			self:drawText(seatTag, sx + SEAT_W - SEAT_PAD - tagW, ty + 2, 0.5, 0.5, 0.5, 1, FONT_SMALL)
			ty = ty + HGT_MEDIUM
			local betLine
			if (seat.bet or 0) > 0 then
				betLine = txt("IGUI_AtfCasino_Blackjack_SeatBet", "Bet %1", fmt(seat.bet))
			else
				betLine = txt("IGUI_AtfCasino_Blackjack_NoBet", "No bet yet")
			end
			self:drawText(betLine, tx, ty, 0.95, 0.9, 0.55, 1, FONT_SMALL)
			ty = ty + HGT_SMALL + 10

			local cards = seat.cards or {}
			local n = #cards
			local step = FAN_STEP
			local avail = SEAT_W - SEAT_PAD * 2 - CARD_W
			if n > 1 and step * (n - 1) > avail then
				step = avail / (n - 1)
			end
			for k, code in ipairs(cards) do
				self:drawCard(tx + (k - 1) * step, ty, code)
			end
			ty = ty + CARD_H + 10

			if (seat.total or 0) > 0 then
				local total = tostring(math.floor(seat.total))
				if seat.soft and not seat.bust then
					total = total .. " " .. txt("IGUI_AtfCasino_Blackjack_Soft", "(soft)")
				end
				self:drawText(total, tx, ty, 1, 1, 1, 1, FONT_MEDIUM)
			end
			ty = ty + HGT_MEDIUM
			local label, r, g, b = outcomeLabel(seat.outcome)
			if seat.bust and not label then
				label, r, g, b = "BUST", 1, 0.3, 0.3
			end
			if label then
				local extra = ""
				if (seat.payout or 0) > 0 then
					extra = "  +" .. fmt(seat.payout)
				end
				self:drawText(label .. extra, tx, ty, r, g, b, 1, FONT_MEDIUM)
			elseif seat.leaving then
				self:drawText(txt("IGUI_AtfCasino_Blackjack_Leaving", "leaving"), tx, ty, 0.7, 0.7, 0.7, 1, FONT_MEDIUM)
			elseif seat.isTurn then
				self:drawText(
					txt("IGUI_AtfCasino_Blackjack_Thinking", "thinking..."),
					tx,
					ty,
					1,
					0.85,
					0.2,
					1,
					FONT_MEDIUM
				)
			end
		else
			self:drawText(seatTag, tx, ty, 0.55, 0.55, 0.55, 1, FONT_MEDIUM)
			self:drawText(
				txt("IGUI_AtfCasino_Blackjack_Open", "open"),
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
		self:drawText(self.logLines[i], PAD + 8, ly + 7 + row * HGT_SMALL, 0.85, 0.85, 0.85, 1, FONT_SMALL)
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

local ERROR_TEXT = {
	DISABLED = "The casino is closed right now",
	TOO_FAR = "You are too far from the dealer",
	TABLE_FULL = "The table is full",
	ALREADY_SEATED = "You are already seated",
	NOT_SEATED = "Sit down first",
	NOT_BETTING_PHASE = "Bets are closed - wait for the next round",
	ALREADY_BET = "You already placed a bet this round",
	BET_TOO_LOW = "That bet is below the table minimum",
	BET_TOO_HIGH = "That bet is above the table maximum",
	BANK_REFUSED = "The cashier refused your stake",
	INSUFFICIENT_BALANCE = "You don't have enough Scraps",
	NOT_YOUR_TURN = "It's not your turn",
	CANNOT_DOUBLE = "You can only double on your first two cards",
	PLAYER_OFFLINE = "Could not reach your account",
	DEAD = "The dealer doesn't deal to the dead",
}

-- Only one table window may exist. Anything else of our Type in the UI manager (a leak from a
-- Lua hot-reload, or a window whose handle we lost) is torn down before we show the real one.
local function removeStrayWindows(keep)
	local ui = UIManager.getUI()
	local strays = {}
	for i = 0, ui:size() - 1 do
		local el = ui:get(i)
		local t = el and el.getTable and el:getTable()
		if t and t ~= keep and t.Type == "AtfCasinoBlackjackWindow" then
			table.insert(strays, t)
		end
	end
	for _, t in ipairs(strays) do
		t:setVisible(false)
		t:removeFromUIManager()
	end
end

function AtfCasinoBlackjack.open()
	local player = getSpecificPlayer(0)
	if player == nil then
		return
	end
	removeStrayWindows(AtfCasinoBlackjack.window)
	local existing = AtfCasinoBlackjack.window
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
	local w = AtfCasinoBlackjackWindow:new(0, 0)
	w:initialise()
	w:setX(math.floor(getCore():getScreenWidth() / 2 - w.width / 2))
	w:setY(math.floor(getCore():getScreenHeight() / 2 - w.height / 2))
	w:addToUIManager()
	w:setVisible(true)
	AtfCasinoBlackjack.window = w
	send("open")
	sendClientCommand(player, ECONOMY_MODULE, "requestBalance", {})
end

local function onServerCommand(module, command, args)
	if module ~= MODULE then
		return
	end
	if command == "guardShot" then
		local player = getSpecificPlayer(0)
		if player then
			local text = txt("IGUI_AtfCasino_GuardShot", "The Creepy Spiffos open fire!")
			if args and args.reason == "godmode" then
				text = txt("IGUI_AtfCasino_GuardShotGodMode", "The Creepy Spiffos don't serve god-mode admins!")
			elseif args and args.reason == "assault" then
				text = txt("IGUI_AtfCasino_GuardShotAssault", "Nobody lays hands on the staff!")
			end
			player:setHaloNote(text, 255, 40, 40, 300)
		end
		return
	end
	local w = AtfCasinoBlackjack.window
	if command == "bjState" then
		if w then
			w:applyState(args)
		end
	elseif command == "bjError" then
		if w then
			local reason = args and args.reason or "ERROR"
			local detail = args and args.detail
			local text = ERROR_TEXT[reason] or ERROR_TEXT[detail or ""] or reason
			if detail and not ERROR_TEXT[detail] and detail ~= reason then
				text = text .. " (" .. tostring(detail) .. ")"
			end
			w:showError(text)
		end
	elseif command == "bjClosed" then
		if w then
			w.closing = true
			w:close()
		end
		local player = getSpecificPlayer(0)
		if player and (args == nil or args.reason ~= "DEAD") then
			player:setHaloNote(
				txt("IGUI_AtfCasino_Blackjack_WalkedAway", "You walked away from the table"),
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
		txt("IGUI_AtfCasino_Blackjack_ContextOption", "Play Blackjack with the Creepy Spiffo Dealer"),
		worldobjects,
		AtfCasinoBlackjack.open
	)
	if math.abs(player:getX() - DEALER.x) > 8 or math.abs(player:getY() - DEALER.y) > 8 then
		option.notAvailable = true
		local tip = ISToolTip:new()
		tip:initialise()
		tip:setVisible(false)
		tip.description = txt("IGUI_AtfCasino_Blackjack_TooFarTip", "Walk up to the dealer first")
		option.toolTip = tip
	end
end
Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)

local function onPlayerDeath(player)
	if player == getSpecificPlayer(0) and AtfCasinoBlackjack.window then
		AtfCasinoBlackjack.window:close()
	end
end
Events.OnPlayerDeath.Add(onPlayerDeath)
