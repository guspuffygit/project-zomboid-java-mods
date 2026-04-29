require "TimedActions/ISBaseTimedAction"
require "CSR_Config"
require "CSR_FeatureFlags"
require "CSR_Utils"

CSR_IgniteCorpseAction = ISBaseTimedAction:derive("CSR_IgniteCorpseAction")

local function consumeIgnition(item)
    if item and item.Use then
        item:Use()
    end
end

local function performLocal(action)
    if not action.character or not action.corpse or not action.character.burnCorpse then
        return
    end

    action.character:burnCorpse(action.corpse)
    consumeIgnition(action.ignition)
end

function CSR_IgniteCorpseAction:new(character, corpse, ignition)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.corpse = corpse
    o.ignition = ignition
    o.maxTime = CSR_Config.CORPSE_IGNITE_TIME
    o.stopOnWalk = not CSR_FeatureFlags.isWalkingActionsEnabled()
    o.stopOnRun = true
    return o
end

function CSR_IgniteCorpseAction:isValid()
    if not CSR_FeatureFlags.isCorpseIgniteEnabled() then
        return false
    end

    if not self.character or not self.corpse or not self.ignition then
        return false
    end

    if self.corpse.getStaticMovingObjectIndex and self.corpse:getStaticMovingObjectIndex() < 0 then
        return false
    end

    local square = self.corpse.getSquare and self.corpse:getSquare() or nil
    if not square then
        return false
    end

    return self.character:DistToSquared(square:getX() + 0.5, square:getY() + 0.5) <= 9
end

function CSR_IgniteCorpseAction:update()
    if self.corpse then
        self.character:faceThisObject(self.corpse)
    end
    self.character:setMetabolicTarget(Metabolics.LightWork)
end

function CSR_IgniteCorpseAction:start()
    self:setActionAnim(CharacterActionAnims.Pour)
    self:setOverrideHandModels(self.ignition, nil)
end

function CSR_IgniteCorpseAction:perform()
    if isClient() then
        local square = self.corpse:getSquare()
        sendClientCommand(self.character, "CommonSenseReborn", "IgniteCorpse", {
            x = square:getX(),
            y = square:getY(),
            z = square:getZ(),
            corpseIndex = self.corpse.getStaticMovingObjectIndex and self.corpse:getStaticMovingObjectIndex() or -1,
            ignitionId = self.ignition.getID and self.ignition:getID() or nil,
            requestId = CSR_Utils.makeRequestId(self.character, "IgniteCorpse"),
            requestTimestamp = getTimestampMs and getTimestampMs() or os.time() * 1000,
        })
    else
        performLocal(self)
    end

    ISBaseTimedAction.perform(self)
end

return CSR_IgniteCorpseAction
