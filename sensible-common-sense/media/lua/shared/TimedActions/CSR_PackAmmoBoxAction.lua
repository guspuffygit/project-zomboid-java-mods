require "TimedActions/ISBaseTimedAction"
require "CSR_Config"
require "CSR_FeatureFlags"
require "CSR_Utils"

CSR_PackAmmoBoxAction = ISBaseTimedAction:derive("CSR_PackAmmoBoxAction")

local function performLocal(action)
    local player = action.character
    local roundType = action.roundType
    local boxType = action.boxType
    local perBox = action.perBox
    if not player or not roundType or not boxType or not perBox then return end

    local rounds = CSR_Utils.collectAmmoRounds(player, roundType, perBox)
    if #rounds < perBox then return end

    local container = player:getInventory()
    for _, round in ipairs(rounds) do
        if round.getContainer then
            local c = round:getContainer() or container
            if c.DoRemoveItem then
                c:DoRemoveItem(round)
            else
                c:Remove(round)
            end
        end
    end

    container:AddItem(boxType)
    container:setDrawDirty(true)
    player:Say("Packed " .. perBox .. " rounds into a box")
end

function CSR_PackAmmoBoxAction:new(character, roundType, boxType, perBox)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.roundType = roundType
    o.boxType = boxType
    o.perBox = perBox
    o.maxTime = CSR_Config.PACK_AMMO_BOX_TIME
    o.stopOnWalk = not CSR_FeatureFlags.isWalkingActionsEnabled()
    o.stopOnRun = true
    return o
end

function CSR_PackAmmoBoxAction:isValid()
    return CSR_Utils.countAmmoRoundsOfType(self.character, self.roundType) >= self.perBox
end

function CSR_PackAmmoBoxAction:update()
    self.character:setMetabolicTarget(Metabolics.LightDomestic)
end

function CSR_PackAmmoBoxAction:start()
    if self.stopOnWalk then
        self:setActionAnim("Loot")
    end
    self.jobType = "Pack Ammo Box"
end

function CSR_PackAmmoBoxAction:perform()
    if isClient() then
        sendClientCommand(self.character, "CommonSenseReborn", "PackAmmoBox", {
            roundType = self.roundType,
            boxType = self.boxType,
            perBox = self.perBox,
            requestId = CSR_Utils.makeRequestId(self.character, "PackAmmoBox"),
        })
    else
        performLocal(self)
    end
    ISBaseTimedAction.perform(self)
end

return CSR_PackAmmoBoxAction
