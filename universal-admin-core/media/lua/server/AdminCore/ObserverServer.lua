if not isServer() then
    return
end
require("AdminCore/OperationsPermissions")
AdminObserverServer = AdminObserverServer or {}
local S, O = AdminObserverServer, AdminOperations
if S.installed then
    return
end
S.installed = true
local sessions, tickets, limits, lastTick = {}, {}, {}, 0
local module = "UniversalAdminCore"
local commands = {
    observeStart = true,
    observeHeartbeat = true,
    observeInterest = true,
    observeStop = true,
    observeTeleport = true,
    observeTeleportPrepare = true,
    observeReturn = true,
    observeStatus = true,
}
local function data()
    local value = ModData.getOrCreate("UniversalAdminCore.Observer.v2")
    value.returns = value.returns or {}
    value.serial = value.serial or 0
    return value
end
local function reply(player, command, args)
    sendServerCommand(player, module, command, args)
end
local function movementResult(player, message, request)
    reply(player, "observeActionResult", { message = message, request = request })
end
local function returnStatus(player, message)
    local origin = data().returns[player:getUsername()]
    reply(
        player,
        "observeStatus",
        { hasReturn = origin ~= nil, returnId = origin and origin.id, message = message }
    )
end
local function allowed(player)
    return O.authorized(player, "ADMIN_SPECTATOR") and not player:isDead()
end
local function stop(player, name, reason)
    local session = sessions[name]
    sessions[name] = nil
    if session and AdminCoreObserverInterest then
        AdminCoreObserverInterest.stop(session.actor, session.id)
    end
    if session and player then
        reply(player, "observeStopped", { id = session.id, reason = reason })
        O.audit("OBSERVE_END", player, session.target .. " | " .. tostring(reason or "Stopped"))
    end
end
local function grant(player, session, command, message)
    session.revision = (session.revision or 0) + 1
    local interest = session.stream and AdminCoreObserverInterest
    reply(player, command or "observeGrant", {
        id = session.id,
        username = session.target,
        render = O.authorized(player, "ADMIN_RENDER_DEBUG"),
        ttl = interest and interest.remaining(player, session.id) or 6000,
        mode = interest and interest.mode(player, session.id) or session.mode,
        x = interest and interest.coordinate(player, session.id, 0) or session.character:getX(),
        y = interest and interest.coordinate(player, session.id, 1) or session.character:getY(),
        z = interest and interest.coordinate(player, session.id, 2) or session.character:getZ(),
        sequence = interest and interest.sequence(player, session.id) or 0,
        revision = session.revision,
        stream = session.stream == true,
        chunkRadius = interest and interest.radius(player, session.id) or 3,
        offsetX = interest and interest.offset(player, session.id, 0) or nil,
        offsetY = interest and interest.offset(player, session.id, 1) or nil,
        message = message,
        returnId = data().returns[player:getUsername()] and data().returns[player:getUsername()].id,
        hasReturn = data().returns[player:getUsername()] ~= nil,
    })
end
local function validRadius(value)
    return type(value) == "number" and value == math.floor(value) and value >= 3 and value <= 9
