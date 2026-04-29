
require "CSR_FeatureFlags"
require "CSR_Theme"
require "CSR_LootFilter"

CSR_ProximityLoot = CSR_ProximityLoot or {}
CSR_ProximityLoot.panel = nil

local MODDATA_KEY = "CSRProximityLoot"
local DEFAULT_KEY = Keyboard and Keyboard.KEY_TAB or 15
local REFRESH_INTERVAL_MS = 800
local PANEL_WIDTH = 340
local PANEL_HEIGHT = 440
local HEADER_HEIGHT = 24
local SEARCH_HEIGHT = 22
local ROW_HEIGHT = 22

local options = nil
local proximityKeyBind = nil
if PZAPI and PZAPI.ModOptions and PZAPI.ModOptions.create then
    options = PZAPI.ModOptions:create("CommonSenseRebornProximityLoot", "Common Sense Reborn - Proximity Loot")
    if options and options.addKeyBind then
        proximityKeyBind = options:addKeyBind("showProximityLoot", "Proximity Loot Panel Hotkey", DEFAULT_KEY)
    end
end

local function getBoundKey()
    if proximityKeyBind and proximityKeyBind.getValue then
        return proximityKeyBind:getValue()
    end
    return DEFAULT_KEY
end

local function getPlayerSafe()
    return getPlayer and getPlayer() or nil
end

local function getState()
    local player = getPlayerSafe()
    if not player then return nil end
    local modData = player:getModData()
    modData[MODDATA_KEY] = modData[MODDATA_KEY] or { x = nil, y = nil }
    return modData[MODDATA_KEY]
end

local function getDisplayName(fullType)
    local scriptItem = ScriptManager and ScriptManager.instance and ScriptManager.instance:FindItem(fullType) or nil
    if scriptItem and scriptItem.getDisplayName then
        return scriptItem:getDisplayName()
    end
    return fullType
end

-- Scan all containers in 3x3 grid around the player (mirrors vanilla ISInventoryPage:refreshBackpacks)
local function scanNearbyItems(playerObj)
    local result = {}
    if not playerObj then return result end

    local playerInv = playerObj:getInventory()
    local cx = playerObj:getX()
    local cy = playerObj:getY()
    local cz = playerObj:getZ()
    local currentSq = playerObj:getCurrentSquare()

    for dy = -1, 1 do
        for dx = -1, 1 do
            local square = getCell():getGridSquare(cx + dx, cy + dy, cz)
            if square then
                if square ~= currentSq and currentSq and not currentSq:canReachTo(square) then
                    square = nil
                end
                if square and isClient() and not SafeHouse.isSafehouseAllowLoot(square, playerObj) then
                    square = nil
                end
            end
            if square then
                -- World objects on ground
                local wobs = square:getWorldObjects()
                for i = 0, wobs:size() - 1 do
                    local o = wobs:get(i)
                    local item = o and o:getItem() or nil
                    if item and item:getContainer() ~= playerInv then
                        table.insert(result, { item = item, container = item:getContainer(), source = "ground", worldObject = o })
                    end
                end

                -- Static/moving objects (corpses, furniture containers)
                local sobs = square:getStaticMovingObjects()
                for i = 0, sobs:size() - 1 do
                    local so = sobs:get(i)
                    local container = so and so:getContainer() or nil
                    if container and container ~= playerInv then
                        if not (instanceof(so, "IsoDeadBody") and so:isAnimal()) then
                            local items = container:getItems()
                            for j = 0, items:size() - 1 do
                                local item = items:get(j)
                                if item then
                                    table.insert(result, { item = item, container = container, source = container:getType() or "container" })
                                end
                            end
                        end
                    end
                end

                -- IsoObject containers (shelves, counters, etc.)
                local obs = square:getObjects()
                for i = 0, obs:size() - 1 do
                    local o = obs:get(i)
                    if o and o.getContainerCount then
                        for ci = 1, o:getContainerCount() do
                            local container = o:getContainerByIndex(ci - 1)
                            if container and container ~= playerInv then
                                local items = container:getItems()
                                for j = 0, items:size() - 1 do
                                    local item = items:get(j)
                                    if item then
                                        table.insert(result, { item = item, container = container, source = container:getType() or "container" })
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return result
end

