if isClient() and not isServer() then
    return
end

local FINE_PARKING_STEAMID = "76561197984809068"
local FINE_PARKING_CURRENCY = "Scraps"
local FINE_PARKING_REASON = "parking_violation"
local FINE_PARKING_COMMISSION_REASON = "parking_fine_commission"
local FINE_PARKING_COMMISSION_PCT = 0.10
local FINE_PARKING_MAX = 1000000

-- SteamID compare goes through AvcsSteamIdApi (Java) because Kahlua's 52-bit
-- mantissa corrupts 64-bit SteamIDs the moment getSteamID() crosses into Lua.
local function AVCS_serverCanFineParking(playerObj)
    if not playerObj then
        return false
    end
    if playerObj:getAccessLevel() == "admin" then
        return true
    end
    if AvcsSteamIdApi and AvcsSteamIdApi.getSteamIDString(playerObj) == FINE_PARKING_STEAMID then
        return true
    end
    return false
end

local function AVCS_notify(playerObj, text, r, g, b)
    if playerObj and playerObj.setHaloNote then
        playerObj:setHaloNote(text, r or 250, g or 250, b or 250, 300)
    end
end

local function AVCS_handleFineOwnerForParking(playerObj, arg)
    if not playerObj or not arg then
        return
    end

    if not AVCS_serverCanFineParking(playerObj) then
        writeLog(
            "AVCS",
            "["
                .. getTimestamp()
                .. "] Warning: Unauthorized fine attempt ["
                .. playerObj:getUsername()
                .. "]"
        )
        return
    end

    if not ATF_Economy or not ATF_Economy.fine then
        AVCS_notify(playerObj, "Economy mod not available", 250, 120, 120)
        return
    end

    local vehicleSQLID = arg.vehicleSQLID
    local amount = tonumber(arg.amount)
    if not vehicleSQLID or not amount or amount <= 0 or amount ~= amount then
        AVCS_notify(playerObj, "Fine cancelled: invalid amount", 250, 120, 120)
        return
    end
    amount = math.floor(amount)
    if amount > FINE_PARKING_MAX then
        amount = FINE_PARKING_MAX
    end

    local record = AVCS.dbByVehicleSQLID and AVCS.dbByVehicleSQLID[vehicleSQLID]
    if not record or not record.OwnerPlayerID then
        AVCS_notify(playerObj, "Fine cancelled: vehicle is not claimed", 250, 120, 120)
        return
    end
    local ownerName = record.OwnerPlayerID

    local result = ATF_Economy.fine(ownerName, FINE_PARKING_CURRENCY, amount, FINE_PARKING_REASON)

    writeLog(
        "AVCS",
        "["
            .. getTimestamp()
            .. "] Fine issued by ["
            .. playerObj:getUsername()
            .. "] against ["
            .. ownerName
            .. "] amount="
            .. tostring(amount)
            .. " "
            .. FINE_PARKING_CURRENCY
            .. " ok="
            .. tostring(result and result.ok)
            .. " reason="
            .. tostring(result and result.reason)
    )

    if result and result.ok then
        local collected = (result.eventIds and #result.eventIds or 0) * amount
        local commission = math.floor(collected * FINE_PARKING_COMMISSION_PCT)
        local commissionOk = false
        if commission > 0 and ATF_Economy.grant then
            local grantResult = ATF_Economy.grant(
                playerObj,
                FINE_PARKING_CURRENCY,
                commission,
                FINE_PARKING_COMMISSION_REASON
            )
            commissionOk = grantResult and grantResult.ok or false
            writeLog(
                "AVCS",
                "["
                    .. getTimestamp()
                    .. "] Commission paid to ["
                    .. playerObj:getUsername()
                    .. "] amount="
                    .. tostring(commission)
                    .. " "
                    .. FINE_PARKING_CURRENCY
                    .. " ok="
                    .. tostring(commissionOk)
                    .. " reason="
                    .. tostring(grantResult and grantResult.reason)
            )
        end

        local msg = "Fined " .. ownerName .. " " .. tostring(amount) .. " " .. FINE_PARKING_CURRENCY
        if commissionOk then
            msg = msg .. " (+" .. tostring(commission) .. " commission)"
        end
        AVCS_notify(playerObj, msg, 120, 250, 120)
    else
        AVCS_notify(
            playerObj,
            "Fine failed: " .. tostring(result and result.reason or "UNKNOWN"),
            250,
            120,
            120
        )
    end
end

local function AVCS_onClientCommandFine(moduleName, command, playerObj, arg)
    if moduleName == "AVCS" and command == "fineOwnerForParking" then
        AVCS_handleFineOwnerForParking(playerObj, arg)
    end
end

Events.OnClientCommand.Add(AVCS_onClientCommandFine)