end
function S.onCommand(mod, command, player, args)
    if
        mod ~= module
        or not commands[command]
        or not player
        or (args ~= nil and type(args) ~= "table")
    then
        return
    end
    local name, now = player:getUsername(), getTimestampMs()
    local session = sessions[name]
    if command == "observeStop" then
        if session and session.actor == player and (not args or args.id == session.id) then
            stop(player, name)
        end
        return
    end
    if not allowed(player) then
        stop(player, name, "Observation permission was revoked.")
        tickets[name] = nil
        if command ~= "observeHeartbeat" then
            movementResult(
                player,
                "You do not have permission to use observer tools.",
                args and args.request
            )
        end
        return
    end
    if command == "observeStatus" then
        local previous = limits[name] and limits[name][command]
        if previous and now - previous < 1000 then
            return
        end
        limits[name] = limits[name] or {}
        limits[name][command] = now
        local persisted = data()
        local legacy = ModData.getOrCreate("UniversalAdminCore.Playtime.v1")[name]
        if legacy and legacy.returnPosition and not persisted.returns[name] then
            local pos = legacy.returnPosition
            if type(pos.x) == "number" and type(pos.y) == "number" and type(pos.z) == "number" then
                persisted.serial = persisted.serial + 1
                persisted.returns[name] =
                    { id = tostring(persisted.serial), x = pos.x, y = pos.y, z = pos.z }
            end
            legacy.returnPosition = nil
        end
        returnStatus(player)
        return
    end
    if type(args) ~= "table" then
        return
    end
    if not AdminCoreObserverBridge then
        return movementResult(
            player,
            "Observer server bridge is unavailable. Restart the server after updating.",
            args.request
        )
    end
    if command == "observeHeartbeat" then
        if not session or session.actor ~= player or args.id ~= session.id then
            return
        end
        if now - session.heartbeat < 1000 then
            return
        end
        local current = AdminCoreObserverBridge.target(player, session.target)
        if current ~= session.character then
            return stop(player, name, "Observed player is no longer available.")
        end
        if session.stream and not AdminCoreObserverInterest.renew(player, session.id) then
            return stop(player, name, "Observer streaming authorization expired.")
        end
        session.heartbeat = now
        grant(player, session)
        return
    end
    if command == "observeInterest" then
        if
            not session
            or session.actor ~= player
            or args.id ~= session.id
            or not session.stream
        then
            return
        end
        if session.interestAt and now - session.interestAt < 200 then
            return
        end
        session.interestAt = now
        local radius = args.chunkRadius
        if radius == nil then
            radius = AdminCoreObserverInterest.radius(player, session.id)
        end
        local relative = args.offsetX ~= nil or args.offsetY ~= nil
        local valid = type(args.sequence) == "number"
            and args.sequence == math.floor(args.sequence)
            and args.sequence > 0
            and args.sequence <= 9007199254740991
            and (args.mode == "FOLLOW" or args.mode == "SOFT" or args.mode == "FREE")
            and type(args.x) == "number"
            and type(args.y) == "number"
            and type(args.z) == "number"
            and validRadius(radius)
            and (
                not relative
                or (
                    args.mode == "SOFT"
                    and type(args.offsetX) == "number"
                    and type(args.offsetY) == "number"
                    and args.offsetX >= -8
                    and args.offsetX <= 8
                    and args.offsetY >= -8
                    and args.offsetY <= 8
                )
            )
        local accepted = false
        if valid and relative then
            accepted = AdminCoreObserverInterest.moveSoft(
                player,
                session.id,
                args.sequence,
                args.offsetX,
                args.offsetY,
                radius
            )
        elseif valid then
            accepted = AdminCoreObserverInterest.moveWithRadius(
                player,
                session.id,
                args.sequence,
                args.mode,
                args.x,
                args.y,
                args.z,
                radius
            )
        end
        if AdminCoreObserverInterest.remaining(player, session.id) <= 0 then
            return stop(player, name, "Observer streaming authorization expired.")
        end
        if not accepted and (not session.deniedAt or now - session.deniedAt >= 2000) then
            session.deniedAt = now
            O.audit(
                "OBSERVE_INTEREST_DENIED",
                player,
                "Invalid, stale or out-of-range observer request"
            )
        end
        grant(
            player,
            session,
            nil,
            not accepted
                    and "Observer view request was rejected; the previous authorized view is retained."
                or nil
        )
        return
    end
    limits[name] = limits[name] or {}
    if limits[name][command] and now - limits[name][command] < 500 then
        return
    end
    limits[name][command] = now
    if command == "observeStart" then
        if type(args.username) ~= "string" or #args.username == 0 or #args.username > 128 then
            return
        end
        local radius = args.chunkRadius == nil and 3 or args.chunkRadius
        if not validRadius(radius) then
            return reply(player, "result", { message = "Invalid observer view size." })
        end
        if player:getVehicle() then
            return reply(
                player,
                "result",
                { message = "Exit your vehicle before using the observer camera." }
            )
        end
        local target = AdminCoreObserverBridge.target(player, args.username)
        if not target then
            return reply(player, "result", { message = "Observed player is no longer available." })
        end
        local x, y, z = player:getX(), player:getY(), player:getZ()
        if session and session.actor == player then
            x, y, z = session.x, session.y, session.z
        end
        if session then
            O.audit("OBSERVE_END", session.actor, "Changed observation target.")
            if AdminCoreObserverInterest then
                AdminCoreObserverInterest.stop(session.actor, session.id)
            end
            sessions[name] = nil
        end
        local persisted = data()
        persisted.serial = persisted.serial + 1
        local id = tostring(persisted.serial)
        local mode = (args.mode == "FREE" or args.mode == "SOFT") and args.mode or "FOLLOW"
        local stream = AdminCoreObserverInterest ~= nil
        if
            stream
            and (
                not AdminCoreObserverInterest.ready()
                or not AdminCoreObserverInterest.startWithRadius(player, target, id, mode, radius)
            )
        then
            return reply(player, "result", {
                message = "Observer streaming is unavailable or not authorized. Restart after updating both client and server.",
            })
        end
        sessions[name] = {
            id = id,
            target = args.username,
            character = target,
            actor = player,
            x = x,
            y = y,
            z = z,
            heartbeat = now,
            mode = mode,
            stream = stream,
        }
        grant(player, sessions[name], "observeStarted")
        O.audit("OBSERVE_START", player, args.username .. " | camera only")
    elseif command == "observeTeleportPrepare" then
        if
            type(args.username) ~= "string"
            or #args.username == 0
            or #args.username > 128
            or type(args.request) ~= "string"
            or #args.request == 0
            or #args.request > 100
        then
            return
        end
        if not O.capable(player, "TeleportToPlayer") then
            return movementResult(player, "Your role cannot teleport to players.", args.request)
        end
        if player:getVehicle() then
            return movementResult(player, "Exit your vehicle before teleporting.", args.request)
        end
        local target = AdminCoreObserverBridge.target(player, args.username)
        if not target or target == player then
            return movementResult(player, "Select another online, living player.", args.request)
        end
        local persisted = data()
        persisted.serial = persisted.serial + 1
        local x, y, z = player:getX(), player:getY(), player:getZ()
        if session and session.actor == player then
            x, y, z = session.x, session.y, session.z
        end
        local ticket = {
            id = tostring(persisted.serial),
            actor = player,
            target = args.username,
            character = target,
            request = args.request,
            expires = now + 15000,
            x = x,
            y = y,
            z = z,
        }
        tickets[name] = ticket
        reply(
            player,
            "observeTeleportReady",
            { ticket = ticket.id, username = ticket.target, request = ticket.request, ttl = 15000 }
        )
    elseif command == "observeTeleport" then
        local ticket = tickets[name]
        if
            not ticket
            or ticket.actor ~= player
            or ticket.id ~= args.ticket
            or now >= ticket.expires
        then
            return movementResult(
                player,
                "Teleport request expired or was already used. Select the player and try again.",
                args.request
            )
        end
        -- Consume before invoking the native movement bridge. A failed action
        -- can be prepared again, while a duplicate packet cannot teleport twice.
        tickets[name] = nil
        if not O.capable(player, "TeleportToPlayer") then
            return movementResult(player, "Your role cannot teleport to players.", ticket.request)
        end
        if player:getVehicle() then
            return movementResult(player, "Exit your vehicle before teleporting.", ticket.request)
        end
        if AdminCoreObserverBridge.target(player, ticket.target) ~= ticket.character then
            return movementResult(
                player,
                "Selected player disconnected or changed character. Select them again.",
                ticket.request
            )
        end
        if not AdminCoreObserverBridge.teleportTo(player, ticket.target) then
            return movementResult(
                player,
                "Teleport failed. Check your role, vehicle and selected player.",
                ticket.request
            )
        end
        local persisted = data()
        -- The original location belongs to the server; no coordinates are accepted on the wire.
        persisted.returns[name] = persisted.returns[name]
            or { id = ticket.id, x = ticket.x, y = ticket.y, z = ticket.z }
        if session and session.actor == player then
            stop(player, name, "Teleported to the selected player.")
        end
        returnStatus(
            player,
            "Teleported to " .. ticket.target .. ". Return to Origin is available."
        )
        O.audit("ADMIN_TELEPORT", player, "Selected player: " .. ticket.target)
    elseif command == "observeReturn" then
        local persisted = data()
        local origin = persisted.returns[name]
        if not O.capable(player, "TeleportToCoordinates") then
            return movementResult(player, "Your role cannot return to saved coordinates.")
        end
        if not origin or origin.id ~= args.id then
            return returnStatus(
                player,
                "There is no matching saved return location. It may already have been used."
            )
        end
        if player:getVehicle() then
            return movementResult(player, "Exit your vehicle before returning.")
        end
        if not AdminCoreObserverBridge.returnTo(player, origin.x, origin.y, origin.z) then
            return movementResult(
                player,
                "Return failed. Your saved origin was kept; check your role and vehicle."
            )
        end
        persisted.returns[name] = nil
        if session and session.actor == player then
            stop(player, name, "Returned to your original position.")
        end
        returnStatus(player, "Returned to your original position.")
        O.audit("ADMIN_TELEPORT", player, "Returned to observation origin")
    end
