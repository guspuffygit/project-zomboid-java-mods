-- Keep the last usable cache while recovering. Authorization remains server-side.
local S = {
    requestId = 0,
    nextRequest = 0,
    waiting = false,
    attempts = 0,
    unavailable = {},
    unavailableCount = 0,
    unknownCount = 0,
}
AVCS.Sync = S
AVCS.cacheRevision = 0

function S.changed()
    AVCS.cacheRevision = AVCS.cacheRevision + 1
end
function S.ready()
    return AVCS.dbByVehicleSQLID ~= nil and AVCS.dbByPlayerID ~= nil
end
function S.validId(id)
    return type(id) == "number"
        and id == id
        and id >= 0
        and id <= 9007199254740991
        and id == math.floor(id)
end
local permissionFields = {
    "AllowDrive",
    "AllowPassenger",
    "AllowSiphonFuel",
    "AllowUninstallParts",
    "AllowAttachVehicle",
    "AllowDetechVehicle",
    "AllowTakeEngineParts",
    "AllowOpeningTrunk",
    "AllowInflatTires",
    "AllowDeflatTires",
}
function S.validClaim(claim)
    if
        type(claim) ~= "table"
        or type(claim.OwnerPlayerID) ~= "string"
        or claim.OwnerPlayerID == ""
        or type(claim.CarModel) ~= "string"
        or not claim.CarModel:find(".", 1, true)
    then
        return false
    end
    for _, key in ipairs(permissionFields) do
        if claim[key] ~= nil and type(claim[key]) ~= "boolean" then
            return false
        end
    end
    for _, key in ipairs({
        "ClaimDateTime",
        "LastLocationX",
        "LastLocationY",
        "LastLocationUpdateDateTime",
        "PermissionRevision",
    }) do
        local value = claim[key]
        if
            value ~= nil
            and (
                type(value) ~= "number"
                or value ~= value
                or value == math.huge
                or value == -math.huge
            )
        then
            return false
        end
    end
    return true
end
local function displayRecord(claim)
    local copy = {}
    for k, v in pairs(claim) do
        copy[k] = v
    end
    for _, key in ipairs({
        "ClaimDateTime",
        "LastLocationX",
        "LastLocationY",
        "LastLocationUpdateDateTime",
    }) do
        copy[key] = copy[key] or 0
    end
    return copy
end
function S.isUnavailable(id)
    return id ~= nil
        and (
            S.unavailable[id] ~= nil
            or S.unknownCount > 0 and not (AVCS.dbByVehicleSQLID or {})[id]
        )
end
function S.degraded()
    return S.unavailableCount > 0 or S.unknownCount > 0
end
function S.warning()
    if not S.degraded() then
        return nil
    end
    return getText("IGUI_AVCS_SyncUnavailable", S.unavailableCount, S.unknownCount)
end
function S.clearUnavailable(id)
    if S.unavailable[id] then
        S.unavailable[id] = nil
        S.unavailableCount = S.unavailableCount - 1
        S.snapshotRevision = (S.snapshotRevision or 0) + 1
    end
end
local function stop()
    if S.hook then
        Events.OnTick.Remove(S.hook)
    end
    S.hook = nil
end

function S.request(retry)
    if S.failed and not retry then
        return
    end
    if S.hook then
        return
    end
    S.failed, S.waiting, S.attempts = false, true, 0
    if retry then
        S.nextRequest = 0
    end
    S.hook = function()
        local player, now = getPlayer(), getTimestampMs()
        if not player or now < S.nextRequest then
            return
        end
        if S.attempts >= 3 then
            S.failed, S.waiting = true, false
            S.vehicle, S.player = nil, nil
            stop()
            print(
                "[AVCS] Claim refresh unavailable. Existing cache retained; reopen a vehicle manager to retry."
            )
            return
        end
        S.attempts = S.attempts + 1
        S.requestId = S.requestId + 1
        S.vehicle, S.player = nil, nil
        S.nextRequest = now + 5000 * S.attempts
        sendClientCommand(
            player,
            "AVCS",
            "requestFullSync",
            { requestId = S.requestId, protocol = 3 }
        )
    end
    Events.OnTick.Add(S.hook)
    S.hook()
