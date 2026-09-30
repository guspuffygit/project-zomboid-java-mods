--[[
	Some codes referenced from
	CarWanna - https://steamcommunity.com/workshop/filedetails/?id=2801264901
	Vehicle Recycling - https://steamcommunity.com/sharedfiles/filedetails/?id=2289429759
	K15's Mods - https://steamcommunity.com/id/KI5/myworkshopfiles/?appid=108600
--]]

if isClient() and not isServer() then
    return
end

--[[
Global variables that is accessed frequently
sortedPlayerTimeoutClaim is a table sorted in last known logon time timestamp and associated player id
--]]
AVCS.sortedPlayerTimeoutClaim = AVCS.sortedPlayerTimeoutClaim or {}

-- Common functions
function AVCS.sortCacheNow()
    table.sort(AVCS.sortedPlayerTimeoutClaim, function(a, b)
        return a.ExpiryTime < b.ExpiryTime
    end)
end

--[[
Global ModData is the server-side database for this vehicle claiming mod.
It is persistence only (serialized with the world save); it is never sent
over the network. Clients receive a full copy via sendServerCommand on
connect (fullSyncVehicleDB / fullSyncPlayerDB) and incremental deltas
(updateClient*) afterwards, and the server re-validates every mutation.

There are two ModData tables, keyed by Vehicle SQL ID or Player ID.
I have both because I want to minimize looping to perform differnt things

ModData AVCSByVehicleSQLID is stored like this
<Vehicle SQL ID>
- <OwnerPlayerID>
- <ClaimDateTime>
- <CarModel>
- <LastLocationX>
- <LastLocationY>
- <LastLocationUpdateDateTime>

ModData AVCSByPlayerID is stored like this
<OwnerPlayerID>
- <LastKnownLogonTime>
- <Vehicle SQL ID 1>
- <Vehicle SQL ID 2>
and so on
--]]