-- Group items by fullType for the list display
local function groupItems(entries, filterText)
    local groups = {}
    local order = {}
    local lowerFilter = filterText and filterText ~= "" and string.lower(filterText) or nil
    local hideFiltered = CSR_LootFilter and CSR_LootFilter.shouldHideItem or nil

    for _, entry in ipairs(entries) do
        local item = entry.item
        local fullType = item:getFullType()
        local displayName = item.getDisplayName and item:getDisplayName() or getDisplayName(fullType)

        local passesSearch = not lowerFilter or string.lower(displayName):find(lowerFilter, 1, true) or string.lower(fullType):find(lowerFilter, 1, true)
        local passesFilter = not hideFiltered or not hideFiltered(item)

        if passesSearch and passesFilter then
            if not groups[fullType] then
                groups[fullType] = {
                    fullType = fullType,
                    displayName = displayName,
                    items = {},
                    texture = item.getTex and item:getTex() or nil,
                }
                table.insert(order, fullType)
            end
            table.insert(groups[fullType].items, entry)
        end
    end

    table.sort(order, function(a, b)
        return groups[a].displayName < groups[b].displayName
    end)

    local sorted = {}
    for _, ft in ipairs(order) do
        table.insert(sorted, groups[ft])
    end
    return sorted
end

-- The panel

local ProximityLootPanel = ISPanel:derive("CSR_ProximityLootPanel")

function ProximityLootPanel:initialise()
    ISPanel.initialise(self)
end

function ProximityLootPanel:createChildren()
    ISPanel.createChildren(self)

    local y = HEADER_HEIGHT + 4

    self.searchEntry = ISTextEntryBox:new("", 10, y, self.width - 82, SEARCH_HEIGHT)
    self.searchEntry:initialise()
    self.searchEntry:instantiate()
    self.searchEntry.tooltip = "Filter items by name or type"
    self:addChild(self.searchEntry)

    self.grabAllButton = ISButton:new(self.width - 68, y, 58, SEARCH_HEIGHT, "Grab All", self, self.onGrabAll)
    self.grabAllButton:initialise()
    self.grabAllButton:instantiate()
    self:addChild(self.grabAllButton)
    CSR_Theme.applyButtonStyle(self.grabAllButton, "accentGreen", false)

    y = y + SEARCH_HEIGHT + 4

    self.listY = y
    self.scrollList = ISScrollingListBox:new(0, y, self.width, self.height - y)
    self.scrollList:initialise()
    self.scrollList:instantiate()
    self.scrollList.itemheight = ROW_HEIGHT
    self.scrollList.drawBorder = false
    self.scrollList.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    self.scrollList.doDrawItem = self.drawItemRow
    self.scrollList.panel = self
    -- Save original onMouseDown so scrollbar still works, then wrap it
    local origScrollListMouseDown = self.scrollList.onMouseDown
    self.scrollList.onMouseDown = function(scrollSelf, mx, my)
        -- Let ISScrollingListBox handle scrollbar/selection first
        if origScrollListMouseDown then
            origScrollListMouseDown(scrollSelf, mx, my)
        end
        -- Then do our custom click-to-grab logic
        ProximityLootPanel.onListMouseDown(scrollSelf, mx, my)
        return true
    end
    self:addChild(self.scrollList)

    self.cachedEntries = {}
    self.cachedGroups = {}
    self.lastRefreshTime = 0
    self.lastFilterText = ""
end

