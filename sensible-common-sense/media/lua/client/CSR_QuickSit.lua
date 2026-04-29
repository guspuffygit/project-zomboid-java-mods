require "CSR_FeatureFlags"

CSR_QuickSit = {}

local DEFAULT_KEY = Keyboard and Keyboard.KEY_SUBTRACT or 74
local SEARCH_RADIUS = 2

local options = nil
local quickSitKeyBind = nil
if PZAPI and PZAPI.ModOptions and PZAPI.ModOptions.create then
    options = PZAPI.ModOptions:create("CommonSenseRebornQuickSit", "Common Sense Reborn - Quick Sit")
    if options and options.addKeyBind then
        quickSitKeyBind = options:addKeyBind("quickSitToggle", "Quick Sit / Stand", DEFAULT_KEY)
    end
end

local function getBoundKey()
    if quickSitKeyBind and quickSitKeyBind.getValue then
        return quickSitKeyBind:getValue()
    end
    return DEFAULT_KEY
end

local function getPlayerByIndex(index)
    return getSpecificPlayer and getSpecificPlayer(index) or nil
end

local function getDistanceSq(player, square)
    if not player or not square then
        return math.huge
    end
    return IsoUtils.DistanceToSquared(player:getX(), player:getY(), square:getX() + 0.5, square:getY() + 0.5)
end

local function hasSeatData(object)
    return object and SeatingManager and SeatingManager.getInstance
        and SeatingManager.getInstance():getTilePositionCount(object) > 0
end

local function isBusy(player)
    if not player then
        return true
    end
    if player:shouldBeTurning() then
        return true
    end
    if player:getVehicle() then
        return true
    end
    if player:isDead() or player:isAsleep() or player:isPlayerMoving() then
        return true
    end
    if player:isClimbing() or player:isAiming() or player:isRunning() or player:isSprinting() then
        return true
    end
    if player:getCharacterActions() and not player:getCharacterActions():isEmpty() then
        return true
    end
    return false
end

local function notify(player, text, good)
    if not player or not HaloTextHelper or not HaloTextHelper.addTextWithArrow then
        return
    end
    HaloTextHelper.addTextWithArrow(
        player,
        text,
        good == true,
        good == true and HaloTextHelper.getColorGreen() or HaloTextHelper.getColorRed()
    )
end

local function getNearbyFurnitureSeat(player)
    if not player then
        return nil
    end

    local cell = getCell and getCell() or nil
    if not cell then
        return nil
    end

    local z = player:getZ()
    local px = math.floor(player:getX())
    local py = math.floor(player:getY())
    local bestObject = nil
    local bestDist = math.huge

    for dy = -SEARCH_RADIUS, SEARCH_RADIUS do
        for dx = -SEARCH_RADIUS, SEARCH_RADIUS do
            local square = cell:getGridSquare(px + dx, py + dy, z)
            if square then
                local objects = square:getObjects()
                if objects then
                    for i = 0, objects:size() - 1 do
                        local object = objects:get(i)
                        if hasSeatData(object) then
                            local dist = getDistanceSq(player, square)
                            if dist < bestDist then
                                bestDist = dist
                                bestObject = object
                            end
                        end
                    end
                end
            end
        end
    end

    return bestObject
end

local function queueFurnitureSit(player, furniture)
    if ISWorldObjectContextMenu and ISWorldObjectContextMenu.onRest and player.getPlayerNum then
        ISWorldObjectContextMenu.onRest(furniture, player:getPlayerNum())
        return
    end

    local action = ISPathFindAction:pathToSitOnFurniture(player, furniture, true)
    if not action then
        return
    end
    if ISWorldObjectContextMenu and ISWorldObjectContextMenu.onRestPathFound and ISWorldObjectContextMenu.onRestPathFailed then
        action:setOnComplete(ISWorldObjectContextMenu.onRestPathFound, player, action)
        action:setOnFail(ISWorldObjectContextMenu.onRestPathFailed, player, furniture, action)
    end
    ISTimedActionQueue.add(action)
end

local function standUp(player)
    if not player then
        return
    end
    player:StopAllActionQueue()
    ISTimedActionQueue.add(ISWaitWhileGettingUp:new(player))
    notify(player, "Standing up", true)
end

local function sitDown(player)
    local furniture = getNearbyFurnitureSeat(player)
    if furniture then
        queueFurnitureSit(player, furniture)
        notify(player, "Taking a seat", true)
        return
    end

    player:reportEvent("EventSitOnGround")
    notify(player, "Sitting down", true)
end

local function toggleQuickSit(player)
    if not player or not CSR_FeatureFlags.isQuickSitEnabled() then
        return
    end

    if player:isSitOnGround() or player:isSittingOnFurniture() then
        standUp(player)
        return
    end

    if isBusy(player) then
        notify(player, "Can't sit right now", false)
        return
    end

    sitDown(player)
end

local function onKeyPressed(key)
    if key ~= getBoundKey() or not CSR_FeatureFlags.isQuickSitEnabled() then
        return
    end

    for i = 0, 3 do
        local player = getPlayerByIndex(i)
        if player then
            toggleQuickSit(player)
        end
    end
end

if Events and Events.OnKeyPressed then
    Events.OnKeyPressed.Add(onKeyPressed)
end

return CSR_QuickSit
