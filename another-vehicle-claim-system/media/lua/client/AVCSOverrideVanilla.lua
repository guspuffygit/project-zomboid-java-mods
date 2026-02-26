--[[
    Some codes referenced from
    CarWanna - https://steamcommunity.com/workshop/filedetails/?id=2801264901
    Vehicle Recycling - https://steamcommunity.com/sharedfiles/filedetails/?id=2289429759
    K15's Mods - https://steamcommunity.com/id/KI5/myworkshopfiles/?appid=108600
]]--

if not isClient() and isServer() then
    return
end

require "ISUI/ISModalDialog"
require "luautils"
require "TimedActions/ISTimedActionQueue" -- usato nei claim/unclaim
require "TimedActions/ISBaseTimedAction"
require "TimedActions/ISAVCSUninstallVehiclePart"
require "TimedActions/ISAVCSTakeEngineParts"

ISAVCSDeniedTimedAction = ISBaseTimedAction:derive("ISAVCSDeniedTimedAction")

function ISAVCSDeniedTimedAction:isValid()
    return true
end

function ISAVCSDeniedTimedAction:perform()
    ISBaseTimedAction.perform(self)
end

function ISAVCSDeniedTimedAction:getDuration()
    return 1
end

local function AVCS_IgnoredAction(character)
    return AVCS_DenyTimed(character)
end

function ISAVCSDeniedTimedAction:new(character, msg)
    local o = ISBaseTimedAction.new(self, character)
    o.maxTime = 1
    o.stopOnWalk = false
    o.stopOnRun  = false
    o.stopOnAim  = false
    if msg and character then
        character:setHaloNote(msg, 250, 250, 250, 300)
    end
    return o
end
-- =========================
-- Helpers
-- =========================
function AVCS_DenyTimed(character)
    return ISAVCSDeniedTimedAction:new(character, getText("IGUI_AVCS_Vehicle_No_Permission"))
end

-- =========================
-- Claim / Unclaim dialogs
-- =========================

local function claimVehicle(player, button, vehicle)
    if button.internal == "NO" then return end
    if luautils.walkAdj(player, vehicle:getSquare()) then
        ISTimedActionQueue.add(ISAVCSVehicleClaimAction:new(player, vehicle))
    end
end

local function claimCfmDialog(player, vehicle)
    local message = string.format("Confirm", vehicle:getScript():getName())
    local playerNum = player:getPlayerNum()
    local modal = ISModalDialog:new(
        (getCore():getScreenWidth() / 2) - (300 / 2),
        (getCore():getScreenHeight() / 2) - (150 / 2),
        300, 150, message, true, player, claimVehicle, playerNum, vehicle
    )
    modal:initialise()
    modal:addToUIManager()
end

local function unclaimVehicle(player, button, vehicle)
    if button.internal == "NO" then return end
    if luautils.walkAdj(player, vehicle:getSquare()) then
        ISTimedActionQueue.add(ISAVCSVehicleUnclaimAction:new(player, vehicle))
    end
end

local function unclaimCfmDialog(player, vehicle)
    local message = string.format("Confirm", vehicle:getScript():getName())
    local playerNum = player:getPlayerNum()
    local modal = ISModalDialog:new(
        (getCore():getScreenWidth() / 2) - (300 / 2),
        (getCore():getScreenHeight() / 2) - (150 / 2),
        300, 150, message, true, player, unclaimVehicle, playerNum, vehicle
    )
    modal:initialise()
    modal:addToUIManager()
end

-- =========================
-- Context menu
-- =========================

