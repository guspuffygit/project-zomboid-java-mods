require "CSR_FeatureFlags"

--[[
    CSR_ClimbWithBags.lua
    Keep bags in your hands when climbing through windows, over fences,
    or up/down sheet ropes. Heavier bags increase climb time proportionally.
    Inspired by hand-bag-window-climb (Workshop 3389093252).

    Also allows climbing while holding a generator or other heavy item
    (gated by EnableClimbWithGenerator). Generators get a heavier time
    penalty. Inspired by Carry Visible Generators (Workshop 3390487814).

    The Java climb methods (climbThroughWindow, climbOverFence, etc.) start a
    character state machine that runs over multiple frames. The state machine
    drops hand items during its execution — AFTER perform() returns. So we
    cannot re-equip immediately in perform(). Instead we:
      1. Remove items from hands before the climb (so the state machine finds
         nothing to drop and items stay safely in inventory).
      2. Schedule a delayed re-equip that polls getCurrentState() each tick
         and restores items once the character exits the climbing state.
]]

local pendingReequips = {}

--- Check if an item should be preserved through climbing.
--- Returns true for bags (if ClimbWithBags enabled) or generators/heavy items
--- (if ClimbWithGenerator enabled).
local function shouldPreserveItem(item)
    if not item then return false end
    if CSR_FeatureFlags.isClimbWithBagsEnabled() and item:IsInventoryContainer() then
        return true
    end
    if CSR_FeatureFlags.isClimbWithGeneratorEnabled() then
        local fullType = item:getFullType()
        if fullType == "Base.Generator" or fullType == "Base.Generator_Blue"
            or fullType == "Base.Generator_Yellow" or fullType == "Base.Generator_Old" then
            return true
        end
    end
    return false
end

--- Calculate extra climb time based on held item weight.
--- Returns a multiplier (1.0 = no penalty, higher = slower).
local function getClimbTimePenalty(player)
    local penalty = 0
    local primary = player:getPrimaryHandItem()
    local secondary = player:getSecondaryHandItem()
    if primary and shouldPreserveItem(primary) then
        local weight = primary:getActualWeight() or 0
        -- Generators are much heavier: 0.25 per kg vs 0.1 per kg for bags
        local rate = primary:IsInventoryContainer() and 0.1 or 0.25
        penalty = penalty + weight * rate
    end
    if secondary and shouldPreserveItem(secondary) and secondary ~= primary then
        local weight = secondary:getActualWeight() or 0
        local rate = secondary:IsInventoryContainer() and 0.1 or 0.25
        penalty = penalty + weight * rate
    end
    return 1.0 + penalty
end

--- Check if character is currently in a climbing state.
local function isClimbingState(character)
    local state = character:getCurrentState()
    if not state then return false end
    return state == ClimbThroughWindowState.instance()
        or state == ClimbOverFenceState.instance()
        or state == ClimbOverWallState.instance()
        or state == ClimbSheetRopeState.instance()
        or state == ClimbDownSheetRopeState.instance()
end

--- Process pending re-equip operations each tick.
--- Waits until the character exits climbing state before restoring bags.
local function processPendingReequips()
    for i = #pendingReequips, 1, -1 do
        local entry = pendingReequips[i]
        local chr = entry.character
        entry.ticks = entry.ticks + 1

        if isClimbingState(chr) then
            entry.seenClimbing = true
        end

        local doReequip = false
        if entry.ticks > 300 then
            -- Safety: give up after ~5 seconds
            table.remove(pendingReequips, i)
        elseif entry.seenClimbing and not isClimbingState(chr) then
            -- Saw the climb start, now it finished
            doReequip = true
        elseif not entry.seenClimbing and entry.ticks > 60 then
            -- Never entered climbing state (instant climb?), re-equip anyway
            doReequip = true
        end

        if doReequip then
            local inv = chr:getInventory()
            if inv then
                if entry.primaryItem and inv:contains(entry.primaryItem) then
                    chr:setPrimaryHandItem(entry.primaryItem)
                    if entry.bothHands then
                        chr:setSecondaryHandItem(entry.primaryItem)
                    end
                    -- v1.8.5: MP sync. Without these, the server-authoritative
                    -- character keeps the climb-state's empty hands and the
                    -- bag stays "unequipped" from other clients' POV until the
                    -- next idle. Forcing a transmit + visual reset closes the
                    -- desync that made bags fall out in MP.
                    if isClient and isClient() then
                        pcall(function()
                            if chr.resetEquippedHandsModels then chr:resetEquippedHandsModels() end
                            if chr.transmitEquippedItem then
                                chr:transmitEquippedItem(entry.primaryItem, BloodBodyPartType.Hand_R, true)
                            end
                            if entry.bothHands and chr.transmitEquippedItem then
                                chr:transmitEquippedItem(entry.primaryItem, BloodBodyPartType.Hand_L, false)
                            end
                        end)
                    end
                end
                if entry.secondaryItem and entry.secondaryItem ~= entry.primaryItem
                   and inv:contains(entry.secondaryItem) then
                    chr:setSecondaryHandItem(entry.secondaryItem)
                    if isClient and isClient() then
                        pcall(function()
                            if chr.resetEquippedHandsModels then chr:resetEquippedHandsModels() end
                            if chr.transmitEquippedItem then
                                chr:transmitEquippedItem(entry.secondaryItem, BloodBodyPartType.Hand_L, false)
                            end
                        end)
                    end
                end
            end
            table.remove(pendingReequips, i)
        end
    end

    if #pendingReequips == 0 then
        Events.OnTick.Remove(processPendingReequips)
    end
end

