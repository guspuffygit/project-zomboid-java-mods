require "TimedActions/ISBaseTimedAction"
require "CSR_Utils"
require "CSR_Config"

CSR_LockpickVehicleDoorAction = ISBaseTimedAction:derive("CSR_LockpickVehicleDoorAction")

function CSR_LockpickVehicleDoorAction:new(character, vehicle, part, tool)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.vehicle = vehicle
    o.part = part
    o.tool = tool
    o.maxTime = CSR_Config.BASE_LOCKPICK_TIME
    o.stopOnWalk = true
    o.stopOnRun = true
    o.stopOnAim = true
    return o
end

function CSR_LockpickVehicleDoorAction:isValid()
    -- Only check that vehicle/part/tool still exist during execution.
    -- Door lock state changes in complete() — don't re-check isLocked here.
    return self.vehicle ~= nil and self.part ~= nil and self.tool ~= nil
end

function CSR_LockpickVehicleDoorAction:update()
    self.character:setMetabolicTarget(Metabolics.LightDomestic)
    self.gruntTimer = (self.gruntTimer or 0) + 1
    if self.gruntTimer >= 120 then
        self.gruntTimer = 0
        local voiceSound = self.character:isFemale() and "VoiceFemaleCorpseLowEffort" or "VoiceMaleCorpseLowEffort"
        self.character:playSound(voiceSound)
    end
end

function CSR_LockpickVehicleDoorAction:adjustMaxTime(maxTime)
    return maxTime
end

function CSR_LockpickVehicleDoorAction:start()
    self:setActionAnim("Craft")
    self:setOverrideHandModels(self.tool, nil)
    self.jobType = "Lockpick Vehicle"
    self.gruntTimer = 0
    self.sound = self.character:playSound("DoorIsLocked")
end

function CSR_LockpickVehicleDoorAction:stop()
    if self.sound and self.character:getEmitter():isPlaying(self.sound) then
        self.character:getEmitter():stopSound(self.sound)
    end
    ISBaseTimedAction.stop(self)
end

function CSR_LockpickVehicleDoorAction:perform()
    if self.sound and self.character:getEmitter():isPlaying(self.sound) then
        self.character:getEmitter():stopSound(self.sound)
    end
    if isClient() then
        sendClientCommand(self.character, "CommonSenseReborn", "LockpickVehicleDoor", {
            vehicleId = self.vehicle:getId(),
            partId = self.part:getId(),
            screwdriverId = self.tool:getID(),
            requestId = CSR_Utils.makeRequestId(self.character, "LockpickVehicleDoor"),
            requestTimestamp = getTimestampMs and getTimestampMs() or os.time() * 1000,
        })
    else
        local success = ZombRandFloat(0, 1) < CSR_Utils.calculateLockpickSuccess(self.character, self.tool, self.part)
        if success then
            CSR_Utils.unlockVehicleDoorPart(self.vehicle, self.part, self.character, true, false)
            self.character:Say("Unlocked it")
        else
            self.tool:setCondition(math.max(0, self.tool:getCondition() - 1))
            self.character:Say("Lockpick failed")
        end
    end
    ISBaseTimedAction.perform(self)
end

return CSR_LockpickVehicleDoorAction
