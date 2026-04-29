require "TimedActions/ISBaseTimedAction"
require "CSR_TrashSpriteWhitelist"

CSR_SweepTrashAction = ISBaseTimedAction:derive("CSR_SweepTrashAction")

function CSR_SweepTrashAction:isValid()
    if not self.character or self.character:isDead() then return false end
    local trashList = CSR_TrashSpriteWhitelist.findTrashOnSquare(self.square)
    return trashList ~= nil
end

function CSR_SweepTrashAction:waitToStart()
    self.character:faceLocation(self.square:getX(), self.square:getY())
    return self.character:shouldBeTurning()
end

function CSR_SweepTrashAction:update()
    self.character:faceLocation(self.square:getX(), self.square:getY())
    self.character:setMetabolicTarget(Metabolics.LightWork)
end

function CSR_SweepTrashAction:start()
    self:setActionAnim("ScrubFloor_Mop")
    self:setOverrideHandModels(self.broom, nil)
    self.sound = self.character:playSound("CleanBloodScrub")
    self.character:reportEvent("EventCleanBlood")
end

function CSR_SweepTrashAction:stop()
    self.character:stopOrTriggerSound(self.sound)
    ISBaseTimedAction.stop(self)
end

function CSR_SweepTrashAction:perform()
    self.character:stopOrTriggerSound(self.sound)
    ISBaseTimedAction.perform(self)
end

function CSR_SweepTrashAction:complete()
    local trashList = CSR_TrashSpriteWhitelist.findTrashOnSquare(self.square)
    if not trashList then return true end

    local removed = 0
    for _, trashObj in ipairs(trashList) do
        if self.square.transmitRemoveItemFromSquare then
            self.square:transmitRemoveItemFromSquare(trashObj)
        end
        removed = removed + 1
    end

    -- Track sweeps on the garbage bag
    if self.garbageBag then
        local md = self.garbageBag:getModData()
        local count = (md["CSR_SweepCount"] or 0) + removed
        md["CSR_SweepCount"] = count
    end

    return true
end

function CSR_SweepTrashAction:getDuration()
    if self.character:isTimedActionInstant() then return 1 end
    return 200
end

function CSR_SweepTrashAction:new(character, square, broom, garbageBag)
    local o = ISBaseTimedAction.new(self, character)
    o.square = square
    o.broom = broom
    o.garbageBag = garbageBag
    o.maxTime = o:getDuration()
    o.caloriesModifier = 5
    return o
end
