if not isServer() then
    return
end
require("AdminCore/OperationsPermissions")
AdminNoiseServer = AdminNoiseServer or {}
local S, O = AdminNoiseServer, AdminOperations
S.requests = S.requests or setmetatable({}, { __mode = "k" })
local requests = S.requests
local radii = { [10] = true, [20] = true, [50] = true, [100] = true, [200] = true, [500] = true }
local function request(module, command, player, args)
    if module ~= "UniversalAdminCore" or command ~= "makeNoise" or not player then
        return
    end
    if type(args) ~= "table" or type(args.radius) ~= "number" or not radii[args.radius] then
        return
    end
    if
        not O.authorized(player, "ADMIN_DEBUG_TOOLS")
        or not O.capable(player, "UseDebugContextMenu")
        or not O.toolAllowed(player, "context.noise." .. args.radius)
        or player:isDead()
    then
        return
    end
    local square = player:getCurrentSquare()
    if not square then
        return
    end
    local now = getTimestampMs()
    if requests[player] and now - requests[player] < 1000 then
        return
    end
    requests[player] = now
    addSound(player, square:getX(), square:getY(), square:getZ(), args.radius, 100)
    O.audit("ADMIN_NOISE", player, "Radius: " .. args.radius .. " tiles at current position")
end
if S.onCommand then
    Events.OnClientCommand.Remove(S.onCommand)
end
S.onCommand = request
Events.OnClientCommand.Add(S.onCommand)
