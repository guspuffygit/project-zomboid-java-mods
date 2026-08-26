---Client side of the Creepy Spiffo Croupier's roulette table. Pure view: clicking the board and every
---button sends an action to the server and the window redraws whatever `rlState` the server pushes
---back. Nothing here decides the winning number, payouts, or money.
require("ISUI/ISCollapsableWindow")
require("ISUI/ISButton")
require("ISUI/ISTextEntryBox")

local MODULE = "AtfCasino"
local COMMAND = "roulette"
local ECONOMY_MODULE = "AfterTheFallEconomy"
local CURRENCY = "Scraps"

local CROUPIER_DEFAULT = { x = 619, y = 9422, z = -1 }
local PICK_RADIUS = 2.5

-- Read at call time: the server rebroadcasts SandboxVars on live admin edits, so the
-- croupier (and this menu) can be moved without a relog.
local function croupierPos()
	local sv = SandboxVars and SandboxVars.AtfCasino
	return {
		x = (sv and sv.CroupierX) or CROUPIER_DEFAULT.x,
		y = (sv and sv.CroupierY) or CROUPIER_DEFAULT.y,
		z = (sv and sv.FloorZ) or CROUPIER_DEFAULT.z,
	}
end

local FONT_SMALL = UIFont.Small
local FONT_MEDIUM = UIFont.Medium
local FONT_LARGE = UIFont.Large
local HGT_SMALL = getTextManager():getFontHeight(FONT_SMALL)
local HGT_MEDIUM = getTextManager():getFontHeight(FONT_MEDIUM)
local HGT_LARGE = getTextManager():getFontHeight(FONT_LARGE)

local PAD = 16
local SEAT_W, SEAT_GAP, SEAT_PAD = 244, 12, 12
local SEAT_BET_LINES = 6
local SEAT_H = SEAT_PAD + HGT_MEDIUM + HGT_SMALL + 6 + SEAT_BET_LINES * HGT_SMALL + 6 + HGT_MEDIUM + SEAT_PAD
local WHEEL_W = 300
local CELL_W, CELL_H = 66, 50
local BOARD_PAD = 10
local BOARD_COLS, BOARD_ROWS = 14, 5
local BOARD_W = BOARD_COLS * CELL_W + BOARD_PAD * 2
local TOP_H = BOARD_ROWS * CELL_H + BOARD_PAD * 2 + HGT_SMALL + 8
local RESULT_BOX = 120
local HISTORY_BOX, HISTORY_GAP = 20, 3
local LOG_LINES = 6
local LOG_H = LOG_LINES * HGT_SMALL + 14
local BTN_W, BTN_H, BTN_GAP, GROUP_GAP = 104, 36, 8, 32
local QUICK_W, ENTRY_W = 70, 150
local SPIN_FLICKER_MS = 90

local RED_NUMBERS = {}
for _, n in ipairs({ 1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36 }) do
	RED_NUMBERS[n] = true
end

local ERROR_TEXT = {
	DISABLED = "The casino is closed right now",
	TOO_FAR = "You are too far from the croupier",
	TABLE_FULL = "The table is full",
	ALREADY_SEATED = "You are already seated",
	NOT_SEATED = "Sit down first",
	NOT_BETTING_PHASE = "Bets are closed - wait for the next spin",
	BET_TOO_LOW = "That chip is below the table minimum",
	BET_TOO_HIGH = "That would put more than the table maximum on one spot",
	TOO_MANY_BETS = "You have chips on too many spots already",
	BAD_BET = "The croupier doesn't take that bet",
	NO_BETS = "You have no chips on the board",
	BANK_REFUSED = "The cashier refused your stake",
	INSUFFICIENT_BALANCE = "You don't have enough Scraps",
	PLAYER_OFFLINE = "Could not reach your account",
	DEAD = "The croupier doesn't deal to the dead",
}

AtfCasinoRoulette = AtfCasinoRoulette or {}
AtfCasinoRoulette.window = nil

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

local function numberColor(n)
	if n == 0 then
		return 0.05, 0.45, 0.15
	elseif RED_NUMBERS[n] then
		return 0.72, 0.1, 0.1
	end
	return 0.08, 0.08, 0.1
