--[[
    CSR_HotbarTransferAttach.lua

    Previously this file overrode ISHotbar:attachItem() to handle attaching items
    that were still inside containers (i.e. not yet in the player's inventory).

    The override has been removed because:
      1. Vanilla ISHotbar:attachItem in B42 already calls
         ISInventoryPaneContextMenu.transferIfNeeded(self.chr, item) and queues
         ISAttachItemHotbar — the override was a duplicate of vanilla logic.
      2. The override skipped self:setAttachAnim(item, slotDef), which sets the
         "AttachAnim" character variable to the slot's animset (belt / back /
         small_belt / etc.). Without it the engine fell back to a default clip
         that visually resembles a surrender / hands-up pose and the attach
         completed incorrectly so the item appeared to "just go to inventory".
      3. The override also skipped queueing ISDetachItemHotbar for an item
         already occupying the target slot.

    Letting vanilla ISHotbar:attachItem run unmodified fixes the broken first-
    time attach-from-container animation reported by users (kickfliptherari,
    v1.6.5) and restores correct slot behaviour.

    File kept intentionally so existing deployments don't see a missing-file
    diff during sync.
]]

