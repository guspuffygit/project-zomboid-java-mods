--[[
	Some codes referenced from
	CarWanna - https://steamcommunity.com/workshop/filedetails/?id=2801264901
	Vehicle Recycling - https://steamcommunity.com/sharedfiles/filedetails/?id=2289429759
	K15's Mods - https://steamcommunity.com/id/KI5/myworkshopfiles/?appid=108600
--]]

if not isClient() and isServer() then
    return
end

-- Request full database sync from server via sendClientCommand
-- Workaround for broken ModData.request() / OnReceiveGlobalModData in Build 42.15.0
local Sync = require("AVCSSync")
local requestFullSync = Sync.request

function AVCS.updateClientClaimVehicle(arg)
    -- A desync has occurred, this shouldn't happen
    -- We will request full data from server
    if type(arg) ~= "table" or not arg.VehicleID or not arg.OwnerPlayerID then
        return
    end
    if not Sync.deltaReady() then
        requestFullSync()
        return
    end

    local previous = AVCS.dbByVehicleSQLID[arg.VehicleID]
    if previous and previous.OwnerPlayerID ~= arg.OwnerPlayerID then
        local owner = AVCS.dbByPlayerID[previous.OwnerPlayerID]
        if not owner then
            requestFullSync()
            return
        end
        owner[arg.VehicleID] = nil
    end
    AVCS.dbByVehicleSQLID[arg.VehicleID] = {
        OwnerPlayerID = arg.OwnerPlayerID,
        ClaimDateTime = arg.ClaimDateTime,
        CarModel = arg.CarModel,
        LastLocationX = arg.LastLocationX,
        LastLocationY = arg.LastLocationY,
        LastLocationUpdateDateTime = arg.LastLocationUpdateDateTime,
    }

    if not AVCS.dbByPlayerID[arg.OwnerPlayerID] then
        AVCS.dbByPlayerID[arg.OwnerPlayerID] = {
            [arg.VehicleID] = true,
            LastKnownLogonTime = getTimestamp(),
        }
    else
        AVCS.dbByPlayerID[arg.OwnerPlayerID][arg.VehicleID] = true
        AVCS.dbByPlayerID[arg.OwnerPlayerID].LastKnownLogonTime = getTimestamp()
    end
    Sync.changed()
end

function AVCS.updateClientUnclaimVehicle(arg)
    if type(arg) ~= "table" or not arg.VehicleID then
        return
    end
    if not Sync.deltaReady() then
        return
    end
    -- A desync has occurred, this shouldn't happen
    -- We will request full data from server
    if not AVCS.dbByVehicleSQLID then
        requestFullSync()
        return
    end

    if AVCS.dbByVehicleSQLID[arg.VehicleID] == nil then
        requestFullSync()
        return
    end

    local record = AVCS.dbByVehicleSQLID[arg.VehicleID]
    local owner = AVCS.dbByPlayerID[record.OwnerPlayerID]
    if not owner or record.OwnerPlayerID ~= arg.OwnerPlayerID then
        requestFullSync()
        return
    end
    AVCS.dbByVehicleSQLID[arg.VehicleID] = nil
    owner[arg.VehicleID] = nil
    Sync.changed()
end

function AVCS.updateClientVehicleCoordinate(arg)
    if not Sync.deltaReady() then
        return
    end
    -- A desync has occurred, this shouldn't happen
    -- We will request full data from server
    if not AVCS.dbByVehicleSQLID then
        requestFullSync()
        return
    end

    if AVCS.dbByVehicleSQLID[arg.VehicleID] == nil then
        requestFullSync()
        return
    end

    AVCS.dbByVehicleSQLID[arg.VehicleID].LastLocationX = arg.LastLocationX
    AVCS.dbByVehicleSQLID[arg.VehicleID].LastLocationY = arg.LastLocationY
    AVCS.dbByVehicleSQLID[arg.VehicleID].LastLocationUpdateDateTime = arg.LastLocationUpdateDateTime
    Sync.changed()
end

-- Batched form sent by the Storm pre-save location sync (AvcsVehicleLocationSync.java)
function AVCS.updateClientVehicleCoordinates(arg)
    if not Sync.deltaReady() then
        return
    end
    if not AVCS.dbByVehicleSQLID then
        requestFullSync()
        return
    end

    local missing = false
    for _, v in ipairs(arg) do
        local entry = AVCS.dbByVehicleSQLID[v.VehicleID]
        if entry then
            entry.LastLocationX = v.LastLocationX
            entry.LastLocationY = v.LastLocationY
            entry.LastLocationUpdateDateTime = v.LastLocationUpdateDateTime
        else
            missing = true
        end
    end
    if missing then
        requestFullSync()
    end
    Sync.changed()
end

