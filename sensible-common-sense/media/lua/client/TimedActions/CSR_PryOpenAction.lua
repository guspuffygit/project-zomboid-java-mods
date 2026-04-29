require "TimedActions/ISBaseTimedAction"
require "CSR_Utils"
require "CSR_Config"

CSR_PryOpenAction = ISBaseTimedAction:derive("CSR_PryOpenAction")

function CSR_PryOpenAction:new(character, target, tool)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.target = target
    o.tool = tool
    o.maxTime = CSR_Config.BASE_PRY_TIME
    o.stopOnWalk = true
    o.stopOnRun = true
    o.stopOnAim = true
    return o
end

function CSR_PryOpenAction:isValid()
    if not CSR_Utils.isPryTarget(self.target) or not self.tool or self.tool:getCondition() <= 0 then
        return false
    end

    if CSR_Utils.isBarricadedForPlayer(self.target, self.character) then
        return false
    end

    local sq = self.target and self.target.getSquare and self.target:getSquare() or nil
    if not sq then
        return false
    end

    return self.character:DistToSquared(sq:getX() + 0.5, sq:getY() + 0.5) <= 4
end

function CSR_PryOpenAction:waitToStart()
    self.character:faceThisObject(self.target or self.character)
    return self.character:shouldBeTurning()
end

function CSR_PryOpenAction:update()
    if self.target then
        self.character:faceThisObject(self.target)
    end
    self.character:setMetabolicTarget(Metabolics.HeavyDomestic)
    -- Intermittent struggle/exertion grunts
    self.gruntTimer = (self.gruntTimer or 0) + 1
    if self.gruntTimer >= 90 then
        self.gruntTimer = 0
        local voiceSound = self.character:isFemale() and "VoiceFemaleExercise" or "VoiceMaleExercise"
        self.character:playSound(voiceSound)
    end
end

function CSR_PryOpenAction:start()
    self:setActionAnim("RemoveBarricade")
    self:setAnimVariable("RemoveBarricade", "CrowbarMid")
    self:setOverrideHandModels(self.tool, nil)
    self.jobType = "Pry Open"
    self.gruntTimer = 0
    self.sound = self.character:playSound("BeginRemoveBarricadePlankCrowbar")
end

function CSR_PryOpenAction:stop()
    if self.sound and self.character:getEmitter():isPlaying(self.sound) then
        self.character:getEmitter():stopSound(self.sound)
    end
    ISBaseTimedAction.stop(self)
end

local pryFailCount = 0

local PRY_FRUSTRATION = {
    "Pry failed",
    "Come on...",
    "It won't budge!",
    "This is really jammed...",
    "Son of a...",
    "I'm gonna break this thing!",
    "Why won't this OPEN?!",
}

local function performLocalPry(self)
    local sandbox = SandboxVars and SandboxVars.CommonSenseReborn or {}
    local success = ZombRandFloat(0, 1) < CSR_Utils.calculatePrySuccess(self.character, self.tool)
    local noiseMult = sandbox.PryNoiseMultiplier or 1.0

    if success then
        if CSR_Utils.unlockTarget(self.target, self.character) then
            addSound(self.character, self.character:getX(), self.character:getY(), self.character:getZ(), CSR_Config.BASE_NOISE_RADIUS * noiseMult, 1)
            pryFailCount = 0
            self.character:Say("Got it open!")
        end
    else
        local wear = math.max(1, math.floor(CSR_Config.TOOL_DAMAGE_ON_FAIL * (sandbox.ToolWearMultiplier or 1.0)))
        self.tool:setCondition(math.max(0, self.tool:getCondition() - wear))
        addSound(self.character, self.character:getX(), self.character:getY(), self.character:getZ(), CSR_Config.BASE_NOISE_RADIUS * noiseMult * 0.5, 1)
        if ZombRandFloat(0, 1) < (sandbox.InjuryChance or 0.1) then
            self.character:getBodyDamage():AddDamage(BodyPartType.Hand_L, CSR_Config.INJURY_DAMAGE)
            self.character:Say("Ouch!")
        else
            pryFailCount = pryFailCount + 1
            local idx = math.min(pryFailCount, #PRY_FRUSTRATION)
            self.character:Say(PRY_FRUSTRATION[idx])
        end
    end
end

function CSR_PryOpenAction:perform()
    if self.sound and self.character:getEmitter():isPlaying(self.sound) then
        self.character:getEmitter():stopSound(self.sound)
    end
    if isClient() then
        local square = self.target:getSquare()
        local sprite = self.target.getSprite and self.target:getSprite() and self.target:getSprite():getName() or ""
        sendClientCommand(self.character, "CommonSenseReborn", "PryTarget", {
            x = square:getX(),
            y = square:getY(),
            z = square:getZ(),
            objectIndex = self.target.getObjectIndex and self.target:getObjectIndex() or -1,
            sprite = sprite,
            crowbarId = self.tool.getID and self.tool:getID() or nil,
            requestId = CSR_Utils.makeRequestId(self.character, "PryTarget"),
            requestTimestamp = getTimestampMs and getTimestampMs() or os.time() * 1000
        })
    else
        performLocalPry(self)
    end

    ISBaseTimedAction.perform(self)
end

return CSR_PryOpenAction