function AVCS.addOptionToMenuOutsideVehicle(player, context, vehicle)
    -- Ignore wrecks
    local vname = vehicle and vehicle:getScript() and vehicle:getScript():getName() or ""
    vname = string.lower(vname)
    if string.match(vname, "burnt") or string.match(vname, "smashed") then
        return
    end

    local checkResult = AVCS.checkPermission(player, vehicle)
    local option
    local toolTip = ISToolTip:new()
    toolTip:initialise()
    toolTip:setVisible(false)

    if type(checkResult) == "boolean" then
        if checkResult == true then
            local playerInv = player:getInventory()
            option = context:addOption(getText("ContextMenu_AVCS_ClaimVehicle"), player, claimCfmDialog, vehicle)
            option.toolTip = toolTip

            if playerInv:getItemCount("Base.AVCSClaimOrb") < 1 and SandboxVars.AVCS.RequireTicket then
                toolTip.description = getText("Tooltip_AVCS_Needs")
                    .. " <LINE><RGB:1,0.2,0.2>"
                    .. getItemNameFromFullType("Base.AVCSClaimOrb") .. " "
                    .. playerInv:getItemCount("Base.AVCSClaimOrb") .. "/1"
                option.notAvailable = true
            else
                if AVCS.checkMaxClaim(player) then
                    if SandboxVars.AVCS.RequireTicket then
                        toolTip.description = getText("Tooltip_AVCS_Needs")
                            .. " <LINE><RGB:0.2,1,0.2>"
                            .. getItemNameFromFullType("Base.AVCSClaimOrb") .. " "
                            .. playerInv:getItemCount("Base.AVCSClaimOrb") .. "/1"
                    else
                        toolTip.description = getText("Tooltip_AVCS_ClaimVehicle")
                    end
                    option.notAvailable = false
                else
                    toolTip.description = "<RGB:0.2,1,0.2>" .. getText("Tooltip_AVCS_ExceedLimit")
                    option.notAvailable = true
                end
            end

        elseif checkResult == false then
            option = context:addOption(getText("ContextMenu_AVCS_UnsupportedVehicle"), player, claimCfmDialog, vehicle)
            option.toolTip = toolTip
            toolTip.description = getText("Tooltip_AVCS_Unsupported")
            option.notAvailable = true
        end

    elseif checkResult.permissions == true then
        option = context:addOption(getText("ContextMenu_AVCS_UnclaimVehicle"), player, unclaimCfmDialog, vehicle)
        option.toolTip = toolTip
        toolTip.description =
            getText("Tooltip_AVCS_Owner") .. ": " .. checkResult.ownerid
            .. " <LINE>"
            .. getText("Tooltip_AVCS_Expire") .. ": "
            .. os.date("%d-%b-%y, %H:%M:%S", (checkResult.LastKnownLogonTime + (SandboxVars.AVCS.ClaimTimeout * 60 * 60)))
        option.notAvailable = false

    elseif checkResult.permissions == false then
        option = context:addOption(getText("ContextMenu_AVCS_UnclaimVehicle"), player, unclaimCfmDialog, vehicle)
        option.toolTip = toolTip
        toolTip.description =
            getText("Tooltip_AVCS_Owner") .. ": " .. checkResult.ownerid
            .. " <LINE>"
            .. getText("Tooltip_AVCS_Expire") .. ": "
            .. os.date("%d-%b-%y, %H:%M:%S", (checkResult.LastKnownLogonTime + (SandboxVars.AVCS.ClaimTimeout * 60 * 60)))
        option.notAvailable = true
    end

    -- Must not be towing or towed
    if option and (vehicle:getVehicleTowedBy() ~= nil or vehicle:getVehicleTowing() ~= nil) then
        toolTip.description = getText("Tooltip_AVCS_Towed")
        option.notAvailable = true
    end
end

if not AVCS.oMenuOutsideVehicle then
    AVCS.oMenuOutsideVehicle = ISVehicleMenu.FillMenuOutsideVehicle
end

function ISVehicleMenu.FillMenuOutsideVehicle(player, context, vehicle, test)
    AVCS.oMenuOutsideVehicle(player, context, vehicle, test)
    AVCS.addOptionToMenuOutsideVehicle(getSpecificPlayer(player), context, vehicle)
end

-- =========================
-- Vanilla actions overrides
-- =========================