end

local function publish(vehicles, players)
    if type(vehicles) ~= "table" or type(players) ~= "table" then
        return false
    end
    -- Owner indexes are derived display data. A missing back-reference must not
    -- permanently lock all vehicles or trigger endless full-table downloads.
    local index, healthy, unavailable, unknown = {}, {}, {}, 0
    local previousVehicles = AVCS.dbByVehicleSQLID or {}
    for id, claim in pairs(vehicles) do
        if S.validId(id) and S.validClaim(claim) then
            healthy[id] = displayRecord(claim)
        else
            -- A numeric-string key identifies a damaged record, not a second claim.
            local known = S.validId(id) and id
                or type(id) == "string" and id:match("^%d+$") and tonumber(id)
            if S.validId(known) then
                unavailable[known] = true
            else
                unknown = unknown + 1
            end
        end
    end
    if unknown > 0 then
        -- An unidentifiable damaged row could be an omitted old claim. Do not infer
        -- deletion for those old identities until a coherent snapshot arrives.
        for id in pairs(previousVehicles) do
            if not healthy[id] then
                unavailable[id] = true
            end
        end
        for id in pairs(S.unavailable) do
            if not healthy[id] then
                unavailable[id] = true
            end
        end
    end
    local unavailableCount = 0
    for id in pairs(unavailable) do
        unavailableCount = unavailableCount + 1
        healthy[id] = S.validClaim(previousVehicles[id]) and displayRecord(previousVehicles[id])
            or nil
    end
    for id, claim in pairs(healthy) do
        local owner = claim.OwnerPlayerID
        if not index[owner] then
            local previous = players[owner] or (AVCS.dbByPlayerID or {})[owner]
            local lastLogon = type(previous) == "table" and tonumber(previous.LastKnownLogonTime)
                or 0
            if
                not lastLogon
                or lastLogon ~= lastLogon
                or lastLogon == math.huge
                or lastLogon == -math.huge
            then
                lastLogon = 0
            end
            index[owner] = {
                LastKnownLogonTime = lastLogon,
            }
        end
        index[owner][id] = true
    end
    AVCS.dbByVehicleSQLID, AVCS.dbByPlayerID = healthy, index
    S.unavailable, S.unavailableCount, S.unknownCount = unavailable, unavailableCount, unknown
    S.invalidEnvelope = false
    S.snapshotRevision = (S.snapshotRevision or 0) + 1
    if S.degraded() then
        print(
            "[AVCS] Claim refresh: "
                .. unavailableCount
                .. " unavailable identities; "
                .. unknown
                .. " unidentified records. Repair server claim data, then reopen a manager to retry."
        )
    end
    S.vehicle, S.player, S.waiting, S.failed = nil, nil, false, false
    stop()
    S.changed()
    return true
end

function S.receiveSnapshot(args)
    if type(args) ~= "table" or args.requestId ~= S.requestId or not S.waiting then
        return
    end
    if type(args.vehicles) ~= "table" or type(args.players) ~= "table" then
        S.invalidEnvelope = true
        return
    end
    publish(args.vehicles, args.players)
end

function S.receive(kind, data, requestId)
    if kind ~= "vehicle" and kind ~= "player" then
        return
    end
    if requestId and requestId ~= S.requestId then
        return
    end
    if type(data) ~= "table" then
        S.invalidEnvelope = true
        return
    end
    S[kind] = data
    if S.vehicle and S.player then
        publish(S.vehicle, S.player)
    end
end

function S.deltaReady()
    if S.ready() and not S.waiting then
        return true
    end
    S.vehicle, S.player = nil, nil
    S.request()
    return false
end

Events.OnDisconnect.Add(function()
    stop()
    S.vehicle, S.player = nil, nil
    S.waiting, S.failed, S.attempts, S.nextRequest = false, false, 0, 0
    AVCS.dbByVehicleSQLID, AVCS.dbByPlayerID = nil, nil
    S.unavailable, S.unavailableCount, S.unknownCount, S.invalidEnvelope = {}, 0, 0, false
    S.changed()
end)
return S
