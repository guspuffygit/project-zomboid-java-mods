-- Exercise the real ObserverClient handlers. Only the engine/network boundary is
-- replaced; camera behavior mirrors AdminCoreObserveCamera.java's grantAt,
-- setMode, pan, active and readiness contract, including TTL units and anchoring.
local root = arg[2] or "universal-admin-core"
require = function() end
local checks = 0
local function check(value, message)
    assert(value, message)
    checks = checks + 1
end
local function equal(actual, expected, message)
    check(
        actual == expected,
        message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual)
    )
end
local function near(actual, expected, message)
    check(math.abs(actual - expected) < 0.00001, message)
end
local function copy(values)
    local result = {}
    for key, value in pairs(values or {}) do
        result[key] = value
    end
    return result
end
local function merge(defaults, values)
    local result = copy(defaults)
    for key, value in pairs(values or {}) do
        result[key] = value
    end
    return result
end
local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) ~= math.huge
end
local function clamp(value, low, high)
    return math.max(low, math.min(high, value))
end
local function player(name, x, y)
    return {
        name = name,
        x = x,
        y = y,
        z = 0,
        dead = false,
        square = {},
        blocked = false,
        getUsername = function(self)
            return self.name
        end,
        getX = function(self)
            return self.x
        end,
        getY = function(self)
            return self.y
        end,
        getZ = function(self)
            return self.z
        end,
        isDead = function(self)
            return self.dead
        end,
        getCurrentSquare = function(self)
            return self.square
        end,
        getPrimaryHandItem = function()
            return nil
        end,
    }
