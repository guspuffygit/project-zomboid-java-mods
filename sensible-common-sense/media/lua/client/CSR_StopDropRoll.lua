require "TimedActions/ISBaseTimedAction"
require "CSR_FeatureFlags"

--[[
    CSR_StopDropRoll.lua
    When on fire, context menu lets the player drop and roll to extinguish.
    Damages outermost clothing layers. Lucky trait reduces damage, Unlucky worsens it.
    Uses Bandage animation + crouch to simulate rolling (no custom animation asset needed).
]]

CSR_StopDropRollAction = ISBaseTimedAction:derive("CSR_StopDropRollAction")

local CLOTHING_LAYER_PRIORITY = {
    "FullSuit", "FullSuitHead", "Jacket", "BathRobe", "Dress",
    "Sweater", "SweaterHat", "Skirt", "Pants", "FullHelmet",
    "Hat", "FullHat", "Mask", "MaskEyes", "MaskFull",
    "TorsoExtra", "ShortSleeveShirt", "Shirt", "Tshirt",
    "Underwear", "Legs1", "TankTop", "Socks", "Shoes",
}

function CSR_StopDropRollAction:isValid()
    if not self.character then return false end
    if self.character:getVehicle() then return false end
    return self.character:isOnFire()
end

function CSR_StopDropRollAction:update()
    self.character:setMetabolicTarget(Metabolics.HeavyDomestic)
    self.tick = self.tick + 1
    if self.tick == self.quashTime and not self.extinguished then
        self.extinguished = true
        self:burnClothing()
        self:extinguishFlames()
        self.character:setHaloNote("Fire out!", 0.3, 1.0, 0.3, 180)
    end
end

function CSR_StopDropRollAction:start()
    self:setActionAnim("Bandage")
    self:setOverrideHandModels(nil, nil)
    self.wasSneaking = self.character:isSneaking()
    self.character:setSneaking(true)
end

function CSR_StopDropRollAction:stop()
    if not self.wasSneaking then
        self.character:setSneaking(false)
    end
    ISBaseTimedAction.stop(self)
end

function CSR_StopDropRollAction:perform()
    if not self.wasSneaking then
        self.character:setSneaking(false)
    end
    -- Safety: extinguish if somehow still burning
    if self.character:isOnFire() and not self.extinguished then
        self:extinguishFlames()
    end
    ISBaseTimedAction.perform(self)
end

function CSR_StopDropRollAction:extinguishFlames()
    if isClient() then
        self.character:sendStopBurning()
    else
        self.character:StopBurning()
    end
    local sq = self.character:getSquare()
    if sq then
        sq:transmitStopFire()
        sq:stopFire()
    end
end

function CSR_StopDropRollAction:burnClothing()
    local numToDamage = self:determineClothingDamage()
    if numToDamage <= 0 then return end

    local damaged = 0
    for _, bodyLocation in ipairs(CLOTHING_LAYER_PRIORITY) do
        if damaged >= numToDamage then break end
        local clothing = nil
        for i = 0, self.character:getWornItems():size() - 1 do
            local item = self.character:getWornItems():getItemByIndex(i)
            if item and item:getBodyLocation() == bodyLocation then
                clothing = item
                break
            end
        end
        if clothing then
            if clothing:getCanHaveHoles() then
                local coveredParts = BloodClothingType.getCoveredParts(clothing:getBloodClothingType())
                if coveredParts then
                    for j = 0, coveredParts:size() - 1 do
                        local part = coveredParts:get(j)
                        if clothing:getVisual():getHole(part) == 0.0 then
                            clothing:getVisual():setHole(part)
                            clothing:removePatch(part)
                            clothing:setCondition(clothing:getCondition() - clothing:getCondLossPerHole())
                            break
                        end
                    end
                end
            else
                clothing:setCondition(math.floor(clothing:getCondition() / 2))
            end
            damaged = damaged + 1
        end
    end

    if damaged > 0 then
        self.character:resetModel()
        sendClothing(self.character)
    end
end

function CSR_StopDropRollAction:determineClothingDamage()
    local lucky = self.character:getTraits():contains("Lucky")
    local unlucky = self.character:getTraits():contains("Unlucky")
    local count = ZombRand(3)
    if lucky then
        count = math.max(0, count - 1 - ZombRand(2))
    elseif unlucky then
        count = count + 1 + ZombRand(2)
    end
    return math.max(0, math.min(count, 3))
end

function CSR_StopDropRollAction:new(character, maxTime, quashTime)
    local o = ISBaseTimedAction.new(self, character)
    o.stopOnWalk = false
    o.stopOnRun = false
    o.stopOnAim = true
    o.tick = 0
    o.quashTime = quashTime
    o.maxTime = maxTime
    o.extinguished = false
    o.ignoreHandsWounds = true
    if character:isTimedActionInstant() then o.maxTime = 1 end
    return o
end

-- Context menu integration
local function onWorldContext(playerNum, context, worldObjects, test)
    if test then return end
    if not CSR_FeatureFlags.isStopDropRollEnabled() then return end

    local player = getSpecificPlayer(playerNum)
    if not player or player:isDead() or player:getVehicle() then return end
    if not player:isOnFire() then return end

    local option = context:addOption("Stop, Drop & Roll", worldObjects, function()
        ISTimedActionQueue.clear(player)
        local lucky = player:getTraits():contains("Lucky")
        local unlucky = player:getTraits():contains("Unlucky")
        local reducedTime = 0
        if lucky then
            reducedTime = 15 + ZombRand(30)
        elseif not unlucky then
            reducedTime = ZombRand(15)
        end
        local action = CSR_StopDropRollAction:new(player, 180, 100 - reducedTime)
        ISTimedActionQueue.add(action)
    end)

    local tooltip = ISWorldObjectContextMenu.addToolTip()
    local lucky = player:getTraits():contains("Lucky")
    local unlucky = player:getTraits():contains("Unlucky")
    local traitLine = ""
    if lucky then
        traitLine = " <LINE> <RGB:0.3,1,0.3> Lucky: faster extinguish, less clothing damage."
    elseif unlucky then
        traitLine = " <LINE> <RGB:1,0.3,0.3> Unlucky: slower extinguish, more clothing damage."
    end
    tooltip.description = "Drop to the ground and roll to smother the flames. <LINE> <LINE> <RGB:1,0.8,0.2> Warning: <RGB:1,1,1> outer clothing layers may be damaged." .. traitLine
    option.toolTip = tooltip
end

Events.OnFillWorldObjectContextMenu.Add(onWorldContext)
