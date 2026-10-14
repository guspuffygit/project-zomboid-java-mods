if not isServer() then
    return
end
require("AdminCore/OperationsPermissions")

AdminSafehouseBoundaryServer = AdminSafehouseBoundaryServer or {}
local S = AdminSafehouseBoundaryServer
if S.installed then
    return
end
S.installed = true
local module = "UniversalAdminCoreBoundary"
local sessions, limits, sequence = {}, {}, 0
local function permitted(player)
    return AdminOperations.authorized(player, "ADMIN_SAFEHOUSE_EDIT")
        and player:getRole()
        and player:getRole():hasCapability(Capability.CanSetupSafehouses)
end
local function data()
    local result = ModData.getOrCreate("UniversalAdminCore.SafehouseBoundaries.v1")
    result.aliases, result.history = result.aliases or {}, result.history or {}
    return result
end
local function reply(player, command, args)
    sendServerCommand(player, module, command, args)
end
local function result(player, message)
    reply(player, "result", { message = message })
end
local function coords(house)
    return { x = house:getX(), y = house:getY(), w = house:getW(), h = house:getH() }
end
local function numeric(args)
    for _, key in ipairs({ "x", "y", "w", "h" }) do
        local n = args[key]
        if
            type(n) ~= "number"
            or n ~= n
            or n == math.huge
            or n == -math.huge
            or n ~= math.floor(n)
        then
            return false
        end
    end
    return math.abs(args.x) <= 1000000
        and math.abs(args.y) <= 1000000
        and args.w >= 2
        and args.h >= 2
        and args.w <= 200
        and args.h <= 200
end
local function identity(rect, created)
    return string.format("%d:%d:%.0f", rect.x, rect.y, created)
end
function S.onCommand(mod, command, player, args)
    if mod ~= module or not player or type(args) ~= "table" then
        return
    end
    if command ~= "snapshot" and command ~= "commit" and command ~= "history" then
        return
    end
    local name, now = player:getUsername(), getTimestampMs()
    if limits[name] and now - limits[name] < 400 then
        return
    end
    limits[name] = now
    if not permitted(player) then
        return result(player, "Permission denied.")
    end
    if not SafehouseBoundaryBridge then
        return result(player, "Boundary server bridge unavailable.")
    end
    if command == "history" then
        local rows, history = {}, data().history
        for i = #history, math.max(1, #history - 24), -1 do
            rows[#rows + 1] = history[i]
        end
        return reply(player, "history", { rows = rows })
    end
    if not numeric(args) then
        return result(player, "Invalid rectangle.")
    end
    if command == "snapshot" then
        local house = SafehouseBoundaryBridge.find(player, args.x, args.y, args.w, args.h)
        if not house then
            return result(player, "Safehouse no longer exists. Refresh the list.")
        end
        sequence = sequence + 1
        local snapshot = coords(house)
        snapshot.id, snapshot.owner, snapshot.title =
            house:getId(), house:getOwner(), house:getTitle()
        snapshot.token = tostring(now) .. ":" .. tostring(sequence)
        sessions[name] = {
            player = player,
            house = house,
            snapshot = snapshot,
            fingerprint = SafehouseBoundaryBridge.fingerprint(player, house),
            expires = now + 120000,
        }
        return reply(player, "snapshot", snapshot)
    end
    local session = sessions[name]
    if
        not session
        or session.player ~= player
        or session.expires < now
        or args.token ~= session.snapshot.token
        or args.id ~= session.snapshot.id
    then
        return result(player, "Editing session expired or changed. Reopen Edit Boundary.")
    end
    if args.mode ~= "Expand" and args.mode ~= "Redraw" then
        return result(player, "Invalid edit mode.")
    end
    if args.reason ~= nil and (type(args.reason) ~= "string" or #args.reason > 160) then
        return result(player, "Reason must be 160 characters or fewer.")
    end
    -- Consume before mutation: double clicks and replayed packets can never apply again.
    sessions[name] = nil
    local house, stored = session.house, data()
    local old, created = session.snapshot, house:getDatetimeCreated()
    local oldKey, newKey = identity(old, created), identity(args, created)
    local previousAlias = stored.aliases[newKey]
    stored.aliases[newKey] = stored.aliases[oldKey] or oldKey
    local ok, response = pcall(
        SafehouseBoundaryBridge.apply,
        player,
        house,
        session.fingerprint,
        args.x,
        args.y,
        args.w,
        args.h,
        args.mode == "Expand"
    )
    if not ok or response ~= "OK" then
        stored.aliases[newKey] = previousAlias
        if not ok then
            print("[Universal Admin Core] Boundary bridge failed: " .. tostring(response))
            return result(player, "Boundary edit failed. Refresh before trying again.")
        end
        return result(player, response)
    end
    local changed = coords(house)
    changed.old = { x = old.x, y = old.y, w = old.w, h = old.h }
    changed.id, changed.owner = old.id, old.owner
    changed.onlineId, changed.created = house:getOnlineID(), created
    local record = {
        event = "SAFEHOUSE_BOUNDARY_EDIT",
        admin = name,
        id = old.id,
        owner = old.owner,
        old = changed.old,
        new = coords(house),
        mode = args.mode,
        reason = args.reason or "",
        at = now,
        propertyId = stored.aliases[newKey],
    }
    stored.history[#stored.history + 1] = record
    while #stored.history > 100 do
        table.remove(stored.history, 1)
    end
    local detail = "owner="
        .. old.owner
        .. " old="
        .. oldKey
        .. ","
        .. old.w
        .. ","
        .. old.h
        .. " new="
        .. newKey
        .. ","
        .. args.w
        .. ","
        .. args.h
        .. " mode="
        .. args.mode
        .. " reason="
        .. (args.reason or "")
    if
        not AdminOperations.audit
        or not pcall(AdminOperations.audit, "SAFEHOUSE_BOUNDARY_EDIT", player, detail)
    then
        print(
            "[Universal Admin Core] SAFEHOUSE_BOUNDARY_EDIT admin="
                .. name
                .. " "
                .. detail:gsub("[%c]", " ")
        )
    end
    -- Native SafehouseSync identifies claims by rectangle and would create a second client
    -- claim. This reliable command updates the same client object before any future sync.
    sendServerCommand(module, "changed", changed)
    result(player, "Boundary updated. Ownership, members and respawn settings preserved.")
end
Events.OnClientCommand.Add(S.onCommand)
Events.EveryOneMinute.Add(function()
    local now = getTimestampMs()
    for name, session in pairs(sessions) do
        if session.expires < now then
            sessions[name] = nil
        end
    end
    for name, at in pairs(limits) do
        if now - at > 120000 then
            limits[name] = nil
        end
    end
end)