-- ISEnterVehicle
if not AVCS.oIsEnterVehicle then
    AVCS.oIsEnterVehicle = ISEnterVehicle.new
end

function ISEnterVehicle:new(character, vehicle, seat)
    if seat ~= 0 then
        if AVCS.getPublicPermission(vehicle, "AllowPassenger") then
            return AVCS.oIsEnterVehicle(self, character, vehicle, seat)
        end
    end

    if seat == 0 then
        if AVCS.getPublicPermission(vehicle, "AllowDrive") then
            return AVCS.oIsEnterVehicle(self, character, vehicle, seat)
        end
    end

    local checkResult = AVCS.checkPermission(character, vehicle)
    checkResult = AVCS.getSimpleBooleanPermission(checkResult)

    if checkResult then
        return AVCS.oIsEnterVehicle(self, character, vehicle, seat)
    end

    character:setHaloNote(getText("IGUI_AVCS_Vehicle_No_Permission"), 250, 250, 250, 300)
    return AVCS_IgnoredAction(character)
end

-- ISSwitchVehicleSeat
if not AVCS.oISSwitchVehicleSeat then
    AVCS.oISSwitchVehicleSeat = ISSwitchVehicleSeat.new
end

function ISSwitchVehicleSeat:new(character, seatTo)
    if not character:getVehicle() then
        return AVCS.oISSwitchVehicleSeat(self, character, seatTo)
    end

    if seatTo ~= 0 then
        if AVCS.getPublicPermission(character:getVehicle(), "AllowPassenger") then
            return AVCS.oISSwitchVehicleSeat(self, character, seatTo)
        end
    end

    if seatTo == 0 then
        if AVCS.getPublicPermission(character:getVehicle(), "AllowDrive") then
            return AVCS.oISSwitchVehicleSeat(self, character, seatTo)
        end
    end

    local checkResult = AVCS.checkPermission(character, character:getVehicle())
    checkResult = AVCS.getSimpleBooleanPermission(checkResult)

    if checkResult then
        return AVCS.oISSwitchVehicleSeat(self, character, seatTo)
    end

    character:setHaloNote(getText("IGUI_AVCS_Vehicle_No_Permission"), 250, 250, 250, 300)
    return AVCS_IgnoredAction(character)
end

-- ISAttachTrailerToVehicle
if not AVCS.oISAttachTrailerToVehicle then
    AVCS.oISAttachTrailerToVehicle = ISAttachTrailerToVehicle.new
end

function ISAttachTrailerToVehicle:new(character, vehicleA, vehicleB, attachmentA, attachmentB)
    local checkResultA = AVCS.getPublicPermission(vehicleA, "AllowAttachVehicle")
    local checkResultB = AVCS.getPublicPermission(vehicleB, "AllowAttachVehicle")

    if checkResultA and checkResultB then
        return AVCS.oISAttachTrailerToVehicle(self, character, vehicleA, vehicleB, attachmentA, attachmentB)
    end

    checkResultA = AVCS.getSimpleBooleanPermission(AVCS.checkPermission(character, vehicleA))
    checkResultB = AVCS.getSimpleBooleanPermission(AVCS.checkPermission(character, vehicleB))

    if checkResultA and checkResultB then
        return AVCS.oISAttachTrailerToVehicle(self, character, vehicleA, vehicleB, attachmentA, attachmentB)
    end

    character:setHaloNote(getText("IGUI_AVCS_Vehicle_No_Permission"), 250, 250, 250, 300)
    return AVCS_IgnoredAction(character)
end

-- ISDetachTrailerFromVehicle
if not AVCS.oISDetachTrailerFromVehicle then
    AVCS.oISDetachTrailerFromVehicle = ISDetachTrailerFromVehicle.new
end

