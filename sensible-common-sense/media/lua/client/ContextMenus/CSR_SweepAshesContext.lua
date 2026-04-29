require "CSR_FeatureFlags"
require "TimedActions/CSR_ClearAshesAction"

-- Sprite prefix for vanilla burnt-floor "ashes" objects. Pattern matches
-- floors_burnt_01_<digits>. Confirmed in vanilla:
--   media/lua/server/WorldGen/features/ground/burnt.lua (ground decoration)
--   floors_burnt_01_1 / _2 are the removable ash piles handled by ISClearAshes.
local ASH_SPRITE_PATTERN = "^floors_burnt_01_%d+$"

local function predicateClearAshesItem(item)
    return not item:isBroken() and item:hasTag(ItemTag.CLEAR_ASHES)
end

local function findAshesObj(square)
    if not square then return nil end
    local objs = square:getObjects()
    if not objs then return nil end
    for i = 0, objs:size() - 1 do
        local obj = objs:get(i)
        if obj and instanceof(obj, "IsoObject") then
            local sprite = obj:getSprite()
            local name = nil
            if sprite then name = sprite:getName() end
            if not name and obj.getSpriteName then name = obj:getSpriteName() end
            if name and string.match(name, ASH_SPRITE_PATTERN) then
                return obj
            end
        end
    end
    return nil
end

local function findAshesFromWorldObjects(worldObjects)
    if not worldObjects then return nil end
    for _, wo in ipairs(worldObjects) do
        local sq = nil
        if instanceof(wo, "IsoObject") then sq = wo:getSquare() end
        if sq then
            local ashes = findAshesObj(sq)
            if ashes then return ashes end
        end
    end
    return nil
end

local function onSweepAshes(worldobjects, playerIndex, ashes)
    local playerObj = getSpecificPlayer(playerIndex)
    if not playerObj or playerObj:isDead() then return end
    local sq = ashes and ashes:getSquare()
    if not sq then return end
    if luautils.walkAdj(playerObj, sq) then
        ISWorldObjectContextMenu.equip(playerObj, playerObj:getPrimaryHandItem(), predicateClearAshesItem, true)
        ISTimedActionQueue.add(CSR_ClearAshesAction:new(playerObj, ashes))
    end
end

local function onContextMenu(playerIndex, context, worldObjects, test)
    if test then return end
    if not CSR_FeatureFlags.isSweepAshesEnabled() then return end
    if not worldObjects or #worldObjects == 0 then return end

    local playerObj = getSpecificPlayer(playerIndex)
    if not playerObj or playerObj:isDead() then return end

    local ashes = findAshesFromWorldObjects(worldObjects)
    if not ashes then return end

    local inv = playerObj:getInventory()
    local hasTool = inv and inv:containsEvalRecurse(predicateClearAshesItem) or false

    local option = context:addOption(getText("ContextMenu_CSR_SweepAshes"), worldObjects, onSweepAshes, playerIndex, ashes)
    if not hasTool then
        option.notAvailable = true
        local tooltip = ISWorldObjectContextMenu.addToolTip()
        tooltip.description = getText("Tooltip_CSR_SweepAshes_NeedBroom")
        option.toolTip = tooltip
    else
        local tooltip = ISWorldObjectContextMenu.addToolTip()
        tooltip.description = getText("Tooltip_CSR_SweepAshes_Ready")
        option.toolTip = tooltip
    end
end

Events.OnFillWorldObjectContextMenu.Add(onContextMenu)
