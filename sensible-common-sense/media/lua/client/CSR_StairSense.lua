require "CSR_FeatureFlags"

local StairSense = ISUIElement:derive("CSR_StairSenseHUD")

local ICON_SIZE = 48
local NEAR_RADIUS = 1       -- player must be within 1 tile of stairs
local THREAT_RADIUS = 3     -- scan 3 tiles around stair top for zombies
local COOLDOWN_MS = 2000
local FADE_IN_MS = 300
local FADE_OUT_MS = 600
local PULSE_SPEED = 3.5
local TEXT_MARGIN = 6

local COLOR_CAUTION = { r = 1.0, g = 0.85, b = 0.0 }
local COLOR_DANGER  = { r = 1.0, g = 0.15, b = 0.1 }

local instance = nil
local iconTex = nil
local lastScanTime = 0
local threatCount = 0
local showAlpha = 0
local nearStairs = false

local function nowMs()
    return getTimestampMs and getTimestampMs() or os.time() * 1000
end

local function isEnabled()
    local sb = SandboxVars and SandboxVars.CommonSenseReborn or nil
    return not sb or sb.EnableStairSense ~= false
end

local function hasStairs(square)
    if square:HasStairsNorth() then return true end
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local obj = objects:get(i)
        local sprite = obj:getSprite()
        if sprite then
            local name = sprite:getName() or ""
            if name:find("stairs") then return true end
        end
    end
    return false
end

local function findNearbyStairs(player)
    local sq = player:getSquare()
    if not sq then return nil end
    local cell = sq:getCell()
    if not cell then return nil end
    local px, py, pz = sq:getX(), sq:getY(), sq:getZ()

    for dy = -NEAR_RADIUS, NEAR_RADIUS do
        for dx = -NEAR_RADIUS, NEAR_RADIUS do
            local checkSq = cell:getGridSquare(px + dx, py + dy, pz)
            if checkSq and hasStairs(checkSq) then
                return checkSq
            end
        end
    end
    return nil
end

local function countZombiesAbove(stairSquare)
    local cell = stairSquare:getCell()
    if not cell then return 0 end
    local sx, sy = stairSquare:getX(), stairSquare:getY()
    local sz = stairSquare:getZ() + 1
    local count = 0

    for dy = -THREAT_RADIUS, THREAT_RADIUS do
        for dx = -THREAT_RADIUS, THREAT_RADIUS do
            local sq = cell:getGridSquare(sx + dx, sy + dy, sz)
            if sq then
                local movingObjects = sq:getMovingObjects()
                for i = 0, movingObjects:size() - 1 do
                    local obj = movingObjects:get(i)
                    if instanceof(obj, "IsoZombie") and not obj:isDead() then
                        count = count + 1
                    end
                end
            end
        end
    end
    return count
end

function StairSense:initialise()
    ISUIElement.initialise(self)
    self:addToUIManager()
    self.javaObject:setWantKeyEvents(false)
    self.javaObject:setConsumeMouseEvents(false)
end

function StairSense:isMouseOver()
    return false
end

function StairSense:onMouseDown()
    return false
end

function StairSense:onMouseUp()
    return false
end

function StairSense:onMouseMove()
    return false
end

function StairSense:onMouseMoveOutside()
    return false
end

function StairSense:onRightMouseDown()
    return false
end

function StairSense:onRightMouseUp()
    return false
end

function StairSense:prerender()
end

function StairSense:render()
    if not isEnabled() then return end
    if showAlpha <= 0.01 then return end
    if not iconTex then
        iconTex = getTexture("media/ui/CSR_StairSense.png")
        if not iconTex then return end
    end

    local pulse = 0.7 + 0.3 * math.sin(nowMs() / 1000 * PULSE_SPEED)
    local alpha = showAlpha * pulse
    local color = threatCount >= 3 and COLOR_DANGER or COLOR_CAUTION

    local iconX = (self.width - ICON_SIZE) / 2
    local iconY = 0

    self:drawTextureScaled(iconTex, iconX, iconY, ICON_SIZE, ICON_SIZE, alpha, color.r, color.g, color.b)

    local text
    if threatCount == 1 then
        text = "You sense movement above..."
    elseif threatCount == 2 then
        text = "You hear shuffling above..."
    elseif threatCount >= 3 then
        text = "A crowd stirs above!"
    end

    if text then
        local font = UIFont.Small
        -- Perf: cache text width; only remeasure when the sentence changes (3 possible strings).
        if self._lastText ~= text then
            self._lastText = text
            self._lastTextW = getTextManager():MeasureStringX(font, text)
        end
        local textW = self._lastTextW
        local textX = (self.width - textW) / 2
        local textY = ICON_SIZE + TEXT_MARGIN
        self:drawText(text, textX, textY, color.r, color.g, color.b, alpha, font)
    end
end

function StairSense:update()
    if not isEnabled() then
        showAlpha = 0
        return
    end

    local player = getPlayer()
    if not player then
        showAlpha = 0
        return
    end

    local now = nowMs()
    local stairSquare = findNearbyStairs(player)
    nearStairs = stairSquare ~= nil

    if nearStairs then
        if now - lastScanTime >= COOLDOWN_MS then
            threatCount = countZombiesAbove(stairSquare)
            lastScanTime = now
        end
    end

    local shouldShow = nearStairs and threatCount > 0
    local dt = 1.0 / 60.0

    if shouldShow then
        showAlpha = math.min(1.0, showAlpha + dt / (FADE_IN_MS / 1000))
    else
        showAlpha = math.max(0.0, showAlpha - dt / (FADE_OUT_MS / 1000))
        if not nearStairs then
            threatCount = 0
            lastScanTime = 0
        end
    end
end

local function createHUD()
    if not isEnabled() then return end
    if instance then
        instance:removeFromUIManager()
    end

    local screenW = getCore():getScreenWidth()
    local panelW = 300
    local panelH = ICON_SIZE + TEXT_MARGIN + 25
    local x = (screenW - panelW) / 2
    local y = 10

    instance = StairSense:new(x, y, panelW, panelH)
    instance:initialise()
    instance:setVisible(true)
end

local function onResolutionChange()
    if instance then
        local screenW = getCore():getScreenWidth()
        local panelW = instance.width
        instance:setX((screenW - panelW) / 2)
    end
end

Events.OnGameStart.Add(createHUD)
Events.OnCreatePlayer.Add(function() createHUD() end)
Events.OnResolutionChange.Add(onResolutionChange)
