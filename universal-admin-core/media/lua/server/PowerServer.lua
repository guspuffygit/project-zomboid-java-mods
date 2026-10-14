if not isServer() then
    return
end
require("AdminCore/OperationsPermissions")
require("AdminCore/PowerDefinitions")
AdminPowerServer = AdminPowerServer or {}
local S, D = AdminPowerServer, AdminPowerDefinitions
if S.installed then
    return
end
S.installed = true
local limits, lastTick = {}, 0
local module = "UniversalAdminPowers"

local function hasEntries(values)
    for _ in pairs(values) do
        return true
    end
    return false
end

local function grants()
    local data = ModData.getOrCreate("UniversalAdminCore.PowerGrants.v1")
    if type(data.users) ~= "table" then
        data.users = {}
    end
    return data.users
end

local function tracked(name, create)
    local users = grants()
    local saved = users[name]
    if not create and type(saved) ~= "table" then
        users[name] = nil
        return nil
    end
    -- Only known boolean IDs are persisted: at most 24 entries per account.
    -- No player references or desired values are replayed across a restart.
    local ids = {}
    if type(saved) == "table" then
        for _, row in ipairs(D.list) do
            if saved[row[1]] == true then
                ids[row[1]] = true
            end
        end
    end
    users[name] = (create or hasEntries(ids)) and ids or nil
    return users[name]
end

local function permitted(player, entry)
    return D.nativeAllowed(player, entry)
        and AdminOperations.authorized(player, entry.permission) == true
        and AdminOperations.toolAllowed(player, "power." .. entry.id)
end

local function sync(player)
    if AdminCoreBridge and AdminCoreBridge.syncPowers then
        AdminCoreBridge.syncPowers(player)
    end
end

local function reply(player, args, values, errorText)
    sendServerCommand(player, module, "state", {
        token = args.token,
        values = values or {},
        error = errorText,
    })
end

function S.onCommand(mod, command, player, args)
    if mod ~= module or command ~= "apply" or not player or type(args) ~= "table" then
        return
    end
    if
        type(args.token) ~= "number"
        or args.token ~= math.floor(args.token)
        or args.token < 1
        or args.token > 2147483647
    then
        return
    end
    if type(args.values) ~= "table" then
        return
    end
    local count, changes = 0, {}
    for id, value in pairs(args.values) do
        count = count + 1
        local entry = type(id) == "string" and D.byId[id]
        if count > #D.list or not entry or type(value) ~= "boolean" then
            return reply(player, args, nil, "Unsupported power request.")
        end
        if not permitted(player, entry) then
            return reply(player, args, nil, "A requested power is no longer allowed for your role.")
        end
        if not player[entry.setter] or not player[entry.getter] then
            return reply(player, args, nil, "This power is unavailable in the current game build.")
        end
        changes[#changes + 1] =
            { entry = entry, value = value, previous = player[entry.getter](player) == true }
    end
    if count == 0 or player:isDead() then
        return
    end
    table.sort(changes, function(a, b)
        return a.entry.id < b.entry.id
    end)
    local name, now = player:getUsername(), getTimestampMs()
    local previous = limits[name]
    if previous and now - previous < 150 then
        return reply(player, args, nil, "Please wait briefly before changing powers again.")
    end
    limits[name] = now
    -- Validate the whole section/preset before changing anything. Boolean setters
    -- are idempotent: retrying a lost response cannot toggle a power twice.
    local applied = {}
    for _, change in ipairs(changes) do
        local ok = pcall(player[change.entry.setter], player, change.value)
        if not ok then
            local restored = pcall(player[change.entry.setter], player, change.previous)
            for _, rollback in ipairs(applied) do
                local rollbackOK = pcall(player[rollback.entry.setter], player, rollback.previous)
                restored = restored and rollbackOK
            end
            sync(player)
            AdminOperations.audit(
                "ADMIN_POWER_FAILED",
                player,
                "power=" .. change.entry.id .. " rollback=" .. tostring(restored)
            )
            return reply(
                player,
                args,
                nil,
                restored and "The game could not apply these powers. Previous values were restored."
                    or "The game could not apply these powers. Check the server audit before retrying."
            )
        end
        applied[#applied + 1] = change
    end
    local ids = tracked(name, true)
    local values, audit = {}, {}
    for _, change in ipairs(changes) do
        values[change.entry.id] = player[change.entry.getter](player) == true
        ids[change.entry.id] = values[change.entry.id] and true or nil
        if values[change.entry.id] ~= change.previous then
            audit[#audit + 1] = change.entry.id .. "=" .. tostring(values[change.entry.id])
        end
    end
    if not hasEntries(ids) then
        grants()[name] = nil
    end
    if #audit > 0 then
        table.sort(audit)
        AdminOperations.audit("ADMIN_POWER", player, table.concat(audit, " "))
    end
    sync(player)
    reply(player, args, values)
end

function S.tick()
    local now = getTimestampMs()
    if now - lastTick < 2000 then
        return
    end
    lastTick = now
    if not hasEntries(grants()) and not hasEntries(limits) then
        return
    end
    local connected = {}
    local players = getOnlinePlayers()
    for i = 0, players:size() - 1 do
        connected[players:get(i):getUsername()] = players:get(i)
    end
    -- Visit only connected accounts. Offline UAC grants remain available for
    -- the next join, even if their role or server policy changed while offline.
    for name, player in pairs(connected) do
        local ids = tracked(name, false)
        if ids then
            local revoked = {}
            for id in pairs(ids) do
                local entry = D.byId[id]
                if not permitted(player, entry) then
                    player[entry.setter](player, false)
                    ids[id], revoked[id] = nil, false
                end
            end
            if hasEntries(revoked) then
                sync(player)
                reply(
                    player,
                    { token = 0 },
                    revoked,
                    "Restricted powers were disabled after your permissions changed."
                )
                AdminOperations.audit(
                    "ADMIN_POWER",
                    player,
                    "Restricted powers revoked after permission change"
                )
            end
            if not hasEntries(ids) then
                grants()[name] = nil
            end
        end
    end
    for name in pairs(limits) do
        if not connected[name] then
            limits[name] = nil
        end
    end
end

Events.OnClientCommand.Add(S.onCommand)
Events.OnTick.Add(S.tick)
