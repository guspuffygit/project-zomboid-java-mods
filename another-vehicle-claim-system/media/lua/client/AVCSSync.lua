-- Bounded recovery for missing/out-of-order claim data. Loaded together with AVCSClient.
local S = { requestId = 0, nextRequest = 0, waiting = false }
AVCS.Sync = S
AVCS.cacheRevision = 0

function S.changed()
    AVCS.cacheRevision = AVCS.cacheRevision + 1
end

function S.ready()
    return not S.waiting and AVCS.dbByVehicleSQLID ~= nil and AVCS.dbByPlayerID ~= nil
end

function S.request()
    S.waiting = true
    if S.hook then
        return
    end
    S.hook = function()
        local player = getPlayer()
        local now = getTimestampMs()
        if not player or now < S.nextRequest then
            return
        end
        S.requestId = S.requestId + 1
        S.vehicle, S.player = nil, nil
        S.nextRequest = now + 5000
        sendClientCommand(player, "AVCS", "requestFullSync", { requestId = S.requestId })
    end
    Events.OnTick.Add(S.hook)
    S.hook()
end

function S.receive(kind, data, requestId)
    -- B42 represents an empty serialized Lua table as nil.
    if data == nil then
        data = {}
    end
    if type(data) ~= "table" or (requestId and requestId ~= S.requestId) then
        return
    end
    S.waiting = true
    S[kind] = data
    if not S.vehicle or not S.player then
        return
    end
    for id, claim in pairs(S.vehicle) do
        local owner = type(claim) == "table" and S.player[claim.OwnerPlayerID]
        if type(owner) ~= "table" or not owner[id] then
            S.vehicle, S.player = nil, nil
            S.request()
            return
        end
    end
    AVCS.dbByVehicleSQLID, AVCS.dbByPlayerID = S.vehicle, S.player
    S.vehicle, S.player, S.waiting = nil, nil, false
    if S.hook then
        Events.OnTick.Remove(S.hook)
    end
    S.hook = nil
    S.changed()
end

function S.deltaReady()
    if S.ready() then
        return true
    end
    -- Never pair a half-snapshot with a delta from a different server state.
    S.vehicle, S.player = nil, nil
    S.request()
    return false
end

Events.OnDisconnect.Add(function()
    if S.hook then
        Events.OnTick.Remove(S.hook)
    end
    S.hook, S.vehicle, S.player = nil, nil, nil
    S.waiting, S.nextRequest = false, 0
    AVCS.dbByVehicleSQLID, AVCS.dbByPlayerID = nil, nil
    S.changed()
end)

return S