-- vehicleID is vehicle object ID
---@param playerObj IsoPlayer
function AVCS.claimVehicle(playerObj, vehicleID)
    if not playerObj or type(vehicleID) ~= "table" or type(vehicleID.vehicle) ~= "number" then
        return
    end
    local vehicleObj = getVehicleById(vehicleID.vehicle)
    if not vehicleObj then
        return
    end
    vehicleID = AVCS.getVehicleID(vehicleObj)
    -- If no ID, we create one
    if not vehicleID then
        vehicleObj:getModData().SQLID = tonumber(getTimestamp() .. vehicleObj:getSqlId())
        vehicleID = vehicleObj:getModData().SQLID
        sendServerCommand("AVCS", "registerClientVehicleSQLID", {
            vehicleObj:getId(),
            vehicleObj:getModData().SQLID,
        })
    end

    -- Make sure is not already claimed
    -- Only SQL ID is persistent, vehicleID is created on runtime
    if AVCS.dbByVehicleSQLID[vehicleID] then
        -- Using vanilla logging function, write to a log with suffix AVCS
        -- Datetime, Unix Time, Warning message, offender username, vehicle full name, coordinate
        -- [26-03-23 22:23:36.671] [1679840616] Warning: Attempting to claim already owned vehicle [Username] [Base.ExtremeCar] [13026,1215]
        if playerObj ~= nil then
            writeLog(
                "AVCS",
                "["
                    .. getTimestamp()
                    .. "] Warning: Attempting to claim already owned vehicle ["
                    .. playerObj:getUsername()
                    .. "] ["
                    .. vehicleObj:getScript():getFullName()
                    .. "] ["
                    .. math.floor(vehicleObj:getX())
                    .. ","
                    .. math.floor(vehicleObj:getY())
                    .. "]"
            )
            sendServerCommand(playerObj, "AVCS", "requestFullResync", {})
        end
    else
        -- Client UI validates at menu-open time only, which is stale by confirm
        -- time (stacked confirm dialogs, ticket dropped before confirm), so the
        -- server must re-validate before committing the claim
        if
            SandboxVars.AVCS.RequireTicket
            and not playerObj:getInventory():getFirstTypeRecurse("AVCSClaimOrb")
        then
            writeLog(
                "AVCS",
                "["
                    .. getTimestamp()
                    .. "] Warning: Attempting to claim without required ticket ["
                    .. playerObj:getUsername()
                    .. "] ["
                    .. vehicleObj:getScript():getFullName()
                    .. "] ["
                    .. math.floor(vehicleObj:getX())
                    .. ","
                    .. math.floor(vehicleObj:getY())
                    .. "]"
            )
            sendServerCommand(playerObj, "AVCS", "requestFullResync", {})
            return
        end

        if not AVCS.checkMaxClaim(playerObj) then
            writeLog(
                "AVCS",
                "["
                    .. getTimestamp()
                    .. "] Warning: Attempting to claim above vehicle limit ["
                    .. playerObj:getUsername()
                    .. "] ["
                    .. vehicleObj:getScript():getFullName()
                    .. "] ["
                    .. math.floor(vehicleObj:getX())
                    .. ","
                    .. math.floor(vehicleObj:getY())
                    .. "]"
            )
            sendServerCommand(playerObj, "AVCS", "requestFullResync", {})
            return
        end

        AVCS.dbByVehicleSQLID[vehicleID] = {
            OwnerPlayerID = playerObj:getUsername(),
            ClaimDateTime = getTimestamp(),
            CarModel = vehicleObj:getScript():getFullName(),
            LastLocationX = math.floor(vehicleObj:getX()),
            LastLocationY = math.floor(vehicleObj:getY()),
            LastLocationUpdateDateTime = getTimestamp(),
        }

        -- Minimum data to send to clients
        local tempArr = {
            VehicleID = vehicleID,
            OwnerPlayerID = playerObj:getUsername(),
            ClaimDateTime = getTimestamp(),
            CarModel = vehicleObj:getScript():getFullName(),
            LastLocationX = math.floor(vehicleObj:getX()),
            LastLocationY = math.floor(vehicleObj:getY()),
            LastLocationUpdateDateTime = getTimestamp(),
        }

        -- Store the updated ModData --
        ModData.add("AVCSByVehicleSQLID", AVCS.dbByVehicleSQLID)

        if not AVCS.dbByPlayerID[playerObj:getUsername()] then
            AVCS.dbByPlayerID[playerObj:getUsername()] = {
                [vehicleID] = true,
                LastKnownLogonTime = getTimestamp(),
            }

            -- New player, insert it to the cache, theoretically should be the latest entry
            table.insert(AVCS.sortedPlayerTimeoutClaim, {
                ExpiryTime = (
                    AVCS.dbByPlayerID[playerObj:getUsername()].LastKnownLogonTime
                    + (SandboxVars.AVCS.ClaimTimeout * 60 * 60)
                ),
                OwnerPlayerID = playerObj:getUsername(),
            })
        else
            AVCS.dbByPlayerID[playerObj:getUsername()][vehicleID] = true
            AVCS.dbByPlayerID[playerObj:getUsername()].LastKnownLogonTime = getTimestamp()
        end

        -- Store the updated ModData --
        ModData.add("AVCSByPlayerID", AVCS.dbByPlayerID)

        local item = playerObj:getInventory():getFirstTypeRecurse("AVCSClaimOrb")
        if item then
            playerObj:getInventory():Remove(item)
            sendRemoveItemFromContainer(playerObj:getInventory(), item)
        end

        sendServerCommand("AVCS", "updateClientClaimVehicle", tempArr)

        AVCS.audit(
            "Claimed",
            playerObj:getUsername(),
            vehicleID,
            AVCS.dbByVehicleSQLID[vehicleID],
            "[orb=" .. tostring(item ~= nil) .. "]"
        )
    end
end

-- vehicleID is SQL ID
---@param auditActor string|nil defaults to playerObj; an AVCS.AUDIT_ACTOR_* for automated removals
---@param auditReason string|nil which checkPermission rule allowed it, or why it fired
function AVCS.unclaimVehicle(playerObj, vehicleID, auditActor, auditReason)
    if AVCS.dbByVehicleSQLID[vehicleID] then
        local record = AVCS.dbByVehicleSQLID[vehicleID]
        local ownerPlayerID = record.OwnerPlayerID

        -- Audit before the delete; the record is the only source for model and coordinates
        AVCS.audit(
            "Unclaimed",
            auditActor or (playerObj and playerObj:getUsername()),
            vehicleID,
            record,
            "[via=" .. tostring(auditReason or "?") .. "]"
        )

        AVCS.dbByVehicleSQLID[vehicleID] = nil

        -- Store the updated ModData --
        ModData.add("AVCSByVehicleSQLID", AVCS.dbByVehicleSQLID)

        if AVCS.dbByPlayerID[ownerPlayerID][vehicleID] then
            AVCS.dbByPlayerID[ownerPlayerID][vehicleID] = nil
        end

        -- If the player has 0 vehicle, remove it completely
        local tempCount = 0
        for k, v in pairs(AVCS.dbByPlayerID[ownerPlayerID]) do
            if k ~= "LastKnownLogonTime" then
                tempCount = tempCount + 1
            end
            if tempCount >= 1 then
                break
            end
        end

        if tempCount == 0 then
            AVCS.dbByPlayerID[ownerPlayerID] = nil
        end

        -- Store the updated ModData --
        ModData.add("AVCSByPlayerID", AVCS.dbByPlayerID)

        -- Case sensitive
        local tempArr = {
            VehicleID = vehicleID,
            OwnerPlayerID = ownerPlayerID,
        }

        sendServerCommand("AVCS", "updateClientUnclaimVehicle", tempArr)
    else
        if playerObj ~= nil then
            sendServerCommand(playerObj, "AVCS", "requestFullResync", {})
        end
    end
