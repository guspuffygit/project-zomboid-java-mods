require "TimedActions/ISBaseTimedAction"

CSR_WarmUpAction = ISBaseTimedAction:derive("CSR_WarmUpAction")

function CSR_WarmUpAction:isValid()
    return not self.character:isDriving()
end

function CSR_WarmUpAction:update()
    if self.character:isCurrentState(IdleState.instance()) or self.character:isSitOnGround() then
        self.character:setMetabolicTarget(self.character:isPlayerMoving() and Metabolics.LightWork or Metabolics.JumpFence)
    end
end

function CSR_WarmUpAction:start()
    self.character:setVariable("ExerciseStarted", false)
    self.character:setVariable("ExerciseEnded", true)
    -- "WarmHands" does not exist in B42; "WashFace" is the closest valid
    -- animation (hands raised to face/mouth area, matching the blow-on-hands intent).
    self:setActionAnim("WashFace")
end

function CSR_WarmUpAction:animEvent(event, parameter)
    if getGameSpeed() ~= 1 then return end
    if event == "Breath" then
        if self.character:isFemale() then
            self.sound = self.character:playSound("BreathingWoman")
        else
            self.sound = self.character:playSound("BreathingMan")
        end
    elseif event == "RubHands" then
        addSound(self.character, self.character:getX(), self.character:getY(), self.character:getZ(), 2, 1)
        self.sound = self.character:playSound("RubHands")
    end
end

function CSR_WarmUpAction:stop()
    if self.sound and self.character:getEmitter():isPlaying(self.sound) then
        self.character:stopOrTriggerSound(self.sound)
    end
    ISBaseTimedAction.stop(self)
end

function CSR_WarmUpAction:perform()
    ISBaseTimedAction.perform(self)
end

function CSR_WarmUpAction:new(character)
    local o = ISBaseTimedAction.new(self, character)
    o.stopOnWalk = false
    o.stopOnRun = true
    o.stopOnAim = false
    o.forceProgressBar = true
    o.maxTime = 1400
    return o
end