function ISDetachTrailerFromVehicle:new(character, vehicle, attachment)
    local checkResult = AVCS.getPublicPermission(vehicle, "AllowDetechVehicle")
    if not checkResult then
        checkResult = AVCS.getSimpleBooleanPermission(AVCS.checkPermission(character, vehicle))
    end

    if checkResult then
        return AVCS.oISDetachTrailerFromVehicle(self, character, vehicle, attachment)
    end

    character:setHaloNote(getText("IGUI_AVCS_Vehicle_No_Permission"), 250, 250, 250, 300)
    return AVCS_IgnoredAction(character)
end


-- ISUninstallVehiclePart (menu action)
do
    local oldOnUninstallPart = ISVehicleMechanics.onUninstallPart

    function ISVehicleMechanics.onUninstallPart(playerObj, part, item)
        local vehicle = part and part:getVehicle() or nil

        local ok = AVCS.getPublicPermission(vehicle, "AllowUninstallParts")
        if not ok then
            ok = AVCS.getSimpleBooleanPermission(AVCS.checkPermission(playerObj, vehicle))
        end
        if not ok then
            playerObj:setHaloNote(getText("IGUI_AVCS_Vehicle_No_Permission"), 250, 250, 250, 300)
            return
        end

        local tbl = part:getTable("uninstall")
        if not tbl then return end

        if not ISVehicleMechanics.cheat then
            if playerObj:getVehicle() then
                ISVehicleMenu.onExit(playerObj)
            end
            ISVehiclePartMenu.transferRequiredItems(playerObj, part, tbl)

            local area = tbl.area or part:getArea()
            ISTimedActionQueue.add(ISPathFindAction:pathToVehicleArea(playerObj, part:getVehicle(), area))

            ISVehiclePartMenu.equipRequiredItems(playerObj, part, tbl)
        end

        local engineCover = nil
        local keyvalues = part:getTable("install")
        if keyvalues and keyvalues.door then
            local doorPart = part:getVehicle():getPartById(keyvalues.door)
            if doorPart and doorPart:getDoor() and doorPart:getInventoryItem() and not doorPart:getDoor():isOpen() then
                engineCover = doorPart
            end
        end

        local time = tonumber(keyvalues and keyvalues.time) or 50
        if engineCover and not ISVehicleMechanics.cheat then
            ISTimedActionQueue.add(ISOpenVehicleDoor:new(playerObj, part:getVehicle(), engineCover))
            ISTimedActionQueue.add(ISAVCSUninstallVehiclePart:new(playerObj, part, time))
            ISTimedActionQueue.add(ISCloseVehicleDoor:new(playerObj, part:getVehicle(), engineCover))
        else
            ISTimedActionQueue.add(ISAVCSUninstallVehiclePart:new(playerObj, part, time))
        end
    end
end

-- ISUninstallVehiclePart (menu action, part menu)
do
    local oldOnUninstallPart = ISVehiclePartMenu and ISVehiclePartMenu.onUninstallPart

        if oldOnUninstallPart then
        function ISVehiclePartMenu.onUninstallPart(playerObj, part, item)
            local vehicle = part and part:getVehicle() or nil

            local ok = AVCS.getPublicPermission(vehicle, "AllowUninstallParts")
            if not ok then
                ok = AVCS.getSimpleBooleanPermission(AVCS.checkPermission(playerObj, vehicle))
            end
            if not ok then
                playerObj:setHaloNote(getText("IGUI_AVCS_Vehicle_No_Permission"), 250, 250, 250, 300)
                return
            end

            local tbl = part:getTable("uninstall")
            if not tbl then return end

            if not ISVehicleMechanics.cheat then
                if playerObj:getVehicle() then
                    ISVehicleMenu.onExit(playerObj)
                end
                ISVehiclePartMenu.transferRequiredItems(playerObj, part, tbl)

                local area = tbl.area or part:getArea()
                ISTimedActionQueue.add(ISPathFindAction:pathToVehicleArea(playerObj, part:getVehicle(), area))

                ISVehiclePartMenu.equipRequiredItems(playerObj, part, tbl)
            end

            local engineCover = nil
            local keyvalues = part:getTable("install")
            if keyvalues and keyvalues.door then
                local doorPart = part:getVehicle():getPartById(keyvalues.door)
                if doorPart and doorPart:getDoor() and doorPart:getInventoryItem() and not doorPart:getDoor():isOpen() then
                    engineCover = doorPart
                end
            end

            local time = tonumber(keyvalues and keyvalues.time) or 50
            if engineCover and not ISVehicleMechanics.cheat then
                ISTimedActionQueue.add(ISOpenVehicleDoor:new(playerObj, part:getVehicle(), engineCover))
                ISTimedActionQueue.add(ISAVCSUninstallVehiclePart:new(playerObj, part, time))
                ISTimedActionQueue.add(ISCloseVehicleDoor:new(playerObj, part:getVehicle(), engineCover))
            else
                ISTimedActionQueue.add(ISAVCSUninstallVehiclePart:new(playerObj, part, time))
            end
        end
    end