function AVCS.updateClientLastLogon(arg)
    if not Sync.deltaReady() then
        return
    end
    if not AVCS.dbByPlayerID then
        requestFullSync()
        return
    end

    if AVCS.dbByPlayerID[arg.PlayerID] == nil then
        requestFullSync()
        return
    end

    AVCS.dbByPlayerID[arg.PlayerID].LastKnownLogonTime = arg.LastKnownLogonTime
end

function AVCS.updateClientSpecifyVehicleUserPermission(arg)
    if not Sync.deltaReady() then
        return
    end
    if not AVCS.dbByVehicleSQLID then
        requestFullSync()
        return
    end
    if AVCS.dbByVehicleSQLID[arg.VehicleID] then
        local record = AVCS.dbByVehicleSQLID[arg.VehicleID]
        if arg.PermissionRevision and arg.PermissionRevision < (record.PermissionRevision or 0) then
            return
        end
        for k, v in pairs(arg) do
            if k ~= "VehicleID" then
                if v then
                    AVCS.dbByVehicleSQLID[arg.VehicleID][k] = v
                else
                    AVCS.dbByVehicleSQLID[arg.VehicleID][k] = nil
                end
            end
        end
    else
        requestFullSync()
    end
    Sync.changed()
end

-- Vehicle ModData does not update immediately, workaround to force sync
function AVCS.registerClientVehicleSQLID(arg)
    if type(arg) ~= "table" or type(arg[1]) ~= "number" or type(arg[2]) ~= "number" then
        return
    end
    if arg[3] == true then
        return
    end -- Native part data carries the authoritative identity.
    local vehicleObj = getVehicleById(arg[1])
    if vehicleObj then
        -- Never overwrite an already known identity with a delayed runtime-ID hint.
        -- Legacy servers without part identities retain their immediate loaded-only hint.
        local data = vehicleObj:getModData()
        if not data.SQLID or data.SQLID == arg[2] then
            data.SQLID = arg[2]
        end
    end
end

-- Admin-only (server re-checks the role): move a claimed vehicle next to the admin
function AVCS.requestAdminTeleportVehicle(vehicleID)
    sendClientCommand(getPlayer(), "AVCS", "adminTeleportVehicle", {
        VehicleID = vehicleID,
        OffsetX = AVCS.AdminTeleportOffset.x,
        OffsetY = AVCS.AdminTeleportOffset.y,
    })
end

function AVCS.onAdminTeleportVehicleResult(arg)
    if type(arg) ~= "table" then
        return
    end
    local reason = arg.reason or "badArgs"
    local msg = getTextOrNull("IGUI_AVCS_Admin_Teleport_" .. reason)
        or getText("IGUI_AVCS_Admin_Teleport_badArgs")
    if arg.ok and arg.X and arg.Y then
        msg = getText("IGUI_AVCS_Admin_Teleport_moved", arg.X, arg.Y)
        if arg.VehicleID and AVCS.dbByVehicleSQLID and AVCS.dbByVehicleSQLID[arg.VehicleID] then
            AVCS.dbByVehicleSQLID[arg.VehicleID].LastLocationX = arg.X
            AVCS.dbByVehicleSQLID[arg.VehicleID].LastLocationY = arg.Y
            AVCS.dbByVehicleSQLID[arg.VehicleID].LastLocationUpdateDateTime = getTimestamp()
        end
        if AVCS.UI.AdminInstance then
            AVCS.UI.AdminInstance:updateVehicleLocation(arg.VehicleID, arg.X, arg.Y)
        end
        if AVCS.UI.UserInstance then
            AVCS.UI.UserInstance:updateVehicleLocation(arg.VehicleID, arg.X, arg.Y)
        end
    end
    getPlayer():setHaloNote(msg, 250, 250, 250, 300)
end

-- Admin-only (server re-checks the role): break a claimed vehicle's tow constraint
function AVCS.requestAdminUntowVehicle(vehicleID)
    sendClientCommand(getPlayer(), "AVCS", "adminUntowVehicle", {
        VehicleID = vehicleID,
    })
end

function AVCS.onAdminUntowVehicleResult(arg)
    if type(arg) ~= "table" then
        return
    end
    local reason = arg.reason or "badArgs"
    local msg = getTextOrNull("IGUI_AVCS_Admin_Untow_" .. reason)
        or getText("IGUI_AVCS_Admin_Untow_badArgs")
    getPlayer():setHaloNote(msg, 250, 250, 250, 300)
end