end

local function spotKey(spot)
	return spot.type .. ":" .. tostring(spot.target)
end

-- Every clickable region of the betting board, in cell units relative to the board origin. Built
-- once; render and hit-testing both walk this list so they can never disagree.
local SPOTS = {}
local function addSpot(type, target, col, row, cols, rows, label)
	local spot = {
		type = type,
		target = target,
		cx = col,
		cy = row,
		cw = cols,
		ch = rows,
		label = label,
	}
	table.insert(SPOTS, spot)
	return spot
end
addSpot("straight", 0, 0, 0, 1, 3, "0")
for n = 1, 36 do
	local col = 1 + math.floor((n - 1) / 3)
	local row = 2 - ((n - 1) % 3)
	addSpot("straight", n, col, row, 1, 1, tostring(n))
end
for c = 1, 3 do
	addSpot("column", c, 13, 3 - c, 1, 1, "2 to 1")
end
addSpot("dozen", 1, 1, 3, 4, 1, "1st 12")
addSpot("dozen", 2, 5, 3, 4, 1, "2nd 12")
addSpot("dozen", 3, 9, 3, 4, 1, "3rd 12")
addSpot("low", 0, 1, 4, 2, 1, "1 - 18")
addSpot("even", 0, 3, 4, 2, 1, "EVEN")
addSpot("red", 0, 5, 4, 2, 1, "RED")
addSpot("black", 0, 7, 4, 2, 1, "BLACK")
addSpot("odd", 0, 9, 4, 2, 1, "ODD")
addSpot("high", 0, 11, 4, 2, 1, "19 - 36")

---@class AtfCasinoRouletteWindow : ISCollapsableWindow
AtfCasinoRouletteWindow = ISCollapsableWindow:derive("AtfCasinoRouletteWindow")

function AtfCasinoRouletteWindow:new(x, y)
	local width = PAD * 2 + SEAT_W * 5 + SEAT_GAP * 4
	local o = ISCollapsableWindow.new(self, x, y, width, 600)
	o.title = txt("IGUI_AtfCasino_Roulette_Title", "Roulette - Creepy Spiffo Croupier")
	o.resizable = false
	o.state = nil
	o.stateAt = 0
	o.lastError = nil
	o.lastErrorAt = 0
	o.logLines = {}
	o.closing = false
	o.hoverSpot = nil
	o.flickerNumber = 0
	o.flickerAt = 0
	return o
end

function AtfCasinoRouletteWindow:addButton(x, y, w, label, fn)
	local b = ISButton:new(x, y, w, BTN_H, label, self, fn)
	b:initialise()
	b.font = FONT_MEDIUM
	self:addChild(b)
	return b
end

function AtfCasinoRouletteWindow:createChildren()
	ISCollapsableWindow.createChildren(self)
	local th = self:titleBarHeight()
	self.headerY = th + 12
	self.topY = self.headerY + HGT_LARGE + 14
	self.boardX = PAD + WHEEL_W + PAD
	self.boardY = self.topY
	self.seatsY = self.topY + TOP_H + 18
	self.logY = self.seatsY + SEAT_H + 16
	self.buttonsY = self.logY + LOG_H + 16
	self:setHeight(self.buttonsY + BTN_H + PAD)

	local y = self.buttonsY
	local x = PAD
	self.sitBtn = self:addButton(x, y, BTN_W, txt("IGUI_AtfCasino_Roulette_Sit", "Sit"), self.onSit)
	x = x + BTN_W + BTN_GAP
	self.leaveBtn = self:addButton(x, y, BTN_W, txt("IGUI_AtfCasino_Roulette_Leave", "Get Up"), self.onLeave)
	x = x + BTN_W + GROUP_GAP

	self.chipLabelX = x
	x = x + getTextManager():MeasureStringX(FONT_MEDIUM, txt("IGUI_AtfCasino_Roulette_ChipLabel", "Chip:")) + 8
	self.betEntry = ISTextEntryBox:new("", x, y, ENTRY_W, BTN_H)
	self.betEntry:initialise()
	self.betEntry:instantiate()
	self.betEntry:setOnlyNumbers(true)
	self.betEntry.font = FONT_MEDIUM
	self:addChild(self.betEntry)
	x = x + ENTRY_W + BTN_GAP
	self.minBtn = self:addButton(x, y, QUICK_W, txt("IGUI_AtfCasino_Roulette_Min", "Min"), self.onMin)
	x = x + QUICK_W + BTN_GAP
	self.maxBtn = self:addButton(x, y, QUICK_W, txt("IGUI_AtfCasino_Roulette_Max", "Max"), self.onMax)
	x = x + QUICK_W + GROUP_GAP
	self.clearBtn = self:addButton(x, y, BTN_W + 20, txt("IGUI_AtfCasino_Roulette_Clear", "Clear Bets"), self.onClear)

	self.closeBtn =
		self:addButton(self.width - BTN_W - PAD, y, BTN_W, txt("IGUI_AtfCasino_Roulette_Close", "Close"), self.close)
	self.closeBtn:setTooltip(
		txt(
			"IGUI_AtfCasino_Roulette_CloseTip",
			"Hides the table. Your seat and chips are kept while you stay near the croupier."
		)
	)
	self:refreshButtons()
