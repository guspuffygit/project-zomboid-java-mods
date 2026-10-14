require("AdminCore/OperationsClient")
require("AdminCore/OverlayManager")
local C = AdminCore
if C.observerInstalled then
    return
end
C.observerInstalled = true
C.observer = {
    mode = "FOLLOW",
    status = "Choose an online player. Camera only; your character stays in place.",
    roster = {},
    expires = 0,
    lastHeartbeat = 0,
    lastRoster = 0,
    lastPan = 0,
    lastId = 0,
    lastInterest = 0,
    interestSequence = 0,
    acknowledgedSequence = 0,
    grantRevision = 0,
    query = "",
    filter = "All",
    facing = true,
    safehouses = false,
    info = false,
    weather = false,
}
local V = C.observer
local function send(command, args)
    sendClientCommand("UniversalAdminCore", command, args or {})
end
local function cameraStop()
    if AdminCoreObserveCamera then
        pcall(AdminCoreObserveCamera.stop)
    end
    if V.fastMoveCaptured and ISFastTeleportMove then
        ISFastTeleportMove.cheat = V.originalFastMove
    end
    V.fastMoveCaptured = false
    for _, id in ipairs({
        "observer.facing",
        "observer.safehouses",
        "observer.community",
        "observer.towns",
        "observer.properties",
    }) do
        AdminOverlayManager.enableOverlay(id, false)
    end
end
function C.clearObserver(reason)
    V.id, V.target, V.pending, V.expires = nil, nil, nil, 0
    C.observing = nil
    V.mode = "FOLLOW"
    V.stream, V.loadingSince, V.requestedMode = false, nil, nil
    V.relativeOffsets = false
    V.interestSequence, V.acknowledgedSequence, V.grantRevision = 0, 0, 0
    V.lastInterest, V.lastPan = 0, 0
    V.interestRequests, V.lastAckCenter = {}, nil
    V.teleportPending = nil
    V.status = reason or "Observation stopped. Your character has not been moved."
    cameraStop()
end
function C.stopObserve()
    if V.id then
        send("observeStop", { id = V.id })
    elseif V.pending then
        send("observeStop", {})
    end
    C.clearObserver()
end
function C.startObserver(name, mode)
    if not C.operationsAllowed("ADMIN_SPECTATOR") then
        C.requestOperations()
        return false
    end
    if type(name) ~= "string" or #name == 0 or #name > 128 then
        return false
    end
    V.pending = name
    C.selectObserver(name)
    V.status = "Requesting server permission..."
    send("observeStart", {
        username = name,
        mode = mode or "FOLLOW",
        chunkRadius = AdminCoreObserveCamera
            and AdminCoreObserveCamera.requestedRadius
            and AdminCoreObserveCamera.requestedRadius(),
    })
    return true
end
function C.startFreeCamera()
    C.openObserverPanel()
    local player = getPlayer()
    if player then
        C.startObserver(player:getUsername(), "FREE")
    end
end
local function validMode(mode)
    return mode == "FOLLOW" or mode == "SOFT" or mode == "FREE"
end
local function finiteCoordinate(value)
    return type(value) == "number" and value == value and math.abs(value) < 10000000
end
function C.sendObserverInterest()
    if not V.id or not V.stream or not AdminCoreObserveCamera then
        return false
    end
    local now = getTimestampMs()
    if now - V.lastInterest < 250 then
        return false
    end
    local x, y, z =
        AdminCoreObserveCamera.getViewX(),
        AdminCoreObserveCamera.getViewY(),
        AdminCoreObserveCamera.getViewZ()
    if not finiteCoordinate(x) or not finiteCoordinate(y) or not finiteCoordinate(z) then
        return false
    end
    V.lastInterest = now
    V.interestSequence = V.interestSequence + 1
    V.interestRequests = V.interestRequests or {}
    local mode = V.requestedMode or V.mode
    local offsetX, offsetY
    if mode == "SOFT" and V.relativeOffsets and AdminCoreObserveCamera.getFollowOffsetX then
        offsetX = V.mode == "SOFT" and AdminCoreObserveCamera.getFollowOffsetX() or 0
        offsetY = V.mode == "SOFT" and AdminCoreObserveCamera.getFollowOffsetY() or 0
    end
    V.interestRequests[V.interestSequence] =
        { x = x, y = y, z = z, mode = mode, offsetX = offsetX, offsetY = offsetY }
    V.interestRequests[V.interestSequence - 32] = nil
    send("observeInterest", {
        id = V.id,
        sequence = V.interestSequence,
        mode = mode,
        x = x,
        y = y,
        z = z,
        offsetX = offsetX,
        offsetY = offsetY,
        chunkRadius = AdminCoreObserveCamera.requestedRadius
            and AdminCoreObserveCamera.requestedRadius(),
    })
    return true
