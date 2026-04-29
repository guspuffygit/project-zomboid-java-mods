require "TimedActions/ISBaseTimedAction"
require "CSR_Utils"
require "CSR_Config"

CSR_PryVehicleDoorAction = ISBaseTimedAction:derive("CSR_PryVehicleDoorAction")

function CSR_PryVehicleDoorAction:new(character, vehicle, part, tool)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.vehicle = vehicle
    o.part = part
    o.tool = tool
    o.maxTime = CSR_Config.BASE_PRY_TIME
    o.stopOnWalk = true
    o.stopOnRun = true
    o.stopOnAim = true
    return o
end

function CSR_PryVehicleDoorAction:isValid()
    -- Only check that vehicle/part/tool still exist during execution.
    -- Door lock state changes in complete() — don't re-check isLocked here.
    return self.vehicle ~= nil and self.part ~= nil and self.tool ~= nil
end

function CSR_PryVehicleDoorAction:update()
    self.character:setMetabolicTarget(Metabolics.HeavyDomestic)
    self.gruntTimer = (self.gruntTimer or 0) + 1
    if self.gruntTimer >= 90 then
        self.gruntTimer = 0
        local voiceSound = self.character:isFemale() and "VoiceFemaleExercise" or "VoiceMaleExercise"
        self.character:playSound(voiceSound)
    end
end

function CSR_PryVehicleDoorAction:adjustMaxTime(maxTime)
    return maxTime
end

function CSR_PryVehicleDoorAction:start()
    self:setActionAnim("RemoveBarricade")
    self:setAnimVariable("RemoveBarricade", "CrowbarMid")
    self:setOverrideHandModels(self.tool, nil)
    self.jobType = "Pry Vehicle Door"
    self.gruntTimer = 0
    self.sound = self.character:playSound("BeginRemoveBarricadePlankCrowbar")
end

function CSR_PryVehicleDoorAction:stop()
    if self.sound and self.character:getEmitter():isPlaying(self.sound) then
        self.character:getEmitter():stopSound(self.sound)
    end
    ISBaseTimedAction.stop(self)
end

function CSR_PryVehicleDoorAction:perform()
    if self.sound and self.character:getEmitter():isPlaying(self.sound) then
        self.character:getEmitter():stopSound(self.sound)
    end
    if isClient() then
        sendClientCommand(self.character, "CommonSenseReborn", "PryVehicleDoor", {
            vehicleId = self.vehicle:getId(),
            partId = self.part:getId(),
            crowbarId = self.tool:getID(),
            requestId = CSR_Utils.makeRequestId(self.character, "PryVehicleDoor"),
            requestTimestamp = getTimestampMs and getTimestampMs() or os.time() * 1000
        })
    else
        local success = ZombRandFloat(0, 1) < CSR_Utils.calculatePrySuccess(self.character, self.tool)
        if success then
            CSR_Utils.unlockVehicleDoorPart(self.vehicle, self.part, self.character, true, true)
            self.character:Say("Got it open!")
        else
            self.tool:setCondition(math.max(0, self.tool:getCondition() - CSR_Config.TOOL_DAMAGE_ON_FAIL))
            self.character:Say("Pry failed")
        end
    end
    ISBaseTimedAction.perform(self)
end

return CSR_PryVehicleDoorAction