end

function AtfCasinoRouletteWindow:onMin()
	if self.state and self.state.minBet then
		self.betEntry:setText(tostring(math.floor(self.state.minBet)))
	end
end

function AtfCasinoRouletteWindow:onMax()
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

function AtfCasinoRouletteWindow:onSit()
	send("sit")
end

function AtfCasinoRouletteWindow:onLeave()
	send("leave")
end

function AtfCasinoRouletteWindow:onClear()
	send("clear")
end

function AtfCasinoRouletteWindow:placeChip(spot)
	local s = self.state
	if not s or (s.you or 0) == 0 then
		self:showError(ERROR_TEXT.NOT_SEATED)
		return
	end
	if not s.canBet then
		self:showError(ERROR_TEXT.NOT_BETTING_PHASE)
		return
	end
	local amount = tonumber(self.betEntry:getInternalText()) or 0
	if amount <= 0 then
		self:showError(txt("IGUI_AtfCasino_Roulette_Err_EnterChip", "Enter a chip amount first"))
		return
	end
	send("bet", { type = spot.type, target = spot.target, amount = amount })
end

function AtfCasinoRouletteWindow:close()
	if not self.closing then
		self.closing = true
		send("close")
	end
	self:setVisible(false)
	self:removeFromUIManager()
	if AtfCasinoRoulette.window == self then
		AtfCasinoRoulette.window = nil
	end
end

function AtfCasinoRouletteWindow:showError(message)
	self.lastError = message
	self.lastErrorAt = getTimestampMs()
end

function AtfCasinoRouletteWindow:applyState(state)
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
	-- chips by board spot, split into mine / everyone else's, so the board can label each cell
	self.chips = {}
	if state.seats then
		for _, seat in ipairs(state.seats) do
			for _, bet in ipairs(seat.bets or {}) do
				local key = bet.type .. ":" .. tostring(math.floor(bet.target or 0))
				local c = self.chips[key]
				if not c then
					c = { mine = 0, others = 0 }
					self.chips[key] = c
				end
				if seat.isYou then
					c.mine = c.mine + (bet.amount or 0)
				else
					c.others = c.others + (bet.amount or 0)
				end
			end
		end
	end
	self:refreshButtons()
end

function AtfCasinoRouletteWindow:refreshButtons()
	local s = self.state
	local seated = s ~= nil and (s.you or 0) > 0
	self.sitBtn:setEnable(s ~= nil and s.canSit == true)
	self.leaveBtn:setEnable(seated)
	self.minBtn:setEnable(s ~= nil and s.canBet == true)
	self.maxBtn:setEnable(s ~= nil and s.canBet == true)
	self.betEntry:setEditable(s ~= nil and s.canBet == true)
	self.clearBtn:setEnable(s ~= nil and s.canClear == true)
end

function AtfCasinoRouletteWindow:secondsLeft()
	if not self.state then
		return 0
	end
	local elapsed = (getTimestampMs() - self.stateAt) / 1000
	return math.max(0, math.floor((self.state.secondsLeft or 0) - elapsed + 0.999))
