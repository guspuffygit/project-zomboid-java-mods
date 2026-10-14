require("AdminCore/WindowSizing")
require("AdminCore/OperationsPermissions")
local C, O = AdminCore, AdminOperations
if C.operationsClientInstalled then
    return
end
C.operationsClientInstalled = true
local state = { features = {}, deniedTools = {}, expires = 0, requested = -10000, owners = {} }
C.operationsState = state
function C.operationsAllowed(feature)
    local player = getPlayer()
    if not player or not O.authorized(player, feature) then
        return false
    end
    return getTimestampMs() < state.expires and state.features[feature] == true
end
function C.operationToolAllowed(id)
    return getTimestampMs() < state.expires and not state.deniedTools[id]
end
function C.requestOperations()
    local now, player = getTimestampMs(), getPlayer()
    if not player or now - state.requested < 1000 then
        return
    end
    state.requested = now
    sendClientCommand(player, "UniversalAdminOperations", "permissions", {})
end
function C.operationsKeepAlive(owner, active)
    state.owners[owner] = active and true or nil
    if active then
        C.requestOperations()
    end
end
Events.OnServerCommand.Add(function(module, command, args)
    if
        module ~= "UniversalAdminOperations"
        or command ~= "permissions"
        or type(args) ~= "table"
    then
        return
    end
    state.features, state.deniedTools = {}, {}
    for key in pairs(O.features) do
        state.features[key] = type(args.features) == "table" and args.features[key] == true
    end
    for id, value in pairs(type(args.deniedTools) == "table" and args.deniedTools or {}) do
        if type(id) == "string" and #id <= 160 and value == true then
            state.deniedTools[id] = true
        end
    end
    state.expires = getTimestampMs() + math.min(15000, math.max(0, tonumber(args.ttl) or 0))
    C.registryVersion = (C.registryVersion or 0) + 1
end)
Events.OnTick.Add(function()
    if O.hasEntries(state.owners) and getTimestampMs() - state.requested >= 5000 then
        C.requestOperations()
    end
end)
local function clear()
    state.features, state.deniedTools, state.owners, state.expires = {}, {}, {}, 0
end
Events.OnDisconnect.Add(clear)
Events.OnMainMenuEnter.Add(clear)
