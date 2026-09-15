-- Admin-only authoritative removal for the ATF Destroy Tile shortcut.
-- Client and server files must be distributed together. No player demolition
-- settings are changed; this is an explicit, audited administrator operation.
if isClient() then return end
ATFPatches_AdminTileRemoval = ATFPatches_AdminTileRemoval or {}
local M = ATFPatches_AdminTileRemoval
M.sessions = M.sessions or setmetatable({}, {__mode = "k"})

local function integer(value, low, high)
    return type(value) == "number" and value == value
        and value >= low and value <= high and value == math.floor(value)
end
local function text(value, limit)
    return type(value) == "string" and #value <= limit and not value:find("[%c]")
end
local function allowed(player)
    return player and player:getRole() and player:getRole():hasCapability(Capability.UseDebugContextMenu)
end
local function audit(player, args, outcome)
    writeLog("ATFAdminTileRemoval", player:getUsername() .. " request=" .. tostring(args.request)
        .. " at=" .. tostring(args.x) .. "," .. tostring(args.y) .. "," .. tostring(args.z)
        .. " index=" .. tostring(args.index) .. " sprite=" .. tostring(args.sprite)
        .. " " .. outcome)
end

local function remove(player, args)
    if args.protocol ~= 1 then return false, "Client/server admin removal versions differ. Update both files." end
    if not integer(args.x, 0, 1000000) or not integer(args.y, 0, 1000000)
        or not integer(args.z, -128, 127) or not integer(args.index, 0, 32766)
        or not integer(args.count, 1, 32767) or args.index >= args.count
        or not text(args.sprite, 160) or args.sprite == "" or not text(args.objectName, 80) then
        return false, "Invalid tile removal request."
    end
    local dx, dy = player:getX() - (args.x + 0.5), player:getY() - (args.y + 0.5)
    if player:isDead() or dx * dx + dy * dy > 100 or math.abs(player:getZ() - args.z) > 1 then
        return false, "Stand within 10 tiles and one floor of the selected tile."
    end
    local cell = getCell()
    local square = cell and cell:getGridSquare(args.x, args.y, args.z)
    if not square then return false, "The tile is not loaded on the server. No removal performed." end
    if not SafeHouse.isSafehouseAllowInteract(square, player) then
        return false, "Server safehouse permissions deny interaction here. Check membership and admin capabilities."
    end
    local objects = square:getObjects()
    if objects:size() ~= args.count or args.index >= objects:size() then
        return false, "Client/server tile lists differ. Reconnect and reselect; no removal performed."
    end
    local obj = objects:get(args.index)
    local sprite = obj and obj:getSprite()
    if not obj or obj:getSquare() ~= square or not sprite or sprite:getName() ~= args.sprite
        or (obj:getObjectName() or "") ~= args.objectName then
        return false, "The selected server object differs. Reconnect and reselect; no removal performed."
    end
    -- Do not erase inaccessible container contents to 'repair' a fridge.
    for i = 0, obj:getContainerCount() - 1 do
        local container = obj:getContainerByIndex(i)
        if container and not container:getItems():isEmpty() then
            return false, "This tile contains items. Preserve or empty them before removal; nothing removed."
        end
    end
    audit(player, args, "requested")
    -- This menu selects ONE tile. Do not let the native default expand removal
    -- to adjacent furniture pieces whose access/contents were not validated.
    -- Native server path handles removal, persistence flags, container events
    -- and replication to relevant clients (including requester).
    square:transmitRemoveItemFromSquare(obj, false)
    if objects:contains(obj) then
        return false, "Server removal did not complete. Inspect server logs before retrying."
    end
    audit(player, args, "removed")
    return true, "Server confirmed tile removal."
end

function M.onClientCommand(module, command, player, args)
    if module ~= "ATFAdminTile" or command ~= "remove" or not allowed(player) then return end
    if type(args) ~= "table" or not integer(args.request, 1, 9007199254740991) then return end
    local state = M.sessions[player]
    if not state then state = {lastId = 0, nextAt = 0}; M.sessions[player] = state end
    if args.request <= state.lastId then
        local result = args.request == state.lastId and state.result
            or {request = args.request, ok = false, text = "Old removal request ignored. Check the tile before retrying."}
        if result then sendServerCommand(player, "ATFAdminTile", "removeResult", result) end
        return
    end
    state.lastId = args.request
    -- Record an uncertain result before entering engine code, so an exception
    -- after partial mutation can never make the same request run twice.
    state.result = {request = args.request, ok = false, text = "Server removal failed. Inspect server logs before retrying."}
    local clock = getTimestampMs()
    if clock < state.nextAt then
        state.result.text = "Please wait briefly before another admin removal."
    else
        state.nextAt = clock + 250
        local completed, ok, message = pcall(remove, player, args)
        if completed then
            state.result.ok, state.result.text = ok, message
        else
            print("[ATF Admin Tile] Removal request " .. tostring(args.request) .. " failed: " .. tostring(ok))
        end
    end
    sendServerCommand(player, "ATFAdminTile", "removeResult", state.result)
end

if not M.__eventRegistered then
    M.__eventRegistered = true
    Events.OnClientCommand.Add(function(...) return ATFPatches_AdminTileRemoval.onClientCommand(...) end)
end
