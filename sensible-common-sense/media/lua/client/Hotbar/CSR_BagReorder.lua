require "CSR_FeatureFlags"

--[[
    CSR_BagReorder.lua
    Drag-to-reorder bag/container buttons on the character inventory sidebar.

    Based on CleanUI's proven DragSort approach (B42.16):
    - Hooks addContainerButton to inject per-button drag handlers
    - Moves buttons by Y position only — never swaps inventory/texture/title
    - Each button always keeps its own .inventory reference
    - Sort priorities stored in player modData keyed by container item ID
    - Clicking a repositioned button always shows the correct inventory
]]

local SORT_KEY = "CSR_ContainerSort"
local DragSort = {}

local function isEnabled()
    return CSR_FeatureFlags and CSR_FeatureFlags.isEquipmentQoLEnabled and CSR_FeatureFlags.isEquipmentQoLEnabled()
end

-- =========================================================================
-- Per-button drag handlers (injected via addContainerButton hook)
-- =========================================================================

DragSort.onMouseDown = function(self, x, y)
    self.original_onMouseDown(self, x, y)
    if not isEnabled() then return end

    self.dragStartMouseY = getMouseY()
    self.dragStartY = self:getY()

    local page = self:getParent():getParent()
    self.canDrag = page.onCharacter
end

DragSort.onMouseMove = function(self, dx, dy, skipOriginal)
    if not skipOriginal then
        self.original_onMouseMove(self, dx, dy)
    end
    if not isEnabled() then return end

    if self.pressed and self.canDrag then
        local page = self:getParent():getParent()

        if math.abs(self.dragStartMouseY - getMouseY()) > (page.buttonSize or 32) / 6 then
            self.isDragging = true
        end

        if self.isDragging then
            local mouseY = getMouseY()
            local parentAbsY = self:getParent():getAbsoluteY()
            local newY = mouseY - parentAbsY - self:getHeight() / 2
            newY = math.max(0, newY)
            self:setY(newY)
            self:bringToTop()
            page:csrCalculateInsertPosition(self)
        end
    end
end

DragSort.onMouseMoveOutside = function(self, dx, dy)
    self.original_onMouseMoveOutside(self, dx, dy)
    if not isEnabled() then return end

    if self.isDragging then
        DragSort.onMouseMove(self, dx, dy, true)
    end

    if self.isDragging and not isMouseButtonDown(0) then
        local page = self:getParent():getParent()
        page.csrDragInsertPosition = nil
        page.csrDraggingButton = nil
        DragSort.onMouseUp(self, 0, 0)
    end
end

DragSort.onMouseUp = function(self, x, y)
    if not isEnabled() then
        self.original_onMouseUp(self, x, y)
        return
    end

    local page = self:getParent():getParent()

    if self.isDragging then
        self.pressed = false
        self.isDragging = false
        page.csrDragInsertPosition = nil
        page.csrDraggingButton = nil
        page:csrReorderContainerButtons(self)
        page:refreshBackpacks()
    else
        self.original_onMouseUp(self, x, y)
    end
end

-- =========================================================================
-- Patch setup (called once on game start)
-- =========================================================================

