if not isServer() then
    return
end

require("AdminCore/ObserverServer")
require("AdminCore/NoiseServer")

AdminCoreServer = AdminCoreServer or {}
local S = AdminCoreServer
local module = "UniversalAdminCore"
local limits, lastTick = {}, 0
local commands = {
    stats = true,
    createSafehouse = true,
    addMember = true,
    transferOwner = true,
    transferOnly = true,
}
local function store()
    return ModData.getOrCreate("UniversalAdminCore.Playtime.v1")
end
local function permitted(player, capability)
    return player and player:getRole() and player:getRole():hasCapability(capability)
end
local function reply(player, command, args)
    sendServerCommand(player, module, command, args)
end
local function result(player, text)
    reply(player, "result", { message = text })
end

function S.onCommand(mod, command, player, args)
    if
        mod ~= module
        or not player
        or not commands[command]
        or (args ~= nil and type(args) ~= "table")
    then
        return
    end
    if not AdminCoreBridge then
        return result(
            player,
            "Admin server bridge is unavailable. Restart the server after building the addon."
        )
    end
    local name, now = player:getUsername(), getTimestampMs()
    if type(args) ~= "table" then
        return
    end
    local cap = command == "stats" and Capability.ReadUserLog
        or command == "createSafehouse" and Capability.CanSetupSafehouses
        or args.kind == "safehouse" and Capability.CanSetupSafehouses
        or args.kind == "faction" and Capability.FactionCheat
    if not cap or not permitted(player, cap) then
        return
    end
    limits[name] = limits[name] or {}
    if limits[name][command] and now - limits[name][command] < 500 then
        return
    end
    limits[name][command] = now
    if command == "stats" then
        if not permitted(player, Capability.ReadUserLog) then
            return
        end
        if type(args.names) ~= "table" or #args.names > 50 then
            return
        end
        local data, rows = store(), {}
        for _, username in ipairs(args.names) do
            if
                type(username) == "string"
                and #username <= 128
                and AdminCoreBridge.knownUser(player, username)
            then
                local record = data[username]
                local row = {
                    username = username,
                    lastSeen = AdminCoreBridge.lastSeen(player, username),
                    tracked = record ~= nil,
                    seconds = record and record.seconds or 0,
                    trackingSince = record and record.since or 0,
                }
                rows[#rows + 1] = row
            end
        end
        reply(player, "stats", { rows = rows })
    elseif command == "createSafehouse" then
        if not permitted(player, Capability.CanSetupSafehouses) then
            return
        end
        if
            type(args.owner) ~= "string"
            or #args.owner > 128
            or type(args.title) ~= "string"
            or #args.title > 128
        then
            return
        end
        for _, key in ipairs({ "x", "y", "w", "h" }) do
            if type(args[key]) ~= "number" then
                return
            end
        end
        local response = AdminCoreBridge.createSafehouse(
            player,
            args.owner,
            args.title,
            args.x,
            args.y,
            args.w,
            args.h
        )
        result(player, response == "OK" and "Safehouse created by the server." or response)
    elseif command == "addMember" or command == "transferOwner" or command == "transferOnly" then
        local capability = args.kind == "safehouse" and Capability.CanSetupSafehouses
            or args.kind == "faction" and Capability.FactionCheat
            or nil
        if not capability or not permitted(player, capability) then
            return
        end
        if
            type(args.id) ~= "string"
            or #args.id > 256
            or type(args.username) ~= "string"
            or #args.username > 128
        then
            return
        end
        local response
        if command == "addMember" then
            response = AdminCoreBridge.addMember(player, args.kind, args.id, args.username)
        elseif type(args.replacement) == "string" and #args.replacement <= 128 then
            if command == "transferOnly" then
                response = AdminCoreBridge.transferOnly(
                    player,
                    args.kind,
                    args.id,
                    args.username,
                    args.replacement
                )
            else
                response = AdminCoreBridge.transferAndRemove(
                    player,
                    args.kind,
                    args.id,
                    args.username,
                    args.replacement
                )
            end
        end
        if response then
            result(player, response == "OK" and "Membership updated by the server." or response)
        end
    end
end

function S.tick()
    local now = getTimestampMs()
    if now - lastTick < 2000 then
        return
    end
    local elapsed = lastTick > 0 and math.max(0, math.min(10, (now - lastTick) / 1000)) or 0
    lastTick = now
    local data, connected = store(), {}
    local players = getOnlinePlayers()
    for i = 0, players:size() - 1 do
        local player = players:get(i)
        local name = player:getUsername()
        connected[name] = player
        local record = data[name]
        if not record then
            record = { seconds = 0, since = getTimestamp() }
            data[name] = record
        end
        -- Count only users seen on the preceding sample; never count server downtime.
        if S.previous and S.previous[name] then
            record.seconds = record.seconds + elapsed
        end
    end
    S.previous = connected
    for name in pairs(limits) do
        if not connected[name] then
            limits[name] = nil
        end
    end
end
Events.OnClientCommand.Add(S.onCommand)
Events.OnTick.Add(S.tick)
print("[Universal Admin Core] Server requests and persistent real-time playtime tracking loaded.")