end

-- Update Player Logon Time
function AVCS.updateLastKnownLogonTime(playerObj)
    if AVCS.dbByPlayerID[playerObj:getUsername()] ~= nil then
        AVCS.dbByPlayerID[playerObj:getUsername()].LastKnownLogonTime = getTimestamp()

        local tempArr = {
            PlayerID = playerObj:getUsername(),
            LastKnownLogonTime = AVCS.dbByPlayerID[playerObj:getUsername()].LastKnownLogonTime,
        }
        sendServerCommand("AVCS", "updateClientLastLogon", tempArr)
        ModData.add("AVCSByPlayerID", AVCS.dbByPlayerID)
    end
end

function AVCS.updateSpecifyVehicleUserPermission(arg)
    if
        type(arg) ~= "table"
        or type(arg.VehicleID) ~= "number"
        or arg.VehicleID ~= arg.VehicleID
        or arg.VehicleID < 0
        or arg.VehicleID > 9007199254740991
        or arg.VehicleID ~= math.floor(arg.VehicleID)
    then
        return false
    end

    local record = AVCS.dbByVehicleSQLID[arg.VehicleID]
    if not record then
        return false
    end

    local allowedFields = {
        AllowDrive = true,
        AllowPassenger = true,
        AllowSiphonFuel = true,
        AllowUninstallParts = true,
        AllowAttachVehicle = true,
        AllowDetechVehicle = true,
        AllowTakeEngineParts = true,
        AllowOpeningTrunk = true,
        AllowInflatTires = true,
        AllowDeflatTires = true,
    }
    for field in pairs(arg) do
        if field ~= "VehicleID" and field ~= "requestId" and not allowedFields[field] then
            return false
        end
    end
    for field in pairs(allowedFields) do
        if arg[field] ~= nil and type(arg[field]) ~= "boolean" then
            return false
        end
    end
    local update = { VehicleID = arg.VehicleID }
    for fieldName in pairs(allowedFields) do
        if arg[fieldName] ~= nil then
            if type(arg[fieldName]) ~= "boolean" then
                return false
            end
            if arg[fieldName] then
                record[fieldName] = true
            else
                record[fieldName] = nil
            end
            update[fieldName] = arg[fieldName]
        end
    end

    record.PermissionRevision = (record.PermissionRevision or 0) + 1
    update.PermissionRevision = record.PermissionRevision
    ModData.add("AVCSByVehicleSQLID", AVCS.dbByVehicleSQLID)
    sendServerCommand("AVCS", "updateClientSpecifyVehicleUserPermission", update)
    return true
end

-- Database might become inconsistent with one another due to whatever reasons
-- Using AVCSByVehicleSQLID as base, we will rebuild the Database on server start
function AVCS.rebuildDB()
    local tempDB = {}
    for k, v in pairs(AVCS.dbByVehicleSQLID) do
        if type(v) ~= "table" or not v.OwnerPlayerID then
            writeLog(
                "AVCS",
                "["
                    .. getTimestamp()
                    .. "] Warning: Skipping invalid vehicle claim ["
                    .. tostring(k)
                    .. "]"
            )
        else
            if not tempDB[v.OwnerPlayerID] then
                tempDB[v.OwnerPlayerID] = {}
            end

            tempDB[v.OwnerPlayerID][k] = true
            local previousPlayerData = AVCS.dbByPlayerID[v.OwnerPlayerID]
            if previousPlayerData and previousPlayerData.LastKnownLogonTime then
                tempDB[v.OwnerPlayerID].LastKnownLogonTime = previousPlayerData.LastKnownLogonTime
            else
                tempDB[v.OwnerPlayerID].LastKnownLogonTime = getTimestamp()
            end
        end
    end

    AVCS.dbByPlayerID = tempDB
    ModData.add("AVCSByPlayerID", AVCS.dbByPlayerID)
