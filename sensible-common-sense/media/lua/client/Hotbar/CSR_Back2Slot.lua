require "CSR_FeatureFlags"

--[[
    CSR_Back2Slot.lua
    Adds a permanent BackSecondary slot to the vanilla hotbar.

    Implementation strategy (rewritten v1.7.4):
      The previous implementation overrode ISHotbar:refresh() and tried to
      snapshot/restore the secondary item before/after vanilla pruning. That
      did not work because vanilla refresh (lines 505-509 of vanilla
      ISHotbar.lua) calls:
          self.availableSlot[i] = nil
          if item then self:removeItem(item, false) end
      whenever a slot is not present in `newSlots`. `newSlots` is built
      exclusively from worn items' getAttachmentsProvided() plus the
      hardcoded "Back" slot, so BackSecondary was always pruned and the
      attached secondary item was force-detached. By the time the post-
      refresh restore ran, the engine had already moved the item back to
      inventory and snapped its model away -- producing the "vanishing
      item" / "unequip leaves item in slot" symptoms players reported.

    New approach (matches NoirRifleSlings' philosophy of "don't override
    refresh"):
      1. CSR_ISHotbarAttachDefinition.lua registers BackSecondary in
         ISHotbarAttachDefinition at file-load time so getSlotDef() and
         loadPosition() can resolve it.
      2. Patch ISHotbar:loadPosition to guarantee BackSecondary is present
         in availableSlot for every player whether or not they have it
         saved (idempotent: only inserts if missing).
      3. Patch ISHotbar:haveThisSlot to ALWAYS return true when asked
         about "BackSecondary". Vanilla refresh() uses this check to
         decide whether to prune a slot -- returning true protects the
         slot AND its attached item from removal during every refresh.

    Net effect: secondary item now persists across clothing changes,
    attach/detach actions, and game reloads with zero snapshot/restore
    machinery. No mutex, no event-deferred restore, no race conditions.
]]

if not ISHotbar then return end
if not ISHotbarAttachDefinition then return end

local BACK2_TYPE = "BackSecondary"

-- =============================================================
-- Patch #1: loadPosition -- ensure BackSecondary always exists.
-- =============================================================
if not ISHotbar._CSR_OrigLoadPosition then
    ISHotbar._CSR_OrigLoadPosition = ISHotbar.loadPosition
end

function ISHotbar:loadPosition()
    ISHotbar._CSR_OrigLoadPosition(self)

    if not CSR_FeatureFlags or not CSR_FeatureFlags.isBack2SlotEnabled
       or not CSR_FeatureFlags.isBack2SlotEnabled() then
        return
    end

    -- If already present (player has it saved), do nothing.
    for _, slot in pairs(self.availableSlot) do
        if slot and slot.slotType == BACK2_TYPE then return end
    end

    -- Resolve the def we registered in CSR_ISHotbarAttachDefinition.lua.
    local slotDef = self:getSlotDef(BACK2_TYPE)
    if not slotDef then return end

    -- v1.7.5: Append at the FIRST UNUSED index (>= 2). NEVER shift existing
    -- indices. Vanilla stores each attached item's hotbar slot as a numeric
    -- index in InventoryItem.attachedSlot, and ISHotbar:update looks the
    -- slot up purely by that integer (`self.availableSlot[item:getAttachedSlot()]`).
    -- The previous v1.7.4 implementation inserted at index 2 and shifted
    -- everything above it up by one. That left every saved attachedSlot
    -- numeric pointing at the wrong slotType -- a 1H or 2H weapon previously
    -- stored at index 2 (a Belt slot) now resolved to BackSecondary, and
    -- because BigBlade/BigWeapon attachments overlap, canBeAttached returned
    -- true and vanilla re-attached the item's model to "Rifle On Back" /
    -- "Blade On Back". That is the "2H axe stays stuck on the secondary
    -- back slot when I switch to a 1H axe" visual glitch.
    local idx = 2
    while self.availableSlot[idx] do idx = idx + 1 end
    self.availableSlot[idx] = { slotType = slotDef.type, name = slotDef.name, def = slotDef }

    -- Persist the new layout so loadPosition() picks it up next session.
    if self.savePosition then self:savePosition() end

    -- ---------------------------------------------------------
    -- v1.7.5 one-time corruption repair for saves that were
    -- previously loaded under v1.7.4's index-shifting code.
    -- v1.7.4 inserted BackSecondary at index 2 and shifted every
    -- higher slot up by 1, but each item's stored
    -- InventoryItem.attachedSlot numeric was NOT shifted to
    -- match -- so an item saved at index 2 (e.g. BeltLeft) was
    -- now resolving to whatever the new index 2 was. Walk every
    -- item in inventory and, when its stored attachedSlotType
    -- string disagrees with the slotType actually living at its
    -- current numeric index, look up the slot whose slotType DOES
    -- match and rewrite the numeric index. Items whose
    -- attachedSlotType no longer corresponds to ANY available
    -- slot are detached cleanly (slot index -1, no model).
    -- This loop is idempotent: items already at their correct
    -- index are unchanged on every subsequent loadPosition.
    -- ---------------------------------------------------------
    local inv = self.chr and self.chr.getInventory and self.chr:getInventory() or nil
    if not inv or not inv.getItems then return end
    local items = inv:getItems()
    if not items or not items.size then return end
    local sz = items:size()
    for i = 0, sz - 1 do
        local it = items:get(i)
        if it and it.getAttachedSlot and it.getAttachedSlotType then
            local curIdx  = it:getAttachedSlot()
            local curType = it:getAttachedSlotType()
            if curIdx and curIdx > -1 and curType then
                local atIdx = self.availableSlot[curIdx]
                if not atIdx or atIdx.slotType ~= curType then
                    -- Numeric index points to the wrong slotType: find
                    -- the index that matches the saved slotType.
                    local fixedIdx = nil
                    for k, slot in pairs(self.availableSlot) do
                        if slot and slot.slotType == curType then
                            fixedIdx = k
                            break
                        end
                    end
                    if fixedIdx then
                        if it.setAttachedSlot then it:setAttachedSlot(fixedIdx) end
                    else
                        -- Slot type no longer exists -- detach cleanly.
                        if it.setAttachedSlot     then it:setAttachedSlot(-1) end
                        if it.setAttachedSlotType then it:setAttachedSlotType(nil) end
                        if it.setAttachedToModel  then it:setAttachedToModel(nil) end
                        if self.chr.removeAttachedItem then
                            self.chr:removeAttachedItem(it)
                        end
                    end
                end
            end
        end
    end
end

-- =============================================================
-- Patch #2: haveThisSlot -- always claim BackSecondary exists.
-- This is the lynchpin: vanilla refresh() prunes any slot for
-- which haveThisSlot returns false, AND removes the item that
-- was attached to it. By returning true unconditionally for our
-- slot type, we make the slot survive every refresh cycle.
-- =============================================================
if not ISHotbar._CSR_OrigHaveThisSlot then
    ISHotbar._CSR_OrigHaveThisSlot = ISHotbar.haveThisSlot
end

function ISHotbar:haveThisSlot(slotType, list)
    if slotType == BACK2_TYPE
       and CSR_FeatureFlags
       and CSR_FeatureFlags.isBack2SlotEnabled
       and CSR_FeatureFlags.isBack2SlotEnabled() then
        return true
    end
    return ISHotbar._CSR_OrigHaveThisSlot(self, slotType, list)
end
