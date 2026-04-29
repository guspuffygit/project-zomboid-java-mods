require "CSR_Utils"
require "CSR_Config"
require "Vehicles/TimedActions/ISHotwireVehicle"

CSR_ImprovisedHotwireAction = ISHotwireVehicle:derive("CSR_ImprovisedHotwireAction")

function CSR_ImprovisedHotwireAction:new(character, screwdriver)
    local o = ISHotwireVehicle.new(self, character)
    o.screwdriver = screwdriver
    o.maxTime = character:isTimedActionInstant() and 1 or CSR_Config.BASE_IMPROVISED_HOTWIRE_TIME
    return o
end

function CSR_ImprovisedHotwireAction:start()
    ISHotwireVehicle.start(self)
    self.jobType = "Improvised Hotwire"
    if self.screwdriver then
        self:setOverrideHandModels(self.screwdriver, nil)
    end
end

function CSR_ImprovisedHotwireAction:complete()
    local vehicle = self.character and self.character:getVehicle() or nil
    if not vehicle then
        return false
    end

    local electricity = self.character:getPerkLevel(Perks.Electricity)
    local wasHotwired = vehicle:isHotwired()

    vehicle:tryHotwire(electricity)

    if not wasHotwired and not vehicle:isHotwired() and self.screwdriver then
        self.screwdriver:setCondition(math.max(0, self.screwdriver:getCondition() - 1))
    end

    return true
end