end

-- Send full database tables to a specific client via sendServerCommand
-- Workaround for broken ModData.request() / OnReceiveGlobalModData in Build 42.15.0
-- Kahlua does not implement weak Lua tables. Keep only bounded string keys.
local lastFullSync = {}
local lastSyncPrune = 0
function AVCS.sendFullSync(playerObj, requestId, protocol)
    if not playerObj then
        return
    end
    local now = getTimestampMs()
    local username = playerObj:getUsername()
    if type(username) ~= "string" or username == "" then
        return
    end
    local count, oldestKey, oldestTime = 0, nil, math.huge
    if now < lastSyncPrune or now - lastSyncPrune >= 10000 or not lastFullSync[username] then
        for key, timestamp in pairs(lastFullSync) do
            if now < timestamp or now - timestamp >= 60000 then
                lastFullSync[key] = nil
            else
                count = count + 1
                if timestamp < oldestTime then
                    oldestKey, oldestTime = key, timestamp
                end
            end
        end
        if count >= 4096 and not lastFullSync[username] and oldestKey then
            lastFullSync[oldestKey] = nil
        end
        lastSyncPrune = now
    end
    local previous = lastFullSync[username]
    if previous and now >= previous and now - previous < 4000 then
        return
    end
    lastFullSync[username] = now
    if
        protocol == 3
        and type(requestId) == "number"
        and requestId == requestId
        and requestId >= 1
        and requestId <= 9007199254740991
        and requestId == math.floor(requestId)
    then
        sendServerCommand(playerObj, "AVCS", "fullSyncSnapshotV3", {
            requestId = requestId,
            vehicles = AVCS.dbByVehicleSQLID,
            players = AVCS.dbByPlayerID,
        })
        return
    end
    if type(requestId) == "number" and requestId == requestId then
        sendServerCommand(
            playerObj,
            "AVCS",
            "fullSyncVehicleDBV2",
            { requestId = requestId, data = AVCS.dbByVehicleSQLID }
        )
        sendServerCommand(
            playerObj,
            "AVCS",
            "fullSyncPlayerDBV2",
            { requestId = requestId, data = AVCS.dbByPlayerID }
        )
        return
    end
    sendServerCommand(playerObj, "AVCS", "fullSyncVehicleDB", AVCS.dbByVehicleSQLID)
    sendServerCommand(playerObj, "AVCS", "fullSyncPlayerDB", AVCS.dbByPlayerID)
end

function AVCS.findLoadedVehicleBySQLID(vehicleID)
    local cell = getCell()
    if not cell then
        return nil
    end

    local vehicles = cell:getVehicles()
    if not vehicles then
        return nil
    end

    local it = vehicles:iterator()
    while it:hasNext() do
        local v = it:next()
        if v and v:getModData().SQLID == vehicleID then
            return v
        end
    end

    return nil
end

-- Best-effort tow-state check, wrapped in pcall in case the getter names
-- change in a future build; falls back to allowing the detach attempt.
function AVCS.vehicleHasTowLink(vehicleObj)
    local ok1, towing = pcall(function()
        return vehicleObj:getVehicleTowing()
    end)
    local ok2, towedBy = pcall(function()
        return vehicleObj:getVehicleTowedBy()
    end)
    if (ok1 and towing ~= nil) or (ok2 and towedBy ~= nil) then
        return true
    end
    -- Both getters failed, assume it might be towing rather than block the admin
    return not ok1 and not ok2
end