end

-- ISTakeEngineParts (menu action)
do
    local oldOnTakeEngineParts = ISVehicleMechanics.onTakeEngineParts

    function ISVehicleMechanics.onTakeEngineParts(playerObj, part)
        local vehicle = part and part:getVehicle() or nil

        local ok = AVCS.getPublicPermission(vehicle, "AllowTakeEngineParts")
        if not ok then
            ok = AVCS.getSimpleBooleanPermission(AVCS.checkPermission(playerObj, vehicle))
        end
        if not ok then
            playerObj:setHaloNote(getText("IGUI_AVCS_Vehicle_No_Permission"), 250, 250, 250, 300)
            return
        end

        if playerObj:getVehicle() then
            ISVehicleMenu.onExit(playerObj)
        end

        local typeToItem, tagToItem = VehicleUtils.getItems(playerObj:getPlayerNum())
        local item = tagToItem[ItemTag.WRENCH] and tagToItem[ItemTag.WRENCH][1]
        if not item then return end
        ISVehiclePartMenu.toPlayerInventory(playerObj, item)

        ISTimedActionQueue.add(ISPathFindAction:pathToVehicleArea(playerObj, part:getVehicle(), part:getArea()))

        local engineCover = nil
        local doorPart = part:getVehicle():getPartById("EngineDoor")
        if doorPart and doorPart:getDoor() and not doorPart:getDoor():isOpen() then
            engineCover = doorPart
        end

        local time = 300
        if engineCover then
            if engineCover:getDoor():isLocked() and VehicleUtils.RequiredKeyNotFound(part, playerObj) then
                ISTimedActionQueue.add(ISUnlockVehicleDoor:new(playerObj, engineCover))
            end
            ISTimedActionQueue.add(ISOpenVehicleDoor:new(playerObj, part:getVehicle(), engineCover))
            ISTimedActionQueue.add(ISAVCSTakeEngineParts:new(playerObj, part, item, time))
            ISTimedActionQueue.add(ISCloseVehicleDoor:new(playerObj, part:getVehicle(), engineCover))
        else
            ISTimedActionQueue.add(ISAVCSTakeEngineParts:new(playerObj, part, item, time))
        end
    end
end
-- ISUninstallVehiclePart
do
    local oldNew = ISUninstallVehiclePart.new

    function ISUninstallVehiclePart:new(character, part, workTime)
        if ISAVCSUninstallVehiclePart then
            return ISAVCSUninstallVehiclePart:new(character, part, workTime)
        end
        return oldNew(self, character, part, workTime)
    end
end
--  ISTakeGasolineFromVehicle
do
    local oldNew = ISTakeGasolineFromVehicle.new
    function ISTakeGasolineFromVehicle:new(character, part, item, ...)
        local vehicle = part and part:getVehicle()
        local ok = AVCS.getPublicPermission(vehicle, "AllowSiphonFuel")
        if not ok then
            ok = AVCS.getSimpleBooleanPermission(AVCS.checkPermission(character, vehicle))
        end
        if not ok then
            return AVCS_DenyTimed(character)
        end
        return oldNew(self, character, part, item, ...)
    end
