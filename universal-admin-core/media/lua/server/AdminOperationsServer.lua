if not isServer() then
    return
end
require("AdminCore/OperationsPermissions")
local O, requests = AdminOperations, setmetatable({}, { __mode = "k" })
local function request(module, command, player, args)
    if module ~= "UniversalAdminOperations" or command ~= "permissions" or not player then
        return
    end
    if args ~= nil and type(args) ~= "table" then
        return
    end
    local now = getTimestampMs()
    if requests[player] and now - requests[player] < 1000 then
        return
    end
    requests[player] = now
    local features = {}
    for key in pairs(O.features) do
        features[key] = O.authorized(player, key)
    end
    local denied = {}
    local role = player:getRole()
    if role and role:hasAdminPower() then
        for id, value in pairs(O.policy().disabledTools or {}) do
            if type(id) == "string" and #id <= 160 and value == true then
                denied[id] = true
            end
        end
    end
    sendServerCommand(
        player,
        "UniversalAdminOperations",
        "permissions",
        { features = features, deniedTools = denied, ttl = 15000 }
    )
end
Events.OnClientCommand.Add(request)