end

-- --- board geometry ---

function AtfCasinoRouletteWindow:spotRect(spot)
	local x = self.boardX + BOARD_PAD + spot.cx * CELL_W
	local y = self.boardY + BOARD_PAD + spot.cy * CELL_H
	return x, y, spot.cw * CELL_W, spot.ch * CELL_H
end

function AtfCasinoRouletteWindow:spotAt(x, y)
	for _, spot in ipairs(SPOTS) do
		local sx, sy, sw, sh = self:spotRect(spot)
		if x >= sx and x < sx + sw and y >= sy and y < sy + sh then
			return spot
		end
	end
	return nil
end

function AtfCasinoRouletteWindow:onMouseDown(x, y)
	if self:getIsVisible() then
		local spot = self:spotAt(x, y)
		if spot then
			self:bringToTop()
			self:placeChip(spot)
			return true
		end
	end
	return ISCollapsableWindow.onMouseDown(self, x, y)
end

function AtfCasinoRouletteWindow:onMouseMove(dx, dy)
	self.hoverSpot = self:spotAt(self:getMouseX(), self:getMouseY())
	return ISCollapsableWindow.onMouseMove(self, dx, dy)
end

function AtfCasinoRouletteWindow:onMouseMoveOutside(dx, dy)
	self.hoverSpot = nil
	return ISCollapsableWindow.onMouseMoveOutside(self, dx, dy)
end

-- --- drawing ---

function AtfCasinoRouletteWindow:drawPanel(x, y, w, h, r, g, b, a, br, bg, bb, thick)
	self:drawRect(x, y, w, h, a, r, g, b)
	self:drawRectBorder(x, y, w, h, 1, br, bg, bb)
	if thick then
		self:drawRectBorder(x + 1, y + 1, w - 2, h - 2, 1, br, bg, bb)
	end
end

function AtfCasinoRouletteWindow:drawCentered(text, x, y, w, h, r, g, b, font, hgt)
	local tw = getTextManager():MeasureStringX(font, text)
	self:drawText(text, x + w / 2 - tw / 2, y + h / 2 - hgt / 2, r, g, b, 1, font)
end

local function spotWins(spot, winning)
	if winning == nil or winning < 0 then
		return false
	end
	local t, n = spot.type, winning
	if t == "straight" then
		return n == spot.target
	end
	if n == 0 then
		return false
	end
	if t == "red" then
		return RED_NUMBERS[n] == true
	elseif t == "black" then
		return not RED_NUMBERS[n]
	elseif t == "odd" then
		return n % 2 == 1
	elseif t == "even" then
		return n % 2 == 0
	elseif t == "low" then
		return n <= 18
	elseif t == "high" then
		return n >= 19
	elseif t == "dozen" then
		return math.floor((n - 1) / 12) + 1 == spot.target
	elseif t == "column" then
		return ((n - 1) % 3) + 1 == spot.target
	end
	return false
end

