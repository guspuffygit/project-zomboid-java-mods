require "TimedActions/ISBaseTimedAction"
require "CSR_Config"
require "CSR_Utils"

CSR_RestapleAction = ISBaseTimedAction:derive("CSR_RestapleAction")

function CSR_RestapleAction:isValid()
    if ISHealthPanel and ISHealthPanel.DidPatientMove then
        if ISHealthPanel.DidPatientMove(self.character, self.patient, self.patientX, self.patientY) then
            return false
        end
    end
    if not self.bodyPart then return false end
    if self.bodyPart:bandaged() then return false end
    local stapler = CSR_Utils.findStapler(self.character)
    local staples = CSR_Utils.findStaples(self.character)
    return stapler ~= nil and staples ~= nil
end

function CSR_RestapleAction:waitToStart()
    if self.character == self.patient then return false end
    self.character:faceThisObject(self.patient)
    return self.character:shouldBeTurning()
end

function CSR_RestapleAction:update()
    if self.character ~= self.patient then
        self.character:faceThisObject(self.patient)
    end
    if ISHealthPanel and ISHealthPanel.setBodyPartActionForPlayer then
        ISHealthPanel.setBodyPartActionForPlayer(self.patient, self.bodyPart, self, "Re-staple", { bandage = true })
    end
    self.character:setMetabolicTarget(Metabolics.LightDomestic)
end

function CSR_RestapleAction:start()
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

function CSR_RestapleAction:stop()
    self:stopSound()
    if ISHealthPanel and ISHealthPanel.setBodyPartActionForPlayer then
        ISHealthPanel.setBodyPartActionForPlayer(self.patient, self.bodyPart, nil, nil, nil)
    end
    ISBaseTimedAction.stop(self)
end

function CSR_RestapleAction:perform()
    self:stopSound()
    ISBaseTimedAction.perform(self)
    if ISHealthPanel and ISHealthPanel.setBodyPartActionForPlayer then
        ISHealthPanel.setBodyPartActionForPlayer(self.patient, self.bodyPart, nil, nil, nil)
    end
end

function CSR_RestapleAction:complete()
    local doctorLevel = self.character:getPerkLevel(Perks.Doctor)

    local staples = CSR_Utils.findStaples(self.character)
    if staples then
        staples:UseAndSync()
    end

    local pain = math.max(3, 15 - doctorLevel)
    self.bodyPart:setAdditionalPain(self.bodyPart:getAdditionalPain() + pain)

    local bandageLife = ZombRandFloat(0.5, 1.5) + (doctorLevel * 0.3)
    self.patient:getBodyDamage():SetBandaged(self.bodyPart:getIndex(), true, bandageLife, false, "Base.Stapler")

    syncBodyPart(self.bodyPart, 0xc001966b8e)

    return true
end

function CSR_RestapleAction:getDuration()
    if self.character:isTimedActionInstant() then return 1 end
    local doctorLevel = self.character:getPerkLevel(Perks.Doctor)
    return math.max(40, 80 - (doctorLevel * 4))
end

function CSR_RestapleAction:stopSound()
    if self.sound and self.character:getEmitter():isPlaying(self.sound) then
        self.character:stopOrTriggerSound(self.sound)
    end
end

function CSR_RestapleAction:new(doctor, patient, bodyPart)
    local o = ISBaseTimedAction.new(self, doctor)
    o.character = doctor
    o.patient = patient
    o.bodyPart = bodyPart
    o.patientX = patient:getX()
    o.patientY = patient:getY()
    o.stopOnWalk = true
    o.stopOnRun = true
    o.maxTime = o:getDuration()
    return o
end

return CSR_RestapleAction
