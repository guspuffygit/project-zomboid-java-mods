require "TimedActions/ISBaseTimedAction"
require "CSR_FeatureFlags"
require "CSR_Utils"

CSR_MassageAction = ISBaseTimedAction:derive("CSR_MassageAction")

local MASSAGE_TIME = 350
local MASSAGE_RANGE = 2

local MASSAGE_OIL_TYPES = {
    ["Butter"] = true,
    ["CookingOil"] = true,
    ["OliveOil"] = true,
    ["VegetableOil"] = true,
}

function CSR_MassageAction.findOilOrButter(player)
    if not player then return nil end
    return CSR_Utils.findPreferredInventoryItem(player, function(item)
        if not item or not item.getType then return false end
        return MASSAGE_OIL_TYPES[item:getType()] == true
    end)
end

function CSR_MassageAction.hasStrain(bodyPart)
    if not bodyPart then return false end
    return bodyPart:getStiffness() > 0
end

function CSR_MassageAction:new(doctor, patient, bodyPart, oil)
    local o = ISBaseTimedAction.new(self, doctor)
    o.character = doctor
    o.patient = patient
    o.bodyPart = bodyPart
    o.oil = oil
    o.oilId = oil and oil.getID and oil:getID() or nil
    o.oilType = oil and oil.getFullType and oil:getFullType() or nil
    o.patientX = patient:getX()
    o.patientY = patient:getY()
    o.stopOnWalk = true
    o.stopOnRun = true
    o.maxTime = MASSAGE_TIME
    return o
end

function CSR_MassageAction:isValid()
    if not self.patient or self.patient:isDead() then return false end
    if self.character == self.patient then return false end
    if not self.bodyPart then return false end
    -- Check patient hasn't walked away
    if ISHealthPanel and ISHealthPanel.DidPatientMove then
        if ISHealthPanel.DidPatientMove(self.character, self.patient, self.patientX, self.patientY) then
            return false
        end
    end
    -- Re-resolve oil
    self.oil = CSR_Utils.findInventoryItemById(self.character, self.oilId, self.oilType) or self.oil
    return self.oil ~= nil and CSR_MassageAction.hasStrain(self.bodyPart)
end

function CSR_MassageAction:waitToStart()
    self.character:faceThisObject(self.patient)
    return self.character:shouldBeTurning()
end

function CSR_MassageAction:update()
    self.character:faceThisObject(self.patient)
    if ISHealthPanel and ISHealthPanel.setBodyPartActionForPlayer then
        ISHealthPanel.setBodyPartActionForPlayer(self.patient, self.bodyPart, self, "Massage", { bandage = true })
    end
    self.character:setMetabolicTarget(Metabolics.LightDomestic)

    -- Periodic low-volume exercise grunt
    self.gruntTimer = (self.gruntTimer or 0) + 1
    if self.gruntTimer >= 120 then
        self.gruntTimer = 0
        local voiceSound = self.patient:isFemale() and "VoiceFemaleExercise" or "VoiceMaleExercise"
        self.patient:playSound(voiceSound)
    end
end

function CSR_MassageAction:start()
    -- Use the bandage animation targeting the specific body part
    self:setActionAnim("Loot")
    self.character:SetVariable("LootPosition", "Mid")
    self.character:reportEvent("EventLootItem")
    self:setOverrideHandModels(nil, nil)
end

function CSR_MassageAction:stop()
    if ISHealthPanel and ISHealthPanel.setBodyPartActionForPlayer then
        ISHealthPanel.setBodyPartActionForPlayer(self.patient, self.bodyPart, nil, nil, nil)
    end
    ISBaseTimedAction.stop(self)
end

function CSR_MassageAction:perform()
    if ISHealthPanel and ISHealthPanel.setBodyPartActionForPlayer then
        ISHealthPanel.setBodyPartActionForPlayer(self.patient, self.bodyPart, nil, nil, nil)
    end

    -- Clear the muscle strain on the target body part
    if self.bodyPart then
        self.bodyPart:setStiffness(0)
    end

    -- Also reduce pain on the part
    if self.bodyPart then
        local currentPain = self.bodyPart:getAdditionalPain()
        if currentPain > 0 then
            self.bodyPart:setAdditionalPain(math.max(0, currentPain - 15))
        end
    end

    -- Award First Aid XP to masseur
    addXp(self.character, Perks.Doctor, 5)

    -- Sync body part state in MP
    if syncBodyPart then
        syncBodyPart(self.bodyPart, 0x00570188)
    end

    -- Consume a small amount of oil/butter (drainable)
    self.oil = CSR_Utils.findInventoryItemById(self.character, self.oilId, self.oilType) or self.oil
    if self.oil then
        if self.oil.Use and self.oil:IsDrainable() then
            self.oil:Use()
        end
        if self.oil.getContainer then
            local container = self.oil:getContainer()
            if container then
                container:setDrawDirty(true)
            end
        end
        if syncInventoryItem then
            syncInventoryItem(self.oil)
        elseif self.oil.transmitModData then
            self.oil:transmitModData()
        end
    end

    self.patient:Say("Ahh... that feels better")
    self.character:Say("Worked out the knots")

    ISBaseTimedAction.perform(self)
end

return CSR_MassageAction