function AVCS.adminUntowVehicle(playerObj, vehicleID)
    local function reply(ok, reason)
        sendServerCommand(
            playerObj,
            "AVCS",
            "adminUntowVehicleResult",
            { ok = ok, reason = reason, VehicleID = vehicleID }
        )
    end

    if not playerObj or string.lower(playerObj:getAccessLevel() or "") ~= "admin" then
        reply(false, "notAdmin")
        return
    end

    if type(vehicleID) ~= "number" then
        reply(false, "badArgs")
        return
    end

    local vehicleObj = AVCS.findLoadedVehicleBySQLID(vehicleID)
    if not vehicleObj then
        reply(false, "notLoaded")
        return
    end

    if not AVCS.vehicleHasTowLink(vehicleObj) then
        reply(false, "notTowing")
        return
    end

    -- Same call vanilla's own detachTrailer command uses (VehicleCommands.lua)
    vehicleObj:breakConstraint(true, false)

    writeLog(
        "AVCS",
        "["
            .. getTimestamp()
            .. "] Admin untow: ["
            .. playerObj:getUsername()
            .. "] ["
            .. vehicleObj:getScript():getFullName()
            .. "] ["
            .. math.floor(vehicleObj:getX())
            .. ","
            .. math.floor(vehicleObj:getY())
            .. "]"
    )

    reply(true, "untowed")
end

AVCS.onClientCommand = function(moduleName, command, playerObj, arg)
    if moduleName == "AVCS" and command == "requestFullSync" then
        AVCS.sendFullSync(
            playerObj,
            type(arg) == "table" and arg.requestId or nil,
            type(arg) == "table" and arg.protocol or nil
        )
    elseif moduleName == "AVCS" and command == "claimVehicle" then
        AVCS.claimVehicle(playerObj, arg)
    elseif moduleName == "AVCS" and command == "unclaimVehicle" then
        local id = type(arg) == "table" and arg[1] or nil
        if not AVCS.checkManagementPermission(playerObj, id) then
            AVCS.audit(
                "Rejected unclaim",
                playerObj:getUsername(),
                id,
                AVCS.dbByVehicleSQLID[id],
                "[via=owner/admin required]"
            )
            AVCS.sendFullSync(playerObj)
            return
        end
        AVCS.unclaimVehicle(playerObj, id, playerObj:getUsername(), "owner/admin management")
    elseif moduleName == "AVCS" and command == "updateLastKnownLogonTime" then
        AVCS.updateLastKnownLogonTime(playerObj)
    elseif moduleName == "AVCS" and command == "updateSpecifyVehicleUserPermission" then
        local id = type(arg) == "table" and arg.VehicleID or nil
        local permitted = AVCS.checkManagementPermission(playerObj, id)
        local ok = permitted and AVCS.updateSpecifyVehicleUserPermission(arg) or false
        if type(arg) == "table" and type(arg.requestId) == "number" then
            sendServerCommand(
                playerObj,
                "AVCS",
                "permissionResult",
                { VehicleID = id, requestId = arg.requestId, ok = ok }
            )
        end
        if not permitted then
            AVCS.audit(
                "Rejected permissions",
                playerObj:getUsername(),
                id,
                AVCS.dbByVehicleSQLID[id],
                "[via=owner/admin required]"
            )
            AVCS.sendFullSync(playerObj)
            return
        end
        if not ok then
            AVCS.sendFullSync(playerObj)
        end
    elseif moduleName == "AVCS" and command == "adminUntowVehicle" then
        AVCS.adminUntowVehicle(playerObj, type(arg) == "table" and arg.VehicleID or nil)
    elseif moduleName == "AVCS" and command == "adminTeleportVehicle" then
        -- Handled in Java (AvcsAdminVehicleTeleport) on Storm servers; that handler sets the flag
        if not AvcsAdminTeleportEnabled then
            sendServerCommand(
                playerObj,
                "AVCS",
                "adminTeleportVehicleResult",
                { ok = false, reason = "noStorm", VehicleID = arg and arg.VehicleID or nil }
            )
        end
    elseif moduleName == "AVCS" and command == "rebuildDB" then
        if playerObj:getAccessLevel() == "admin" then
            AVCS.rebuildDB()
        end
    elseif moduleName == "AVCS" and command == "relayClientUpdateVehicleSQLID" then
        -- Transition from Mule Part SQLID to Vehicle SQLID
        -- Relay ModData changes
        if type(arg) ~= "table" or type(arg[1]) ~= "number" then
            return
        end
        local vehicleObj = getVehicleById(arg[1])
        if vehicleObj then
            -- We removing at server-side because client-side takes time to be updated to the server
            -- Client-side mod data changes can unfortunately be lost if server shutdown at this very moment
            -- It just bad game design thus we doing it at server-side in hope that the changes is saved if that happens
            local tempPart = AVCS.getMulePart(vehicleObj)
            if not vehicleObj:getModData().SQLID and tempPart and tempPart:getModData().SQLID then
                vehicleObj:getModData().SQLID = tempPart:getModData().SQLID
                tempPart:getModData().SQLID = nil
                vehicleObj:transmitPartModData(tempPart)
            end
            sendServerCommand("AVCS", "registerClientVehicleSQLID", {
                vehicleObj:getId(),
                vehicleObj:getModData().SQLID,
            })
        end
    end
