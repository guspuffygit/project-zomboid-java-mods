require "CSR_FeatureFlags"

local MIN_FATIGUE = 0.3

--- Check if an object looks like a dumpster by sprite name.
local function isDumpsterObject(obj)
    if not obj or type(obj.getSprite) ~= "function" then return false end
    local sprite = obj:getSprite()
    if not sprite or type(sprite.getName) ~= "function" then return false end
    local name = sprite:getName()
    if not name then return false end
    if string.find(name, "^trash_01_2[4-9]") then return true end
    if string.find(name, "^street_decoration_01_1[6-9]") then return true end
    return false
end

--- Search all objects on a square for a dumpster.
local function findDumpsterOnSquareObj(square)
    if not square then return nil end
    local objects = square:getObjects()
    if not objects then return nil end
    for i = 0, objects:size() - 1 do
        local obj = objects:get(i)
        if isDumpsterObject(obj) then return obj end
    end
    return nil
end

--- Find a dumpster from worldObjects, falling back to scanning the square.
local function findDumpsterFromWorldObjects(worldObjects)
    if not worldObjects then return nil end
    for i = 1, #worldObjects do
        local wo = worldObjects[i]
        if isDumpsterObject(wo) then return wo end
        local square = wo and type(wo.getSquare) == "function" and wo:getSquare() or nil
        local obj = findDumpsterOnSquareObj(square)
        if obj then return obj end
    end
    return nil
end

local function doSleep(player, playerNum, square, sayText)
    player:Say(sayText)
    player:setVariable("ExerciseStarted", false)
    player:setVariable("ExerciseEnded", true)
    ISTimedActionQueue.clear(player)
    -- Walk to the target square, then invoke vanilla sleep with bed=nil (floor sleep).
    -- ISPathFindAction:pathToNearest expects a table of {x,y,z} location tables.
    local locations = { { square:getX(), square:getY(), square:getZ() } }
    if AdjacentFreeTileFinder and AdjacentFreeTileFinder.isTileOrAdjacent and
        AdjacentFreeTileFinder.isTileOrAdjacent(player:getCurrentSquare(), square) then
        -- Already adjacent — invoke sleep directly without path-find overhead.
        ISWorldObjectContextMenu.onSleepWalkToComplete(playerNum, nil)
        return
    end
    local action = ISPathFindAction:pathToNearest(player, locations)
    action:setOnComplete(ISWorldObjectContextMenu.onSleepWalkToComplete, playerNum, nil)
    ISTimedActionQueue.add(action)
end

local function onWorldContext(playerNum, context, worldObjects, test)
    if test then return end
    if not CSR_FeatureFlags.isSleepAnywhereEnabled() then return end

    local player = getSpecificPlayer(playerNum)
    if not player or player:isDead() then return end

    local fatigue = 0
    if CharacterStat and player:getStats() then
        fatigue = player:getStats():get(CharacterStat.FATIGUE) or 0
    end
    if not isClient() and fatigue < MIN_FATIGUE then return end

    -- Find the ground square from clicked world objects
    local square = nil
    for i = 1, #worldObjects do
        local obj = worldObjects[i]
        if obj and obj.getSquare then
            square = obj:getSquare()
            if square then break end
        end
    end
    if not square then return end

    -- Don't offer sleep if player is already asleep or in a vehicle
    if player:isAsleep() then return end
    if player:getVehicle() then return end

    local fatiguePercent = math.floor(fatigue * 100)

    -- Check for dumpster
    local dumpster = findDumpsterFromWorldObjects(worldObjects)
    if dumpster then
        local dumpText = string.format("Sleep in Dumpster (Fatigue: %d%%)", fatiguePercent)
        local opt = context:addOption(dumpText, worldObjects, function()
            doSleep(player, playerNum, square, "This dumpster looks... cozy?")
        end)
        local tip = ISWorldObjectContextMenu.addToolTip()
        tip.description = "Sleep inside the dumpster. <LINE> <LINE> <RGB:1,0.4,0.4> Very poor sleep quality. <RGB:1,1,1> <LINE> <RGB:1,0.8,0.2> Unhappiness <RGB:1,1,1> increases while sleeping."
        opt.toolTip = tip
    end

    -- Always offer floor sleep
    local text = string.format("Sleep Here (Fatigue: %d%%)", fatiguePercent)
    local opt = context:addOption(text, worldObjects, function()
        doSleep(player, playerNum, square, "Im feeling droopy")
    end)
    local tip = ISWorldObjectContextMenu.addToolTip()
    tip.description = "Sleep on the ground. <LINE> <LINE> <RGB:1,0.8,0.2> Poor sleep quality <RGB:1,1,1> — no bed comfort bonus."
    opt.toolTip = tip
end

Events.OnFillWorldObjectContextMenu.Add(onWorldContext)
