--[[
Top-level "Destroy tile" shortcut for admins.

Vanilla buries tile destruction under Debug > Brush Tool > Destroy tile >
<sprite>. This adds the same sprite submenu directly at the top of the
right-click menu, gated exactly like the vanilla Debug menu
(Capability.UseDebugContextMenu in MP, isDebugEnabled in SP/debug), and
destroys through the same path (sledgeDestroy), so it grants no ability an
admin doesn't already have - it just removes two levels of nesting.

Registered on OnPreFillWorldObjectContextMenu (not OnFill) because OnFill is
skipped inside safehouses the player can't interact with, and an admin tool
should work everywhere; Pre also places the option at the top of the menu.

Hot-reload safe via the trampoline pattern: the event handler is registered
once and dispatches through a global table whose fields each reload replaces.
]]

ATFPatches_DestroyTileShortcut = ATFPatches_DestroyTileShortcut or {}
local Shortcut = ATFPatches_DestroyTileShortcut

local function canUse(playerObj)
    if isClient() then
        return playerObj:getRole():hasCapability(Capability.UseDebugContextMenu)
    end
    return isDebugEnabled()
end

local function destroyTile(obj)
    if isClient() then
        sledgeDestroy(obj)
    else
        obj:getSquare():transmitRemoveItemFromSquare(obj)
    end
end

function Shortcut.onPreFillWorldObjectContextMenu(player, context, worldobjects, test)
    local playerObj = getSpecificPlayer(player)
    if not playerObj or not canUse(playerObj) then
        return
    end

    local square = nil
    for _, obj in ipairs(worldobjects) do
        square = obj:getSquare()
        break
    end
    if not square then
        return
    end

    -- Same expansion the vanilla Debug menu does: the picked worldobjects
    -- list misses floor/wall objects on the square.
    local objects = copyTable(worldobjects)
    for i = 1, square:getObjects():size() do
        table.insert(objects, square:getObjects():get(i - 1))
    end

    local entries = {}
    local seen = {}
    for _, obj in ipairs(objects) do
        if not seen[obj] and obj:getSprite() ~= nil and obj:getSprite():getName() ~= nil then
            seen[obj] = true
            table.insert(entries, obj)
        end
    end
    if #entries == 0 then
        return
    end

    if test then
        return ISWorldObjectContextMenu.setTest()
    end

    local option = context:addDebugOption("Destroy tile", worldobjects)
    local subMenu = context:getNew(context)
    context:addSubMenu(option, subMenu)

    for _, obj in ipairs(entries) do
        local spriteName = obj:getSprite():getName()
        local opt = subMenu:addOption(spriteName, obj, destroyTile)
        local tooltip = ISToolTip:new()
        tooltip:initialise()
        tooltip:setName("")
        tooltip:setTexture(spriteName)
        opt.toolTip = tooltip
    end
end

if not Shortcut.__eventRegistered then
    Shortcut.__eventRegistered = true
    Events.OnPreFillWorldObjectContextMenu.Add(function(...)
        return ATFPatches_DestroyTileShortcut.onPreFillWorldObjectContextMenu(...)
    end)
end
