--[[
Top-level "Destroy tile" shortcut for admins.

Vanilla buries tile destruction under Debug > Brush Tool > Destroy tile >
<sprite>. This adds the same sprite submenu directly at the top of the
right-click menu, gated exactly like the vanilla Debug menu
(Capability.UseDebugContextMenu in MP, isDebugEnabled in SP/debug), and sends
multiplayer removal requests to the server for validation and a result.
The dedicated admin path works independently of the ordinary-player sledgehammer
setting. Safehouse access, role capability and the selected tile are checked on
the server. Ordinary-player demolition and interaction permissions are unchanged.

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
        return playerObj and playerObj:getRole() and playerObj:getRole():hasCapability(Capability.UseDebugContextMenu)
    end
    return isDebugEnabled()
end

local function notice(player, text)
    if player then player:setHaloNote(text, 220, 230, 255, 300) end
end

function Shortcut.destroyTile(obj, player)
    if not player or not canUse(player) then return end
    local square = obj and obj:getSquare()
    local sprite = obj and obj:getSprite()
    if not square or not sprite or obj:getObjectIndex() < 0 then
        notice(player, "Tile changed. Select it again.")
        return
    end
    if not isClient() then
        square:transmitRemoveItemFromSquare(obj)
        return
    end
    if Shortcut.pending then
        notice(player, "Waiting for the previous server removal result.")
        return
    end
    -- Monotonic per client: the server rejects older IDs rather than replaying
    -- an operation against a replacement object that inherited the same index.
    Shortcut.requestId = math.max(getTimestampMs(), (Shortcut.requestId or 0) + 1)
    local args = {
        protocol = 1, request = Shortcut.requestId,
        x = square:getX(), y = square:getY(), z = square:getZ(),
        index = obj:getObjectIndex(), count = square:getObjects():size(),
        sprite = sprite:getName(), objectName = obj:getObjectName() or "",
    }
    Shortcut.pending = {request = args.request, player = player, deadline = getTimestampMs() + 8000}
    -- The native server removal packet changes the local world. Never erase a
    -- tile optimistically, and never resend a timed-out destructive request.
    sendClientCommand(player, "ATFAdminTile", "remove", args)
    notice(player, "Requesting tile removal from server...")
end

function Shortcut.onServerCommand(module, command, args)
    if module ~= "ATFAdminTile" or command ~= "removeResult" or type(args) ~= "table" then return end
    local pending = Shortcut.pending
    if not pending or args.request ~= pending.request then return end
    Shortcut.pending = nil
    notice(pending.player, tostring(args.text or "Server returned no removal explanation."))
end

function Shortcut.onTick()
    local pending = Shortcut.pending
    if pending and getTimestampMs() >= pending.deadline then
        Shortcut.pending = nil
        notice(pending.player, "Server did not confirm removal. Check the tile before retrying; no automatic retry.")
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
        local opt = subMenu:addOption(spriteName, obj, Shortcut.destroyTile, playerObj)
        local tooltip = ISToolTip:new()
        tooltip:initialise()
        tooltip:setName("")
        tooltip:setTexture(spriteName)
        tooltip.description = "Admin server removal of this tile only. Must be nearby with safehouse access; containers must be empty. The server reports success or denial."
        opt.toolTip = tooltip
    end
end

if not Shortcut.__eventRegistered then
    Shortcut.__eventRegistered = true
    Events.OnPreFillWorldObjectContextMenu.Add(function(...)
        return ATFPatches_DestroyTileShortcut.onPreFillWorldObjectContextMenu(...)
    end)
end

if not Shortcut.__resultEventsRegistered then
    Shortcut.__resultEventsRegistered = true
    Events.OnServerCommand.Add(function(...) return ATFPatches_DestroyTileShortcut.onServerCommand(...) end)
    Events.OnTick.Add(function() return ATFPatches_DestroyTileShortcut.onTick() end)
end
