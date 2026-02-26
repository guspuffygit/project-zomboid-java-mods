require "TimedActions/ISBaseTimedAction"

ISAVCSTakeEngineParts = ISBaseTimedAction:derive("ISAVCSTakeEngineParts")

local function hasPermission(character, vehicle)
    local ok = AVCS.getPublicPermission(vehicle, "AllowTakeEngineParts")
    if not ok then
        ok = AVCS.getSimpleBooleanPermission(AVCS.checkPermission(character, vehicle))
    end
    return ok == true
end

function ISAVCSTakeEngineParts:isValid()
    if not self.part or not self.vehicle then return false end
    if not hasPermission(self.character, self.vehicle) then return false end
    return true
end

function ISAVCSTakeEngineParts:update()
    if not isServer() then
        self.character:faceThisObject(self.vehicle)
        if self.item then
            self.item:setJobDelta(self:getJobDelta())
        end
    end
    self.character:setMetabolicTarget(Metabolics.MediumWork)
end

function ISAVCSTakeEngineParts:start()
    if isServer() then return end
    if self.item then
        self.item:setJobType(getText("IGUI_TakeEngineParts"))
    end
end

function ISAVCSTakeEngineParts:stop()
    if not isServer() and self.item then
        self.item:setJobDelta(0)
    end
    ISBaseTimedAction.stop(self)
end

function ISAVCSTakeEngineParts:perform()
    if not isServer() and self.item then
        self.item:setJobDelta(0)
    end
    ISBaseTimedAction.perform(self)
    return true
end

function ISAVCSTakeEngineParts:complete()
    if not isServer() then return true end
    if not self.vehicle or not self.part then return false end
    if not hasPermission(self.character, self.vehicle) then return false end

    local cond = self.part:getCondition()
    local skill = self.character:getPerkLevel(Perks.Mechanics) - self.vehicle:getScript():getEngineRepairLevel()
    local condForPart = math.max(20 - skill, 5)

    local numParts = 0
    if condForPart > 0 then
        local roll = ZombRand(condForPart / 3, condForPart)
        numParts = math.floor(cond / roll)
    end

    if numParts > 0 then
        local items = self.character:getInventory():AddItems("Base.EngineParts", tonumber(numParts))
        if items then
            sendAddItemsToContainer(self.character:getInventory(), items)
        end
    else
        self.character:getXp():AddXP(Perks.Mechanics, 1, false, false, true)
    end

    self.part:setCondition(0)
    self.vehicle:transmitPartCondition(self.part)
    self.character:sendObjectChange("mechanicActionDone", { success = (numParts > 0) })

    if numParts > 0 then
        self.character:addMechanicsItem(
            self.item:getID() .. self.vehicle:getMechanicalID() .. "1",
            self.part,
            getGameTime():getCalender():getTimeInMillis()
        )
    else
        self.character:getXp():AddXP(Perks.Mechanics, 1, false, false, true)
    end

    if not self.character:getMechanicsItem(self.vehicle:getMechanicalID() .. "3") then
        self.character:getXp():AddXP(Perks.Mechanics, math.floor(cond / condForPart) / 2, false, false, true)
    end
    self.character:addMechanicsItem(
        self.vehicle:getMechanicalID() .. "3",
        self.part,
        getGameTime():getCalender():getTimeInMillis()
    )

    return true
end

function ISAVCSTakeEngineParts:getExtraLogData()
    if self.vehicle then
        return { self.vehicle:getScript():getName() }
    end
end

function ISAVCSTakeEngineParts:getDuration()
    if self.character:isTimedActionInstant() then
        return 1
    end
    if self.duration and self.duration > 0 then
        return self.duration
    end
    if self.maxTime and self.maxTime > 0 then
        return self.maxTime
    end
    return 300
end

function ISAVCSTakeEngineParts:new(character, part, item, maxTime)
    local o = ISBaseTimedAction.new(self, character)
    o.vehicle = part and part:getVehicle() or nil
    o.part = part
    o.item = item
    o.duration = tonumber(maxTime) or 300
    o.maxTime = o:getDuration()
    o.jobType = getText("IGUI_TakeEngineParts")
    return o
end