end
local function modeStatus(mode)
    return mode == "FREE"
            and (V.stream and "Free camera: streaming a bounded area. WASD, Shift/Ctrl speed, F focus, Esc stop." or "Free camera: loaded tiles only. WASD, Shift/Ctrl speed, F focus, Esc stop.")
        or mode == "SOFT" and "Soft follow: WASD pans around the selected player. F locks again."
        or "Camera locked to the selected player. Your character stays in place."
end
function C.observerMode(mode)
    if not validMode(mode) then
        return false
    end
    if V.id and V.stream then
        V.requestedMode = mode
        C.sendObserverInterest()
        return true
    end
    if V.id and AdminCoreObserveCamera and AdminCoreObserveCamera.setMode(mode) then
        V.mode = mode
        V.status = modeStatus(mode)
        return true
    end
    return false
end
function C.selectedObserverName()
    local panel = C.observePanel
    local name = panel and panel.targets and panel.targets:getOptionText(panel.targets.selected)
        or V.selected
        or V.target
    if type(name) == "string" and #name > 0 and name ~= "No matching players" then
        return name
    end
    return nil
end
function C.selectObserver(name)
    V.selected = type(name) == "string" and name ~= "No matching players" and name or nil
    V.infoRefresh = 0
    local panel = C.observePanel
    if panel and panel.targets and V.selected then
        for i = 1, #panel.targets.options do
            if panel.targets:getOptionText(i) == V.selected then
                panel.targets.selected = i
                break
            end
        end
    end
end
function C.observerTeleport()
    if V.teleportPending then
        return
    end
    local name = C.selectedObserverName()
    if not name then
        V.status = "Select an online player before teleporting."
        return
    end
    if not C.operationsAllowed("ADMIN_SPECTATOR") then
        C.requestOperations()
        V.status = "Observer permission is unavailable. Refresh your admin permissions."
        return
    end
    if not AdminOperations.capable(getPlayer(), "TeleportToPlayer") then
        V.status = "Your role cannot teleport to players."
        return
    end
    C.confirm(
        "Teleport your character to "
            .. name
            .. "? Return to Origin will save your starting location.",
        function()
            if C.selectedObserverName() ~= name or V.teleportPending then
                return
            end
            V.movementSequence = (V.movementSequence or 0) + 1
            local request = tostring(getTimestampMs()) .. ":" .. tostring(V.movementSequence)
            V.teleportPending = {
                request = request,
                username = name,
                expires = getTimestampMs() + 15000,
            }
            V.status = "Requesting teleport to " .. name .. "..."
            send("observeTeleportPrepare", { username = name, request = request })
        end
    )
end
function C.observerReturn()
    if not V.returnId then
        V.status = "No saved return location. Teleport to a player first."
        return
    end
    if
        not C.operationsAllowed("ADMIN_SPECTATOR")
        or not AdminOperations.capable(getPlayer(), "TeleportToCoordinates")
    then
        V.status = "Your role cannot return to saved coordinates."
        return
    end
    local id = V.returnId
    C.stopObserve()
    V.status = "Returning to your saved origin..."
    send("observeReturn", { id = id })
