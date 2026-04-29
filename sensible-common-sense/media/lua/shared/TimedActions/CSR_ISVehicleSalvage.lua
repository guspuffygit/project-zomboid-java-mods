--[[
    CSR_ISVehicleSalvage.lua
    Timed action for salvaging a vehicle.
    Plays blowtorch animation, drains torch uses, awards XP,
    drops scrap materials on completion, removes the vehicle.
]]

require "TimedActions/ISBaseTimedAction"

CSR_ISVehicleSalvage = ISBaseTimedAction:derive("CSR_ISVehicleSalvage")

-- Loot table: { fullType, baseChance (0-1) }
-- Higher MetalWelding linearly increases each chance (bonusPerLevel applied)
local LOOT_TABLE = {
    { type = "Base.ScrapMetal",          baseChance = 0.90, maxQty = 8 },
    { type = "Base.SheetMetal",          baseChance = 0.70, maxQty = 4 },
    { type = "Base.SmallSheetMetal",     baseChance = 0.75, maxQty = 6 },
    { type = "Base.MetalPipe",           baseChance = 0.50, maxQty = 3 },
    { type = "Base.MetalBar",            baseChance = 0.45, maxQty = 3 },
    { type = "Base.Wire",               baseChance = 0.40, maxQty = 4 },
    { type = "Base.ElectronicsScrap",    baseChance = 0.35, maxQty = 3 },
    { type = "Base.Nails",              baseChance = 0.30, maxQty = 10 },
    { type = "Base.Screws",             baseChance = 0.30, maxQty = 10 },
    { type = "Base.UnusableMetal",       baseChance = 0.60, maxQty = 5 },
    { type = "Base.LeadPipe",           baseChance = 0.20, maxQty = 1 },
    { type = "Base.MetalStrips",        baseChance = 0.25, maxQty = 2 },
}

local TORCH_USES = 1
local BASE_TIME  = 2500  -- ticks

function CSR_ISVehicleSalvage:new(player, vehicle, torch)
    local o = ISBaseTimedAction.new(self) or {}
    setmetatable(o, self)
    self.__index = self

    o.character    = player
    o.vehicle      = vehicle
    o.torch        = torch
    o.stopOnWalk   = true
    o.stopOnRun    = true
    o.forceProgressBar = true

    -- Scale time with MetalWelding: each level reduces 80 ticks
    local weldLvl = player:getPerkLevel(Perks.MetalWelding)
    o.maxTime = math.max(800, BASE_TIME - (weldLvl * 80))

    return o
end

function CSR_ISVehicleSalvage:isValid()
    if not self.vehicle then return false end
    local vSq = self.vehicle:getSquare()
    if not vSq then return false end
    return true
end

function CSR_ISVehicleSalvage:waitToStart()
    self.character:faceThisObject(self.vehicle)
    return false
end

function CSR_ISVehicleSalvage:update()
    self.character:faceThisObject(self.vehicle)
end

function CSR_ISVehicleSalvage:start()
    self:setActionAnim("BlowTorch")
    self:setOverrideHandModels(self.torch and self.torch:getStaticModel() or nil, nil)
    self._soundID = self.character:playSound("BlowTorch")
end

function CSR_ISVehicleSalvage:stopSound()
    if self._soundID then
        local emitter = self.character:getEmitter()
        if emitter then
            if emitter:isPlaying(self._soundID) then
                self.character:stopOrTriggerSound(self._soundID)
            end
            emitter:stopSoundByName("BlowTorch")
        end
        self._soundID = nil
    end
end

function CSR_ISVehicleSalvage:stop()
    self:stopSound()
    ISBaseTimedAction.stop(self)
end

function CSR_ISVehicleSalvage:perform()
    self:stopSound()

    local player  = self.character
    local vehicle = self.vehicle
    if not player or not vehicle then
        ISBaseTimedAction.perform(self)
        return
    end

    local sq = vehicle:getSquare()

    -- 1) Drain torch
    if self.torch then
        local currentUses = self.torch:getCurrentUses()
        if currentUses and currentUses > 0 then
            local newUses = currentUses - TORCH_USES
            if newUses <= 0 then
                player:getInventory():Remove(self.torch)
            else
                self.torch:setCurrentUses(newUses)
            end
        end
    end

    -- 2) Calculate loot rolls
    local weldLvl = player:getPerkLevel(Perks.MetalWelding)
    local mechLvl = player:getPerkLevel(Perks.Mechanics)
    local bonusPerLevel = 0.03  -- +3% per MetalWelding level above 3

    local droppedSomething = false
    for _, entry in ipairs(LOOT_TABLE) do
        local chance = entry.baseChance + (math.max(0, weldLvl - 3) * bonusPerLevel)
        chance = math.min(chance, 0.98)

        -- Roll for each possible quantity
        local qty = 0
        for q = 1, entry.maxQty do
            if ZombRand(100) < (chance * 100) then
                qty = qty + 1
            else
                break  -- fail stops further rolls for this item
            end
        end

        if qty > 0 then
            for i = 1, qty do
                if sq then
                    sq:AddWorldInventoryItem(entry.type, 0, 0, 0)
                    droppedSomething = true
                end
            end
        end
    end

    -- 3) Award XP
    local xpMech  = 10 + (mechLvl * 2)
    local xpWeld  = 15 + (weldLvl * 2)
    player:getXp():AddXP(Perks.Mechanics,    xpMech)
    player:getXp():AddXP(Perks.MetalWelding, xpWeld)

    -- 4) Remove the vehicle
    if isClient() then
        sendClientCommand(player, "vehicle", "remove", { vehicle = vehicle:getId() })
    else
        vehicle:permanentlyRemove()
    end

    -- 5) HaloText feedback
    if player.setHaloNote then
        local msg = string.format("Vehicle salvaged! +%d Mechanics, +%d Welding", xpMech, xpWeld)
        player:setHaloNote(msg, 0.5, 1.0, 0.5, 300)
    end

    ISBaseTimedAction.perform(self)
end

return CSR_ISVehicleSalvage
