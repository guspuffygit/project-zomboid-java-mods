require "TimedActions/ISBaseTimedAction"

--[[
    CSR_UncapBarrelAction.lua
    Timed action that uncaps a vanilla barrel by adding a FluidContainer
    component.  Once the component exists the barrel behaves like a native
    PZ fluid container (fill, drain, rain collection) with no further CSR
    code needed — safe to remove the mod afterwards.
]]

CSR_UncapBarrelAction = ISBaseTimedAction:derive("CSR_UncapBarrelAction")

function CSR_UncapBarrelAction:isValid()
    if not self.barrel or not self.barrel:getSquare() then return false end
    if self.barrel:hasComponent(ComponentType.FluidContainer) then return false end
    return true
end

function CSR_UncapBarrelAction:start()
    self:setActionAnim("Disassemble")
end

function CSR_UncapBarrelAction:stop()
    ISBaseTimedAction.stop(self)
end

function CSR_UncapBarrelAction:perform()
    -- Guard against race in MP (another player uncapped first)
    if self.barrel:hasComponent(ComponentType.FluidContainer) then
        ISBaseTimedAction.perform(self)
        return
    end

    local component = ComponentType.FluidContainer:CreateComponent()
    component:setCapacity(self.capacity)
    component:setContainerName("CSR_Barrel")
    component:setRainCatcher(0.25)
    component:setCanPlayerEmpty(true)
    GameEntityFactory.AddComponent(self.barrel, true, component)

    local md = self.barrel:getModData()
    md.CSR_UB_Uncapped = true
    if self.barrel.transmitModData then
        self.barrel:transmitModData()
    end

    -- Light wrench wear
    if self.wrench and self.wrench:getCondition() > 0 then
        self.wrench:setCondition(self.wrench:getCondition() - 1)
    end

    self.character:setHaloNote(getText("IGUI_CSR_UB_Uncapped"), 0.7, 1.0, 0.7, 200)
    ISBaseTimedAction.perform(self)
end

function CSR_UncapBarrelAction:new(character, barrel, wrench)
    local o = ISBaseTimedAction.new(self, character)
    o.barrel = barrel
    o.wrench = wrench
    o.stopOnWalk = true
    o.stopOnRun = true
    o.maxTime = 300
    local sv = SandboxVars and SandboxVars.CommonSenseReborn or {}
    o.capacity = tonumber(sv.UsefulBarrelCapacity) or 400
    return o
end