end
function S.tick()
    local now = getTimestampMs()
    if now - lastTick < 2000 then
        return
    end
    lastTick = now
    local connected = {}
    local players = getOnlinePlayers()
    for i = 0, players:size() - 1 do
        local player = players:get(i)
        connected[player:getUsername()] = player
    end
    for name, session in pairs(sessions) do
        local player = connected[name]
        if player ~= session.actor then
            if session.actor then
                O.audit("OBSERVE_END", session.actor, "Disconnected or character changed")
            end
            stop(nil, name, "Disconnected or character changed")
        elseif not allowed(player) or player:getVehicle() then
            stop(player, name, "Observation permission or character state changed.")
        elseif now - session.heartbeat > 10000 then
            stop(player, name, "Observation heartbeat timed out.")
        elseif session.stream and AdminCoreObserverInterest.remaining(player, session.id) <= 0 then
            stop(player, name, "Observer streaming authorization expired.")
        elseif
            not AdminCoreObserverBridge
            or AdminCoreObserverBridge.target(player, session.target) ~= session.character
        then
            stop(player, name, "Observed player is no longer available.")
        end
    end
    for name in pairs(limits) do
        if not connected[name] then
            limits[name] = nil
        end
    end
    for name, ticket in pairs(tickets) do
        if connected[name] ~= ticket.actor or now >= ticket.expires then
            tickets[name] = nil
        end
    end
end
Events.OnClientCommand.Add(S.onCommand)
Events.OnTick.Add(S.tick)
