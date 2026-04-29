require "TimedActions/ISBaseTimedAction"
require "CSR_Config"
require "CSR_FeatureFlags"
require "CSR_Utils"

CSR_PackAllAmmoBoxesAction = ISBaseTimedAction:derive("CSR_PackAllAmmoBoxesAction")

local function performLocal(action)
    local player = action.character
    local roundType = action.roundType
    local boxType = action.boxType
    local perBox = action.perBox
    if not player or not roundType or not boxType or not perBox then return end

    local totalAvailable = CSR_Utils.countAmmoRoundsOfType(player, roundType)
    local boxesToMake = math.floor(totalAvailable / perBox)
    if boxesToMake < 1 then return end

    local totalToRemove = boxesToMake * perBox
    local rounds = CSR_Utils.collectAmmoRounds(player, roundType, totalToRemove)
    if #rounds < totalToRemove then return end

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

    for _ = 1, boxesToMake do
        container:AddItem(boxType)
    end
    container:setDrawDirty(true)
    player:Say("Packed " .. boxesToMake .. " boxes (" .. totalToRemove .. " rounds)")
end

function CSR_PackAllAmmoBoxesAction:new(character, roundType, boxType, perBox, label)
    local totalAvailable = CSR_Utils.countAmmoRoundsOfType(character, roundType)
    local boxesToMake = math.floor(totalAvailable / perBox)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.roundType = roundType
    o.boxType = boxType
    o.perBox = perBox
    o.label = label or "Pack ammo boxes"
    o.maxTime = math.max(CSR_Config.PACK_AMMO_BOX_TIME, boxesToMake * CSR_Config.BULK_PACK_AMMO_BOX_TIME_PER_ITEM)
    o.stopOnWalk = not CSR_FeatureFlags.isWalkingActionsEnabled()
    o.stopOnRun = true
    return o
end

function CSR_PackAllAmmoBoxesAction:isValid()
    return CSR_Utils.countAmmoRoundsOfType(self.character, self.roundType) >= self.perBox
end

function CSR_PackAllAmmoBoxesAction:update()
    self.character:setMetabolicTarget(Metabolics.LightDomestic)
end

function CSR_PackAllAmmoBoxesAction:start()
    if self.stopOnWalk then
        self:setActionAnim("Loot")
    end
    self.jobType = self.label
end

function CSR_PackAllAmmoBoxesAction:perform()
    if isClient() then
        sendClientCommand(self.character, "CommonSenseReborn", "PackAllAmmoBoxes", {
            roundType = self.roundType,
            boxType = self.boxType,
            perBox = self.perBox,
            requestId = CSR_Utils.makeRequestId(self.character, "PackAllAmmoBoxes"),
        })
    else
        performLocal(self)
    end
    ISBaseTimedAction.perform(self)
end

return CSR_PackAllAmmoBoxesAction
