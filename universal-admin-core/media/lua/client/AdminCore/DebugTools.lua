require("AdminCore/Registry")
require("AdminCore/OperationsClient")
local C = AdminCore
if C.safeDebugToolsInstalled then
    return
end
C.safeDebugToolsInstalled = true
local sequence, pending, lastDiagnostics = 0, {}, nil
local function allowed(capability, id)
    return C.operationsAllowed("ADMIN_DEBUG_TOOLS")
        and C.allowed(capability)
        and C.operationToolAllowed(id)
end
local function request(command, args, capability, id)
    if not allowed(capability, id) then
        return C.message("This debug tool is no longer allowed for your role.")
    end
    sequence = sequence % 2147483647 + 1
    args.token = sequence
    pending[sequence] = { player = getPlayer(), time = getTimestampMs() }
    for token, record in pairs(pending) do
        if getTimestampMs() - record.time > 15000 then
            pending[token] = nil
        end
    end
    sendClientCommand(getPlayer(), "UniversalAdminDebug", command, args)
end
local function prompt(title, value, callback)
    local panel = ISTextBox:new(0, 0, 540, 200, title, value, nil, function(_, button)
        if button.internal == "OK" then
            callback(button.parent.entry:getText())
        end
    end)
    panel:initialise()
    panel:addToUIManager()
    C.fit(panel, panel.width, panel.height)
end
local function nearby()
    local player = getPlayer()
    return player and (player:getVehicle() or player:getNearVehicle())
end

C.registerAction({
    id = "debug.inspectObjects",
    title = "Inspect nearby tile / object IDs...",
    category = "World",
    group = { "Admin diagnostics" },
    keywords = "object sprite coordinates container diagnostic inspect",
    tooltip = "Read-only server inspection of one loaded tile within 8 tiles. No inventory contents or arbitrary mod data.",
    allowed = function()
        return allowed(Capability.UseDebugContextMenu, "debug.inspectObjects")
    end,
    run = function()
        local player = getPlayer()
        prompt(
            "Inspect loaded tile within 8 tiles: x,y,z",
            string.format("%d,%d,%d", player:getX(), player:getY(), player:getZ()),
            function(text)
                local x, y, z = text:match("^%s*(%-?%d+)%s*,%s*(%-?%d+)%s*,%s*(%-?%d+)%s*$")
                if not x then
                    return C.message("Enter integer coordinates as x,y,z.")
                end
                request(
                    "objects",
                    { x = tonumber(x), y = tonumber(y), z = tonumber(z) },
                    Capability.UseDebugContextMenu,
                    "debug.inspectObjects"
                )
            end
        )
    end,
})

C.registerAction({
    id = "debug.inspectVehicle",
    title = "Inspect nearby vehicle...",
    category = "World",
    group = { "Admin diagnostics" },
    keywords = "vehicle script skin parts model diagnostic",
    allowed = function()
        return allowed(Capability.ManipulateVehicle, "debug.inspectVehicle")
    end,
    available = function()
        return nearby() ~= nil
    end,
    run = function()
        local vehicle = nearby()
        if vehicle then
            request(
                "vehicle",
                { vehicle = vehicle:getId() },
                Capability.ManipulateVehicle,
                "debug.inspectVehicle"
            )
        end
    end,
})

C.registerAction({
    id = "debug.vehicleSkin",
    title = "Change nearby vehicle skin...",
    category = "World",
    group = { "Admin diagnostics" },
    keywords = "vehicle skin model color visuals",
    tooltip = "Select an existing skin from the vehicle script. The server checks your role, proximity and current skin.",
    allowed = function()
        return allowed(Capability.ManipulateVehicle, "debug.vehicleSkin")
    end,
    available = function()
        local vehicle = nearby()
        return vehicle ~= nil and vehicle:getSkinCount() > 1
    end,
    run = function()
        local vehicle = nearby()
        if not vehicle then
            return
        end
        local id, expected, count = vehicle:getId(), vehicle:getSkinIndex(), vehicle:getSkinCount()
        prompt(
            "Vehicle " .. id .. ": skin index (0 to " .. (count - 1) .. ")",
            tostring(expected),
            function(text)
                local index = tonumber(text)
                if not index or index ~= math.floor(index) or index < 0 or index >= count then
                    return C.message("Choose an existing skin index in the displayed range.")
                end
                C.confirm("Apply skin " .. index .. " to vehicle " .. id .. "?", function()
                    request(
                        "skin",
                        { vehicle = id, index = index, expected = expected },
                        Capability.ManipulateVehicle,
                        "debug.vehicleSkin"
                    )
                end)
            end
        )
    end,
})

C.registerAction({
    id = "debug.copyDiagnostics",
    title = "Copy last object / vehicle diagnostics",
    category = "World",
    group = { "Admin diagnostics" },
    keywords = "copy clipboard inspect diagnostics",
    allowed = function()
        return allowed(Capability.UseDebugContextMenu, "debug.copyDiagnostics")
    end,
    available = function()
        return lastDiagnostics ~= nil and Clipboard ~= nil
    end,
    run = function()
        Clipboard.setClipboard(lastDiagnostics)
    end,
})

C.registerAction({
    id = "debug.supportedTools",
    title = "Supported admin debug tools...",
    category = "World",
    group = { "Admin diagnostics" },
    keywords = "debug replacement item attachment reload model xray supported",
    allowed = function()
        return C.operationsAllowed("ADMIN_DEBUG_TOOLS")
    end,
    run = function()
        C.message(
            "Available without full debug mode:\nNearby object/sprite/coordinate inspection; bounded container summary; vehicle script/skin/part summary; server-authorized vehicle skin change; copy diagnostics.\n\nReplacement items: use the existing Items List Viewer with its native item permissions.\n\nArbitrary visual reload, missing model attachment repair and X-ray are not exposed: no verified safe independent engine interface. Full PZ debug mode remains unchanged."
        )
    end,
})

Events.OnServerCommand.Add(function(module, command, args)
    if
        module ~= "UniversalAdminDebug"
        or command ~= "result"
        or type(args) ~= "table"
        or type(args.text) ~= "string"
    then
        return
    end
    local record = pending[args.token]
    if not record or record.player ~= getPlayer() or getTimestampMs() - record.time > 15000 then
        return
    end
    pending[args.token] = nil
    lastDiagnostics = args.text:sub(1, 6000)
    C.message(lastDiagnostics)
end)
local function clear()
    pending, lastDiagnostics = {}, nil
end
Events.OnDisconnect.Add(clear)
Events.OnMainMenuEnter.Add(clear)