end
function C.observerInformation()
    local name = C.selectedObserverName()
    if not C.operationsAllowed("ADMIN_SPECTATOR") then
        return {
            "Player information",
            "Observer permission is unavailable.",
            "Refresh your admin permissions.",
            "",
        }
    end
    if not name then
        return {
            "Player information",
            "Select an online player in the menu.",
            "Observation is not required to view a loaded player.",
            "",
        }
    end
    local now = getTimestampMs()
    if V.infoName == name and now < (V.infoRefresh or 0) and V.infoLines then
        return V.infoLines
    end
    V.infoName, V.infoRefresh = name, now + 250
    local target = getPlayerFromUsername(name)
    local lines = {
        "Selected player: " .. name,
        V.target == name and V.id and "Actively observing this player."
            or "Not spectating this selection.",
    }
    if not target or target:isDead() or not target:getCurrentSquare() then
        lines[3] = V.stream
                and V.target == name
                and "Loading the selected player's area and updates."
            or "Player details are unavailable outside loaded cells."
        lines[4] = V.stream and V.target == name and "Your character remains at its origin."
            or "Start observation to load their area, or use Teleport To."
    else
        lines[3] =
            string.format("Position: %.1f, %.1f, %.1f", target:getX(), target:getY(), target:getZ())
        local weapon = target:getPrimaryHandItem()
        lines[4] = "Visible held item: " .. tostring(weapon and weapon:getDisplayName() or "None")
    end
    V.infoLines = lines
    return lines
end
function C.observerWeather(value)
    V.weather = value == true and V.render == true
    if AdminCoreObserveCamera then
        AdminCoreObserveCamera.setHideWeather(V.weather)
    end
end
function C.observedPlayer()
    if not V.target then
        return nil
    end
    local now = getTimestampMs()
    if V.cachedName ~= V.target or now >= (V.targetRefresh or 0) then
        V.cachedName = V.target
        V.targetRefresh = now + 250
        V.cachedPlayer = getPlayerFromUsername(V.target)
    end
    local player = V.cachedPlayer
    return player and not player:isDead() and player:getCurrentSquare() and player or nil
