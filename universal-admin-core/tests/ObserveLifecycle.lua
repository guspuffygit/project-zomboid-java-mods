-- Drive real client and server handlers with crafted, stale and replayed packets.
local root = arg[2] or "universal-admin-core"
require = function() end
local checks = 0
local function check(value, message)
    assert(value, message)
    checks = checks + 1
end
local function events()
    return setmetatable({}, {
        __index = function(t, key)
            local event = { handlers = {} }
            event.Add = function(fn)
                event.handlers[#event.handlers + 1] = fn
            end
            rawset(t, key, event)
            return event
        end,
    })
end
local now, authority, render, loaded = 100000, true, true, true
local returnCapability, returnBridgeWorks = true, true
local grants = true
getTimestampMs = function()
    return now
end
getTimestamp = function()
    return math.floor(now / 1000)
end
Capability = setmetatable({}, {
    __index = function(_, key)
        return key
    end,
})
Keyboard = { KEY_ESCAPE = 1, KEY_F = 33 }
isKeyDown = function()
    return false
end
ISFastTeleportMove = { cheat = true }
local function player(name, x)
    return {
        name = name,
        x = x,
        y = 20,
        z = 0,
        dead = false,
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
        getVehicle = function(self)
            return self.vehicle
        end,
        getCurrentSquare = function()
            return loaded and {} or nil
        end,
        getRole = function()
            return {
                hasAdminPower = function()
                    return authority
                end,
                hasCapability = function(_, cap)
                    return authority
                        and (cap ~= "UseDebugContextMenu" or render)
                        and (cap ~= "TeleportToCoordinates" or returnCapability)
                end,
            }
        end,
    }
end
local actor, guest, other = player("admin", 10), player("guest", 100), player("guest-two", 200)
local online = { actor, guest, other }
local byName = { admin = actor, guest = guest, ["guest-two"] = other }
getPlayer = function()
    return actor
end
getPlayerFromUsername = function(name)
    return loaded and byName[name] or nil
end
getOnlinePlayers = function()
    return {
        size = function()
            return #online
        end,
        get = function(_, i)
            return online[i + 1]
        end,
    }
end
local persisted = {}
ModData = {
    getOrCreate = function(key)
        persisted[key] = persisted[key] or {}
        return persisted[key]
    end,
}
isServer = function()
    return true
end
dofile(root .. "/media/lua/shared/AdminCore/OperationsPermissions.lua")
local audits = {}
AdminOperations.audit = function(event, p, detail)
    audits[#audits + 1] = { event = event, name = p:getUsername(), detail = detail }
end
local toServer, toClient = {}, {}
local sends, teleports, returns = 0, 0, 0
local lastTicket, lastMovementCamera
local function wire(args)
    if type(args) ~= "table" then
        return args
    end
    for _ in pairs(args) do
        return args
    end
    return nil
end
sendClientCommand = function(module, command, args)
    toServer[#toServer + 1] = { module = module, command = command, args = wire(args) }
end
sendServerCommand = function(p, module, command, args)
    if command == "observeTeleportReady" then
        lastTicket = args.ticket
    end
    toClient[#toClient + 1] = { module = module, command = command, args = wire(args) }
end
local camera, blocked, oldBlock, weather, lease = nil, false, false, false, 0
AdminCoreObserveCamera = {
    grant = function(name, allow)
        if not camera then
            oldBlock = blocked
        end
        blocked = true
        camera = name
        lease = now + 6000
        if not allow then
            weather = false
        end
        return true
    end,
    active = function()
        return camera ~= nil and now < lease
    end,
    stop = function()
        camera = nil
        blocked = oldBlock
        weather = false
    end,
    setMode = function()
        return camera ~= nil
    end,
    pan = function()
        return true
    end,
    setHideWeather = function(value)
        weather = value
    end,
}
AdminCore = {
    allowed = function()
        return false
    end,
    message = function() end,
    confirm = function(_, callback)
        callback()
    end,
    operationsAllowed = function(key)
        return grants and AdminOperations.authorized(actor, key)
    end,
    requestOperations = function() end,
    operationsKeepAlive = function() end,
}
AdminOverlayManager = { enableOverlay = function() end }
Events = events()
dofile(root .. "/media/lua/client/AdminCore/ObserverClient.lua")
dofile(root .. "/media/lua/client/AdminCore/DataAndObserve.lua")
local clientEvents = Events
AdminCore.openObserverPanel = function() end
AdminCoreObserverBridge = {
    target = function(p, name)
        return authority and byName[name] or nil
    end,
    teleportTo = function(p, name)
        local target = byName[name]
        if not authority or not target then
            return false
        end
        teleports = teleports + 1
        lastMovementCamera = camera
        p.x = target.x
        p.y = target.y
        p.z = target.z
        return true
    end,
    returnTo = function(p, x, y, z)
        if not authority or not returnBridgeWorks then
            return false
        end
        returns = returns + 1
        lastMovementCamera = camera
        p.x = x
        p.y = y
        p.z = z
        return true
    end,
}
Events = events()
dofile(root .. "/media/lua/server/AdminCore/ObserverServer.lua")
local function drain(dropGrants)
    for _ = 1, 20 do
        if #toServer == 0 and #toClient == 0 then
            return
        end
        while #toServer > 0 do
            local p = table.remove(toServer, 1)
            AdminObserverServer.onCommand(p.module, p.command, actor, p.args)
        end
        while #toClient > 0 do
            local p = table.remove(toClient, 1)
            if not (dropGrants and p.command == "observeGrant") then
                for _, fn in ipairs(clientEvents.OnServerCommand.handlers) do
                    fn(p.module, p.command, p.args)
                end
            end
        end
    end
    error("Unexpected command echo loop")
end
local function advance(ms, client, dropGrants)
    now = now + ms
    if client ~= false then
        for _, fn in ipairs(clientEvents.OnTick.handlers) do
            fn()
        end
    end
    drain(dropGrants)
    AdminObserverServer.tick()
    drain(dropGrants)
end
local function start(name)
    now = now + 600
    AdminCore.startObserver(name or "guest")
    drain()
end
authority = false
AdminObserverServer.onCommand("UniversalAdminCore", "observeStart", actor, { username = "guest" })
check(
    #toClient == 1 and toClient[1].command == "observeActionResult" and teleports == 0,
    "Crafted outsider observe start gets denial feedback, never a grant or movement"
)
AdminObserverServer.onCommand("UniversalAdminCore", "observeTeleport", actor, { id = "1" })
AdminObserverServer.onCommand("UniversalAdminCore", "observeReturn", actor, { id = "1", x = 9999 })
check(teleports == 0 and returns == 0, "Crafted unauthorized movement commands do nothing")
authority = true
start()
check(
    AdminCore.observing == "guest" and camera == "guest" and blocked,
    "Authorized start grants camera and captures movement block"
)
check(actor.x == 10 and teleports == 0, "Starting observation leaves the avatar in place")
check(
    not ISFastTeleportMove.cheat,
    "Vanilla fast-teleport input is suspended while camera-only observation is active"
)
for _ = 1, 120 do
    advance(1000)
    check(
        AdminCore.observing == "guest" and actor.x == 10,
        "Heartbeat renews camera without teleporting the admin"
    )
end
AdminCore.observerMode("SOFT")
AdminCore.observerMode("FREE")
check(actor.x == 10 and teleports == 0, "Free and soft modes never mutate server position")
local oldId = AdminCore.observer.id
start("guest-two")
check(
    AdminCore.observing == "guest-two" and AdminCore.observer.id ~= oldId,
    "Target changes keep persistent observation active"
)
for _, fn in ipairs(clientEvents.OnServerCommand.handlers) do
    fn("UniversalAdminCore", "observeStopped", { id = oldId })
    fn(
        "UniversalAdminCore",
        "observeGrant",
        { id = oldId, username = "guest", ttl = 6000, render = true }
    )
end
check(
    AdminCore.observing == "guest-two",
    "Stale stop and grant acknowledgements cannot change new target"
)
local cloned = player("admin", 700)
AdminObserverServer.onCommand(
    "UniversalAdminCore",
    "observeStop",
    cloned,
    { id = AdminCore.observer.id }
)
drain()
check(
    AdminCore.observing == "guest-two",
    "Second session with same account cannot stop the first session"
)
AdminCore.observerWeather(true)
check(weather, "Authorized visual filter starts")
render = false
advance(2000)
check(
    not weather and not AdminCore.observer.render,
    "Server rechecks render permission on heartbeat and clears filters"
)
render = true
AdminCore.stopObserve()
drain()
check(
    camera == nil and not blocked and actor.x == 10,
    "Stop restores camera/input without moving character"
)
check(ISFastTeleportMove.cheat, "Pre-existing fast-teleport input setting is restored")
blocked = true
start()
AdminCore.stopObserve()
drain()
check(blocked, "Existing movement block is preserved after observer cleanup")
blocked = false
start()
local teleportId = AdminCore.observer.id
AdminCore.observerTeleport()
drain()
check(
    actor.x == 100 and teleports == 1 and not AdminCore.observer.id and not blocked,
    "Explicit teleport exits camera and moves once"
)
local returnId = AdminCore.observer.returnId
check(returnId ~= nil, "Server preserves authorized original-position return")
AdminObserverServer.onCommand("UniversalAdminCore", "observeTeleport", actor, { id = teleportId })
drain()
check(teleports == 1, "Teleport replay cannot move again")
now = now + 600
AdminObserverServer.onCommand(
    "UniversalAdminCore",
    "observeReturn",
    actor,
    { id = returnId, x = 9999, y = 9999, z = 9 }
)
drain()
check(
    actor.x == 10 and returns == 1 and AdminCore.observer.returnId == nil,
    "Return ignores forged coordinates and consumes server origin"
)
now = now + 600
AdminObserverServer.onCommand("UniversalAdminCore", "observeReturn", actor, { id = returnId })
drain()
check(returns == 1, "Return replay cannot move again")
start()
authority = false
advance(2000)
check(
    not camera and not blocked and not AdminCore.observer.id,
    "Revocation removes camera grant without restart"
)
authority = true
start()
byName.guest = player("guest", 400)
advance(2000)
check(
    not camera and not AdminCore.observer.id,
    "Character identity changes terminate old target session"
)
byName.guest = guest
start()
for _ = 1, 7 do
    advance(1000, true, true)
end
check(
    not camera and not blocked and not AdminCore.observer.id,
    "Lost server grant responses expire camera locally"
)
start()
local last = teleports
loaded = false
advance(1000)
check(not camera and teleports == last, "Leaving loaded cells never triggers automatic teleports")
loaded = true
start()
for _, fn in ipairs(clientEvents.OnKeyPressed.handlers) do
    fn(Keyboard.KEY_ESCAPE)
end
drain()
check(not camera and not blocked, "Escape restores original camera and movement")
start()
for _, fn in ipairs(clientEvents.OnDisconnect.handlers) do
    fn()
end
online = {}
advance(2000, false)
check(
    not camera and not blocked and not AdminCore.observer.id,
    "Disconnect cleanup is immediate and independent of server delivery"
)
online = { actor, guest, other }
now = now + 2000
ModData.getOrCreate("UniversalAdminCore.Playtime.v1").admin =
    { returnPosition = { x = 7, y = 8, z = 0 } }
AdminObserverServer.onCommand("UniversalAdminCore", "observeStatus", actor, {})
drain()
check(
    AdminCore.observer.returnId ~= nil and actor.x == 10,
    "Old return markers migrate to explicit Return without automatic character movement"
)
check(
    ModData.getOrCreate("UniversalAdminCore.Playtime.v1").admin.returnPosition == nil,
    "Legacy return marker is consumed, not left dormant"
)
check(#audits > 10, "Meaningful starts, ends and teleports are audited")
-- Clear the migrated origin, then exercise the standalone menu workflow.
AdminCore.observerReturn()
drain()
check(
    actor.x == 7 and actor.y == 8 and AdminCore.observer.returnId == nil,
    "Return succeeds without active spectating and clears the button"
)
actor.x, actor.y = 10, 20
AdminCore.selectObserver("guest-two")
now = now + 1000
AdminCore.observerTeleport()
local pendingCount = #toServer
AdminCore.observerTeleport()
check(
    #toServer == pendingCount,
    "Repeated click while prepare is pending does not create duplicate teleport requests"
)
drain()
check(
    actor.x == 200 and teleports == 2 and not AdminCore.observer.id,
    "Teleport uses the selected player without an observation session"
)
check(
    lastMovementCamera == nil,
    "Camera is detached before the native teleport packet is requested"
)
local menuOrigin = AdminCore.observer.returnId
now = now + 1000
AdminObserverServer.onCommand(
    "UniversalAdminCore",
    "observeTeleport",
    actor,
    { ticket = lastTicket }
)
drain()
check(teleports == 2, "Consumed standalone teleport ticket cannot be replayed")
now = now + 1000
AdminCore.selectObserver("guest")
AdminCore.observerTeleport()
drain()
check(
    actor.x == 100 and AdminCore.observer.returnId == menuOrigin,
    "Further selected-player teleports preserve the first server-owned origin"
)
returnCapability = false
AdminCore.observerReturn()
drain()
check(
    actor.x == 100
        and AdminCore.observer.status:find("role", 1, true)
        and AdminCore.observer.returnId == menuOrigin,
    "Missing coordinate capability explains denial and retains origin"
)
returnCapability = true
actor.vehicle = {}
now = now + 1000
AdminCore.observerReturn()
drain()
check(
    actor.x == 100 and AdminCore.observer.status:find("vehicle", 1, true),
    "Return while in a vehicle gives useful server feedback"
)
actor.vehicle = nil
returnBridgeWorks = false
now = now + 1000
AdminCore.observerReturn()
drain()
check(
    actor.x == 100
        and AdminCore.observer.returnId == menuOrigin
        and AdminCore.observer.status:find("saved origin was kept", 1, true),
    "Native Return refusal preserves recovery origin and explains the failure"
)
returnBridgeWorks = true
now = now + 1000
AdminCore.observerReturn()
drain()
check(
    actor.x == 10 and actor.y == 20 and AdminCore.observer.returnId == nil,
    "Return uses server origin and explicit hasReturn=false clears UI"
)
AdminCore.observer.returnId = "stale-client-marker"
for _, fn in ipairs(clientEvents.OnServerCommand.handlers) do
    fn("UniversalAdminCore", "observeStatus", nil)
end
check(
    AdminCore.observer.returnId == nil,
    "Native empty-table to nil wire encoding clears stale Return state"
)
now = now + 1000
AdminObserverServer.onCommand(
    "UniversalAdminCore",
    "observeTeleportPrepare",
    actor,
    { username = "guest", request = "captured-target" }
)
local captured = lastTicket
toClient = {}
byName.guest = player("guest", 900)
now = now + 1000
AdminObserverServer.onCommand("UniversalAdminCore", "observeTeleport", actor, { ticket = captured })
drain()
check(
    actor.x == 10
        and teleports == 3
        and AdminCore.observer.status:find("changed character", 1, true),
    "Prepared target identity changes cannot redirect a stale ticket"
)
byName.guest = guest
now = now + 1000
AdminObserverServer.onCommand(
    "UniversalAdminCore",
    "observeTeleportPrepare",
    actor,
    { username = "guest", request = "captured-actor" }
)
captured = lastTicket
toClient = {}
now = now + 1000
AdminObserverServer.onCommand(
    "UniversalAdminCore",
    "observeTeleport",
    cloned,
    { ticket = captured }
)
drain()
check(
    cloned.x == 700 and actor.x == 10 and teleports == 3,
    "A second account session cannot use the first actor's movement ticket"
)
now = now + 16000
AdminObserverServer.onCommand("UniversalAdminCore", "observeTeleport", actor, { ticket = captured })
drain()
check(
    actor.x == 10 and teleports == 3 and AdminCore.observer.status:find("expired", 1, true),
    "Expired movement tickets cannot move and give useful feedback"
)
now = now + 1000
AdminObserverServer.onCommand(
    "UniversalAdminCore",
    "observeTeleportPrepare",
    actor,
    { username = "guest", request = "revoked-ticket" }
)
captured = lastTicket
toClient = {}
authority = false
now = now + 1000
AdminObserverServer.onCommand("UniversalAdminCore", "observeTeleport", actor, { ticket = captured })
drain()
check(
    actor.x == 10 and teleports == 3,
    "Permission revocation after preparing a ticket still blocks actual movement"
)
authority = true
now = now + 1000
AdminObserverServer.onCommand(
    "UniversalAdminCore",
    "observeTeleportPrepare",
    actor,
    { username = "guest", request = "vehicle-ticket" }
)
captured = lastTicket
toClient = {}
actor.vehicle = {}
now = now + 1000
AdminObserverServer.onCommand("UniversalAdminCore", "observeTeleport", actor, { ticket = captured })
drain()
check(
    actor.x == 10 and teleports == 3 and AdminCore.observer.status:find("vehicle", 1, true),
    "Entering a vehicle after preparation is rechecked at the actual teleport"
)
actor.vehicle = nil
now = now + 1000
AdminObserverServer.onCommand("UniversalAdminCore", "observeReturn", actor, { id = "already-used" })
drain()
check(
    AdminCore.observer.returnId == nil and AdminCore.observer.status:find("no matching", 1, true),
    "Expired or used Return requests clear stale state with feedback"
)
-- Remote streaming bridge contract: real server handler, isolated native lease boundary.
local nativeReady, nativeLease, interestCalls = false, nil, 0
AdminCoreObserverInterest = {
    ready = function()
        return nativeReady
    end,
    startWithRadius = function(p, target, id, mode, radius)
        if not authority or not render then
            return false
        end
        nativeLease = {
            actor = p,
            target = target,
            id = id,
            mode = mode,
            radius = radius,
            offsetX = 0,
            offsetY = 0,
            sequence = 0,
            expires = now + 6000,
        }
        return true
    end,
    stop = function(p, id)
        if nativeLease and nativeLease.actor == p and nativeLease.id == id then
            nativeLease = nil
        end
    end,
    remaining = function()
        return nativeLease and authority and render and math.max(0, nativeLease.expires - now) or 0
    end,
    renew = function()
        if not nativeLease or not authority or not render or now >= nativeLease.expires then
            return false
        end
        nativeLease.expires = now + 6000
        return true
    end,
    coordinate = function(_, _, axis)
        return axis == 0 and guest.x + nativeLease.offsetX
            or axis == 1 and guest.y + nativeLease.offsetY
            or guest.z
    end,
    radius = function()
        return nativeLease and nativeLease.radius or 0
    end,
    offset = function(_, _, axis)
        return axis == 0 and nativeLease.offsetX or nativeLease.offsetY
    end,
    sequence = function()
        return nativeLease.sequence
    end,
    mode = function()
        return nativeLease.mode
    end,
    moveWithRadius = function(_, _, sequence, mode, _, _, _, radius)
        interestCalls = interestCalls + 1
        if not nativeLease or sequence <= nativeLease.sequence then
            return false
        end
        nativeLease.sequence = sequence
        nativeLease.mode = mode
        nativeLease.radius = radius
        nativeLease.offsetX, nativeLease.offsetY = 0, 0
        return true
    end,
    moveSoft = function(_, _, sequence, offsetX, offsetY, radius)
        interestCalls = interestCalls + 1
        if not nativeLease or sequence <= nativeLease.sequence then
            return false
        end
        nativeLease.sequence = sequence
        nativeLease.mode = "SOFT"
        nativeLease.offsetX, nativeLease.offsetY = offsetX, offsetY
        nativeLease.radius = radius
        return true
    end,
}
toServer, toClient = {}, {}
now = now + 1000
AdminObserverServer.onCommand("UniversalAdminCore", "observeStart", actor, { username = "guest" })
check(
    #toClient == 1 and toClient[1].command == "result" and nativeLease == nil,
    "Partially installed native streaming fails closed instead of advertising stream support"
)
nativeReady = true
render = true
authority = true
online = { actor, guest, other }
toClient = {}
now = now + 1000
AdminObserverServer.onCommand(
    "UniversalAdminCore",
    "observeStart",
    actor,
    { username = "guest", mode = "FOLLOW" }
)
local firstGrant = toClient[#toClient].args
check(
    firstGrant.stream
        and firstGrant.chunkRadius == 3
        and firstGrant.x == guest.x
        and firstGrant.y == guest.y
        and firstGrant.sequence == 0
        and firstGrant.revision == 1,
    "Native ready grant carries server-derived center, bounded region, sequence and revision"
)
local remoteId = firstGrant.id
now = now + 250
toClient = {}
AdminObserverServer.onCommand(
    "UniversalAdminCore",
    "observeInterest",
    actor,
    { id = remoteId, sequence = 1, mode = "FREE", x = guest.x, y = guest.y, z = guest.z }
)
local interestGrant = toClient[#toClient].args
check(
    interestGrant.mode == "FREE" and interestGrant.sequence == 1 and interestGrant.revision == 2,
    "Accepted mode change is acknowledged with increasing revision"
)
check(
    interestGrant.ttl == 5750 and nativeLease.expires == now + 5750,
    "Interest acknowledgment reports remaining TTL without renewing native lease"
)
now = now + 250
toClient = {}
AdminObserverServer.onCommand(
    "UniversalAdminCore",
    "observeInterest",
    actor,
    { id = remoteId, sequence = 1, mode = "FREE", x = guest.x, y = guest.y, z = guest.z }
)
local rejectedGrant = toClient[#toClient].args
check(
    rejectedGrant.sequence == 1 and rejectedGrant.revision == 3 and rejectedGrant.message,
    "Rejected replay keeps accepted sequence but advances reply revision and explains rejection"
)
local beforeInterest = interestCalls
now = now + 250
toClient = {}
AdminObserverServer.onCommand(
    "UniversalAdminCore",
    "observeInterest",
    actor,
    { id = remoteId, sequence = 1.5, mode = "FREE", x = guest.x, y = guest.y, z = guest.z }
)
check(
    interestCalls == beforeInterest and toClient[#toClient].args.message,
    "Fractional interest sequence never reaches native bridge"
)
toClient = {}
now = now + 250
AdminObserverServer.onCommand(
    "UniversalAdminCore",
    "observeInterest",
    actor,
    { id = "forged", sequence = 99, mode = "FREE", x = 99999, y = 99999, z = 0 }
)
AdminObserverServer.onCommand(
    "UniversalAdminCore",
    "observeInterest",
    cloned,
    { id = remoteId, sequence = 99, mode = "FREE", x = 99999, y = 99999, z = 0 }
)
check(
    #toClient == 0 and interestCalls == beforeInterest,
    "Forged session or replacement actor cannot widen interest"
)
now = now + 1000
AdminObserverServer.onCommand("UniversalAdminCore", "observeHeartbeat", actor, { id = remoteId })
check(
    toClient[#toClient].args.ttl == 6000
        and toClient[#toClient].args.revision > rejectedGrant.revision,
    "Authorized heartbeat alone renews lease and carries newer reply revision"
)
render = false
now = now + 250
toClient = {}
AdminObserverServer.onCommand(
    "UniversalAdminCore",
    "observeInterest",
    actor,
    { id = remoteId, sequence = 2, mode = "FOLLOW", x = guest.x, y = guest.y, z = guest.z }
)
check(
    nativeLease == nil and toClient[#toClient].command == "observeStopped",
    "Render permission revocation stops remote interest independently of spectator role"
)
render = true
now = now + 1000
toClient = {}
AdminObserverServer.onCommand("UniversalAdminCore", "observeStart", actor, { username = "guest" })
remoteId = toClient[#toClient].args.id
now = now + 6001
toClient = {}
AdminObserverServer.onCommand("UniversalAdminCore", "observeHeartbeat", actor, { id = remoteId })
check(
    nativeLease == nil and toClient[#toClient].command == "observeStopped",
    "Expired native lease cannot be revived by a late heartbeat"
)
now = now + 1000
toClient = {}
AdminObserverServer.onCommand(
    "UniversalAdminCore",
    "observeStart",
    actor,
    { username = "guest", mode = "SOFT", chunkRadius = 7 }
)
remoteId = toClient[#toClient].args.id
check(
    nativeLease.radius == 7
        and toClient[#toClient].args.chunkRadius == 7
        and toClient[#toClient].args.offsetX == 0
        and toClient[#toClient].args.offsetY == 0,
    "Requested viewport radius and relative SOFT offsets are acknowledged by the server"
)
for _, invalidRadius in ipairs({ 2, 10, 3.5, math.huge, 0 / 0, "9", false }) do
    now = now + 600
    toClient = {}
    AdminObserverServer.onCommand(
        "UniversalAdminCore",
        "observeStart",
        actor,
        { username = "guest", chunkRadius = invalidRadius }
    )
    check(
        nativeLease.id == remoteId
            and nativeLease.radius == 7
            and toClient[#toClient].command == "result",
        "Invalid start radius leaves the previous authorized session intact"
    )
end
now = now + 250
toClient = {}
local leaseExpiry = nativeLease.expires
guest.x = guest.x + 20
AdminObserverServer.onCommand("UniversalAdminCore", "observeInterest", actor, {
    id = remoteId,
    sequence = 1,
    mode = "SOFT",
    x = guest.x - 20,
    y = guest.y,
    z = guest.z,
    offsetX = 2,
    offsetY = -3,
    chunkRadius = 9,
})
local softGrant = toClient[#toClient].args
check(
    softGrant.x == guest.x + 2
        and softGrant.y == guest.y - 3
        and softGrant.offsetX == 2
        and softGrant.offsetY == -3
        and softGrant.chunkRadius == 9
        and softGrant.sequence == 1
        and not softGrant.message,
    "Moving target position is resolved server-side instead of becoming extra SOFT pan"
)
check(nativeLease.expires == leaseExpiry, "Radius and offset changes do not renew the lease")
now = now + 1000
guest.x = guest.x + 10
AdminObserverServer.onCommand("UniversalAdminCore", "observeHeartbeat", actor, { id = remoteId })
check(
    toClient[#toClient].args.x == guest.x + 2
        and toClient[#toClient].args.offsetX == 2
        and toClient[#toClient].args.chunkRadius == 9,
    "Heartbeat keeps accepted radius and pan offsets while following target motion"
)
for _, invalidRadius in ipairs({ 2, 10, 3.5, math.huge, 0 / 0, "9", false }) do
    now = now + 250
    toClient = {}
    beforeInterest = interestCalls
    AdminObserverServer.onCommand("UniversalAdminCore", "observeInterest", actor, {
        id = remoteId,
        sequence = 2,
        mode = "SOFT",
        x = guest.x,
        y = guest.y,
        z = guest.z,
        offsetX = 0,
        offsetY = 0,
        chunkRadius = invalidRadius,
    })
    check(
        interestCalls == beforeInterest
            and toClient[#toClient].args.message
            and toClient[#toClient].args.chunkRadius == 9
            and toClient[#toClient].args.offsetX == 2,
        "Rejected viewport request reports the retained authoritative radius and offsets"
    )
end
for _, offsets in ipairs({ { 8.1, 0 }, { 0, -8.1 }, { math.huge, 0 }, { 0 / 0, 0 }, { 0 } }) do
    now = now + 250
    toClient = {}
    beforeInterest = interestCalls
    AdminObserverServer.onCommand("UniversalAdminCore", "observeInterest", actor, {
        id = remoteId,
        sequence = 2,
        mode = "SOFT",
        x = guest.x,
        y = guest.y,
        z = guest.z,
        offsetX = offsets[1],
        offsetY = offsets[2],
    })
    check(
        interestCalls == beforeInterest
            and toClient[#toClient].args.message
            and toClient[#toClient].args.sequence == 1,
        "Invalid or incomplete relative offsets do not reach native movement"
    )
end
now = now + 250
toClient = {}
AdminObserverServer.onCommand(
    "UniversalAdminCore",
    "observeInterest",
    actor,
    { id = remoteId, sequence = 2, mode = "FOLLOW", x = guest.x, y = guest.y, z = guest.z }
)
check(
    toClient[#toClient].args.sequence == 2
        and toClient[#toClient].args.chunkRadius == 9
        and toClient[#toClient].args.offsetX == 0
        and not toClient[#toClient].args.message,
    "Legacy interest fields preserve accepted radius and still change modes"
)
now = now + 1000
toClient = {}
AdminObserverServer.onCommand("UniversalAdminCore", "observeStart", actor, { username = "guest" })
online = { guest, other }
now = now + 2001
AdminObserverServer.tick()
check(nativeLease == nil, "Disconnect cleanup clears separate server interest")
print("PASS: " .. checks .. " observer authorization, replay, camera-only and cleanup checks")