end

-- ISTakeEngineParts
do
    local oldNew = ISTakeEngineParts.new
    function ISTakeEngineParts:new(character, part, item, maxTime)
        if ISAVCSTakeEngineParts then
            return ISAVCSTakeEngineParts:new(character, part, item, maxTime)
        end
        return oldNew(self, character, part, item, maxTime)
    end
end

-- ISInflateTire
do

    local oldNew = ISInflateTire.new
    
    function ISInflateTire:new(character, part, item, psiTarget, ...)
        local vehicle = part and part:getVehicle()

        -- Se non c’è vehicle/part, lascia vanilla decidere (isValid ecc.)
        if not vehicle then
            return oldNew(self, character, part, item, psiTarget, ...)
        end

        local ok = AVCS.getPublicPermission(vehicle, "AllowInflatTires")
        if not ok then
            ok = AVCS.getSimpleBooleanPermission(AVCS.checkPermission(character, vehicle))
        end
        if not ok then
            return AVCS_DenyTimed(character)
        end

        -- IMPORTANTISSIMO: ritorna l’azione vanilla, senza toccare maxTime/perform/update
        return oldNew(self, character, part, item, psiTarget, ...)
    end
end

-- ISDeflateTire
do
    local oldNew = ISDeflateTire.new
    function ISDeflateTire:new(character, part, psiTarget, ...)
        local vehicle = part and part:getVehicle()
        local ok = AVCS.getPublicPermission(vehicle, "AllowDeflatTires")
        if not ok then
            ok = AVCS.getSimpleBooleanPermission(AVCS.checkPermission(character, vehicle))
        end
        if not ok then
            return AVCS_DenyTimed(character)
        end
        return oldNew(self, character, part, psiTarget, ...)
    end
end

-- ISSmashVehicleWindow
if not AVCS.oISSmashVehicleWindow then
    AVCS.oISSmashVehicleWindow = ISSmashVehicleWindow.new
end

function ISSmashVehicleWindow:new(character, part, open)
    local vehicle = part and part.getVehicle and part:getVehicle()
    if not vehicle then
        return AVCS.oISSmashVehicleWindow(self, character, part, open)
    end

    local checkResult = AVCS.getSimpleBooleanPermission(AVCS.checkPermission(character, vehicle))
    if checkResult then
        return AVCS.oISSmashVehicleWindow(self, character, part, open)
    end

    character:setHaloNote(getText("IGUI_AVCS_Vehicle_No_Permission"), 250, 250, 250, 300)
    return AVCS_IgnoredAction(character)
end

-- ISOpenVehicleDoor (passenger = all doors, trunk = trunk only)

do
    local oldNew = ISOpenVehicleDoor.new

    local function isTrunkPart(part)
        local id = string.lower(part:getId() or "")
        return AVCS.matchTrunkPart(id)
    end

    function ISOpenVehicleDoor:new(character, vehicle, part)
        if not part or not instanceof(part, "VehiclePart") then
            return oldNew(self, character, vehicle, part)
        end

        -- OWNER / CLAIM: sempre consentito
        if AVCS.getSimpleBooleanPermission(AVCS.checkPermission(character, vehicle)) then
            return oldNew(self, character, vehicle, part)
        end

        -- PUBBLICO: AllowPassenger = tutto
        if AVCS.getPublicPermission(vehicle, "AllowPassenger") then
            return oldNew(self, character, vehicle, part)
        end

        -- PUBBLICO: AllowOpeningTrunk = SOLO trunk
        if AVCS.getPublicPermission(vehicle, "AllowOpeningTrunk") then
            if isTrunkPart(part) then
                return oldNew(self, character, vehicle, part)
            end
        end

        character:setHaloNote(getText("IGUI_AVCS_Vehicle_No_Permission"), 250, 250, 250, 300)
        return AVCS_IgnoredAction(character)
    end
end