local function patchBagReorder()
    if not ISInventoryPage or ISInventoryPage.__csr_bag_reorder_patched then return end
    ISInventoryPage.__csr_bag_reorder_patched = true

    -- -----------------------------------------------------------------
    -- Hook addContainerButton: inject per-button drag handlers
    -- -----------------------------------------------------------------
    local origAddContainerButton = ISInventoryPage.addContainerButton
    function ISInventoryPage:addContainerButton(container, texture, name, tooltip)
        local button = origAddContainerButton(self, container, texture, name, tooltip)

        if self.onCharacter and isEnabled() then
            if not button.original_onMouseDown then
                button.original_onMouseDown = button.onMouseDown
                button.original_onMouseMove = button.onMouseMove
                button.original_onMouseMoveOutside = button.onMouseMoveOutside
                button.original_onMouseUp = button.onMouseUp
            end
            button.onMouseDown = DragSort.onMouseDown
            button.onMouseMove = DragSort.onMouseMove
            button.onMouseMoveOutside = DragSort.onMouseMoveOutside
            button.onMouseUp = DragSort.onMouseUp
        end

        return button
    end

    -- -----------------------------------------------------------------
    -- Priority storage: player modData keyed by container item ID
    -- -----------------------------------------------------------------
    function ISInventoryPage:csrGetContainerSortPriority(container)
        local playerObj = getSpecificPlayer(self.player)
        if not playerObj then return 1000 end
        local modData = playerObj:getModData()

        local sortKey = SORT_KEY
        if container == playerObj:getInventory() then
            sortKey = SORT_KEY .. "_Main"
        else
            local item = container:getContainingItem()
            if item then
                sortKey = SORT_KEY .. "_" .. item:getID()
            end
        end

        if modData[sortKey] then
            return modData[sortKey]
        end

        -- Fallback: use current array position
        for i, button in ipairs(self.backpacks) do
            if button.inventory == container then
                return 1000 + i
            end
        end

        return 1000
    end

    function ISInventoryPage:csrSetContainerSortPriority(container, priority)
        local playerObj = getSpecificPlayer(self.player)
        if not playerObj then return end
        local modData = playerObj:getModData()

        local sortKey = SORT_KEY
        if container == playerObj:getInventory() then
            sortKey = SORT_KEY .. "_Main"
        else
            local item = container:getContainingItem()
            if item then
                sortKey = SORT_KEY .. "_" .. item:getID()
            end
        end

        modData[sortKey] = priority
    end

    -- -----------------------------------------------------------------
    -- Calculate visual insert position during drag
    -- -----------------------------------------------------------------
    function ISInventoryPage:csrCalculateInsertPosition(draggedButton)
        if not self.onCharacter then return end

        self.csrDraggingButton = draggedButton

        local buttons = {}
        for _, button in ipairs(self.backpacks) do
            if button:getIsVisible() and button ~= draggedButton then
                table.insert(buttons, button)
            end
        end

        if #buttons == 0 then
            self.csrDragInsertPosition = 0
            return
        end

        table.sort(buttons, function(a, b) return a:getY() < b:getY() end)

        local draggedY = draggedButton:getY() + draggedButton:getHeight() / 2

        for i, button in ipairs(buttons) do
            local buttonCenterY = button:getY() + button:getHeight() / 2
            if draggedY < buttonCenterY then
                self.csrDragInsertPosition = i - 1
                return
            end
        end

        self.csrDragInsertPosition = #buttons
    end

    -- -----------------------------------------------------------------
    -- Reorder: assign sort priorities based on current Y positions
    -- -----------------------------------------------------------------
    function ISInventoryPage:csrReorderContainerButtons(draggedButton)
        if draggedButton and draggedButton.dragStartY then
            if math.abs(draggedButton:getY() - draggedButton.dragStartY) <= 16 then
                draggedButton:setY(draggedButton.dragStartY)
                return
            end
        end

        local buttonsWithY = {}
        for _, button in ipairs(self.backpacks) do
            if button:getIsVisible() then
                table.insert(buttonsWithY, {
                    button = button,
                    inventory = button.inventory,
                    y = button:getY()
                })
            end
        end

        table.sort(buttonsWithY, function(a, b) return a.y < b.y end)

        for index, data in ipairs(buttonsWithY) do
            self:csrSetContainerSortPriority(data.inventory, index * 10)
        end
    end

    -- -----------------------------------------------------------------
    -- Apply saved sort order by repositioning buttons via setY()
    -- -----------------------------------------------------------------
    function ISInventoryPage:csrApplyContainerSort()
        if not self.onCharacter then return end

        local buttonsWithSort = {}
        for _, button in ipairs(self.backpacks) do
            if button:getIsVisible() then
                local priority = self:csrGetContainerSortPriority(button.inventory)
                table.insert(buttonsWithSort, {
                    button = button,
                    priority = priority
                })
            end
        end

        table.sort(buttonsWithSort, function(a, b) return a.priority < b.priority end)

        -- Determine button height from existing layout
        local btnH = 0
        if #buttonsWithSort > 0 then
            local rawH = buttonsWithSort[1].button:getHeight()
            btnH = (type(rawH) == "number" and rawH) or (rawH and (rawH + 0)) or 0
        end
        if btnH <= 0 then return end
        -- Read first button's Y as the starting offset
        local rawY = buttonsWithSort[1].button:getY()
        local startY = (type(rawY) == "number" and rawY) or (rawY and (rawY + 0)) or 0

        for index, data in ipairs(buttonsWithSort) do
            local y = startY + (index - 1) * btnH
            data.button:setY(y)
        end
    end

    -- -----------------------------------------------------------------
    -- Hook refreshBackpacks to re-apply drag sort order
    -- -----------------------------------------------------------------
    local origRefreshBackpacks = ISInventoryPage.refreshBackpacks
    function ISInventoryPage:refreshBackpacks()
        origRefreshBackpacks(self)

        -- Apply saved sort order (player side only)
        if isEnabled() and self.onCharacter then
            self:csrApplyContainerSort()
        end
    end

    -- -----------------------------------------------------------------
    -- Hook onMouseWheel to preserve custom order during scrolling
    -- -----------------------------------------------------------------
    local origMouseWheel = ISInventoryPage.onMouseWheel
    function ISInventoryPage:onMouseWheel(del)
        if isEnabled() and self.onCharacter then
            local originalOrder = {}
            local hasOrder = false

            for index, button in ipairs(self.backpacks) do
                originalOrder[button] = index
                hasOrder = true
            end

            table.sort(self.backpacks, function(a, b) return a:getY() < b:getY() end)

            local result = origMouseWheel(self, del)

            if hasOrder then
                table.sort(self.backpacks, function(a, b)
                    return originalOrder[a] < originalOrder[b]
                end)
            end

            return result
        end
        return origMouseWheel(self, del)
    end
end

if Events and Events.OnGameStart then
    Events.OnGameStart.Add(patchBagReorder)
end