end
local function fixture()
    local f = {
        now = 100000,
        authority = true,
        grants = true,
        terrainReady = false,
        actor = player("admin", 10, 20),
        target = player("remote", 1000, 2000),
        commands = {},
        overlays = {},
        overlayCalls = {},
        keys = {},
        keepAlive = {},
        camera = {
            mode = "FOLLOW",
            deadline = 0,
            grantCalls = {},
            modeCalls = {},
            panCalls = {},
            predictionCalls = {},
            stops = 0,
        },
    }
    f.loaded = false
    Events = setmetatable({}, {
        __index = function(t, key)
            local event = { handlers = {} }
            event.Add = function(fn)
                event.handlers[#event.handlers + 1] = fn
            end
            rawset(t, key, event)
            return event
        end,
    })
    f.events = Events
    function f.fire(event, ...)
        for _, fn in ipairs(f.events[event].handlers) do
            fn(...)
        end
    end
    function f.receive(command, args, module)
        f.fire("OnServerCommand", module or "UniversalAdminCore", command, args)
    end
    function f.tick(milliseconds)
        f.now = f.now + (milliseconds or 0)
        f.fire("OnTick")
    end
    function f.count(command)
        local count = 0
        for _, item in ipairs(f.commands) do
            if item.command == command then
                count = count + 1
            end
        end
        return count
    end
    function f.last(command)
        for i = #f.commands, 1, -1 do
            if f.commands[i].command == command then
                return f.commands[i]
            end
        end
    end
    function f.origin(message)
        equal(f.actor.x, 10, message .. " actor X")
        equal(f.actor.y, 20, message .. " actor Y")
        equal(f.actor.z, 0, message .. " actor Z")
    end
    getTimestampMs = function()
        return f.now
    end
    getPlayer = function()
        if f.noActor then
            return nil
        end
        return f.actor
    end
    getPlayerFromUsername = function(name)
        if name == f.actor.name then
            return f.actor
        end
        if f.loaded and name == f.target.name then
            return f.target
        end
    end
    getOnlinePlayers = function()
        return {
            size = function()
                return 2
            end,
            get = function(_, i)
                return i == 0 and f.actor or f.target
            end,
        }
    end
    Keyboard = {
        KEY_ESCAPE = 1,
        KEY_F = 33,
        KEY_D = 32,
        KEY_A = 30,
        KEY_S = 31,
        KEY_W = 17,
        KEY_LSHIFT = 42,
        KEY_LCONTROL = 29,
    }
    isKeyDown = function(key)
        return f.keys[key] == true
    end
    ISFastTeleportMove = { cheat = true }
    sendClientCommand = function(module, command, args)
        f.commands[#f.commands + 1] =
            { module = module, command = command, args = copy(args), at = f.now }
    end
    AdminOperations = {
        authorized = function(p, operation)
            return p == f.actor and f.authority and operation == "ADMIN_SPECTATOR"
        end,
        capable = function(p, capability)
            return p == f.actor and f.authority and not f.deniedCapability[capability]
        end,
    }
    f.deniedCapability = {}
    AdminOverlayManager = {
        enableOverlay = function(id, enabled)
            f.overlays[id] = enabled == true
            f.overlayCalls[#f.overlayCalls + 1] = { id = id, enabled = enabled }
        end,
    }
    AdminCore = {
        operationsAllowed = function(operation)
            return f.grants and f.authority and operation == "ADMIN_SPECTATOR"
        end,
        requestOperations = function()
            f.permissionRequests = (f.permissionRequests or 0) + 1
        end,
        operationsKeepAlive = function(key, enabled)
            f.keepAlive[key] = enabled
        end,
        confirm = function(question, callback)
            f.confirmQuestion = question
            f.confirm = callback
        end,
        openObserverPanel = function()
            f.openedPanel = true
        end,
    }
    local camera = f.camera
    local api = {}
    api.stop = function()
        camera.stops = camera.stops + 1
        camera.name, camera.deadline, camera.stream = nil, 0, false
        camera.mode, camera.panX, camera.panY = "FOLLOW", 0, 0
        if camera.originalBlock ~= nil then
            f.actor.blocked = camera.originalBlock
        end
        camera.originalBlock, camera.weather = nil, false
    end
    api.active = function()
        if not camera.name then
            return false
        end
        if f.now >= camera.deadline or f.actor.dead or not f.authority or f.noActor then
            api.stop()
            return false
        end
        return true
    end
    api.grant = function(name, render)
        if f.refuseCamera or not f.authority or f.actor.dead then
            return false
        end
        if not camera.name then
            camera.originalBlock = f.actor.blocked
            f.actor.blocked = true
        end
        if camera.name ~= name then
            camera.mode, camera.panX, camera.panY = "FOLLOW", 0, 0
        end
        camera.name, camera.deadline, camera.render = name, f.now + 6000, render
        if not render then
            camera.weather = false
        end
        return true
    end
    api.grantAt = function(name, render, x, y, z, ttlSeconds, stream)
        camera.grantCalls[#camera.grantCalls + 1] = {
            name = name,
            render = render,
            x = x,
            y = y,
            z = z,
            ttl = ttlSeconds,
            stream = stream,
            at = f.now,
        }
        -- AdminCoreObserverBridge.validPosition and native grantAt's z < 32.
        if
            not finite(x)
            or not finite(y)
            or not finite(z)
            or math.abs(x) > 1000000
            or math.abs(y) > 1000000
            or z < -32
            or z >= 32
            or not finite(ttlSeconds)
            or ttlSeconds <= 0
            or ttlSeconds > 6
            or not api.grant(name, render)
        then
            return false
        end
        camera.x, camera.y, camera.z = x, y, z
        camera.deadline, camera.stream = f.now + math.floor(ttlSeconds * 1000), stream and render
        camera.panX, camera.panY = 0, 0
        camera.offsetX, camera.offsetY = nil, nil
        if camera.mode == "FREE" then
            camera.freeX, camera.freeY, camera.freeZ = x, y, z
            camera.anchorX, camera.anchorY = x, y
        end
        return true
    end
    api.setMode = function(mode)
        camera.modeCalls[#camera.modeCalls + 1] = mode
        if not api.active() or (mode ~= "FOLLOW" and mode ~= "SOFT" and mode ~= "FREE") then
            return false
        end
        if camera.mode == mode then
            return true
        end
        if not camera.stream and not f.loaded then
            return false
        end
        if mode == "FREE" then
            camera.freeX = camera.stream and camera.x or f.target.x + camera.panX
            camera.freeY = camera.stream and camera.y or f.target.y + camera.panY
            camera.freeZ = camera.stream and camera.z or f.target.z
            camera.anchorX, camera.anchorY = camera.freeX, camera.freeY
        end
        camera.mode, camera.panX, camera.panY = mode, 0, 0
        return true
    end
    api.getViewX = function()
        if f.invalidView then
            return f.invalidView
        end
        return camera.mode == "FREE" and camera.freeX
            or (
                    camera.offsetX and f.loaded and (f.target.x + camera.offsetX)
                    or camera.stream and camera.x
                    or f.target.x
                )
                + camera.panX
    end
    api.getViewY = function()
        return camera.mode == "FREE" and camera.freeY
            or (
                    camera.offsetY and f.loaded and (f.target.y + camera.offsetY)
                    or camera.stream and camera.y
                    or f.target.y
                )
                + camera.panY
    end
    api.getViewZ = function()
        return camera.mode == "FREE" and camera.freeZ or camera.z
    end
    api.ready = function()
        return api.active() and f.terrainReady
    end
    api.setFollowOffset = function(x, y)
        if not finite(x) or not finite(y) or math.abs(x) > 8 or math.abs(y) > 8 then
            return false
        end
        camera.offsetX, camera.offsetY = x, y
        return true
    end
    api.getFollowOffsetX = function()
        return (camera.offsetX or 0) + camera.panX
    end
    api.getFollowOffsetY = function()
        return (camera.offsetY or 0) + camera.panY
    end
    api.requestedRadius = function()
        return f.requestedRadius or 3
    end
    api.grantRadius = function(radius)
        if not finite(radius) or radius ~= math.floor(radius) or radius < 3 or radius > 9 then
            return false
        end
        camera.radius = radius
        return true
    end
    local function applyPrediction(dx, dy)
        if not camera.stream and not f.loaded then
            return false
        end
        if camera.mode == "SOFT" and camera.offsetX then
            if
                math.abs(api.getFollowOffsetX() + dx) > 8
                or math.abs(api.getFollowOffsetY() + dy) > 8
            then
                return false
            end
            camera.panX, camera.panY = camera.panX + dx, camera.panY + dy
            return true
        end
        local selected = f.loaded and not f.target.dead and f.target.square and f.target or nil
        -- Native SOFT bounds use the target, even when the server grant already
        -- contains an accepted pan offset. FREE bounds use the grant anchor.
        local anchorX = camera.mode == "SOFT" and (selected and selected.x or camera.x)
            or camera.anchorX
        local anchorY = camera.mode == "SOFT" and (selected and selected.y or camera.y)
            or camera.anchorY
        local x, y = api.getViewX() + dx, api.getViewY() + dy
        local limit = camera.mode == "SOFT" and 8 or 24
        if math.abs(x - anchorX) > limit or math.abs(y - anchorY) > limit then
            return false
        end
        if camera.mode == "FREE" then
            camera.freeX, camera.freeY = x, y
        else
            camera.panX, camera.panY = x - camera.x, y - camera.y
        end
        return true
    end
    api.pan = function(dx, dy)
        camera.panCalls[#camera.panCalls + 1] = { x = dx, y = dy }
        if not api.active() or camera.mode == "FOLLOW" or not finite(dx) or not finite(dy) then
            return false
        end
        return applyPrediction(clamp(dx, -2, 2), clamp(dy, -2, 2))
    end
    api.restorePrediction = function(dx, dy)
        camera.predictionCalls[#camera.predictionCalls + 1] = { x = dx, y = dy }
        if
            not api.active()
            or not camera.stream
            or camera.mode == "FOLLOW"
            or not finite(dx)
            or not finite(dy)
        then
            return false
        end
        -- Recovery accepts the full offset without the keyboard pan's +/-2
        -- per-frame clamp, then enforces the native +/-8 or +/-24 area bound.
        return applyPrediction(dx, dy)
    end
    api.setHideWeather = function(value)
        camera.weather = value and api.active() and camera.render
    end
    AdminCoreObserveCamera = api
    f.api = api
    dofile(root .. "/media/lua/client/AdminCore/ObserverClient.lua")
    f.client, f.state = AdminCore, AdminCore.observer
    function f.start(values)
        local packet = merge({
            id = 1,
            username = "remote",
            render = true,
            stream = true,
            x = 1000,
            y = 2000,
            z = 0,
            ttl = 6000,
            mode = "FOLLOW",
            revision = 1,
            sequence = 0,
        }, values)
        check(f.client.startObserver(packet.username, packet.mode), "valid start request accepted")
        f.receive("observeStarted", packet)
        return packet
    end
    function f.ack(values)
        local packet = merge({
            id = f.state.id,
            render = true,
            stream = true,
            x = camera.x,
            y = camera.y,
            z = camera.z,
            ttl = 6000,
            mode = f.state.mode,
            revision = f.state.grantRevision + 1,
            sequence = f.state.interestSequence,
        }, values)
        f.receive("observeGrant", packet)
        return packet
    end
    return f
end

-- A remote target missing from the local IsoPlayer list is a loading state,
-- never an implicit request to move the administrative character.
local f = fixture()
f.start()
equal(f.state.id, 1, "remote observation remains active")
equal(f.state.target, "remote", "remote target retained")
check(f.state.stream and f.state.loadingSince == f.now, "remote starts in streaming/loading state")
equal(f.count("observeStop"), 0, "remote missing locally does not stop")
equal(f.count("observeTeleportPrepare"), 0, "remote missing locally never starts teleport")
equal(f.count("observeTeleport"), 0, "remote missing locally never teleports")
equal(f.camera.grantCalls[1].name, "remote", "native grant uses selected username")
equal(f.camera.grantCalls[1].ttl, 6, "6000 ms becomes six native seconds")
check(
    f.camera.grantCalls[1].render and f.camera.grantCalls[1].stream,
    "native remote render/stream flags forwarded"
)
equal(f.camera.x, 1000, "native grant uses server X")
equal(f.camera.y, 2000, "native grant uses server Y")
check(
    f.actor.blocked and not ISFastTeleportMove.cheat,
    "camera freezes normal and fast-teleport movement"
)
f.origin("initial remote camera")
local information = f.client.observerInformation()
check(information[3]:find("Loading", 1, true), "information admits player details are loading")
check(information[4]:find("origin", 1, true), "information preserves camera-only distinction")

-- Actual ticks continue sending FOLLOW interest without a local target. The
-- limiter applies across direct calls, key/mode requests and frame ticks.
f.tick()
equal(f.count("observeInterest"), 0, "new lease does not submit before server movement interval")
f.tick(249)
equal(f.count("observeInterest"), 0, "initial interest waits the full client interval")
f.tick(1)
equal(f.count("observeInterest"), 1, "FOLLOW sends interest while remote is locally missing")
equal(f.last("observeInterest").args.sequence, 1, "first interest sequence")
equal(f.last("observeInterest").args.mode, "FOLLOW", "FOLLOW request is explicit")
equal(f.last("observeInterest").args.x, 1000, "interest center is camera/server center")
equal(f.last("observeInterest").args.y, 2000, "interest Y is camera/server center")
equal(f.count("observeHeartbeat"), 1, "active remote session sends heartbeat")
for _ = 1, 249 do
    f.tick(1)
end
equal(f.count("observeInterest"), 1, "249 ms of frame ticks cannot exceed four Hz")
check(not f.client.sendObserverInterest(), "direct interest calls share rate limit")
f.tick(1)
equal(f.count("observeInterest"), 2, "interest allowed at exact 250 ms boundary")
equal(f.last("observeInterest").args.sequence, 2, "second sequence is monotonic")
for _ = 1, 7 do
    f.tick(250)
end
equal(f.count("observeInterest"), 9, "FOLLOW continues four-Hz polling without local target")
equal(f.last("observeInterest").args.sequence, 9, "FOLLOW sequence stays monotonic")
local lastTime, lastSequence = nil, 0
for _, command in ipairs(f.commands) do
    if command.command == "observeInterest" then
        if lastTime then
            check(command.at - lastTime >= 250, "each interest spacing is at least 250 ms")
        end
        check(command.args.sequence > lastSequence, "each interest sequence strictly increases")
        lastTime, lastSequence = command.at, command.args.sequence
    end
end
equal(#f.camera.panCalls, 0, "FOLLOW never pans the camera")
f.origin("FOLLOW remote polling")

-- Mode buttons request a mode; only a matching server ACK changes camera/UI.
local modesBefore, interestsBefore = #f.camera.modeCalls, f.count("observeInterest")
check(f.client.observerMode("FREE"), "FREE request accepted")
equal(f.state.mode, "FOLLOW", "request does not optimistically change mode")
equal(f.camera.mode, "FOLLOW", "request does not optimistically change native camera")
equal(#f.camera.modeCalls, modesBefore, "no native mode call before ACK")
equal(f.count("observeInterest"), interestsBefore, "mode request does not bypass rate limit")
equal(f.state.requestedMode, "FREE", "pending authoritative mode retained")
f.tick(250)
equal(f.last("observeInterest").args.mode, "FREE", "next interest carries requested mode")
check(not f.client.observerMode("INVALID"), "invalid outgoing mode rejected")
equal(f.state.requestedMode, "FREE", "invalid mode cannot replace pending request")
local nativeBefore = #f.camera.grantCalls
f.ack({ id = 99, mode = "FREE" })
equal(f.state.mode, "FOLLOW", "wrong session ACK does not change mode")
equal(#f.camera.grantCalls, nativeBefore, "wrong session ACK does not call camera")
f.ack({ mode = "FREE" })
equal(f.state.mode, "FREE", "server ACK changes UI mode")
equal(f.camera.mode, "FREE", "server ACK changes native camera mode")
equal(f.state.requestedMode, nil, "acknowledged requested mode cleared")
equal(f.state.acknowledgedSequence, f.state.interestSequence, "server sequence acknowledged")
check(f.state.id ~= nil, "FREE ACK does not require a local target")

-- FREE uses the predicted camera center, never actor coordinates. Model native
-- pan's 0.1-second frame clamp and grantAt's FREE anchor reset on each ACK.
f.terrainReady = true
f.tick(250)
equal(f.state.loadingSince, nil, "FREE readiness only requires terrain, not target IsoPlayer")
f.keys[Keyboard.KEY_D] = true
f.keys[Keyboard.KEY_S] = true
f.tick(250)
near(f.last("observeInterest").args.x, 1000.6, "FREE interest predicts panned X")
near(f.last("observeInterest").args.y, 2000.6, "FREE interest predicts panned Y")
equal(f.last("observeInterest").args.z, 0, "FREE interest retains server Z")
f.origin("FREE predicted camera pan")
local prediction = f.last("observeInterest").args
f.ack({ x = prediction.x, y = prediction.y, mode = "FREE" })
near(f.api.getViewX(), prediction.x, "FREE ACK rebases native camera to accepted center")
near(f.api.getViewY(), prediction.y, "FREE ACK rebases native camera Y")
f.keys[Keyboard.KEY_LSHIFT] = true
f.tick(250)
near(
    f.last("observeInterest").args.x,
    prediction.x + 1.5,
    "Shift pan remains bounded by native frame delta"
)
f.keys = {}
local afterPan = f.api.getViewX()
f.client.observePanel = { search = {
    isFocused = function()
        return true
    end,
} }
-- Avoid roster dependencies unrelated to streaming while exercising search focus.
f.client.refreshObserverRoster = function() end
f.keys[Keyboard.KEY_D] = true
f.tick(250)
near(f.api.getViewX(), afterPan, "search focus prevents keyboard panning")
f.fire("OnKeyPressed", Keyboard.KEY_F)
equal(f.state.requestedMode, nil, "search focus also suppresses F mode shortcut")
f.client.observePanel, f.keys = nil, {}
f.fire("OnKeyPressed", Keyboard.KEY_F)
equal(f.state.mode, "FREE", "F shortcut waits for server ACK")
equal(f.state.requestedMode, "FOLLOW", "F shortcut requests FOLLOW")
f.ack({ mode = "FOLLOW" })
equal(f.state.mode, "FOLLOW", "F request takes effect on ACK")

-- ACKs may arrive several pan frames late. Keep only motion made after that
-- submitted center, including offsets larger than one keyboard pan frame.
-- Same-sequence heartbeat ACKs use the last accepted center instead, so the
-- accepted portion cannot accumulate again on every heartbeat.
for _, mode in ipairs({ "FREE", "SOFT" }) do
    f = fixture()
    f.loaded, f.terrainReady = mode == "SOFT", true
    f.start({ mode = mode })
    equal(f.state.mode, mode, mode .. " initial authoritative mode applied")
    equal(f.camera.mode, mode, mode .. " initial native mode applied")
    f.tick(250)
    f.keys[Keyboard.KEY_D] = true
    f.tick(250)
    local submitted = copy(f.last("observeInterest").args)
    near(submitted.x, 1000.6, mode .. " submitted center contains initial movement")
    for _ = 1, 5 do
        f.tick(100)
    end
    local predicted = f.api.getViewX()
    near(predicted, 1003.6, mode .. " movement continues while earlier ACK is in transit")
    local laterSequence = f.state.interestSequence
    local delayed = f.ack({ sequence = submitted.sequence, x = submitted.x, y = submitted.y })
    near(f.api.getViewX(), predicted, mode .. " delayed ACK preserves post-request movement")
    near(
        f.camera.predictionCalls[#f.camera.predictionCalls].x,
        3,
        mode .. " recovery restores full offset without per-frame clamp"
    )
    equal(
        f.state.acknowledgedSequence,
        submitted.sequence,
        mode .. " delayed sequence acknowledged"
    )
    equal(
        f.state.interestRequests[submitted.sequence],
        nil,
        mode .. " acknowledged request released"
    )
    check(
        f.state.interestRequests[laterSequence] ~= nil,
        mode .. " later outstanding request retained"
    )
    local grantsBefore, restoresBefore = #f.camera.grantCalls, #f.camera.predictionCalls
    f.receive("observeGrant", delayed)
    equal(#f.camera.grantCalls, grantsBefore, mode .. " duplicate delayed ACK cannot re-grant")
    equal(
        #f.camera.predictionCalls,
        restoresBefore,
        mode .. " duplicate delayed ACK cannot reapply prediction"
    )
    near(f.api.getViewX(), predicted, mode .. " duplicate delayed ACK leaves view unchanged")
    f.keys = {}
    for _ = 1, 5 do
        f.ack({ sequence = submitted.sequence, x = submitted.x, y = submitted.y })
        near(
            f.api.getViewX(),
            predicted,
            mode .. " same-sequence heartbeat cannot repeat accepted movement"
        )
        near(
            f.camera.predictionCalls[#f.camera.predictionCalls].x,
            3,
            mode .. " heartbeat uses previous accepted center"
        )
    end
    -- Reach the next polling boundary without another pan frame, submitting
    -- the settled current view so all remaining movement can be acknowledged.
    f.tick(50)
    laterSequence = f.state.interestSequence
    local latest = f.state.interestRequests[laterSequence]
    f.ack({ sequence = laterSequence, x = latest.x, y = latest.y })
    near(f.api.getViewX(), predicted, mode .. " later outstanding request is accepted exactly once")
    near(
        f.camera.predictionCalls[#f.camera.predictionCalls].x,
        0,
        mode .. " accepted motion is removed from remaining prediction"
    )
    f.keys[Keyboard.KEY_D] = true
    f.tick(100)
    local unsent = f.api.getViewX()
    near(unsent, predicted + 0.6, mode .. " unsent local pan follows latest ACK")
    f.keys = {}
    for _ = 1, 3 do
        f.ack({ sequence = laterSequence, x = latest.x, y = latest.y })
        near(f.api.getViewX(), unsent, mode .. " heartbeat preserves unsent pan exactly once")
        near(
            f.camera.predictionCalls[#f.camera.predictionCalls].x,
            0.6,
            mode .. " heartbeat carries only unaccepted pan"
        )
    end
    restoresBefore = #f.camera.predictionCalls
    f.ack({
        sequence = laterSequence,
        x = 1000,
        y = 2000,
        message = "Interest rejected by server bounds.",
    })
    near(f.api.getViewX(), 1000, mode .. " explicit rejection drops local prediction")
    equal(
        #f.camera.predictionCalls,
        restoresBefore,
        mode .. " explicit rejection does not restore rejected offset"
    )
    equal(f.state.lastAckCenter.x, 1000, mode .. " rejection establishes accepted baseline")
    f.ack({ sequence = laterSequence, x = 1000, y = 2000 })
    near(f.api.getViewX(), 1000, mode .. " later heartbeat cannot resurrect rejected movement")
    local nextMode = mode == "FREE" and "SOFT" or "FREE"
    f.client.observerMode(nextMode)
    f.tick(150)
    local switchRequest = f.last("observeInterest").args
    equal(switchRequest.mode, nextMode, mode .. " switch request carries desired mode")
    f.keys[Keyboard.KEY_D] = true
    f.tick(100)
    check(f.api.getViewX() > 1000, mode .. " old mode may pan while mode-change ACK is in flight")
    restoresBefore = #f.camera.predictionCalls
    f.ack({ sequence = switchRequest.sequence, mode = nextMode, x = 1002, y = 2001 })
    equal(f.state.mode, nextMode, mode .. " authoritative ACK changes mode after delayed request")
    near(f.api.getViewX(), 1002, mode .. " mode change drops old-mode prediction")
    near(f.api.getViewY(), 2001, mode .. " mode change establishes accepted Y baseline")
    equal(
        #f.camera.predictionCalls,
        restoresBefore,
        mode .. " mode change cannot restore old-mode offset"
    )
    f.origin(mode .. " delayed prediction flow")
end

-- The request journal is bounded even if new interest packets never receive
-- ACKs, while heartbeats legitimately renew the session's short server lease.
f = fixture()
f.terrainReady = true
f.start({ mode = "FREE" })
f.tick(250)
local function requestCount(state)
    local count = 0
    for _ in pairs(state.interestRequests or {}) do
        count = count + 1
    end
    return count
end
for iteration = 1, 40 do
    f.tick(250)
    if iteration % 8 == 0 then
        f.ack({ sequence = 0, x = 1000, y = 2000 })
    end
    check(requestCount(f.state) <= 32, "outstanding request journal never exceeds 32")
end
equal(f.state.id, 1, "heartbeat-maintained session survives outstanding interest requests")
equal(f.state.interestSequence, 41, "journal pruning does not reuse sequence numbers")
equal(requestCount(f.state), 32, "journal keeps at most the latest 32 submitted centers")
equal(f.state.interestRequests[9], nil, "oldest overflow request released")
check(
    f.state.interestRequests[10] and f.state.interestRequests[41],
    "latest 32 outstanding centers retained"
)
f.client.stopObserve()
equal(requestCount(f.state), 0, "stop releases outstanding request journal")
equal(f.state.lastAckCenter, nil, "stop releases prediction baseline")
f.origin("bounded request journal")

-- Native recovery refuses prediction beyond bounds; the real client retains
-- the authoritative grant when recovery returns false, never an unsafe view.
f = fixture()
f.loaded, f.terrainReady = true, true
f.start({ mode = "SOFT" })
f.tick(250)
local boundedRequest = copy(f.last("observeInterest").args)
check(f.api.restorePrediction(8, 0), "native SOFT prediction accepts exact target bound")
f.ack({ sequence = boundedRequest.sequence, x = 1007, y = 2000 })
near(
    f.camera.predictionCalls[#f.camera.predictionCalls].x,
    8,
    "client asks to preserve full outstanding offset"
)
near(f.api.getViewX(), 1007, "out-of-bounds recovered view falls back to accepted center")
equal(f.state.id, 1, "rejected prediction does not invalidate an otherwise valid grant")
f.origin("native prediction bounds")

-- Stale/wrong-session packets cannot revive a mode, replace the center, or
-- extend a lease. ACK TTL is remaining milliseconds, not a fresh six seconds.
f = fixture()
f.start({ ttl = 3500 })
equal(f.camera.grantCalls[1].ttl, 3.5, "fractional native TTL seconds forwarded")
equal(f.state.expires, 103500, "Lua lease uses packet's remaining milliseconds")
equal(f.camera.deadline, f.state.expires, "native and Lua lease deadlines agree")
f.tick(1000)
local firstAck = f.ack({ ttl = 2500, revision = 2 })
equal(f.state.expires, 103500, "remaining-TTL ACK preserves initial deadline")
f.tick(1000)
f.ack({ ttl = 1500, revision = 3 })
equal(f.state.expires, 103500, "later remaining-TTL ACK does not renew initial deadline")
local expiry, grantsBefore = f.state.expires, #f.camera.grantCalls
f.ack({ id = 999, revision = 100, mode = "FREE", x = 9999 })
equal(f.state.expires, expiry, "wrong ID cannot change expiry")
equal(#f.camera.grantCalls, grantsBefore, "wrong ID cannot grant native camera")
f.ack({ revision = 1, mode = "FREE", x = 8888 })
equal(f.state.grantRevision, 3, "lower revision ignored")
equal(f.state.mode, "FOLLOW", "lower revision cannot restore stale mode")
equal(f.camera.x, 1000, "lower revision cannot replace stream center")
equal(f.state.expires, expiry, "lower revision cannot extend lease")
equal(#f.camera.grantCalls, grantsBefore, "lower revision cannot grant native camera")
f.receive("observeGrant", firstAck)
equal(f.state.expires, expiry, "old ACK replay ignored")
-- Same-revision duplicate was delivered later with its original remaining TTL.
local duplicate = f.ack({ ttl = 1500, revision = 4 })
expiry, grantsBefore = f.state.expires, #f.camera.grantCalls
f.tick(500)
f.receive("observeGrant", duplicate)
equal(f.state.expires, expiry, "duplicate ACK cannot extend lease indefinitely")
equal(#f.camera.grantCalls, grantsBefore, "duplicate ACK cannot reset native lease")
f.ack({ revision = 1, mode = "INVALID", x = 0 / 0 })
equal(f.state.id, 1, "malformed stale revision ignored before validation")
equal(#f.camera.grantCalls, grantsBefore, "malformed stale packet cannot reach native camera")
f.now = expiry - 1
f.tick()
equal(f.state.id, 1, "session lives until exact lease deadline")
f.tick(1)
equal(f.state.id, nil, "lease expires at exact deadline")
equal(f.count("observeStop"), 1, "lease expiration sends one stop")
check(not f.actor.blocked and ISFastTeleportMove.cheat, "lease expiration restores movement")
f.origin("lease expiration")

-- Every malformed current grant is rejected. Native boundary covers coordinate
-- bounds/z ranges beyond Lua's finite check, without accepting fake assets/APIs.
local malformed = {
    { values = { x = 0 / 0 }, label = "NaN X" },
    { values = { y = math.huge }, label = "infinite Y" },
    { values = { x = "1000" }, label = "numeric-string coordinate" },
    { values = { z = 32 }, label = "unsupported Z" },
    { values = { x = 1000001 }, label = "native coordinate bound" },
    { values = { mode = "INVALID" }, label = "invalid mode" },
    { values = { ttl = 0 }, label = "zero lease" },
    { values = { ttl = "invalid" }, label = "invalid lease" },
    { values = { ttl = math.huge }, label = "infinite lease" },
    { values = { ttl = 0 / 0 }, label = "NaN lease" },
    { values = { revision = 0 }, label = "zero ACK revision" },
    { values = { revision = 1.5 }, label = "fractional ACK revision" },
    { values = { revision = math.huge }, label = "infinite ACK revision" },
    { values = { revision = 0 / 0 }, label = "NaN ACK revision" },
    { values = { sequence = -1 }, label = "negative acknowledged sequence" },
    { values = { sequence = 1.5 }, label = "fractional acknowledged sequence" },
    { values = { sequence = math.huge }, label = "infinite acknowledged sequence" },
}
for _, example in ipairs(malformed) do
    f = fixture()
    f.start()
    f.ack(example.values)
    equal(f.state.id, nil, example.label .. " stops invalid grant")
    equal(f.count("observeStop"), 1, example.label .. " reports one stop")
    check(not f.actor.blocked and ISFastTeleportMove.cheat, example.label .. " restores movement")
    f.origin(example.label)
end
f = fixture()
f.start()
f.tick(250)
f.invalidView = 0 / 0
f.tick(250)
equal(f.count("observeInterest"), 1, "invalid predicted camera coordinate is not sent")
equal(f.state.interestSequence, 1, "invalid camera read does not consume sequence")
f.invalidView = nil
f.tick()
equal(f.count("observeInterest"), 2, "valid camera read resumes promptly after rejected read")
equal(f.state.interestSequence, 2, "resumed interest stays monotonic")
f.ack({ sequence = 20 })
equal(f.state.acknowledgedSequence, 20, "server acknowledged sequence accepted")
f.tick(250)
equal(
    f.last("observeInterest").args.sequence,
    21,
    "interest sequence advances beyond authoritative ACK"
)
f = fixture()
f.start({ ttl = 6000 })
f.now = 105999
f.tick()
equal(f.state.id, 1, "six-second grant remains active at 5.999 seconds")
f.tick(1)
equal(f.state.id, nil, "six-second grant expires at six seconds, not six milliseconds")

-- FOLLOW readiness requires both terrain and target updates. Losing readiness
-- can recover; long loading is bounded despite renewed server permissions.
f = fixture()
f.start()
f.terrainReady = true
f.tick(250)
check(f.state.loadingSince ~= nil, "terrain alone does not resolve FOLLOW loading")
f.loaded = true
f.tick(250)
equal(f.state.loadingSince, nil, "loaded target plus terrain resumes FOLLOW")
check(
    f.state.status:find("locked", 1, true),
    "readiness replaces loading status with mode description"
)
f.target.square = nil
f.tick(250)
equal(f.state.loadingSince, f.now, "loss of target square re-enters loading")
f.target.square = {}
f.tick(250)
equal(f.state.loadingSince, nil, "target-square recovery resumes same session")
equal(f.count("observeStop"), 0, "temporary loading never stops or teleports")
f.origin("readiness recovery")
f = fixture()
f.start()
local loadingStarted = f.state.loadingSince
for _ = 1, 39 do
    f.tick(500)
    f.ack()
    equal(f.state.loadingSince, loadingStarted, "fresh grant does not reset loading timeout")
    equal(f.state.id, 1, "session remains loading before 20 seconds")
end
f.tick(499)
equal(f.state.id, 1, "19.999 seconds remains loading")
f.tick(1)
equal(f.state.id, nil, "20-second loading timeout stops active session")
check(f.state.status:find("timed out", 1, true), "loading timeout tells user why camera ended")
equal(f.count("observeStop"), 1, "loading timeout sends one stop")
equal(f.count("observeTeleportPrepare"), 0, "loading timeout never auto-teleports")
equal(f.count("observeTeleport"), 0, "loading timeout never moves actor")
check(not f.actor.blocked and ISFastTeleportMove.cheat, "loading timeout restores input")
equal(f.state.interestSequence, 0, "loading timeout clears sequencing")
equal(f.state.grantRevision, 0, "loading timeout clears ACK revision")
for _, id in ipairs({
    "observer.facing",
    "observer.safehouses",
    "observer.community",
    "observer.towns",
    "observer.properties",
}) do
    equal(f.overlays[id], false, "loading timeout clears " .. id)
end
f.origin("loading timeout")

-- Existing explicit movement requires user confirmation and a matching,
-- unexpired prepare ticket; camera detaches before sending actual movement.
f = fixture()
f.start({ hasReturn = true, returnId = "saved-origin" })
f.client.observerTeleport()
equal(f.count("observeTeleportPrepare"), 0, "Teleport waits for explicit confirmation")
check(
    f.confirmQuestion:find("Teleport your character", 1, true),
    "confirmation describes character movement"
)
f.confirm()
equal(f.count("observeTeleportPrepare"), 1, "confirmed Teleport requests ticket")
local pending = f.state.teleportPending
f.receive("observeTeleportReady", { request = "stale", username = "remote", ticket = "wrong" })
equal(f.state.teleportPending, pending, "wrong request ticket ignored")
f.receive(
    "observeTeleportReady",
    { request = pending.request, username = "other", ticket = "wrong" }
)
equal(f.count("observeTeleport"), 0, "wrong target ticket ignored")
f.receive(
    "observeTeleportReady",
    { request = pending.request, username = "remote", ticket = "ticket-one" }
)
equal(f.state.id, nil, "explicit Teleport stops observation")
equal(f.state.teleportPending, nil, "explicit Teleport consumes pending request")
equal(f.count("observeStop"), 1, "explicit Teleport tells server to detach camera")
equal(f.count("observeTeleport"), 1, "explicit Teleport sends one authorized movement command")
equal(f.last("observeTeleport").args.ticket, "ticket-one", "movement uses server-issued ticket")
check(
    not f.actor.blocked and ISFastTeleportMove.cheat,
    "movement command sent after input restored"
)
equal(f.commands[#f.commands - 1].command, "observeStop", "detach command precedes Teleport")
f.receive(
    "observeTeleportReady",
    { request = pending.request, username = "remote", ticket = "ticket-one" }
)
equal(f.count("observeTeleport"), 1, "replayed ticket does not issue another movement command")
f.origin("client explicit movement delegation")
f.client.observerReturn()
equal(f.count("observeReturn"), 1, "explicit Return retained")
equal(f.last("observeReturn").args.id, "saved-origin", "Return uses retained saved-origin ID")

f = fixture()
f.start()
f.client.observerTeleport()
f.confirm()
pending = f.state.teleportPending
f.now = pending.expires
f.receive(
    "observeTeleportReady",
    { request = pending.request, username = "remote", ticket = "expired" }
)
equal(f.count("observeTeleport"), 0, "expired ticket cannot issue movement")
f.tick()
equal(f.state.teleportPending, nil, "expired prepare request cleared on tick")
f = fixture()
f.start()
f.client.observerTeleport()
f.confirm()
pending = f.state.teleportPending
f.client.selectObserver("other")
f.receive(
    "observeTeleportReady",
    { request = pending.request, username = "remote", ticket = "cancelled" }
)
equal(f.count("observeTeleport"), 0, "selection change cancels prepared movement")
equal(f.state.id, 1, "selection change does not silently end camera")
f.client.observerTeleport()
f.confirm()
f.fire("OnKeyPressed", Keyboard.KEY_ESCAPE)
equal(f.state.teleportPending, nil, "Escape cancels pending Teleport")
equal(f.state.id, 1, "first Escape cancelling Teleport leaves observer active")
f.fire("OnKeyPressed", Keyboard.KEY_ESCAPE)
equal(f.state.id, nil, "next Escape stops observation")

-- Disconnect/menu teardown, server stop and revoked permission clean local
-- state. Wrong session/stale start cannot replace the currently active session.
f = fixture()
f.start({ id = 20, hasReturn = true, returnId = "saved-origin" })
f.receive("observeStopped", { id = 19, reason = "stale stop" })
equal(f.state.id, 20, "wrong-session stop ignored")
f.client.startObserver("remote")
f.receive("observeStarted", { id = 19, username = "remote", ttl = 6000 })
equal(f.state.id, 20, "stale start ID ignored")
equal(f.state.pending, "remote", "stale start does not consume pending selection")
local removed = 0
f.client.observePanel = {
    removeFromUIManager = function()
        removed = removed + 1
    end,
}
f.fire("OnDisconnect")
equal(f.state.id, nil, "disconnect clears active ID")
equal(f.state.pending, nil, "disconnect clears pending start")
equal(f.state.returnId, nil, "disconnect clears return marker")
equal(f.state.lastId, 0, "disconnect allows IDs from next server")
equal(f.state.selected, nil, "disconnect clears selection")
equal(f.client.observing, nil, "disconnect clears shared observing marker")
equal(f.client.observePanel, nil, "disconnect drops panel")
equal(removed, 1, "disconnect removes panel from native UI manager")
equal(f.keepAlive.observer, false, "disconnect releases permissions keep-alive")
check(not f.actor.blocked and ISFastTeleportMove.cheat, "disconnect restores movement state")
f.origin("disconnect")
f.fire("OnMainMenuEnter")
equal(removed, 1, "menu cleanup remains safe after disconnect")
for _, change in ipairs({ "authority", "dead", "camera" }) do
    f = fixture()
    f.start()
    if change == "authority" then
        f.authority = false
    elseif change == "dead" then
        f.actor.dead = true
    else
        f.api.stop()
    end
    f.tick(1)
    equal(f.state.id, nil, change .. " loss stops camera session")
    equal(f.count("observeStop"), 1, change .. " loss notifies server exactly once")
    check(not f.actor.blocked and ISFastTeleportMove.cheat, change .. " loss restores input")
    f.tick(1000)
    equal(f.count("observeStop"), 1, change .. " loss cannot repeat stop every frame")
end

-- Reload guard must not register duplicate listeners or reset live state.
f = fixture()
f.start()
local state, listeners = f.state, #f.events.OnServerCommand.handlers
dofile(root .. "/media/lua/client/AdminCore/ObserverClient.lua")
equal(AdminCore.observer, state, "reload preserves live observer state")
equal(#f.events.OnServerCommand.handlers, listeners, "reload does not duplicate server handlers")
equal(#f.events.OnTick.handlers, 1, "reload does not duplicate tick handlers")
equal(#f.events.OnKeyPressed.handlers, 1, "reload does not duplicate key handlers")
f.receive("observeGrant", { id = 1 }, "DifferentMod")
equal(f.state.id, 1, "unrelated module packet ignored")
f.receive("observeGrant", "malformed")
equal(f.state.id, 1, "non-table packet ignored")
-- Relative SOFT offsets preserve only unsent keyboard movement. Native target
-- interpolation between the request and reply must never become extra pan.
f = fixture()
f.loaded = true
f.requestedRadius = 7
f.start({ mode = "SOFT", offsetX = 0, offsetY = 0, chunkRadius = 5 })
equal(f.last("observeStart").args.chunkRadius, 7, "start requests viewport radius")
equal(f.camera.radius, 5, "server radius controls native loading")
f.now = f.now + 250
check(f.api.pan(2, 0), "initial soft pan")
check(f.client.sendObserverInterest(), "soft interest submitted")
local sent = f.last("observeInterest").args
equal(sent.offsetX, 2, "request contains relative pan")
equal(sent.chunkRadius, 7, "interest requests changed viewport radius")
check(f.api.pan(0.5, 0), "post-request soft pan")
f.target.x = f.target.x + 4
f.ack({ mode = "SOFT", x = 1006, offsetX = 2, offsetY = 0, chunkRadius = 7 })
near(
    f.api.getViewX(),
    1006.5,
    "ACK preserves target interpolation plus only the extra keyboard pan"
)
near(f.api.getFollowOffsetX(), 2.5, "target movement is not replayed as pan")
equal(f.camera.radius, 7, "ACK expands native region")
f.target.x = f.target.x + 3
f.ack({ mode = "SOFT", x = 1009, offsetX = 2, offsetY = 0, chunkRadius = 7 })
near(f.api.getViewX(), 1009.5, "heartbeat keeps pending pan without accumulating target movement")
f.ack({ mode = "SOFT", x = 1009, offsetX = 2, offsetY = 0, message = "Denied", chunkRadius = 5 })
near(f.api.getFollowOffsetX(), 2, "denied movement discards prediction")
equal(f.camera.radius, 5, "denied reply uses retained authorized radius")
f.origin("relative soft follow")
for _, radius in ipairs({ 2, 10, 3.5 }) do
    f = fixture()
    f.start({ chunkRadius = radius })
    equal(f.state.id, nil, "invalid radius fails closed")
end
print("PASS " .. checks .. " Observer streaming client checks")
