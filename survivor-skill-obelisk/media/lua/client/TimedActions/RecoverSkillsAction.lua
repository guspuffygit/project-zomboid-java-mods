require("TimedActions/ISBaseTimedAction")

---@class RecoverSkillsAction : ISBaseTimedAction
---@field character IsoGameCharacter
---@field deathId number
---@field sound number
RecoverSkillsAction = ISBaseTimedAction:derive("RecoverSkillsAction")

function RecoverSkillsAction:isValid()
    return self.deathId ~= nil
end

function RecoverSkillsAction:update()
    self.character:setMetabolicTarget(Metabolics.LightDomestic)
    if not self.character:getEmitter():isPlaying(self.sound) then
        self.sound = self.character:playSound("SurvivorSkillObeliskRecover")
    end
end

function RecoverSkillsAction:start()
    self:setActionAnim("VehicleWorkOnMid")
    self.sound = getSoundManager():playUISound("SurvivorSkillObeliskRecover")
end

function RecoverSkillsAction:stop()
    if self.sound ~= 0 then
        getSoundManager():stopUISound(self.sound)
        self.sound = 0
    end
    ISBaseTimedAction.stop(self)
end

function RecoverSkillsAction:perform()
    if self.sound ~= 0 then
        getSoundManager():stopUISound(self.sound)
        self.sound = 0
    end

    sendClientCommand(
        self.character,
        "SurvivorSkillObelisk",
        "recoverSkills",
        { id = self.deathId }
    )

    ISBaseTimedAction.perform(self)
end

function RecoverSkillsAction:new(character, deathId)
    local o = {}
    setmetatable(o, self)
    self.__index = self
    o.stopOnWalk = true
    o.stopOnRun = true

    o.character = character
    o.deathId = deathId

    -- ISReadABook derives maxTime from in-game minutes × 2 × minutesPerDay; substituting
    -- realSec × 24/minutesPerDay for in-game minutes cancels minutesPerDay out, so 1 real
    -- second is a fixed 48 maxTime units regardless of the world's day-length setting.
    o.maxTime = 121 * 30
    if character:isTimedActionInstant() then
        o.maxTime = 1
    end

    return o
end
