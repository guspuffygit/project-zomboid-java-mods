require "CSR_FeatureFlags"
require "CSR_TrashSpriteWhitelist"

local MAX_BAG_SWEEPS = 20

local function findBroom(playerObj)
    local inv = playerObj:getInventory()
    if not inv then return nil end
    local items = inv:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item and not item:isBroken() then
            local fullType = item:getFullType()
            if fullType == "Base.Broom" or fullType == "Base.BroomCrafted" then
                return item
            end
        end
    end
    return nil
end

local function findGarbageBag(playerObj)
    local inv = playerObj:getInventory()
    if not inv then return nil end
    local items = inv:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item then
            local fullType = item:getFullType()
            if fullType == "Base.Garbagebag" then
                local count = item:getModData()["CSR_SweepCount"] or 0
                if count < MAX_BAG_SWEEPS then
                    return item
                end
            end
        end
    end
    return nil
end

local function findTrashSquare(worldObjects)
    for _, obj in ipairs(worldObjects) do
        local square = nil
        if instanceof(obj, "IsoObject") then
            square = obj:getSquare()
        end
        if square then
            local trashList = CSR_TrashSpriteWhitelist.findTrashOnSquare(square)
            if trashList then
                return square
            end
        end
    end
    return nil
end

local function onSweepTrash(playerObj, square, broom, garbageBag)
    if luautils.walkAdj(playerObj, square, true) then
        ISTimedActionQueue.add(CSR_SweepTrashAction:new(playerObj, square, broom, garbageBag))
    end
end

local function onContextMenu(playerIndex, context, worldObjects, test)
    if test then return end
    if not CSR_FeatureFlags.isSweepTrashEnabled() then return end

    if not worldObjects or #worldObjects == 0 then return end

    local playerObj = getSpecificPlayer(playerIndex)
    if not playerObj or playerObj:isDead() then return end

    local square = findTrashSquare(worldObjects)
    if not square then return end

    local broom = findBroom(playerObj)
    local garbageBag = findGarbageBag(playerObj)

    local option = context:addOption("Sweep Up Trash", playerObj, onSweepTrash, square, broom, garbageBag)

    if not broom and not garbageBag then
        option.notAvailable = true
        local tooltip = ISWorldObjectContextMenu.addToolTip()
        tooltip.description = "Requires a broom and a garbage bag"
        option.toolTip = tooltip
    elseif not broom then
        option.notAvailable = true
        local tooltip = ISWorldObjectContextMenu.addToolTip()
        tooltip.description = "Requires a broom"
        option.toolTip = tooltip
    elseif not garbageBag then
        option.notAvailable = true
        local tooltip = ISWorldObjectContextMenu.addToolTip()
        tooltip.description = "Requires a garbage bag (not full)"
        option.toolTip = tooltip
    else
        local count = garbageBag:getModData()["CSR_SweepCount"] or 0
        local remaining = MAX_BAG_SWEEPS - count
        local tooltip = ISWorldObjectContextMenu.addToolTip()
        tooltip.description = "Bag capacity: " .. remaining .. "/" .. MAX_BAG_SWEEPS .. " sweeps remaining"
        option.toolTip = tooltip
        if broom.getIcon then
            option.iconTexture = broom:getIcon()
        end
    end
end

Events.OnFillWorldObjectContextMenu.Add(onContextMenu)
