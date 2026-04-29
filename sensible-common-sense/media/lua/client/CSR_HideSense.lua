require "CSR_FeatureFlags"

--[[
    CSR_HideSense.lua
    Hide in large furniture — closets, dumpsters, fridges, beds.
    Player becomes invisible/ghost to zombies with a fade-to-black screen.
    Based on BB_Hide (B41 Workshop 2991351207), ported to B42.
    Invisibility uses setInvisible + setGhostMode (same as JeevesQoL).
    Black screen uses UIManager.FadeOut (same as vanilla sleep).
]]

local hidingPlayer = nil
local hidingPlayerNum = nil
local hidingCategory = nil
local hidingObject = nil
local hidingX = 0
local hidingY = 0
local hidingZ = 0
local hidingGrace = 0
local GRACE_TICKS = 60
local CONTAINER_CHECK_INTERVAL = 120
local containerCheckTimer = 0

--- Check if an IsoObject has the bed sprite flag.
local function isBedObject(obj)
    if not obj then return false end
    local sprite = obj:getSprite()
    if not sprite then return false end
    local props = sprite:getProperties()
    if not props then return false end
    if type(props.Is) == "function" then
        if props:Is(IsoFlagType.bed) then return true end
    end
    if type(props.get) == "function" then
        if props:get("BedType") then return true end
    end
    return false
end

--- Categorize an IsoObject by sprite flags, container type, or sprite name.
--- Returns "bed", "closet", "fridge", "dumpster", "couch", "table", "crate", "barrel", or nil.
local function categorizeObject(obj)
    if not obj or type(obj.getSprite) ~= "function" then return nil end

    -- Bed detection via sprite property flag
    if isBedObject(obj) then return "bed" end

    -- Get sprite name for pattern checks
    local sprite = obj:getSprite()
    local name = nil
    if sprite and type(sprite.getName) == "function" then
        name = sprite:getName()
    end

    -- Dumpster sprites
    if name then
        if string.find(name, "^trash_01_2[4-9]") then return "dumpster" end
        if string.find(name, "^street_decoration_01_1[6-9]") then return "dumpster" end
    end

    -- Barrel — uncapped via CSR Useful Barrels feature
    if type(obj.getModData) == "function" then
        local md = obj:getModData()
        if md and md.CSR_UB_Uncapped then return "barrel" end
    end

    -- Container-based detection
    if type(obj.getContainerCount) == "function" then
        local count = obj:getContainerCount() or 0
        local maxCap = 0
        local isFridge = false
        local containerType = nil
        for i = 0, count - 1 do
            local c = obj:getContainerByIndex(i)
            if c then
                local t = c:getType()
                if t == "fridge" or t == "freezer" then
                    isFridge = true
                end
                if t then containerType = t end
                local cap = c:getCapacity() or 0
                if cap > maxCap then maxCap = cap end
            end
        end
        if isFridge then return "fridge" end
        -- Closets/wardrobes: specific container types or large capacity in wardrobe-like sprites
        if containerType == "wardrobe" or containerType == "closet" then return "closet" end
        if containerType == "crate" and maxCap >= 40 then return "crate" end
    end

    -- Sprite-based fallbacks for closet-like furniture (wardrobes, clothing racks)
    if name then
        if string.find(name, "^furniture_storage_01_") then return "closet" end
        if string.find(name, "^furniture_clothing_01_") then return "closet" end
        if string.find(name, "refrigeration") then return "fridge" end
        -- Couches/sofas — seating sprites but not chairs
        if string.find(name, "^furniture_seating_01_") then
            -- Sofas are typically multi-tile; single chairs are smaller sprites
            -- Sofas use indices 0-23 in the vanilla sheet, chairs start higher
            local idx = tonumber(string.match(name, "furniture_seating_01_(%d+)"))
            if idx and idx < 24 then return "couch" end
        end
        -- Large tables — only multi-tile tables
        if string.find(name, "^furniture_table_01_") then
            -- Large dining/office tables (sprites 0-15 are large tables in vanilla)
            local idx = tonumber(string.match(name, "furniture_table_01_(%d+)"))
            if idx and idx < 16 then return "table" end
        end
        -- Industrial crates
        if string.find(name, "^industry_crate_") then return "crate" end
    end

    return nil