function ProximityLootPanel:refresh()
    local playerObj = getPlayerSafe()
    if not playerObj then return end

    local ok, entries = pcall(scanNearbyItems, playerObj)
    if not ok then entries = {} end
    self.cachedEntries = entries
    local filterText = self.searchEntry and self.searchEntry:getText() or ""
    self.lastFilterText = filterText
    self.cachedGroups = groupItems(self.cachedEntries, filterText)

    self.scrollList:clear()
    for _, group in ipairs(self.cachedGroups) do
        self.scrollList:addItem(group.displayName .. " (" .. #group.items .. ")", group)
    end
end

function ProximityLootPanel:update()
    ISPanel.update(self)

    if not self:getIsVisible() then return end

    -- Don't refresh while a timed action is running (prevents interference with transfers)
    local player = getPlayerSafe()
    if player and ISTimedActionQueue and ISTimedActionQueue.hasAction then
        if ISTimedActionQueue.hasAction(ISTimedActionQueue.getTimedActionQueue(player)) then
            return
        end
    end

    local now = getTimestampMs()
    local filterText = self.searchEntry and self.searchEntry:getText() or ""
    local filterChanged = filterText ~= self.lastFilterText

    if filterChanged or (now - self.lastRefreshTime) > REFRESH_INTERVAL_MS then
        self.lastRefreshTime = now
        self:refresh()
    end
end

function ProximityLootPanel.drawItemRow(self, y, item, alt)
    local panel = self.panel
    if not panel or not item or not item.item then return y + self.itemheight end

    local group = item.item
    local text = CSR_Theme.colors.text

    if self.mouseoverselected == item.index then
        self:drawRect(0, y, self.width, self.itemheight, 0.15, 0.4, 0.6, 0.9)
    end

    local iconX = 4
    local tex = group.texture
    if tex then
        local iconSize = self.itemheight - 4
        self:drawTextureScaledAspect(tex, iconX, y + 2, iconSize, iconSize, 1.0, 1, 1, 1)
        iconX = iconX + iconSize + 4
    else
        iconX = iconX + 22
    end

    local count = #group.items
    local label = group.displayName
    if count > 1 then
        label = label .. "  x" .. count
    end

    -- Check food freshness status
    local foodTag = nil
    local tagColor = nil
    if group.items[1] and group.items[1].item then
        local sampleItem = group.items[1].item
        if sampleItem.isFood and sampleItem:isFood() then
            local food = sampleItem.getFood and sampleItem:getFood()
            if food then
                if sampleItem:isRotten() then
                    foodTag = " [Rotten]"
                    tagColor = { r = 0.8, g = 0.2, b = 0.2 }
                elseif sampleItem:getOffAgeHours() > 0 and sampleItem:getAge() > sampleItem:getOffAgeHours() then
                    foodTag = " [Stale]"
                    tagColor = { r = 0.9, g = 0.7, b = 0.2 }
                elseif sampleItem:isFrozen() then
                    foodTag = " [Frozen]"
                    tagColor = { r = 0.4, g = 0.7, b = 1.0 }
                end
            end
        end
        -- Check fluid container fill level
        if not foodTag and sampleItem.getFluidContainer then
            local fc = sampleItem:getFluidContainer()
            if fc then
                local amount = fc:getAmount()
                local capacity = fc:getCapacity()
                if capacity and capacity > 0 then
                    if amount <= 0 then
                        foodTag = " [Empty]"
                        tagColor = { r = 0.6, g = 0.6, b = 0.6 }
                    else
                        local pct = math.floor((amount / capacity) * 100)
                        foodTag = " [" .. pct .. "%]"
                        if pct <= 25 then
                            tagColor = { r = 0.9, g = 0.5, b = 0.2 }
                        else
                            tagColor = { r = 0.4, g = 0.7, b = 1.0 }
                        end
                    end
                end
            end
        end
    end

    self:drawText(label, iconX, y + 3, text.r, text.g, text.b, 0.95, UIFont.Small)

    if foodTag and tagColor then
        local labelW = getTextManager():MeasureStringX(UIFont.Small, label)
        self:drawText(foodTag, iconX + labelW, y + 3, tagColor.r, tagColor.g, tagColor.b, 0.9, UIFont.Small)
    end

    return y + self.itemheight
end

function ProximityLootPanel.onListMouseDown(self, x, y)
    if not self.panel then return false end

    local row = self:rowAt(x, y)
    if row < 1 or row > #self.items then return false end

    local group = self.items[row].item
    if not group or not group.items or #group.items == 0 then return false end

    local playerObj = getPlayerSafe()
    if not playerObj then return false end

    -- Grab one item from this group
    local entry = group.items[1]
    if entry and entry.item and entry.container then
        if ISInventoryPaneContextMenu and ISInventoryPaneContextMenu.transferIfNeeded then
            -- For ground items, pass the IsoWorldInventoryObject so vanilla handles walkAdj properly
            local transferTarget = entry.worldObject or entry.item
            if not entry.worldObject and entry.container.getParent and entry.container:getParent() then
                local sq = nil
                if entry.container:getParent().getSquare then
                    sq = entry.container:getParent():getSquare()
                end
                if sq then
                    luautils.walkAdj(playerObj, sq)
                end
            end
            ISInventoryPaneContextMenu.transferIfNeeded(playerObj, transferTarget)
        end
    end

    self.panel:refresh()
    return true
end

function ProximityLootPanel:onGrabAll()
    local playerObj = getPlayerSafe()
    if not playerObj then return end

    -- Use the selected inventory container if available, otherwise main inventory
    local destContainer = playerObj:getInventory()
    local invWindow = getPlayerInventory and getPlayerInventory(0) or nil
    if invWindow and invWindow.inventoryPane and invWindow.inventoryPane.inventory then
        destContainer = invWindow.inventoryPane.inventory
    end

    local filterText = self.searchEntry and self.searchEntry:getText() or ""
    local groups = groupItems(self.cachedEntries, filterText)

    for _, group in ipairs(groups) do
        for _, entry in ipairs(group.items) do
            if entry.item and entry.container and entry.container ~= destContainer then
                if instanceof(entry.item, "InventoryItem") then
                    if entry.worldObject and entry.worldObject.getSquare then
                        luautils.walkAdj(playerObj, entry.worldObject:getSquare())
                    end
                    if ISInventoryTransferUtil and ISInventoryTransferUtil.newInventoryTransferAction then
                        ISTimedActionQueue.add(ISInventoryTransferUtil.newInventoryTransferAction(playerObj, entry.item, entry.container, destContainer))
                    elseif ISInventoryPaneContextMenu and ISInventoryPaneContextMenu.transferIfNeeded then
                        local transferTarget = entry.worldObject or entry.item
                        ISInventoryPaneContextMenu.transferIfNeeded(playerObj, transferTarget)
                    end
                end
            end
        end
    end

    self:refresh()
end

function ProximityLootPanel:prerender()
    ISPanel.prerender(self)
    CSR_Theme.drawPanelChrome(self, "Nearby Loot", HEADER_HEIGHT)

    local muted = CSR_Theme.colors.textMuted
    local total = self.cachedEntries and #self.cachedEntries or 0
    -- Perf: only rebuild countText + remeasure when total changes.
    if self._lastCount ~= total then
        self._lastCount = total
        self._lastCountText = tostring(total) .. " items"
        self._lastCountW = getTextManager():MeasureStringX(UIFont.Small, self._lastCountText)
    end
    local countText = self._lastCountText
    local textW = self._lastCountW
    self:drawText(countText, self.width - textW - 40, math.floor((HEADER_HEIGHT - 16) / 2) + 1, muted.r, muted.g, muted.b, 0.7, UIFont.Small)
end

function ProximityLootPanel:onMouseDown(x, y)
    if y <= HEADER_HEIGHT then
        self.dragging = true
        self.dragX = x
        self.dragY = y
        self:bringToTop()
        return true
    end
    return ISPanel.onMouseDown(self, x, y)
end

function ProximityLootPanel:onMouseMove(dx, dy)
    if self.dragging then
        local mouseX = getMouseX and getMouseX() or self:getX()
        local mouseY = getMouseY and getMouseY() or self:getY()
        self:setX(mouseX - self.dragX)
        self:setY(mouseY - self.dragY)
        return true
    end
    return ISPanel.onMouseMove(self, dx, dy)
end

function ProximityLootPanel:onMouseMoveOutside(dx, dy)
    if self.dragging then
        return self:onMouseMove(dx, dy)
    end
    return ISPanel.onMouseMoveOutside(self, dx, dy)
end

function ProximityLootPanel:onMouseUp(x, y)
    if self.dragging then
        self.dragging = false
        local state = getState()
        if state then
            state.x = math.floor(self:getX())
            state.y = math.floor(self:getY())
        end
        return true
    end
    return ISPanel.onMouseUp(self, x, y)
end

function ProximityLootPanel:onMouseUpOutside(x, y)
    if self.dragging then
        self.dragging = false
        local state = getState()
        if state then
            state.x = math.floor(self:getX())
            state.y = math.floor(self:getY())
        end
        return true
    end
    return ISPanel.onMouseUpOutside(self, x, y)
end

function ProximityLootPanel:onMouseWheel(del)
    if self.scrollList and self.scrollList.onMouseWheel then
        return self.scrollList:onMouseWheel(del)
    end
    return false
end

-- Keep the original context menu option as well
local function getActualItems(items)
    if ISInventoryPane and ISInventoryPane.getActualItems then
        return ISInventoryPane.getActualItems(items)
    end
    return items or {}
end

local function getOpenLootContainers(playerNum)
    local lootWindow = getPlayerLoot(playerNum)
    local page = lootWindow and lootWindow.inventoryPane and lootWindow.inventoryPane.inventoryPage or nil
    local buttons = page and page.backpacks or nil
    local containers = {}
    local seen = {}

    if not buttons then return containers end

    for _, button in ipairs(buttons) do
        local container = button and button.inventory or nil
        if container and not seen[container] then
            seen[container] = true
            table.insert(containers, container)
        end
    end

    return containers
end

local function getRequestedTypes(actualItems)
    local requested = {}
    local firstType = nil

    for _, item in ipairs(actualItems) do
        local fullType = item and item.getFullType and item:getFullType() or nil
        if fullType then
            requested[fullType] = true
            firstType = firstType or fullType
        end
    end

    return requested, firstType
end

local function gatherNearbyMatches(playerNum, selectedItems)
    local playerObj = getSpecificPlayer(playerNum)
    local playerInv = playerObj and playerObj:getInventory() or nil
    if not playerObj or not playerInv then
        return {}, 0, nil
    end

    local actualItems = getActualItems(selectedItems)
    local requestedTypes, firstType = getRequestedTypes(actualItems)
    if not firstType then
        return {}, 0, nil
    end

    local matchesByContainer = {}
    local total = 0

    for _, container in ipairs(getOpenLootContainers(playerNum)) do
        if container ~= playerInv then
            local items = container:getItems()
            local list = {}
            for i = 1, items:size() do
                local item = items:get(i - 1)
                if item and requestedTypes[item:getFullType()] and item:getContainer() ~= playerInv and not isForceDropHeavyItem(item) then
                    table.insert(list, item)
                end
            end
            if #list > 0 then
                matchesByContainer[container] = list
                total = total + #list
            end
        end
    end

    return matchesByContainer, total, firstType
end

local function queueNearbyTransfers(playerNum, matchesByContainer)
    local playerObj = getSpecificPlayer(playerNum)
    local playerInv = playerObj and playerObj:getInventory() or nil
    if not playerObj or not playerInv then return end

    for container, items in pairs(matchesByContainer) do
        if #items > 0 then
            if not luautils.walkToContainer(container, playerNum) then
                return
            end

            table.sort(items, function(a, b)
                local aType = a:getFullType() or ""
                local bType = b:getFullType() or ""
                if aType == bType then
                    return (a:getUnequippedWeight() or 0) <= (b:getUnequippedWeight() or 0)
                end
                return aType < bType
            end)

            for _, item in ipairs(items) do
                if ISInventoryPaneContextMenu and ISInventoryPaneContextMenu.transferIfNeeded then
                    ISInventoryPaneContextMenu.transferIfNeeded(playerObj, item)
                end
            end
        end
    end
end

function CSR_ProximityLoot.addContextOptions(playerNum, context, items)
    if not CSR_FeatureFlags.isProximityLootHelperEnabled() then
        return
    end

    local matchesByContainer, total, firstType = gatherNearbyMatches(playerNum, items)
    if total <= 0 or not firstType then
        return
    end

    local displayName = getDisplayName(firstType)

    local option = context:addOptionOnTop(string.format("Grab Nearby Matching (%d)", total), items, function(_, pn, grouped)
        queueNearbyTransfers(pn, grouped)
    end, playerNum, matchesByContainer)

    option.toolTip = ISInventoryPaneContextMenu.addToolTip and ISInventoryPaneContextMenu.addToolTip() or nil
    if option.toolTip then
        option.toolTip.description = string.format("Transfer all visible nearby %s items from currently open loot sources.", displayName)
    end
end

-- Panel lifecycle
local function createPanel()
    if CSR_ProximityLoot.panel or not CSR_FeatureFlags.isProximityLootHelperEnabled() then
        return
    end

    local state = getState()
    if not state then return end

    local core = getCore and getCore() or nil
    local screenWidth = core and core:getScreenWidth() or 1280
    local screenHeight = core and core:getScreenHeight() or 720
    local x = tonumber(state.x) or math.max(20, screenWidth - PANEL_WIDTH - 20)
    local y = tonumber(state.y) or math.max(40, math.floor(screenHeight / 2 - PANEL_HEIGHT / 2))

    local panel = ProximityLootPanel:new(x, y, PANEL_WIDTH, PANEL_HEIGHT)
    panel:initialise()
    panel:instantiate()
    panel:addToUIManager()
    panel:setVisible(false)
    CSR_ProximityLoot.panel = panel
end

local function togglePanel()
    if not CSR_FeatureFlags.isProximityLootHelperEnabled() then
        return
    end

    if not CSR_ProximityLoot.panel then
        createPanel()
    end

    if CSR_ProximityLoot.panel then
        local visible = not CSR_ProximityLoot.panel:getIsVisible()
        CSR_ProximityLoot.panel:setVisible(visible)
        if visible then
            CSR_ProximityLoot.panel:refresh()
            CSR_ProximityLoot.panel:bringToTop()
        end
    end
end

function CSR_ProximityLoot.toggle()
    togglePanel()
end

local function onKeyPressed(key)
    if key == getBoundKey() then
        togglePanel()
    end
end

local function onGameStart()
    createPanel()
end

-- Sidebar icon button on the loot panel container button column
local searchIconTex = nil

local function getSearchIcon()
    if not searchIconTex then
        searchIconTex = getTexture("media/ui/CSR_ProximityLoot.png")
    end
    return searchIconTex
end

local function onProximitySidebarClick(target, button)
    togglePanel()
    -- Update button highlight
    if button and button.setBackgroundRGBA then
        local isVisible = CSR_ProximityLoot.panel and CSR_ProximityLoot.panel:getIsVisible()
        if isVisible then
            button:setBackgroundRGBA(0.34, 0.66, 0.96, 0.6)
        else
            button:setBackgroundRGBA(0.0, 0.0, 0.0, 0.0)
        end
    end
end

local function onRefreshContainers(inventoryPage, stage)
    if stage ~= "buttonsAdded" then return end
    if not CSR_FeatureFlags.isProximityLootHelperEnabled() then return end
    -- Only add to the loot panel (not the character inventory panel)
    if inventoryPage.onCharacter then return end

    -- Remove old CSR proximity button if it exists (from previous refresh)
    if inventoryPage.csrProximityButton then
        inventoryPage.containerButtonPanel:removeChild(inventoryPage.csrProximityButton)
        inventoryPage.csrProximityButton = nil
    end

    local numBackpacks = #inventoryPage.backpacks
    local btnSize = inventoryPage.buttonSize
    local y = numBackpacks * btnSize + 2

    local button = ISButton:new(0, y, btnSize, btnSize, "", inventoryPage, onProximitySidebarClick)
    button.anchorLeft = false
    button.anchorTop = false
    button.anchorRight = true
    button.anchorBottom = false
    button:initialise()
    button:forceImageSize(math.min(btnSize - 2, 32), math.min(btnSize - 2, 32))

    local icon = getSearchIcon()
    if icon then
        button:setImage(icon)
    end

    -- Style: highlight if panel is currently visible
    local isVisible = CSR_ProximityLoot.panel and CSR_ProximityLoot.panel:getIsVisible()
    if isVisible then
        button:setBackgroundRGBA(0.34, 0.66, 0.96, 0.6)
    else
        button:setBackgroundRGBA(0.0, 0.0, 0.0, 0.0)
    end
    button:setBackgroundColorMouseOverRGBA(0.3, 0.3, 0.3, 1.0)
    button:setBorderRGBA(0.7, 0.7, 0.7, 0.35)
    button:setTextureRGBA(0.34, 0.66, 0.96, 1.0)
    button.tooltip = "Nearby Loot (Tab)"
    button:setSound("activate", nil)

    inventoryPage.containerButtonPanel:addChild(button)
    inventoryPage.csrProximityButton = button
end

if Events then
    if Events.OnFillInventoryObjectContextMenu then
        Events.OnFillInventoryObjectContextMenu.Add(CSR_ProximityLoot.addContextOptions)
    end
    if Events.OnKeyPressed then Events.OnKeyPressed.Add(onKeyPressed) end
    if Events.OnGameStart then Events.OnGameStart.Add(onGameStart) end
    if Events.OnRefreshInventoryWindowContainers then
        Events.OnRefreshInventoryWindowContainers.Add(onRefreshContainers)
    end
end

return CSR_ProximityLoot
