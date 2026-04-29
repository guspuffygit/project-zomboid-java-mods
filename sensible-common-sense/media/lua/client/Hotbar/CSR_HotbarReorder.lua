require "CSR_FeatureFlags"

--[[
    CSR_HotbarReorder.lua
    Adds drag-to-reorder for hotbar slots.
    Left-click-drag a slot to another slot position to swap them.
    The new order is persisted via modData.
]]

local function patchHotbarReorder()
    if not ISHotbar or ISHotbar.__csr_reorder_patched then return end
    ISHotbar.__csr_reorder_patched = true

    -- Store originals
    local origRender = ISHotbar.render
    local origOnMouseDown = ISHotbar.onMouseDown
    local origOnMouseUp = ISHotbar.onMouseUp

    -- Track drag state per hotbar instance via fields:
    --   self.csrDragSourceSlot  = index being dragged
    --   self.csrDragging        = true when drag threshold exceeded

    function ISHotbar:onMouseDown(x, y)
        if not CSR_FeatureFlags or not CSR_FeatureFlags.isEquipmentQoLEnabled or not CSR_FeatureFlags.isEquipmentQoLEnabled() then
            return origOnMouseDown(self, x, y)
        end

        local slotIndex = self:getSlotIndexAt(x, y)
        if slotIndex ~= -1 and not ISMouseDrag.dragging then
            -- Start tracking for potential reorder drag
            self.csrDragSourceSlot = slotIndex
            self.csrDragStartX = x
            self.csrDragStartY = y
            self.csrDragging = false
            return true
        end

        self.csrDragSourceSlot = nil
        self.csrDragging = false
        return origOnMouseDown(self, x, y)
    end

    function ISHotbar:onMouseMove(dx, dy)
        if self.csrDragSourceSlot and not self.csrDragging then
            local mx = self:getMouseX()
            local my = self:getMouseY()
            local distX = math.abs(mx - (self.csrDragStartX or mx))
            local distY = math.abs(my - (self.csrDragStartY or my))
            if distX > 8 or distY > 8 then
                self.csrDragging = true
            end
        end
    end

    function ISHotbar:onMouseMoveOutside(dx, dy)
        if self.csrDragging then
            -- Keep tracking outside
            return
        end
    end

    function ISHotbar:onMouseUp(x, y)
        if self.csrDragging and self.csrDragSourceSlot then
            local targetSlot = self:getSlotIndexAt(x, y)
            if targetSlot ~= -1 and targetSlot ~= self.csrDragSourceSlot then
                -- Swap the two slots
                local srcIdx = self.csrDragSourceSlot
                local srcSlot = self.availableSlot[srcIdx]
                local tgtSlot = self.availableSlot[targetSlot]

                if srcSlot and tgtSlot then
                    -- Detach both items from the character model first
                    local srcItem = self.attachedItems[srcIdx]
                    local tgtItem = self.attachedItems[targetSlot]
                    if srcItem then
                        self.chr:removeAttachedItem(srcItem)
                        srcItem:setAttachedSlot(-1)
                        srcItem:setAttachedSlotType(nil)
                        srcItem:setAttachedToModel(nil)
                    end
                    if tgtItem then
                        self.chr:removeAttachedItem(tgtItem)
                        tgtItem:setAttachedSlot(-1)
                        tgtItem:setAttachedSlotType(nil)
                        tgtItem:setAttachedToModel(nil)
                    end

                    -- Swap slot definitions
                    self.availableSlot[srcIdx] = tgtSlot
                    self.availableSlot[targetSlot] = srcSlot

                    -- Re-attach items — guard against nil attachment lookups
                    if srcItem and srcItem:getAttachmentType() then
                        local model = srcSlot.def and srcSlot.def.attachments and srcSlot.def.attachments[srcItem:getAttachmentType()]
                        if model then
                            self:attachItem(srcItem, model, targetSlot, srcSlot.def, false)
                        end
                    end
                    if tgtItem and tgtItem:getAttachmentType() then
                        local model = tgtSlot.def and tgtSlot.def.attachments and tgtSlot.def.attachments[tgtItem:getAttachmentType()]
                        if model then
                            self:attachItem(tgtItem, model, srcIdx, tgtSlot.def, false)
                        end
                    end

                    -- Persist the new order
                    self:savePosition()
                end
            end

            self.csrDragSourceSlot = nil
            self.csrDragging = false
            return true
        end

        -- Not a reorder drag — handle as normal click
        local wasSource = self.csrDragSourceSlot
        self.csrDragSourceSlot = nil
        self.csrDragging = false

        if wasSource and not ISMouseDrag.dragging then
            -- It was a simple click (no drag threshold exceeded), activate slot
            local index = self:getSlotIndexAt(x, y)
            if index > -1 and self:isAllowedToActivateSlot() then
                self:activateSlot(index)
            end
            return true
        end

        return origOnMouseUp(self, x, y)
    end

    function ISHotbar:onMouseUpOutside(x, y)
        -- Cancel reorder if mouse released outside
        self.csrDragSourceSlot = nil
        self.csrDragging = false
    end

    -- Patch render to show drag indicator
    function ISHotbar:render()
        origRender(self)

        if not self.csrDragging or not self.csrDragSourceSlot then return end

        local srcIdx = self.csrDragSourceSlot
        local targetIdx = self:getSlotIndexAt(self:getMouseX(), self:getMouseY())

        -- Highlight the source slot being dragged (blue outline)
        local srcX = self.margins + 1 + (srcIdx - 1) * (self.slotWidth + self.slotPad)
        self:drawRectBorder(srcX, self.margins + 1, self.slotWidth, self.slotHeight, 0.9, 0.34, 0.66, 0.96)

        -- Highlight the target slot (green outline if valid swap)
        if targetIdx ~= -1 and targetIdx ~= srcIdx then
            local tgtX = self.margins + 1 + (targetIdx - 1) * (self.slotWidth + self.slotPad)
            self:drawRectBorder(tgtX, self.margins + 1, self.slotWidth, self.slotHeight, 0.9, 0.38, 0.78, 0.58)
            self:drawRect(tgtX, self.margins + 1, self.slotWidth, self.slotHeight, 0.15, 0.38, 0.78, 0.58)
        end
    end
end

if Events and Events.OnGameStart then
    Events.OnGameStart.Add(patchHotbarReorder)
end
