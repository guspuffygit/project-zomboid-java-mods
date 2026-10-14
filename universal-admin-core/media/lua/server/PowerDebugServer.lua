if not isServer() then
    return
end
require("AdminCore/OperationsPermissions")
AdminPowerDebugServer = AdminPowerDebugServer or {}
local S, O = AdminPowerDebugServer, AdminOperations
if S.installed then
    return
end
S.installed = true
local limits = {}
local ids = {
    objects = "debug.inspectObjects",
    vehicle = "debug.inspectVehicle",
    skin = "debug.vehicleSkin",
}
local function integer(value, low, high)
    return type(value) == "number" and value == math.floor(value) and value >= low and value <= high
end
local function clean(value)
    return tostring(value or "unknown"):gsub("[%c]", " "):sub(1, 180)
end
local function reply(player, args, text)
    sendServerCommand(
        player,
        "UniversalAdminDebug",
        "result",
        { token = args.token, text = text:sub(1, 6000) }
    )
end

function S.onCommand(module, command, player, args)
    if
        module ~= "UniversalAdminDebug"
        or not ids[command]
        or not player
        or type(args) ~= "table"
    then
        return
    end
    if not integer(args.token, 1, 2147483647) then
        return
    end
    local capability = command == "objects" and "UseDebugContextMenu" or "ManipulateVehicle"
    if
        not O.authorized(player, "ADMIN_DEBUG_TOOLS")
        or not O.capable(player, capability)
        or not O.toolAllowed(player, ids[command])
    then
        return reply(player, args, "This debug tool is not allowed for your current role.")
    end
    if player:isDead() then
        return
    end
    local name, now = player:getUsername(), getTimestampMs()
    if limits[name] and now - limits[name] < 500 then
        return reply(player, args, "Please wait briefly before requesting this tool again.")
    end
    limits[name] = now
    if command == "objects" then
        if
            not integer(args.x, -1000000, 1000000)
            or not integer(args.y, -1000000, 1000000)
            or not integer(args.z, -32, 31)
        then
            return
        end
        if
            math.abs(player:getX() - args.x) > 8
            or math.abs(player:getY() - args.y) > 8
            or math.floor(player:getZ()) ~= args.z
        then
            return reply(
                player,
                args,
                "Inspect a loaded tile within 8 tiles on your current floor."
            )
        end
        local square = getCell():getGridSquare(args.x, args.y, args.z)
        if not square then
            return reply(player, args, "That tile is not loaded by the server.")
        end
        local objects, lines =
            square:getObjects(), { string.format("Tile: %d, %d, %d", args.x, args.y, args.z) }
        lines[#lines + 1] = "Read-only inspection. Container contents and mod data are not exposed."
        for i = 0, math.min(objects:size(), 20) - 1 do
            local object = objects:get(i)
            local sprite = object:getSprite()
            local container = object:getContainer()
            lines[#lines + 1] = string.format(
                "[%d] %s | sprite: %s",
                i,
                clean(object:getObjectName()),
                clean(sprite and sprite:getName())
            )
            if container then
                lines[#lines + 1] = "Container type: "
                    .. clean(container:getType())
                    .. " | item count: "
                    .. container:getItems():size()
            end
        end
        if objects:size() > 20 then
            lines[#lines + 1] = "First 20 objects shown; "
                .. objects:size()
                .. " total on this tile."
        end
        return reply(player, args, table.concat(lines, "\n"))
    end
    if not integer(args.vehicle, -32768, 32767) then
        return
    end
    local vehicle = getVehicleById(args.vehicle)
    if
        not vehicle
        or math.abs(vehicle:getX() - player:getX()) > 8
        or math.abs(vehicle:getY() - player:getY()) > 8
        or math.floor(vehicle:getZ()) ~= math.floor(player:getZ())
    then
        return reply(player, args, "The vehicle is no longer nearby on your current floor.")
    end
    local script = vehicle:getScript()
    if command == "vehicle" then
        return reply(
            player,
            args,
            "Vehicle: "
                .. vehicle:getId()
                .. "\nScript: "
                .. clean(script and script:getFullName())
                .. string.format(
                    "\nPosition: %.1f, %.1f, %.0f",
                    vehicle:getX(),
                    vehicle:getY(),
                    vehicle:getZ()
                )
                .. "\nSkin: "
                .. vehicle:getSkinIndex()
                .. " ("
                .. vehicle:getSkinCount()
                .. " available)"
                .. "\nParts: "
                .. vehicle:getPartCount()
                .. "\nRead-only inspection; use Mechanics for individual parts."
        )
    end
    if
        not integer(args.index, 0, vehicle:getSkinCount() - 1)
        or not integer(args.expected, 0, vehicle:getSkinCount() - 1)
    then
        return reply(player, args, "Skin index is outside this vehicle's available skins.")
    end
    if vehicle:getSkinIndex() ~= args.expected then
        return reply(
            player,
            args,
            "The vehicle skin changed. Inspect the vehicle again before editing."
        )
    end
    if vehicle:getSkinIndex() == args.index then
        return reply(player, args, "The vehicle already uses that skin.")
    end
    -- Wrap the same two native methods used by VehicleCommands.setSkinIndex,
    -- adding independent authorization, proximity and stale-state validation.
    vehicle:setSkinIndex(args.index)
    vehicle:transmitSkinIndex()
    O.audit(
        "VEHICLE_SKIN_CHANGE",
        player,
        "vehicle=" .. vehicle:getId() .. " old=" .. args.expected .. " new=" .. args.index
    )
    reply(player, args, "Vehicle skin updated by the server.")
end

local lastCleanup = 0
Events.OnTick.Add(function()
    local now = getTimestampMs()
    if now - lastCleanup < 30000 then
        return
    end
    lastCleanup = now
    for name, time in pairs(limits) do
        if now - time > 30000 then
            limits[name] = nil
        end
    end
end)
Events.OnClientCommand.Add(S.onCommand)