AVCS.OnServerCommand = function(moduleName, command, arg)
    if moduleName ~= "AVCS" then
        return
    end

    if command == "fullSyncVehicleDBV2" then
        Sync.receive("vehicle", arg.data, arg.requestId)
    elseif command == "fullSyncPlayerDBV2" then
        Sync.receive("player", arg.data, arg.requestId)
    elseif command == "fullSyncVehicleDB" then
        Sync.receive("vehicle", arg)
    elseif command == "fullSyncPlayerDB" then
        Sync.receive("player", arg)
    elseif command == "updateClientClaimVehicle" then
        AVCS.updateClientClaimVehicle(arg)
    elseif command == "updateClientUnclaimVehicle" then
        AVCS.updateClientUnclaimVehicle(arg)
    elseif command == "updateClientVehicleCoordinate" then
        AVCS.updateClientVehicleCoordinate(arg)
    elseif command == "updateClientVehicleCoordinates" then
        AVCS.updateClientVehicleCoordinates(arg)
    elseif command == "updateClientLastLogon" then
        AVCS.updateClientLastLogon(arg)
    elseif command == "requestFullResync" then
        requestFullSync()
    elseif command == "updateClientSpecifyVehicleUserPermission" then
        AVCS.updateClientSpecifyVehicleUserPermission(arg)
    elseif command == "registerClientVehicleSQLID" then
        AVCS.registerClientVehicleSQLID(arg)
    elseif command == "adminTeleportVehicleResult" then
        AVCS.onAdminTeleportVehicleResult(arg)
    elseif command == "adminUntowVehicleResult" then
        AVCS.onAdminUntowVehicleResult(arg)
    elseif command == "damageBlocked" then
        getPlayer():setHaloNote(getText("IGUI_AVCS_Vehicle_No_Permission"), 250, 250, 250, 300)
    elseif command == "containerBlocked" then
        getPlayer():setHaloNote(getText("IGUI_AVCS_Vehicle_No_Permission"), 250, 250, 250, 300)
        ISInventoryPage.dirtyUI()
    elseif command == "enterBlocked" then
        -- The server refused our seat; we entered it predictively, so back out of it
        local playerObj = getPlayer()
        local vehicleObj = playerObj and playerObj:getVehicle()
        if
            vehicleObj
            and ISExitVehicle
            and (not arg or not arg.vehicle or vehicleObj:getId() == arg.vehicle)
        then
            ISTimedActionQueue.clear(playerObj)
            ISTimedActionQueue.add(ISExitVehicle:new(playerObj))
        end
        if playerObj then
            playerObj:setHaloNote(getText("IGUI_AVCS_Vehicle_No_Permission"), 250, 250, 250, 300)
        end
    end
end

local function openClientUserManager()
    if AVCS.UI.UserInstance ~= nil then
        AVCS.UI.UserInstance:close()
    end

    local width = math.floor(650 * AVCS.getUIFontScale())
    local height = math.floor(350 * AVCS.getUIFontScale())

    local x = getCore():getScreenWidth() / 2 - (width / 2)
    local y = getCore():getScreenHeight() / 2 - (height / 2)

    AVCS.UI.UserInstance = AVCS.UI.UserManagerMain:new(x, y, width, height)
    AVCS.UI.UserInstance:initialise()
    AVCS.UI.UserInstance:addToUIManager()
    AVCS.UI.UserInstance:setVisible(true)
end

local function openClientAdminManager()
    if AVCS.UI.AdminInstance ~= nil then
        AVCS.UI.AdminInstance:close()
    end

    local width = math.floor(955 * AVCS.getUIFontScale())
    local height = math.floor(500 * AVCS.getUIFontScale())

    local x = getCore():getScreenWidth() / 2 - (width / 2)
    local y = getCore():getScreenHeight() / 2 - (height / 2)

    AVCS.UI.AdminInstance = AVCS.UI.AdminManagerMain:new(x, y, width, height)
    AVCS.UI.AdminInstance:initialise()
    AVCS.UI.AdminInstance:addToUIManager()
    AVCS.UI.AdminInstance:setVisible(true)
end

function AVCS.ClientOnPreFillWorldObjectContextMenu(player, context, worldObjects, test)
    context:addOption(
        getText("ContextMenu_AVCS_ClientUserUI"),
        worldObjects,
        openClientUserManager,
        nil
    )
    if
        (string.lower(getPlayer():getAccessLevel()) == "admin")
        or (not isClient() and not isServer())
    then
        context:addOption(
            getText("ContextMenu_AVCS_AdminUserUI"),
            worldObjects,
            openClientAdminManager,
            nil
        )
    end
end

function AVCS.ClientEveryHours()
    if AVCS.dbByPlayerID and AVCS.dbByPlayerID[getPlayer():getUsername()] ~= nil then
        sendClientCommand(getPlayer(), "AVCS", "updateLastKnownLogonTime", nil)
    end
end

function AVCS.AfterGameStart()
    if not getPlayer() then
        return
    end
    Events.OnServerCommand.Add(AVCS.OnServerCommand)
    requestFullSync()
    sendClientCommand(getPlayer(), "AVCS", "updateLastKnownLogonTime", nil)
    Events.OnTick.Remove(AVCS.AfterGameStart)
end

Events.OnTick.Add(AVCS.AfterGameStart)
Events.OnPreFillWorldObjectContextMenu.Add(AVCS.ClientOnPreFillWorldObjectContextMenu)
Events.EveryHours.Add(AVCS.ClientEveryHours)