end

-- Remove given player ID from DBs completely
-- This hopefully thororughly remove the player from server-side Global ModData
-- We don't really need to care about client-side AVCSByPlayerID Global ModData as client will always get new fresh set onConnected
-- We do need to care about server-side as we don't want the AVCSByPlayerID to be bloated which will slow down other functions
function AVCS.removePlayerCompletely(playerID)
    if AVCS.dbByPlayerID[playerID] ~= nil then
        for k, v in pairs(AVCS.dbByPlayerID[playerID]) do
            if k ~= "LastKnownLogonTime" then
                AVCS.unclaimVehicle(nil, k, AVCS.AUDIT_ACTOR_TIMEOUT, "claim-timeout")
            end
        end
    end
end

--[[
Transform dbAVCSByPlayerID into array of {LastKnownLogonTime, OwnerPlayerID}
--]]
local function createSortedPlayerTimeoutClaim()
    local temp = {}
    for k, v in pairs(AVCS.dbByPlayerID) do
        table.insert(temp, {
            ExpiryTime = (v.LastKnownLogonTime + (SandboxVars.AVCS.ClaimTimeout * 60 * 60)),
            OwnerPlayerID = k,
        })
    end

    AVCS.sortedPlayerTimeoutClaim = temp
    AVCS.sortCacheNow()
end

function AVCS.doClaimTimeout()
    local varIndex = 1
    local needSort = false
    -- As we dealing with indexes, we want to control the index value as we increment to avoid removing wrong index
    while varIndex <= #AVCS.sortedPlayerTimeoutClaim do
        if getTimestamp() > AVCS.sortedPlayerTimeoutClaim[varIndex].ExpiryTime then
            if AVCS.dbByPlayerID[AVCS.sortedPlayerTimeoutClaim[varIndex].OwnerPlayerID] ~= nil then
                -- Cache is not always up-to-date, validate the actual
                if
                    getTimestamp()
                    > (
                        AVCS.dbByPlayerID[AVCS.sortedPlayerTimeoutClaim[varIndex].OwnerPlayerID].LastKnownLogonTime
                        + (SandboxVars.AVCS.ClaimTimeout * 60 * 60)
                    )
                then
                    AVCS.removePlayerCompletely(
                        AVCS.sortedPlayerTimeoutClaim[varIndex].OwnerPlayerID
                    )
                    table.remove(AVCS.sortedPlayerTimeoutClaim, varIndex)
                else
                    -- Update the expiry time
                    AVCS.sortedPlayerTimeoutClaim[varIndex].ExpiryTime = (
                        AVCS.dbByPlayerID[AVCS.sortedPlayerTimeoutClaim[varIndex].OwnerPlayerID].LastKnownLogonTime
                        + (SandboxVars.AVCS.ClaimTimeout * 60 * 60)
                    )
                    needSort = true
                    varIndex = varIndex + 1
                end
            else
                -- User no longer exist, remove from index
                table.remove(AVCS.sortedPlayerTimeoutClaim, varIndex)
            end
        else
            -- Since sorted, assume everybody else has not expired
            break
        end
    end

    if needSort then
        AVCS.sortCacheNow()
    end
end

local function OnInitGlobalModData(isNewGame)
    -- When Mod first added to server
    if not ModData.exists("AVCSByVehicleSQLID") then
        ModData.create("AVCSByVehicleSQLID")
    end
    if not ModData.exists("AVCSByPlayerID") then
        ModData.create("AVCSByPlayerID")
    end

    -- Set global variable as this is frequently accessed
    AVCS.dbByVehicleSQLID = ModData.get("AVCSByVehicleSQLID")
    AVCS.dbByPlayerID = ModData.get("AVCSByPlayerID")

    if SandboxVars.AVCS.RebuildDB then
        AVCS.rebuildDB()
    end

    createSortedPlayerTimeoutClaim()
end

Events.OnInitGlobalModData.Add(OnInitGlobalModData)
Events.EveryTenMinutes.Add(AVCS.doClaimTimeout)
Events.OnClientCommand.Add(AVCS.onClientCommand)