function AtfCasinoRouletteWindow:drawBoard(s)
	local bx, by = self.boardX, self.boardY
	self:drawPanel(bx, by, BOARD_W, TOP_H, 0.05, 0.28, 0.12, 0.9, 0.35, 0.6, 0.35, false)
	local winning = s and s.winningNumber or -1
	if winning ~= nil and winning < 0 then
		winning = nil
	end
	local canBet = s and s.canBet == true
	for _, spot in ipairs(SPOTS) do
		local x, y, w, h = self:spotRect(spot)
		local r, g, b = 0.05, 0.22, 0.1
		local font, hgt = FONT_SMALL, HGT_SMALL
		if spot.type == "straight" then
			r, g, b = numberColor(spot.target)
			font, hgt = FONT_MEDIUM, HGT_MEDIUM
		elseif spot.type == "red" then
			r, g, b = 0.55, 0.08, 0.08
		elseif spot.type == "black" then
			r, g, b = 0.06, 0.06, 0.08
		end
		local won = spotWins(spot, winning)
		if won then
			r, g, b = math.min(1, r + 0.25), math.min(1, g + 0.25), math.min(1, b + 0.25)
		end
		self:drawRect(x + 1, y + 1, w - 2, h - 2, 1, r, g, b)
		local br, bg, bb, thick = 0.85, 0.8, 0.55, false
		if won then
			br, bg, bb, thick = 1, 1, 1, true
		elseif canBet and self.hoverSpot == spot then
			br, bg, bb, thick = 1, 0.95, 0.5, true
		end
		self:drawRectBorder(x, y, w, h, 1, br, bg, bb)
		if thick then
			self:drawRectBorder(x + 1, y + 1, w - 2, h - 2, 1, br, bg, bb)
		end
		self:drawCentered(spot.label, x, y, w, h, 1, 1, 1, font, hgt)
		local chips = self.chips and self.chips[spotKey(spot)]
		if chips then
			if chips.mine > 0 then
				local label = fmt(chips.mine)
				local lw = getTextManager():MeasureStringX(FONT_SMALL, label) + 8
				local cx = x + w / 2 - lw / 2
				local cy = y + h - HGT_SMALL - 3
				self:drawRect(cx, cy, lw, HGT_SMALL + 1, 0.95, 0.95, 0.8, 0.2)
				self:drawRectBorder(cx, cy, lw, HGT_SMALL + 1, 1, 0.6, 0.45, 0.05)
				self:drawText(label, cx + 4, cy, 0.1, 0.1, 0.1, 1, FONT_SMALL)
			end
			if chips.others > 0 then
				local label = fmt(chips.others)
				local lw = getTextManager():MeasureStringX(FONT_SMALL, label)
				self:drawText(label, x + w - lw - 3, y + 2, 0.8, 0.8, 0.85, 0.9, FONT_SMALL)
			end
		end
	end
	local hint
	if not s then
		hint = ""
	elseif (s.you or 0) == 0 then
		hint = txt("IGUI_AtfCasino_Roulette_SitHint", "Sit down to play")
	elseif canBet then
		hint = txt("IGUI_AtfCasino_Roulette_BoardHint", "Click the board to place a chip")
	else
		hint = txt("IGUI_AtfCasino_Roulette_BoardClosed", "Bets are closed")
	end
	self:drawText(hint, bx + BOARD_PAD, by + BOARD_PAD + BOARD_ROWS * CELL_H + 6, 0.85, 0.85, 0.85, 1, FONT_SMALL)
end

function AtfCasinoRouletteWindow:drawWheel(s)
	local wx, wy = PAD, self.topY
	self:drawPanel(wx, wy, WHEEL_W, TOP_H, 0.07, 0.07, 0.09, 0.85, 0.32, 0.32, 0.36, false)
	self:drawText(txt("IGUI_AtfCasino_Roulette_Wheel", "Wheel"), wx + 12, wy + 8, 1, 1, 1, 1, FONT_MEDIUM)
	local phase = s and s.phase
	local shown, dim = nil, false
	if phase == "SPINNING" then
		local nowMs = getTimestampMs()
		if nowMs - self.flickerAt > SPIN_FLICKER_MS then
			self.flickerAt = nowMs
			self.flickerNumber = ZombRand(37)
		end
		shown = self.flickerNumber
	elseif phase == "SETTLE" and s.winningNumber and s.winningNumber >= 0 then
		shown = s.winningNumber
	elseif s and s.history and s.history[1] then
		shown, dim = s.history[1], true
	end
	local bxp = wx + WHEEL_W / 2 - RESULT_BOX / 2
	local byp = wy + 8 + HGT_MEDIUM + 12
	if shown ~= nil then
		local r, g, b = numberColor(shown)
		local a = dim and 0.45 or 1
		self:drawRect(bxp, byp, RESULT_BOX, RESULT_BOX, a, r, g, b)
		self:drawRectBorder(bxp, byp, RESULT_BOX, RESULT_BOX, 1, 0.85, 0.8, 0.55)
		self:drawRectBorder(bxp + 1, byp + 1, RESULT_BOX - 2, RESULT_BOX - 2, 1, 0.85, 0.8, 0.55)
		self:drawCentered(tostring(shown), bxp, byp, RESULT_BOX, RESULT_BOX, 1, 1, 1, FONT_LARGE, HGT_LARGE)
	else
		self:drawRectBorder(bxp, byp, RESULT_BOX, RESULT_BOX, 1, 0.4, 0.4, 0.45)
		self:drawCentered(
			txt("IGUI_AtfCasino_Roulette_NoSpinYet", "no spins yet"),
			bxp,
			byp,
			RESULT_BOX,
			RESULT_BOX,
			0.5,
			0.5,
			0.5,
			FONT_SMALL,
			HGT_SMALL
		)
	end
	local hy = byp + RESULT_BOX + 14
	self:drawText(txt("IGUI_AtfCasino_Roulette_History", "Last numbers"), wx + 12, hy, 0.7, 0.7, 0.7, 1, FONT_SMALL)
	hy = hy + HGT_SMALL + 4
	local hx = wx + 12
	for _, n in ipairs((s and s.history) or {}) do
		if hx + HISTORY_BOX > wx + WHEEL_W - 12 then
			break
		end
		local r, g, b = numberColor(n)
		self:drawRect(hx, hy, HISTORY_BOX, HISTORY_BOX, 1, r, g, b)
		self:drawRectBorder(hx, hy, HISTORY_BOX, HISTORY_BOX, 1, 0.5, 0.5, 0.5)
		self:drawCentered(tostring(n), hx, hy, HISTORY_BOX, HISTORY_BOX, 1, 1, 1, FONT_SMALL, HGT_SMALL)
		hx = hx + HISTORY_BOX + HISTORY_GAP
	end