--- Schedule a delayed re-equip after climbing finishes.
local function scheduleReequip(character, primaryItem, secondaryItem, bothHands)
    table.insert(pendingReequips, {
        character = character,
        primaryItem = primaryItem,
        secondaryItem = secondaryItem,
        bothHands = bothHands,
        ticks = 0,
        seenClimbing = false,
    })
    if #pendingReequips == 1 then
        Events.OnTick.Add(processPendingReequips)
    end
end

local function initClimbPatches()
    if not CSR_FeatureFlags.isClimbWithBagsEnabled() and not CSR_FeatureFlags.isClimbWithGeneratorEnabled() then return end

    -- Patch ISClimbThroughWindow
    if ISClimbThroughWindow and ISClimbThroughWindow.perform and not ISClimbThroughWindow.__csr_climb_patched then
        ISClimbThroughWindow.__csr_climb_patched = true
        local originalWindowPerform = ISClimbThroughWindow.perform

        function ISClimbThroughWindow:perform()
            local primary = self.character:getPrimaryHandItem()
            local secondary = self.character:getSecondaryHandItem()
            local savedPrimary = shouldPreserveItem(primary) and primary or nil
            local savedSecondary = (shouldPreserveItem(secondary) and secondary ~= primary) and secondary or nil
            local bothHands = (primary and secondary and primary == secondary)

            if not savedPrimary and not savedSecondary then
                originalWindowPerform(self)
                return
            end

            -- Remove items from hands so the Java state machine won't drop them
            if savedPrimary then self.character:removeFromHands(savedPrimary) end
            if savedSecondary then self.character:removeFromHands(savedSecondary) end

            -- Run vanilla perform (triggers the climb state machine)
            originalWindowPerform(self)

            -- Re-equip after the climb animation finishes
            scheduleReequip(self.character, savedPrimary, savedSecondary, bothHands)
        end

        -- Patch new() to apply time penalty based on item weight
        local originalWindowNew = ISClimbThroughWindow.new
        function ISClimbThroughWindow:new(character, item, ...)
            local action = originalWindowNew(self, character, item, ...)
            if action and character then
                local penalty = getClimbTimePenalty(character)
                if penalty > 1.0 and action.maxTime then
                    action.maxTime = math.floor(action.maxTime * penalty)
                end
            end
            return action
        end
    end

    -- Patch ISClimbOverFence
    if ISClimbOverFence and ISClimbOverFence.perform and not ISClimbOverFence.__csr_climb_patched then
        ISClimbOverFence.__csr_climb_patched = true
        local originalFencePerform = ISClimbOverFence.perform

        function ISClimbOverFence:perform()
            local primary = self.character:getPrimaryHandItem()
            local secondary = self.character:getSecondaryHandItem()
            local savedPrimary = shouldPreserveItem(primary) and primary or nil
            local savedSecondary = (shouldPreserveItem(secondary) and secondary ~= primary) and secondary or nil
            local bothHands = (primary and secondary and primary == secondary)

            if not savedPrimary and not savedSecondary then
                originalFencePerform(self)
                return
            end

            if savedPrimary then self.character:removeFromHands(savedPrimary) end
            if savedSecondary then self.character:removeFromHands(savedSecondary) end

            originalFencePerform(self)

            scheduleReequip(self.character, savedPrimary, savedSecondary, bothHands)
        end

        local originalFenceNew = ISClimbOverFence.new
        function ISClimbOverFence:new(character, dir, ...)
            local action = originalFenceNew(self, character, dir, ...)
            if action and character then
                local penalty = getClimbTimePenalty(character)
                if penalty > 1.0 and action.maxTime then
                    action.maxTime = math.floor(action.maxTime * penalty)
                end
            end
            return action
        end
    end

    -- Patch ISClimbSheetRopeAction
    if ISClimbSheetRopeAction and ISClimbSheetRopeAction.perform and not ISClimbSheetRopeAction.__csr_climb_patched then
        ISClimbSheetRopeAction.__csr_climb_patched = true
        local originalRopePerform = ISClimbSheetRopeAction.perform

        function ISClimbSheetRopeAction:perform()
            local primary = self.character:getPrimaryHandItem()
            local secondary = self.character:getSecondaryHandItem()
            local savedPrimary = shouldPreserveItem(primary) and primary or nil
            local savedSecondary = (shouldPreserveItem(secondary) and secondary ~= primary) and secondary or nil
            local bothHands = (primary and secondary and primary == secondary)

            if not savedPrimary and not savedSecondary then
                originalRopePerform(self)
                return
            end

            if savedPrimary then self.character:removeFromHands(savedPrimary) end
            if savedSecondary then self.character:removeFromHands(savedSecondary) end

            originalRopePerform(self)

            scheduleReequip(self.character, savedPrimary, savedSecondary, bothHands)
        end
    end
end

-- v1.8.5: Hook BOTH OnGameStart and OnServerStarted. Self-hosted MP runs both
-- the client (this) and the server in the same Lua state -- if only OnGameStart
-- fires, the patches are missing on the host's authoritative server thread
-- when remote clients trigger climbs. Idempotent guard flag (__csr_climb_patched)
-- prevents double-patching.
Events.OnGameStart.Add(initClimbPatches)
if Events and Events.OnServerStarted then
    Events.OnServerStarted.Add(initClimbPatches)
end

-- Clear stale pending re-equips on new character (MP reconnect, death respawn).
-- Prevents re-equip attempts against a defunct character / inventory.
local function clearPendingOnCreatePlayer()
    if #pendingReequips > 0 then
        for i = #pendingReequips, 1, -1 do pendingReequips[i] = nil end
        if Events and Events.OnTick then
            Events.OnTick.Remove(processPendingReequips)
        end
    end
end
Events.OnCreatePlayer.Add(clearPendingOnCreatePlayer)
