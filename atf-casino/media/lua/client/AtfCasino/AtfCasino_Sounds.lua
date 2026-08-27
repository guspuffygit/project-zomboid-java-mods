-- Table-game sound cues, driven by diffing successive server state snapshots.
-- Each game window calls the matching function from applyState with the
-- previous and the new state; this module derives what just happened.
--
-- Sounds play through the local player's emitter (playSoundImpl, never
-- playSound: that one broadcasts a PlaySound packet to other MP clients),
-- so each instance can be volume-scaled by the user's 0-10 casino level.
require("ISUI/ISVolumeControl")

AtfCasinoSounds = AtfCasinoSounds or {}
local S = AtfCasinoSounds

local VOLUME_FILE = "atf-casino-volume.txt"
local DEFAULT_LEVEL = 7

local function clampLevel(n)
    n = math.floor(tonumber(n) or DEFAULT_LEVEL)
    if n < 0 then
        return 0
    end
    if n > 10 then
        return 10
    end
    return n
end

function S.getLevel()
    if S.level == nil then
        local level = DEFAULT_LEVEL
        local reader = getFileReader(VOLUME_FILE, true)
        if reader then
            local line = reader:readLine()
            reader:close()
            if line and tonumber(line) then
                level = clampLevel(line)
            end
        end
        S.level = level
    end
    return S.level
end

local function play(name)
    local level = S.getLevel()
    if level <= 0 then
        return nil, nil
    end
    local player = getSpecificPlayer(0)
    local emitter = player and player:getEmitter()
    if not emitter then
        return nil, nil
    end
    local handle = emitter:playSoundImpl(name, player)
    if not handle or handle == 0 then
        return nil, nil
    end
    emitter:setVolume(handle, level / 10)
    return handle, emitter
end

S.play = play

local function startSpinSound()
    S.spinHandle, S.spinEmitter = play("AtfCasinoRouletteSpin")
end

local function stopSpinSound()
    if S.spinHandle and S.spinEmitter then
        S.spinEmitter:stopSound(S.spinHandle)
    end
    S.spinHandle, S.spinEmitter = nil, nil
end

function S.setLevel(level)
    level = clampLevel(level)
    if level == S.getLevel() then
        return
    end
    S.level = level
    local writer = getFileWriter(VOLUME_FILE, true, false)
    if writer then
        writer:write(tostring(level))
        writer:close()
    end
    if S.spinHandle then
        if level <= 0 then
            stopSpinSound()
        else
            S.spinEmitter:setVolume(S.spinHandle, level / 10)
        end
    elseif S.spinActive and level > 0 then
        startSpinSound()
    end
end

function S.addVolumeControl(window, x, y, width, height)
    local control = ISVolumeControl:new(x, y, width, height, nil, function(_, _, volume)
        S.setLevel(volume)
    end)
    control:initialise()
    control.volume = S.getLevel()
    control.tooltip = "Casino sound volume"
    window:addChild(control)
    return control
end

local function mySeat(s)
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

local function totalCards(s)
    local n = 0
    if s.dealer and s.dealer.cards then
        n = n + #s.dealer.cards
    end
    if s.seats then
        for _, seat in ipairs(s.seats) do
            n = n + #(seat.cards or {})
        end
    end
    return n
end

local function totalBets(s)
    local n = 0
    if s.seats then
        for _, seat in ipairs(s.seats) do
            n = n + (seat.bet or 0)
        end
    end
    return n
end

function S.blackjack(old, new)
    if not old or not new then
        return
    end
    if old.phase == "BETTING" and new.phase == "PLAYING" then
        play("AtfCasinoCardShuffle")
        play("AtfCasinoCardDeal")
    elseif old.phase == new.phase and totalCards(new) > totalCards(old) then
        play("AtfCasinoCardDeal")
    end
    if old.dealer and new.dealer and old.dealer.hidden and new.dealer.hidden == false then
        play("AtfCasinoCardFlip")
    end
    if new.phase == "BETTING" and totalBets(new) > totalBets(old) then
        play("AtfCasinoChipBet")
    end
    local meOld, meNew = mySeat(old), mySeat(new)
    local outcome = meNew and meNew.outcome or nil
    if outcome and outcome ~= (meOld and meOld.outcome or nil) then
        if outcome == "WIN" or outcome == "BLACKJACK" then
            play("AtfCasinoChipPayout")
            play("AtfCasinoWin")
        elseif outcome == "PUSH" then
            play("AtfCasinoChipBet")
        elseif outcome == "LOSE" or outcome == "BUST" then
            play("AtfCasinoLose")
        end
    end
end

local function myRouletteBets(s)
    local me = mySeat(s)
    return (me and me.bets) or {}
end

function S.startRouletteSpin(win)
    S.stopRouletteSpin(win)
    S.spinActive = true
    startSpinSound()
end

function S.stopRouletteSpin(win)
    S.spinActive = false
    stopSpinSound()
end

function S.roulette(win, old, new)
    if not new then
        return
    end
    if new.phase == "SPINNING" then
        if not old or old.phase ~= "SPINNING" then
            S.startRouletteSpin(win)
        end
    elseif old and old.phase == "SPINNING" then
        S.stopRouletteSpin(win)
        play("AtfCasinoRouletteBall")
    end
    if not old then
        return
    end
    if new.phase == "BETTING" then
        local before, after = 0, 0
        for _, b in ipairs(myRouletteBets(old)) do
            before = before + (b.amount or 0)
        end
        for _, b in ipairs(myRouletteBets(new)) do
            after = after + (b.amount or 0)
        end
        if after > before then
            play("AtfCasinoChipBet")
        end
    end
    if new.phase == "SETTLE" and old.phase ~= "SETTLE" then
        local bets = myRouletteBets(new)
        if #bets > 0 then
            local won = false
            for _, b in ipairs(bets) do
                if b.won == true then
                    won = true
                end
            end
            if won then
                play("AtfCasinoChipPayout")
                play("AtfCasinoWin")
            else
                play("AtfCasinoLose")
            end
        end
    end
end

function S.holdem(old, new)
    if not old or not new then
        return
    end
    if old.phase ~= new.phase then
        if new.phase == "PREFLOP" then
            play("AtfCasinoCardShuffle")
            play("AtfCasinoCardDeal")
        elseif
            new.phase == "FLOP"
            or new.phase == "TURN"
            or new.phase == "RIVER"
            or new.phase == "SHOWDOWN"
        then
            play("AtfCasinoCardFlip")
        end
    end
    if totalBets(new) > totalBets(old) then
        play("AtfCasinoChipBet")
    end
    local meOld, meNew = mySeat(old), mySeat(new)
    if meNew and (meNew.won or 0) > 0 and (not meOld or (meOld.won or 0) == 0) then
        play("AtfCasinoChipPayout")
        play("AtfCasinoWin")
    end
end
