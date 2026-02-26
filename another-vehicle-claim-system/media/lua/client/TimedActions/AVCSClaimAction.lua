require "TimedActions/ISBaseTimedAction"
require "StormLib"

---@class ISAVCSVehicleClaimAction : ISBaseTimedAction
---@field character IsoGameCharacter
---@field vehicle BaseVehicle
---@field sound number
ISAVCSVehicleClaimAction = ISBaseTimedAction:derive("ISAVCSVehicleClaimAction")

function ISAVCSVehicleClaimAction:isValid()
    return self.vehicle and not self.vehicle:isRemovedFromWorld()
end

function ISAVCSVehicleClaimAction:waitToStart()
    self.character:faceThisObject(self.vehicle)
    return self.character:shouldBeTurning()
end

function ISAVCSVehicleClaimAction:update()
    Storm.debug('Facing vehicle')
    self.character:faceThisObject(self.vehicle)
    self.character:setMetabolicTarget(Metabolics.LightDomestic)
    if not self.character:getEmitter():isPlaying(self.sound) then
        self.sound = self.character:playSound("AVCSClaimSound")
    end
end

function ISAVCSVehicleClaimAction:start()
    Storm.debug('Walking to vehicle')
    self:setActionAnim("VehicleWorkOnMid")
    self.sound = self.character:playSound("AVCSClaimSound")
end

function ISAVCSVehicleClaimAction:stop()
    if self.sound ~= 0 then
        self.character:getEmitter():stopSound(self.sound)
    end
    ISBaseTimedAction.stop(self)
end

function ISAVCSVehicleClaimAction:perform()
    Storm.debug('performing')
    if self.sound ~= 0 then
        Storm.debug('stopping sound')
        self.character:getEmitter():stopSound(self.sound)
    end

    Storm.debug('Sending client command AVCS.claimVehicle(' .. self.vehicle:getId() .. ')')
	sendClientCommand(self.character, "AVCS", "claimVehicle", { vehicle = self.vehicle:getId() })

    Storm.debug('playSound CarLock')
    self.character:playSound("CarLock")

    if UdderlyVehicleRespawn and SandboxVars.AVCS.UdderlyRespawn then
        UdderlyVehicleRespawn.SpawnRandomVehicleSomewhere()
    end

    ISBaseTimedAction.perform(self)
end

function ISAVCSVehicleClaimAction:new(character, vehicle)
    local o = {}
    setmetatable(o, self)
    self.__index = self
    o.stopOnWalk = true
    o.stopOnRun = true

    ---@type IsoGameCharacter
    o.character = character
    ---@type BaseVehicle
    o.vehicle = vehicle

    o.maxTime = 480
    if character:isTimedActionInstant() then
        o.maxTime = 1
    end

    return o
end
