require "TimedActions/ISBaseTimedAction"
require "CSR_FeatureFlags"
require "CSR_Utils"

CSR_RepairAllClothingAction = ISBaseTimedAction:derive("CSR_RepairAllClothingAction")

-- Cost model (per damaged garment processed):
--   * 1 thread Use
--   * 1 needle condition damage
--   * 1 fabric strip consumed
-- Effect (per garment):
--   * setCondition(conditionMax)
--   * removePatch() on every covered body part that currently has one
-- The action is one timed action that loops over all damaged worn clothing in
-- a single perform() so the player sees one craft animation, not N. Server
-- re-validates inventory and applies all changes authoritatively in MP.

local function performLocal(action)
    local player = action.character
    if not player then return end
    local inv = player:getInventory()
    if not inv then return end

    local list = CSR_Utils.getDamagedWornClothing(player)
    if #list == 0 then return end

    local processed = 0
    for _, item in ipairs(list) do
        local thread = CSR_Utils.findPreferredThread(player)
        local needle = CSR_Utils.findPreferredNeedle(player)
        local fabric = CSR_Utils.findPreferredFabricMaterial(player)
        if not (thread and needle and fabric) then break end

        if item.getConditionMax and item.setCondition then
            item:setCondition(item:getConditionMax())
        end

        if item.getCoveredParts and item.getPatchType and item.removePatch then
            local parts = item:getCoveredParts()
            if parts and parts.size then
                for i = 0, parts:size() - 1 do
                    local part = parts:get(i)
                    if part and item:getPatchType(part) ~= nil then
                        item:removePatch(part)
                    end
                end
            end
        end

        if thread.Use then thread:Use() else inv:Remove(thread) end
        if needle.setCondition and needle.getCondition then
            needle:setCondition(math.max(0, needle:getCondition() - 1))
        end
        inv:Remove(fabric)

        processed = processed + 1
    end

    if processed > 0 then
        player:Say("Mended my clothes")
        if Perks and Perks.Tailoring and addXp then
            addXp(player, Perks.Tailoring, 3 * processed)
        end
    end
end

function CSR_RepairAllClothingAction:new(character, thread, needle, fabric)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    -- thread/needle/fabric are only used as start-time references for the
    -- hand-model anim; per-item consumption is recomputed inside perform().
    o.thread = thread
    o.needle = needle
    o.fabric = fabric
    o.threadId = thread and thread.getID and thread:getID() or nil
    o.threadType = thread and thread.getFullType and thread:getFullType() or nil
    o.needleId = needle and needle.getID and needle:getID() or nil
    o.needleType = needle and needle.getFullType and needle:getFullType() or nil
    o.fabricId = fabric and fabric.getID and fabric:getID() or nil
    o.fabricType = fabric and fabric.getFullType and fabric:getFullType() or nil
    o.maxTime = 600
    o.stopOnWalk = not CSR_FeatureFlags.isWalkingActionsEnabled()
    o.stopOnRun = true
    return o
end

function CSR_RepairAllClothingAction:isValid()
    if CSR_Utils.findPreferredThread(self.character) == nil then return false end
    if CSR_Utils.findPreferredNeedle(self.character) == nil then return false end
    if CSR_Utils.findPreferredFabricMaterial(self.character) == nil then return false end
    local list = CSR_Utils.getDamagedWornClothing(self.character)
    return #list > 0
end

function CSR_RepairAllClothingAction:update()
    self.character:setMetabolicTarget(Metabolics.LightDomestic)
end

function CSR_RepairAllClothingAction:start()
    self.needle = CSR_Utils.findInventoryItemById(self.character, self.needleId, self.needleType) or self.needle
    self:setActionAnim("Craft")
    if self.needle and self.fabric then
        self:setOverrideHandModels(self.needle, self.fabric)
    end
end

function CSR_RepairAllClothingAction:perform()
    if isClient() then
        sendClientCommand(self.character, "CommonSenseReborn", "RepairAllClothing", {
            requestId = CSR_Utils.makeRequestId(self.character, "RepairAllClothing")
        })
    else
        performLocal(self)
    end

    ISBaseTimedAction.perform(self)
end

return CSR_RepairAllClothingAction