end

--- Search all objects on a square for a hideable one.
local function findHideableOnSquare(square)
    if not square then return nil, nil end
    local objects = square:getObjects()
    if not objects then return nil, nil end
    for i = 0, objects:size() - 1 do
        local obj = objects:get(i)
        if obj and not instanceof(obj, "IsoWorldInventoryObject") then
            local category = categorizeObject(obj)
            if category then return obj, category end
        end
    end
    return nil, nil
end

--- Find a hideable object from worldObjects, falling back to scanning the square.
local function findHideableFromWorldObjects(worldObjects)
    if not worldObjects then return nil, nil end
    for i = 1, #worldObjects do
        local wo = worldObjects[i]
        local category = categorizeObject(wo)
        if category then return wo, category end
        local square = wo and type(wo.getSquare) == "function" and wo:getSquare() or nil
        local obj, cat = findHideableOnSquare(square)
        if obj then return obj, cat end
    end
    return nil, nil
end

-- Invisibility: setInvisible + setGhostMode (proven by JeevesQoL_SafeLogin)
local function setPlayerHidden(player, playerNum, hidden)
    pcall(function()
        player:setInvisible(hidden)
        player:setGhostMode(hidden)
    end)
    -- Fade to black / fade in using vanilla UIManager (same as sleep screen)
    if hidden then
        pcall(function()
            UIManager.setFadeBeforeUI(playerNum, true)
            UIManager.FadeOut(playerNum, 1)
        end)
    else
        pcall(function()
            UIManager.FadeIn(playerNum, 1)
            UIManager.setFadeBeforeUI(playerNum, false)
        end)
    end
end

local function startHiding(player, category, obj)
    local playerNum = player:getPlayerNum()
    hidingPlayer = player
    hidingPlayerNum = playerNum
    hidingCategory = category
    hidingObject = obj
    hidingX = player:getX()
    hidingY = player:getY()
    hidingZ = player:getZ()
    hidingGrace = GRACE_TICKS
    containerCheckTimer = 0
    setPlayerHidden(player, playerNum, true)
    player:Say("...")

    -- Persist hiding state to moddata for reconnect survival
    local modData = player:getModData()
    if modData then
        modData.CSRHideSenseActive = true
        modData.CSRHideSenseCategory = category
        modData.CSRHideSenseX = hidingX
        modData.CSRHideSenseY = hidingY
        modData.CSRHideSenseZ = hidingZ
    end
end

local function stopHiding()
    if hidingPlayer then
        setPlayerHidden(hidingPlayer, hidingPlayerNum, false)
        -- Clear persistence
        local modData = hidingPlayer:getModData()
        if modData then
            modData.CSRHideSenseActive = nil
            modData.CSRHideSenseCategory = nil
            modData.CSRHideSenseX = nil
            modData.CSRHideSenseY = nil
            modData.CSRHideSenseZ = nil
        end
    end
    hidingPlayer = nil
    hidingPlayerNum = nil
    hidingCategory = nil
    hidingObject = nil
end

local function isHiding()
    return hidingPlayer ~= nil
end

