require "TimedActions/ISBaseTimedAction"
require "CSR_Config"
require "CSR_FeatureFlags"
require "CSR_Utils"

CSR_StapleWoundAction = ISBaseTimedAction:derive("CSR_StapleWoundAction")

function CSR_StapleWoundAction:isValid()
    if ISHealthPanel and ISHealthPanel.DidPatientMove then
        if ISHealthPanel.DidPatientMove(self.character, self.patient, self.patientX, self.patientY) then
            return false
        end
    end
    if not self.bodyPart then return false end
    if self.bodyPart:bandaged() or self.bodyPart:stitched() then return false end
    local stapler = CSR_Utils.findStapler(self.character)
    local staples = CSR_Utils.findStaples(self.character)
    return stapler ~= nil and staples ~= nil
end

function CSR_StapleWoundAction:waitToStart()
    if self.character == self.patient then
        return false
    end
    self.character:faceThisObject(self.patient)
    return self.character:shouldBeTurning()
end

function CSR_StapleWoundAction:update()
    if self.character ~= self.patient then
        self.character:faceThisObject(self.patient)
    end
    if ISHealthPanel and ISHealthPanel.setBodyPartActionForPlayer then
        ISHealthPanel.setBodyPartActionForPlayer(self.patient, self.bodyPart, self, "Staple Wound", { bandage = true })
    end
    self.character:setMetabolicTarget(Metabolics.LightDomestic)
end

function CSR_StapleWoundAction:start()
    if self.character == self.patient then
        self:setActionAnim(CharacterActionAnims.Bandage)
        if ISHealthPanel and ISHealthPanel.getBandageType then
            self:setAnimVariable("BandageType", ISHealthPanel.getBandageType(self.bodyPart))
        end
        self.character:reportEvent("EventBandage")
    else
        self:setActionAnim("Loot")
        self.character:SetVariable("LootPosition", "Mid")
        self.character:reportEvent("EventLootItem")
    end
    self:setOverrideHandModels(nil, nil)
    self.sound = self.character:playSound("FirstAidApplyStitch")
end

function CSR_StapleWoundAction:stop()
    self:stopSound()
    if ISHealthPanel and ISHealthPanel.setBodyPartActionForPlayer then
        ISHealthPanel.setBodyPartActionForPlayer(self.patient, self.bodyPart, nil, nil, nil)
    end
    ISBaseTimedAction.stop(self)
end

function CSR_StapleWoundAction:perform()
    self:stopSound()
    ISBaseTimedAction.perform(self)
    if ISHealthPanel and ISHealthPanel.setBodyPartActionForPlayer then
        ISHealthPanel.setBodyPartActionForPlayer(self.patient, self.bodyPart, nil, nil, nil)
    end
end

function CSR_StapleWoundAction:complete()
    local doctorLevel = self.character:getPerkLevel(Perks.Doctor)

    if self.character:hasTrait(CharacterTrait.HEMOPHOBIC) and self.bodyPart:getBleedingTime() > 0 then
        self.character:getStats():add(CharacterStat.PANIC, 50)
        syncPlayerStats(self.character, 0x00000100)
    end

    local staples = CSR_Utils.findStaples(self.character)
    if staples then
        staples:UseAndSync()
    end

    local pain = CSR_Config.STAPLE_WOUND_PAIN - (doctorLevel * 2)
    if pain < 5 then pain = 5 end
    self.bodyPart:setAdditionalPain(self.bodyPart:getAdditionalPain() + pain)

    if self.bodyPart:isDeepWounded() then
        self.bodyPart:setStitched(true)
        self.bodyPart:setStitchTime(((1 + doctorLevel) / 2) * ZombRandFloat(1.0, 3.0))
    elseif self.bodyPart:isCut() then
        self.bodyPart:setCut(false, true)
    elseif self.bodyPart:scratched() then
        self.bodyPart:setScratched(false, true)
    end

    local bandageLife = ZombRandFloat(0.5, 1.5) + (doctorLevel * 0.3)
    self.patient:getBodyDamage():SetBandaged(self.bodyPart:getIndex(), true, bandageLife, false, "Base.Stapler")

    local infectionChance = CSR_Config.STAPLE_WOUND_INFECTION_CHANCE or 3
    if ZombRand(infectionChance + math.floor(doctorLevel * 0.5)) == 0 then
        self.bodyPart:setInfectedWound(true)
    end

    syncBodyPart(self.bodyPart, 0x00570188)

    return true
end

function CSR_StapleWoundAction:stopSound()
    if self.sound and self.character:getEmitter():isPlaying(self.sound) then
        self.character:stopOrTriggerSound(self.sound)
    end
end

function CSR_StapleWoundAction:getDuration()
    if self.character:isTimedActionInstant() then
        return 1
    end
    local doctorLevel = self.character:getPerkLevel(Perks.Doctor)
    return math.max(50, CSR_Config.STAPLE_WOUND_BASE_TIME - (doctorLevel * 5))
end

function CSR_StapleWoundAction:new(doctor, patient, bodyPart)
    local o = ISBaseTimedAction.new(self, doctor)
    o.character = doctor
    o.patient = patient
    o.bodyPart = bodyPart
    o.patientX = patient:getX()
    o.patientY = patient:getY()
    o.stopOnWalk = true
    o.stopOnRun = true

    local doctorLevel = doctor:getPerkLevel(Perks.Doctor)
    o.maxTime = math.max(50, CSR_Config.STAPLE_WOUND_BASE_TIME - (doctorLevel * 5))
    if doctor:isTimedActionInstant() then
        o.maxTime = 1
    end

    return o
end

return CSR_StapleWoundAction