end
function C.refreshObserverRoster(force)
    local now = getTimestampMs()
    if not force and now - V.lastRoster < 2000 then
        return
    end
    V.lastRoster = now
    V.roster = {}
    if not C.operationsAllowed("ADMIN_SPECTATOR") then
        return
    end
    local online, actor = getOnlinePlayers(), getPlayer()
    if not online or not actor then
        return
    end
    local query = (V.query or ""):lower()
    local ownFaction = Faction and Faction.getPlayerFaction(actor)
    for i = 0, online:size() - 1 do
        local player = online:get(i)
        local name = player:getUsername()
        local nearby = (player:getX() - actor:getX()) ^ 2 + (player:getY() - actor:getY()) ^ 2
            <= 80 ^ 2
        if
            name ~= actor:getUsername()
            and not player:isDead()
            and name:lower():find(query, 1, true)
            and (V.filter ~= "Nearby" or nearby)
            and (
                V.filter ~= "Faction"
                or ownFaction and Faction.getPlayerFaction(player) == ownFaction
            )
        then
            V.roster[#V.roster + 1] = name
            if #V.roster >= 1000 then
                break
            end
        end
    end
    table.sort(V.roster, function(a, b)
        return a:lower() < b:lower()
    end)
    if C.refreshObserverChoices then
        C.refreshObserverChoices()
    end
end
function C.observerNext(step)
    C.refreshObserverRoster()
    if #V.roster == 0 then
        V.status = "No matching online players."
        return
    end
    local selected = 0
    for i, name in ipairs(V.roster) do
        if name == V.target then
            selected = i
            break
        end
    end
    selected = ((selected - 1 + step) % #V.roster) + 1
    C.startObserver(V.roster[selected])
end
local function applyOverlays()
    AdminOverlayManager.enableOverlay("observer.facing", V.id ~= nil and V.facing)
    AdminOverlayManager.enableOverlay(
        "observer.safehouses",
        V.id ~= nil and V.safehouses and V.render
    )
    AdminOverlayManager.enableOverlay(
        "observer.community",
        V.id ~= nil and V.community and V.render
    )
    AdminOverlayManager.enableOverlay("observer.towns", V.id ~= nil and V.towns and V.render)
    AdminOverlayManager.enableOverlay(
        "observer.properties",
        V.id ~= nil and V.properties and V.render
    )
end
C.updateObserverOverlays = applyOverlays
local function applyGrant(args)
    local revision, sequence
    if args.stream == true then
        revision, sequence = args.revision, args.sequence
        if not finiteCoordinate(revision) or revision < 1 or revision ~= math.floor(revision) then
            return false
        end
        if revision <= V.grantRevision then
            return nil
        end
        if not finiteCoordinate(sequence) or sequence < 0 or sequence ~= math.floor(sequence) then
            return false
        end
    end
    if not finiteCoordinate(args.ttl) then
        return false
    end
    local ttl = math.max(0, math.min(6000, args.ttl))
    if ttl <= 0 or not AdminCoreObserveCamera then
        return false
    end
    if args.stream == true then
        if
            not AdminCoreObserveCamera.grantAt
            or not finiteCoordinate(args.x)
            or not finiteCoordinate(args.y)
            or not finiteCoordinate(args.z)
            or not validMode(args.mode)
        then
            return false
        end
        local relative = args.mode == "SOFT"
            and args.offsetX ~= nil
            and args.offsetY ~= nil
            and AdminCoreObserveCamera.setFollowOffset ~= nil
        if
            relative
            and (
                not finiteCoordinate(args.offsetX)
                or not finiteCoordinate(args.offsetY)
                or math.abs(args.offsetX) > 8
                or math.abs(args.offsetY) > 8
            )
        then
            return false
        end
        local previousMode = V.mode
        local predictionX, predictionY
        if
            V.stream
            and previousMode == args.mode
            and args.mode ~= "FOLLOW"
            and not args.message
        then
            local reference = sequence == V.acknowledgedSequence and V.lastAckCenter
                or V.interestRequests and V.interestRequests[sequence]
            if reference and reference.mode == args.mode and reference.z == args.z then
                local viewX, viewY
                if
                    relative
                    and V.relativeOffsets
                    and reference.offsetX ~= nil
                    and reference.offsetY ~= nil
                then
                    viewX, viewY =
                        AdminCoreObserveCamera.getFollowOffsetX(),
                        AdminCoreObserveCamera.getFollowOffsetY()
                    if finiteCoordinate(viewX) and finiteCoordinate(viewY) then
                        predictionX, predictionY =
                            viewX - reference.offsetX, viewY - reference.offsetY
                    end
                elseif not relative then
                    viewX, viewY =
                        AdminCoreObserveCamera.getViewX(), AdminCoreObserveCamera.getViewY()
                    if finiteCoordinate(viewX) and finiteCoordinate(viewY) then
                        predictionX, predictionY = viewX - reference.x, viewY - reference.y
                    end
                end
            end
        end
        local radius = args.chunkRadius or 3
        if
            not finiteCoordinate(radius)
            or radius ~= math.floor(radius)
            or radius < 3
            or radius > 9
        then
            return false
        end
        if
            AdminCoreObserveCamera.grantRadius
            and not AdminCoreObserveCamera.grantRadius(radius)
        then
            return false
        end
        if
            not AdminCoreObserveCamera.grantAt(
                V.target,
                args.render == true,
                args.x,
                args.y,
                args.z,
                ttl / 1000,
                true
            )
        then
            return false
        end
        if not AdminCoreObserveCamera.setMode(args.mode) then
            return false
        end
        if relative and not AdminCoreObserveCamera.setFollowOffset(args.offsetX, args.offsetY) then
            return false
        end
        V.relativeOffsets = args.offsetX ~= nil
            and args.offsetY ~= nil
            and AdminCoreObserveCamera.setFollowOffset ~= nil
        V.stream, V.grantRevision, V.mode = true, revision, args.mode
        if predictionX and AdminCoreObserveCamera.restorePrediction then
            AdminCoreObserveCamera.restorePrediction(predictionX, predictionY)
        end
        V.acknowledgedSequence = math.max(V.acknowledgedSequence, sequence)
        V.interestSequence = math.max(V.interestSequence, V.acknowledgedSequence)
        V.lastAckCenter = {
            x = args.x,
            y = args.y,
            z = args.z,
            mode = args.mode,
            offsetX = args.offsetX,
            offsetY = args.offsetY,
        }
        for submitted in pairs(V.interestRequests or {}) do
            if submitted <= sequence then
                V.interestRequests[submitted] = nil
            end
        end
        if V.requestedMode == args.mode or args.message then
            V.requestedMode = nil
        end
        if previousMode ~= V.mode then
            V.status = modeStatus(V.mode)
        end
    else
        if not AdminCoreObserveCamera.grant(V.target, args.render == true) then
            return false
        end
        V.stream = false
    end
    V.render = args.render == true
    V.expires = getTimestampMs() + ttl
    if args.message then
        V.status = args.message
    end
    return true
end
local function onServer(mod, command, args)
    if mod ~= "UniversalAdminCore" then
        return
    end
    -- B42 encodes an empty table as a nil payload. A cleared Return marker
    -- must still reach the UI, including acknowledgements from an older server.
    if command == "observeStatus" and args == nil then
        args = {}
    end
    if type(args) ~= "table" then
        return
    end
    if command == "observeStarted" then
        if V.pending ~= args.username or (tonumber(args.id) or 0) < V.lastId then
            return
        end
        V.pending = nil
        V.lastId = tonumber(args.id) or V.lastId
        V.id, V.target, V.render = args.id, args.username, args.render == true
        V.mode, V.requestedMode = "FOLLOW", nil
        V.interestSequence, V.acknowledgedSequence, V.grantRevision = 0, 0, 0
        -- The server's new lease starts with a movement-rate timestamp. Wait
        -- one interest interval rather than immediately submitting a rejected
        -- zero-motion request while that lease is still under 200 ms old.
        V.lastInterest, V.lastPan = getTimestampMs(), getTimestampMs()
        V.interestRequests, V.lastAckCenter = {}, nil
        if args.hasReturn ~= nil then
            V.returnId = args.hasReturn and args.returnId or nil
        else
            V.returnId = args.returnId or V.returnId
        end
        V.lastHeartbeat = 0
        C.observing = V.target
        if not applyGrant(args) then
            C.stopObserve()
            V.status = "Camera unavailable. Check Storm and the admin role."
            return
        end
        if ISFastTeleportMove and not V.fastMoveCaptured then
            V.originalFastMove = ISFastTeleportMove.cheat
            V.fastMoveCaptured = true
            ISFastTeleportMove.cheat = false
        end
        if not V.stream and not C.observedPlayer() then
            C.stopObserve()
            V.status = "Target is outside loaded cells. Use Teleport To here first, then observe."
            return
        end
        if V.stream then
            V.loadingSince = getTimestampMs()
            V.status = "Loading observer terrain and player updates. Your character stays in place."
        else
            C.observerMode(args.mode or "FOLLOW")
        end
        applyOverlays()
    elseif command == "observeGrant" and V.id == args.id then
        local accepted = applyGrant(args)
        if accepted == nil then
            return
        end
        if not accepted then
            C.stopObserve()
            return
        end
        if not V.render then
            C.observerWeather(false)
        end
        applyOverlays()
    elseif command == "observeStopped" and V.id == args.id then
        C.clearObserver(args.reason)
    elseif command == "observeStatus" then
        V.returnId = args.returnId
        if args.message then
            V.status = args.message
        end
    elseif command == "observeTeleportReady" then
        local pending = V.teleportPending
        if
            not pending
            or pending.request ~= args.request
            or pending.username ~= args.username
            or getTimestampMs() >= pending.expires
            or type(args.ticket) ~= "string"
        then
            return
        end
        V.teleportPending = nil
        if C.selectedObserverName() ~= args.username then
            V.status = "Selection changed. Teleport was cancelled."
            return
        end
        -- Detach and restore input before the native movement packet arrives.
        C.stopObserve()
        V.status = "Teleporting to " .. args.username .. "..."
        send("observeTeleport", { ticket = args.ticket, request = args.request })
    elseif command == "observeActionResult" then
        if
            V.teleportPending and (not args.request or V.teleportPending.request == args.request)
        then
            V.teleportPending = nil
        end
        V.status = args.message or "Observer action was not completed."
    end
end
local function tick()
    if V.teleportPending and getTimestampMs() >= V.teleportPending.expires then
        V.teleportPending = nil
        V.status = "Teleport request timed out. Select the player and try again."
    end
    if C.observePanel then
        C.refreshObserverRoster()
    end
    if not V.id then
        return
    end
    local now, player = getTimestampMs(), getPlayer()
    if V.fastMoveCaptured and ISFastTeleportMove then
        ISFastTeleportMove.cheat = false
    end
    if
        not player
        or player:isDead()
        or now >= V.expires
        or not AdminOperations.authorized(player, "ADMIN_SPECTATOR")
    then
        C.stopObserve()
        V.status = "Observation ended: player, permission or server grant expired."
        return
    end
    if not AdminCoreObserveCamera or not AdminCoreObserveCamera.active() then
        C.stopObserve()
        V.status = "Observed player is no longer available. Choose another player."
        return
    end
    local available = C.observedPlayer()
    if V.stream then
        local ready = AdminCoreObserveCamera.ready() and (V.mode == "FREE" or available ~= nil)
        if ready then
            if V.loadingSince then
                V.status = modeStatus(V.mode)
            end
            V.loadingSince = nil
        else
            if not V.loadingSince then
                V.loadingSince = now
                V.status = "Loading observer terrain and player updates..."
            elseif now - V.loadingSince >= 20000 then
                C.stopObserve()
                V.status =
                    "Observer loading timed out. Your origin is intact; select the player and try again."
                return
            end
        end
    elseif not available then
        C.stopObserve()
        V.status = "Observed player is no longer available. Choose another player."
        return
    end
    if now - V.lastHeartbeat >= 2000 then
        V.lastHeartbeat = now
        send("observeHeartbeat", { id = V.id })
    end
    local elapsed = math.min(0.1, math.max(0, (now - V.lastPan) / 1000))
    V.lastPan = now
    if
        V.mode ~= "FOLLOW"
        and not (C.observePanel and C.observePanel.search and C.observePanel.search:isFocused())
    then
        local function down(key)
            return Keyboard[key] and isKeyDown(Keyboard[key])
        end
        local dx = (down("KEY_D") and 1 or 0) - (down("KEY_A") and 1 or 0)
        local dy = (down("KEY_S") and 1 or 0) - (down("KEY_W") and 1 or 0)
        local speed = down("KEY_LSHIFT") and 15 or down("KEY_LCONTROL") and 2 or 6
        if dx ~= 0 or dy ~= 0 then
            AdminCoreObserveCamera.pan(dx * speed * elapsed, dy * speed * elapsed)
        end
    end
    if V.stream then
        C.sendObserverInterest()
    end
end
Events.OnServerCommand.Add(onServer)
Events.OnTick.Add(function()
    local ok, err = pcall(tick)
    if not ok then
        C.stopObserve()
        V.status = "Observer stopped after a client error."
        print("[Universal Admin Core] " .. tostring(err))
    end
end)
Events.OnKeyPressed.Add(function(key)
    if key == Keyboard.KEY_ESCAPE and V.teleportPending then
        V.teleportPending = nil
        V.status = "Teleport was cancelled."
        return
    end
    if not V.id then
        return
    end
    if key == Keyboard.KEY_ESCAPE then
        C.stopObserve()
    elseif
        key == Keyboard.KEY_F
        and not (C.observePanel and C.observePanel.search and C.observePanel.search:isFocused())
    then
        C.observerMode("FOLLOW")
    end
end)
local function disconnect()
    C.clearObserver("Disconnected.")
    V.returnId = nil
    V.lastId = 0
    V.roster = {}
    V.teleportPending, V.selected, V.infoLines = nil, nil, nil
    if C.observePanel then
        C.observePanel:removeFromUIManager()
        C.observePanel = nil
    end
    C.operationsKeepAlive("observer", false)
end
Events.OnDisconnect.Add(disconnect)
Events.OnMainMenuEnter.Add(disconnect)
require("AdminCore/ObserverOverlays")
require("AdminCore/ObserverUI")
require("AdminCore/ObserverWorldContext")