-- Boredom/sickness while hiding + container fullness check
local function onHidingTick()
    if not isHiding() then return end
    local player = hidingPlayer
    if not player or player:isDead() then
        stopHiding()
        return
    end
    -- Grace period after starting to hide
    if hidingGrace > 0 then
        hidingGrace = hidingGrace - 1
    else
        -- Stop hiding if player walks away from hiding spot or enters vehicle
        local dx = math.abs(player:getX() - hidingX)
        local dy = math.abs(player:getY() - hidingY)
        if dx > 0.5 or dy > 0.5 or player:getZ() ~= hidingZ or player:getVehicle() then
            stopHiding()
            return
        end
    end

    -- Periodic container fullness check (someone could fill the container while you're hiding)
    containerCheckTimer = containerCheckTimer + 1
    if containerCheckTimer >= CONTAINER_CHECK_INTERVAL then
        containerCheckTimer = 0
        if hidingCategory ~= "bed" and hidingObject and type(hidingObject.getContainerCount) == "function" then
            local containerCount = hidingObject:getContainerCount() or 0
            if containerCount > 0 then
                local container = hidingObject:getContainerByIndex(0)
                if container then
                    local cap = container:getCapacity() or 0
                    local weight = container:getCapacityWeight() or 0
                    if cap > 0 and weight >= (cap / 1.3) then
                        player:setHaloNote("Too cramped! Forced out.", 1, 0.5, 0.2, 200)
                        stopHiding()
                        return
                    end
                end
            end
        end
    end

    -- Apply boredom
    local stats = player:getStats()
    if stats then
        local boredom = stats:get(CharacterStat.BOREDOM) or 0
        stats:set(CharacterStat.BOREDOM, math.min(boredom + 0.0003, 1.0))

        -- Sickness for dumpsters, fridges, crates, and barrels
        if hidingCategory == "dumpster" or hidingCategory == "fridge"
            or hidingCategory == "crate" or hidingCategory == "barrel" then
            local nausea = stats:get(CharacterStat.SICKNESS) or 0
            stats:set(CharacterStat.SICKNESS, math.min(nausea + 0.0001, 0.5))
        end
    end
end

local TOOLTIPS = {
    bed       = "Hide under the bed. <LINE> <LINE> Become invisible to zombies. <LINE> <RGB:1,0.8,0.2> Boredom <RGB:1,1,1> increases while hiding. <LINE> Press ESC or move to stop.",
    closet    = "Hide in the closet. <LINE> <LINE> Become invisible to zombies. <LINE> <RGB:1,0.8,0.2> Boredom <RGB:1,1,1> increases while hiding. <LINE> Press ESC or move to stop.",
    dumpster  = "Hide in the dumpster. <LINE> <LINE> Become invisible to zombies. <LINE> <RGB:1,0.8,0.2> Boredom <RGB:1,1,1> increases while hiding. <LINE> <RGB:1,0.4,0.4> Nausea <RGB:1,1,1> increases slowly (it stinks). <LINE> Press ESC or move to stop.",
    fridge    = "Hide in the fridge. <LINE> <LINE> Become invisible to zombies. <LINE> <RGB:1,0.8,0.2> Boredom <RGB:1,1,1> increases while hiding. <LINE> <RGB:1,0.4,0.4> Nausea <RGB:1,1,1> increases slowly (tight space). <LINE> Press ESC or move to stop.",
    couch     = "Hide behind the couch. <LINE> <LINE> Become invisible to zombies. <LINE> <RGB:1,0.8,0.2> Boredom <RGB:1,1,1> increases while hiding. <LINE> Press ESC or move to stop.",
    table     = "Hide under the table. <LINE> <LINE> Become invisible to zombies. <LINE> <RGB:1,0.8,0.2> Boredom <RGB:1,1,1> increases while hiding. <LINE> Press ESC or move to stop.",
    crate     = "Hide inside the crate. <LINE> <LINE> Become invisible to zombies. <LINE> <RGB:1,0.8,0.2> Boredom <RGB:1,1,1> increases while hiding. <LINE> <RGB:1,0.4,0.4> Nausea <RGB:1,1,1> increases slowly (tight space). <LINE> Press ESC or move to stop.",
    barrel    = "Hide inside the barrel. <LINE> <LINE> Become invisible to zombies. <LINE> <RGB:1,0.8,0.2> Boredom <RGB:1,1,1> increases while hiding. <LINE> <RGB:1,0.4,0.4> Nausea <RGB:1,1,1> increases slowly (tight space). <LINE> Press ESC or move to stop.",
}

local LABELS = {
    bed      = "Hide Under Bed",
    closet   = "Hide in Closet",
    dumpster = "Hide in Dumpster",
    fridge   = "Hide in Fridge",
    couch    = "Hide Behind Couch",
    table    = "Hide Under Table",
    crate    = "Hide in Crate",
    barrel   = "Hide in Barrel",
}

-- Context menu
local function onWorldContext(playerNum, context, worldObjects, test)
    if test then return end
    if not CSR_FeatureFlags.isHideInFurnitureEnabled() then return end

    local player = getSpecificPlayer(playerNum)
    if not player or player:isDead() then return end
    if player:getVehicle() then return end

    if isHiding() then
        context:addOption("Stop Hiding", worldObjects, function()
            stopHiding()
        end)
        return
    end

    local obj, category = findHideableFromWorldObjects(worldObjects)
    if not obj then return end

    -- Check container capacity — can't hide if container is too full (skip for beds)
    if category ~= "bed" and type(obj.getContainerCount) == "function" then
        local containerCount = obj:getContainerCount() or 0
        if containerCount > 0 then
            local container = obj:getContainerByIndex(0)
            if container then
                local cap = container:getCapacity() or 0
                local weight = container:getCapacityWeight() or 0
                if cap > 0 and weight >= (cap / 1.7) then
                    local opt = context:addOption("Hide (Too Full)", worldObjects, nil)
                    opt.notAvailable = true
                    local tooltip = ISWorldObjectContextMenu.addToolTip()
                    tooltip.description = "The container is too full to hide inside."
                    opt.toolTip = tooltip
                    return
                end
            end
        end
    end

    local label = LABELS[category] or "Hide"
    local opt = context:addOption(label, worldObjects, function()
        startHiding(player, category, obj)
    end)
    local desc = TOOLTIPS[category]
    if desc then
        local tooltip = ISWorldObjectContextMenu.addToolTip()
        tooltip.description = desc
        opt.toolTip = tooltip
    end
end

-- Cancel hiding on ESC or movement keys
local function onKeyPressed(key)
    if not isHiding() then return end
    if key == Keyboard.KEY_ESCAPE then
        stopHiding()
        return
    end
    local binds = getCore()
    if binds then
        if key == binds:getKey("Forward") or key == binds:getKey("Backward")
        or key == binds:getKey("Left")    or key == binds:getKey("Right") then
            stopHiding()
        end
    end
end

-- Restore hiding state after reconnect/load
local function onGameStart()
    local player = getPlayer()
    if not player then return end
    local modData = player:getModData()
    if not modData or not modData.CSRHideSenseActive then return end

    local category = modData.CSRHideSenseCategory
    local x = modData.CSRHideSenseX
    local y = modData.CSRHideSenseY
    local z = modData.CSRHideSenseZ
    if not category or not x or not y or not z then
        modData.CSRHideSenseActive = nil
        return
    end

    -- Verify player is still near the hiding spot
    local dx = math.abs(player:getX() - x)
    local dy = math.abs(player:getY() - y)
    if dx > 1 or dy > 1 or player:getZ() ~= z then
        modData.CSRHideSenseActive = nil
        return
    end

    -- Find the hideable object on the square
    local sq = player:getCurrentSquare()
    local obj, cat = findHideableOnSquare(sq)
    if obj and cat then
        startHiding(player, cat, obj)
    else
        modData.CSRHideSenseActive = nil
    end
end

if not _G.__CSR_HideSense_evRegistered then
    _G.__CSR_HideSense_evRegistered = true
    Events.OnFillWorldObjectContextMenu.Add(onWorldContext)
    Events.OnPlayerUpdate.Add(onHidingTick)
    Events.OnKeyPressed.Add(onKeyPressed)
    Events.OnGameStart.Add(onGameStart)
end