end

function AtfCasinoRouletteWindow:render()
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
		status = txt("IGUI_AtfCasino_Roulette_Connecting", "Talking to the croupier...")
	elseif s.phase == "BETTING" then
		if (s.secondsLeft or 0) > 0 then
			status = txt(
				"IGUI_AtfCasino_Roulette_BetsClosing",
				"Place your bets - spinning in %1s",
				tostring(self:secondsLeft())
			)
		else
			status = txt("IGUI_AtfCasino_Roulette_Betting", "Place your bets")
		end
	elseif s.phase == "SPINNING" then
		status = txt("IGUI_AtfCasino_Roulette_Spinning", "No more bets - the wheel is spinning")
		sr, sg, sb = 1, 0.85, 0.2
	else
		local n = s.winningNumber or 0
		local color = string.upper(s.winningColor or "")
		status = txt(
			"IGUI_AtfCasino_Roulette_Settle",
			"%1 %2 - next spin in %3s",
			tostring(n),
			color,
			tostring(self:secondsLeft())
		)
		if n == 0 then
			sr, sg, sb = 0.4, 1, 0.5
		elseif RED_NUMBERS[n] then
			sr, sg, sb = 1, 0.45, 0.45
		end
	end
	self:drawText(status, PAD, self.headerY, sr, sg, sb, 1, FONT_LARGE)

	local bal = 0
	if ATFEconomy and ATFEconomy.getBalance then
		bal = ATFEconomy.getBalance(CURRENCY)
	end
	local balText = txt("IGUI_AtfCasino_Roulette_Balance", "Balance: %1 Scraps", fmt(bal))
	local bw = tm:MeasureStringX(FONT_MEDIUM, balText)
	self:drawText(balText, self.width - bw - PAD, self.headerY, 0.95, 0.9, 0.55, 1, FONT_MEDIUM)
	if s then
		local lim = txt("IGUI_AtfCasino_Roulette_Limits", "Chips %1 - %2", fmt(s.minBet or 0), fmt(s.maxBet or 0))
		local lw = tm:MeasureStringX(FONT_SMALL, lim)
		self:drawText(lim, self.width - lw - PAD, self.headerY + HGT_MEDIUM + 2, 0.7, 0.7, 0.7, 1, FONT_SMALL)
	end

	self:drawWheel(s)
	self:drawBoard(s)

	-- seats
	local maxSeats = (s and s.maxSeats) or 5
	local bySeat = {}
	if s and s.seats then
		for _, seat in ipairs(s.seats) do
			bySeat[seat.index] = seat
		end
	end
	local settled = s and s.phase == "SETTLE"
	for i = 1, maxSeats do
		local sx = PAD + (i - 1) * (SEAT_W + SEAT_GAP)
		local sy = self.seatsY
		local seat = bySeat[i]
		local br, bg, bb, thick = 0.32, 0.32, 0.36, false
		local pr, pg, pb, pa = 0.07, 0.07, 0.09, 0.8
		if seat and seat.isYou then
			br, bg, bb, thick = 0.4, 0.7, 1, true
			pr, pg, pb = 0.06, 0.09, 0.16
		end
		self:drawPanel(sx, sy, SEAT_W, SEAT_H, pr, pg, pb, pa, br, bg, bb, thick)
		local tx = sx + SEAT_PAD
		local ty = sy + SEAT_PAD
		local seatTag = txt("IGUI_AtfCasino_Roulette_EmptySeat", "Seat %1", tostring(i))
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
			local stakeLine
			if (seat.staked or 0) > 0 then
				stakeLine = txt("IGUI_AtfCasino_Roulette_SeatStaked", "On the board: %1", fmt(seat.staked))
			else
				stakeLine = txt("IGUI_AtfCasino_Roulette_NoBets", "No chips down")
			end
			self:drawText(stakeLine, tx, ty, 0.95, 0.9, 0.55, 1, FONT_SMALL)
			ty = ty + HGT_SMALL + 6

			local bets = seat.bets or {}
			local shown = math.min(#bets, SEAT_BET_LINES)
			if #bets > SEAT_BET_LINES then
				shown = SEAT_BET_LINES - 1
			end
			for k = 1, shown do
				local bet = bets[k]
				local line = fmt(bet.amount) .. " on " .. tostring(bet.label or bet.type)
				local lr, lg, lb = 0.85, 0.85, 0.85
				if settled and bet.won == true then
					line = line .. "  +" .. fmt(bet.payout or 0)
					lr, lg, lb = 0.4, 1, 0.4
				elseif settled and bet.won == false then
					lr, lg, lb = 0.6, 0.45, 0.45
				end
				self:drawText(line, tx, ty + (k - 1) * HGT_SMALL, lr, lg, lb, 1, FONT_SMALL)
			end
			if #bets > SEAT_BET_LINES then
				self:drawText(
					"+" .. tostring(#bets - shown) .. " more",
					tx,
					ty + shown * HGT_SMALL,
					0.6,
					0.6,
					0.6,
					1,
					FONT_SMALL
				)
			end
			ty = ty + SEAT_BET_LINES * HGT_SMALL + 6

			if settled and (seat.staked or 0) > 0 then
				if (seat.payout or 0) > 0 then
					self:drawText(
						txt("IGUI_AtfCasino_Roulette_Won", "WON +%1", fmt(seat.payout)),
						tx,
						ty,
						0.4,
						1,
						0.4,
						1,
						FONT_MEDIUM
					)
				else
					self:drawText(txt("IGUI_AtfCasino_Roulette_Lost", "LOST"), tx, ty, 1, 0.4, 0.4, 1, FONT_MEDIUM)
				end
			elseif seat.leaving then
				self:drawText(txt("IGUI_AtfCasino_Roulette_Leaving", "leaving"), tx, ty, 0.7, 0.7, 0.7, 1, FONT_MEDIUM)
			end
		else
			self:drawText(seatTag, tx, ty, 0.55, 0.55, 0.55, 1, FONT_MEDIUM)
			self:drawText(
				txt("IGUI_AtfCasino_Roulette_Open", "open"),
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
	local feltW = self.width - PAD * 2
	self:drawPanel(PAD, ly, feltW, LOG_H, 0.04, 0.04, 0.05, 0.75, 0.25, 0.25, 0.28, false)
	local first = math.max(1, #self.logLines - LOG_LINES + 1)
	local row = 0
	for i = first, #self.logLines do
		self:drawText(self.logLines[i], PAD + 8, ly + 7 + row * HGT_SMALL, 0.85, 0.85, 0.85, 1, FONT_SMALL)
		row = row + 1
	end

	self:drawText(
		txt("IGUI_AtfCasino_Roulette_ChipLabel", "Chip:"),
		self.chipLabelX,
		self.buttonsY + BTN_H / 2 - HGT_MEDIUM / 2,
		0.9,
		0.9,
		0.9,
		1,
		FONT_MEDIUM
	)

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

-- Only one table window may exist. Anything else of our Type in the UI manager (a leak from a
-- Lua hot-reload, or a window whose handle we lost) is torn down before we show the real one.
local function removeStrayWindows(keep)
	local ui = UIManager.getUI()
	local strays = {}
	for i = 0, ui:size() - 1 do
		local el = ui:get(i)
		local t = el and el.getTable and el:getTable()
		if t and t ~= keep and t.Type == "AtfCasinoRouletteWindow" then
			table.insert(strays, t)
		end
	end
	for _, t in ipairs(strays) do
		t:setVisible(false)
		t:removeFromUIManager()
	end
end

function AtfCasinoRoulette.open()
	local player = getSpecificPlayer(0)
	if player == nil then
		return
	end
	removeStrayWindows(AtfCasinoRoulette.window)
	local existing = AtfCasinoRoulette.window
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
	local w = AtfCasinoRouletteWindow:new(0, 0)
	w:initialise()
	w:setX(math.floor(getCore():getScreenWidth() / 2 - w.width / 2))
	w:setY(math.floor(getCore():getScreenHeight() / 2 - w.height / 2))
	w:addToUIManager()
	w:setVisible(true)
	AtfCasinoRoulette.window = w
	send("open")
	sendClientCommand(player, ECONOMY_MODULE, "requestBalance", {})
end

local function onServerCommand(module, command, args)
	if module ~= MODULE then
		return
	end
	local w = AtfCasinoRoulette.window
	if command == "rlState" then
		if w then
			w:applyState(args)
		end
	elseif command == "rlError" then
		if w then
			local reason = args and args.reason or "ERROR"
			local detail = args and args.detail
			local text = ERROR_TEXT[reason] or ERROR_TEXT[detail or ""] or reason
			if detail and not ERROR_TEXT[detail] and detail ~= reason then
				text = text .. " (" .. tostring(detail) .. ")"
			end
			w:showError(text)
		end
	elseif command == "rlClosed" then
		if w then
			w.closing = true
			w:close()
		end
		local player = getSpecificPlayer(0)
		if player and (args == nil or args.reason ~= "DEAD") then
			player:setHaloNote(
				txt("IGUI_AtfCasino_Roulette_WalkedAway", "You walked away from the wheel"),
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
	local CROUPIER = croupierPos()
	if not player or player:getZ() ~= CROUPIER.z then
		return
	end
	local sq = clickedSquare(worldobjects)
	local cx, cy
	if sq then
		cx, cy = sq:getX(), sq:getY()
	else
		cx = ISCoordConversion.ToWorldX(getMouseX(), getMouseY(), CROUPIER.z)
		cy = ISCoordConversion.ToWorldY(getMouseX(), getMouseY(), CROUPIER.z)
	end
	if math.abs(cx - CROUPIER.x) > PICK_RADIUS or math.abs(cy - CROUPIER.y) > PICK_RADIUS then
		return
	end
	local option = context:addOption(
		txt("IGUI_AtfCasino_Roulette_ContextOption", "Play Roulette with the Creepy Spiffo Croupier"),
		worldobjects,
		AtfCasinoRoulette.open
	)
	if math.abs(player:getX() - CROUPIER.x) > 8 or math.abs(player:getY() - CROUPIER.y) > 8 then
		option.notAvailable = true
		local tip = ISToolTip:new()
		tip:initialise()
		tip:setVisible(false)
		tip.description = txt("IGUI_AtfCasino_Roulette_TooFarTip", "Walk up to the croupier first")
		option.toolTip = tip
	end
end
Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)

local function onPlayerDeath(player)
	if player == getSpecificPlayer(0) and AtfCasinoRoulette.window then
		AtfCasinoRoulette.window:close()
	end
end
Events.OnPlayerDeath.Add(onPlayerDeath)
