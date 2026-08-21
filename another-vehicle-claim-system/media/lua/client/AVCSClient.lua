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
local function requestFullSync()
    sendClientCommand(getPlayer(), "AVCS", "requestFullSync", nil)
end

function AVCS.updateClientClaimVehicle(arg)
    -- A desync has occurred, this shouldn't happen
    -- We will request full data from server
    if not AVCS.dbByVehicleSQLID then
        requestFullSync()
        return
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
end

function AVCS.updateClientUnclaimVehicle(arg)
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

    AVCS.dbByVehicleSQLID[arg.VehicleID] = nil
    AVCS.dbByPlayerID[arg.OwnerPlayerID][arg.VehicleID] = nil
end

function AVCS.updateClientVehicleCoordinate(arg)
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
end

-- Batched form sent by the Storm pre-save location sync (AvcsVehicleLocationSync.java)
function AVCS.updateClientVehicleCoordinates(arg)
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
end

function AVCS.updateClientLastLogon(arg)
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
    if not AVCS.dbByVehicleSQLID then
        requestFullSync()
        return
    end
    if AVCS.dbByVehicleSQLID[arg.VehicleID] then
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
end

-- Vehicle ModData does not update immediately, workaround to force sync
function AVCS.registerClientVehicleSQLID(arg)
    local vehicleObj = getVehicleById(arg[1])
    if vehicleObj then
        vehicleObj:getModData().SQLID = arg[2]
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

AVCS.OnServerCommand = function(moduleName, command, arg)
    if moduleName ~= "AVCS" then
        return
    end

    if command == "fullSyncVehicleDB" then
        AVCS.dbByVehicleSQLID = arg
    elseif command == "fullSyncPlayerDB" then
        AVCS.dbByPlayerID = arg
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
    requestFullSync()
    sendClientCommand(getPlayer(), "AVCS", "updateLastKnownLogonTime", nil)
    Events.OnServerCommand.Add(AVCS.OnServerCommand)
    Events.OnTick.Remove(AVCS.AfterGameStart)
end

Events.OnTick.Add(AVCS.AfterGameStart)
Events.OnPreFillWorldObjectContextMenu.Add(AVCS.ClientOnPreFillWorldObjectContextMenu)
Events.EveryHours.Add(AVCS.ClientEveryHours)
