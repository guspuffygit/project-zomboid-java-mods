--[[
    Some codes referenced from
    CarWanna - https://steamcommunity.com/workshop/filedetails/?id=2801264901
    Vehicle Recycling - https://steamcommunity.com/sharedfiles/filedetails/?id=2289429759
    K15's Mods - https://steamcommunity.com/id/KI5/myworkshopfiles/?appid=108600
]]--

require "TimedActions/ISBaseTimedAction"
require "TimedActions/ISAVCSUninstallVehiclePart"
require "TimedActions/ISAVCSTakeEngineParts"
local ok = pcall(require, "AVCSShared")
if not ok then return end
AVCS = AVCS or {}

if isServer() and (not isClient()) and ISInventoryPage == nil then
    ISInventoryPage = {}
end

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
-- Vanilla actions overrides
-- =========================

-- ISEnterVehicle
if ISEnterVehicle and ISEnterVehicle.new then
    if not AVCS.oIsEnterVehicle then
        AVCS.oIsEnterVehicle = ISEnterVehicle.new
    end
else
    return
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
