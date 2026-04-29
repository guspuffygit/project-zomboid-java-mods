require "TimedActions/ISBaseTimedAction"
require "CSR_Utils"
require "CSR_Config"

CSR_LockpickOpenAction = ISBaseTimedAction:derive("CSR_LockpickOpenAction")

function CSR_LockpickOpenAction:new(character, target, tool)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.target = target
    o.tool = tool
    o.maxTime = CSR_Config.BASE_LOCKPICK_TIME
    o.stopOnWalk = true
    o.stopOnRun = true
    o.stopOnAim = true
    return o
end

function CSR_LockpickOpenAction:isValid()
    if not self.target or not self.tool then return false end
    if not CSR_Utils.isPaperclip(self.tool) and self.tool:getCondition() <= 0 then return false end
    if not CSR_Utils.canLockpickWorldTarget(self.target, self.character) then return false end
    local sq = self.target and self.target.getSquare and self.target:getSquare() or nil
    if not sq then return false end
    return self.character:DistToSquared(sq:getX() + 0.5, sq:getY() + 0.5) <= 4
end

function CSR_LockpickOpenAction:update()
    self.character:setMetabolicTarget(Metabolics.LightDomestic)
    -- Intermittent focused effort grunts
    self.gruntTimer = (self.gruntTimer or 0) + 1
    if self.gruntTimer >= 120 then
        self.gruntTimer = 0
        local voiceSound = self.character:isFemale() and "VoiceFemaleCorpseLowEffort" or "VoiceMaleCorpseLowEffort"
        self.character:playSound(voiceSound)
    end
end

function CSR_LockpickOpenAction:start()
    self:setActionAnim("Craft")
    self:setOverrideHandModels(self.tool, nil)
    self.jobType = "Lockpick"
    self.gruntTimer = 0
    self.sound = self.character:playSound("DoorIsLocked")
end

function CSR_LockpickOpenAction:stop()
    if self.sound and self.character:getEmitter():isPlaying(self.sound) then
        self.character:getEmitter():stopSound(self.sound)
    end
    ISBaseTimedAction.stop(self)
end

local lockpickFailCount = 0

local LOCKPICK_FRUSTRATION = {
    "Lockpick failed",
    "Almost had it...",
    "Slipped again...",
    "This lock is tricky...",
    "Are you kidding me?!",
    "I can't feel the pins!",
    "This is impossible!",
}

local function performLocal(self)
    local success = ZombRandFloat(0, 1) < CSR_Utils.calculateLockpickSuccess(self.character, self.tool, self.target)
    if success and CSR_Utils.unlockTarget(self.target, self.character) then
        lockpickFailCount = 0
        if CSR_Utils.isPaperclip(self.tool) then
            self.character:getInventory():Remove(self.tool)
        end
        self.character:Say("Unlocked it")
        return
    end

    if not CSR_Utils.isPaperclip(self.tool) then
        self.tool:setCondition(math.max(0, self.tool:getCondition() - 1))
    end
    lockpickFailCount = lockpickFailCount + 1
    local idx = math.min(lockpickFailCount, #LOCKPICK_FRUSTRATION)
    self.character:Say(LOCKPICK_FRUSTRATION[idx])
end

function CSR_LockpickOpenAction:perform()
    if self.sound and self.character:getEmitter():isPlaying(self.sound) then
        self.character:getEmitter():stopSound(self.sound)
    end
    if isClient() then
        local square = self.target and self.target.getSquare and self.target:getSquare() or nil
        if square then
            sendClientCommand(self.character, "CommonSenseReborn", "LockpickTarget", {
                x = square:getX(),
                y = square:getY(),
                z = square:getZ(),
                objectIndex = self.target.getObjectIndex and self.target:getObjectIndex() or -1,
                sprite = self.target.getSprite and self.target:getSprite() and self.target:getSprite():getName() or "",
                screwdriverId = self.tool:getID(),
                isPaperclip = CSR_Utils.isPaperclip(self.tool) or false,
                requestId = CSR_Utils.makeRequestId(self.character, "LockpickTarget"),
                requestTimestamp = getTimestampMs and getTimestampMs() or os.time() * 1000,
            })
        end
    else
        performLocal(self)
    end

    ISBaseTimedAction.perform(self)
end

return CSR_LockpickOpenAction
