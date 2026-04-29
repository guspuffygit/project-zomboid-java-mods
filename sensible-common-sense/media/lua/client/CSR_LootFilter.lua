
require "CSR_FeatureFlags"
require "CSR_Theme"
require "CSR_Utils"

CSR_LootFilter = {
    panel = nil,
}

local MODDATA_KEY = "CSRLootFilter"
local DEFAULT_KEY = Keyboard and Keyboard.KEY_BACKSLASH or 43
local HIDE_EQUIPPED_DEFAULT_KEY = Keyboard and Keyboard.KEY_DECIMAL or 83
local FILTERS = {
    { key = "Underwear", group = "Apparel", tooltip = "Hide underwear, socks, stockings, and swimwear.", matcher = "bodyLocContains", terms = { "underwear", "socks", "stockings", "swimwear" } },
    { key = "Cotton", group = "Apparel", tooltip = "Hide cotton clothing items.", matcher = "tag", terms = { ItemTag.RIP_CLOTHING_COTTON } },
    { key = "Denim", group = "Apparel", tooltip = "Hide denim clothing items.", matcher = "tag", terms = { ItemTag.RIP_CLOTHING_DENIM } },
    { key = "Jewelry", group = "Apparel", tooltip = "Hide rings, necklaces, dog tags, and similar jewelry-slot items.", matcher = "bodyLocContains", terms = { "necklace", "ring", "ears", "eartop", "belly" } },
    { key = "Cups", group = "Household", tooltip = "Hide cups, mugs, glasses, and similar small fluid containers.", matcher = "fullTypeExact", terms = { "Base.PlasticCup", "Base.Mug", "Base.TeaCup", "Base.GlassTumbler", "Base.FountainCup", "Base.DrinkingGlass", "Base.GlassWine", "Base.Teacup" } },
    { key = "Cookware", group = "Household", tooltip = "Hide low-capacity and niche cookware items.", matcher = "fullTypeExact", terms = { "Base.BakingTray", "Base.BakingPan", "Base.RoastingPan", "Base.MuffinTray", "Base.Saucepan" } },
    { key = "Utensils", group = "Household", tooltip = "Hide utensils and kitchen flavor items.", matcher = "fullTypeExact", terms = { "Base.Spoon", "Base.Fork", "Base.ButterKnife", "Base.BreadKnife", "Base.PlasticKnife", "Base.Strainer", "Base.Ladle", "Base.Spatula", "Base.CarvingFork", "Base.Whisk", "Base.CheeseGrater", "Base.PizzaCutter", "Base.CuttingBoard", "Base.PlasticTray", "Base.BastingBrush", "Base.Plate" } },
    { key = "Toiletries", group = "Household", tooltip = "Hide low-priority bathroom and grooming items.", matcher = "fullTypePrefix", terms = { "Base.Comb", "Base.Razor", "Base.Tooth", "Base.ToiletBrush", "Base.Plunger", "Base.Mirror", "Base.RubberDuck", "Base.Makeup", "Base.Lipstick" } },
    { key = "Magazines", group = "Literature", tooltip = "Hide generic magazines and TV magazines.", matcher = "fullTypePrefix", terms = { "Base.Magazine", "Base.TVMag" } },
    { key = "Writing", group = "Literature", tooltip = "Hide pens, notebooks, papers, and similar writing clutter.", matcher = "fullTypePrefix", terms = { "Base.Pen", "Base.RedPen", "Base.BluePen", "Base.Marker", "Base.Photo", "Base.Diary", "Base.Journal", "Base.Catalog", "Base.Notebook", "Base.Notepad", "Base.SheetPaper", "Base.GraphPaper", "Base.Clipboard", "Base.MenuCard", "Base.Phonebook", "Base.ParkingTicket", "Base.SpeedingTicket", "Base.Paperwork", "Base.Letter", "Base.GenericMail", "Base.Receipt", "Base.Note" } },
    { key = "Recycling", group = "Literature", tooltip = "Hide newspapers, brochures, fliers, and similar disposable literature.", matcher = "displayCategory", terms = { "brochure", "flier", "newspaper" } },
    { key = "Junk", group = "Trash", tooltip = "Hide small junk and low-value clutter items.", matcher = "fullTypePrefix", terms = { "Base.IDcard", "Base.Card_", "Base.Straw", "Base.CameraFilm", "Base.IndexCard", "Base.BusinessCard", "Base.CreditCard", "Base.CompassGeometry", "Base.CorrectionFluid", "Base.Staple", "Base.MagnifyingGlass", "Base.HolePunch", "Base.RubberBand", "Base.TongueDepressor", "Base.Mov_SaltLick", "Base.BathTowel", "Base.DishCloth", "Base.CheeseCloth" } },
    { key = "Toys", group = "Trash", tooltip = "Hide toys, board game pieces, and similar flavor items.", matcher = "fullTypePrefix", terms = { "Base.CatToy", "Base.DogChew", "Base.Clitter", "Base.Toy", "Base.Doll", "Base.Crayons", "Base.Bricktoys", "Base.Cube", "Base.CardDeck", "Base.GamePiece", "Base.Chess", "Base.Backgammon", "Base.CheckerBoard", "Base.Dice", "Base.Birdie", "Base.GolfBall" } },
    { key = "Scrap", group = "Trash", tooltip = "Hide empty cans and similar metal scrap clutter.", matcher = "fullTypeExact", terms = { "Base.TinCanEmpty", "Base.PopEmpty", "Base.Pop2Empty", "Base.Pop3Empty", "Base.SodaCan" } },
    { key = "ManualUnwanted", group = "Personal", tooltip = "Hide items you already marked unwanted in vanilla.", matcher = "unwanted", terms = {} },
    { key = "ClipboardItems", group = "Personal", tooltip = "Hide items that appear on any clipboard checklist in your inventory.", matcher = "clipboard", terms = {} },
}

local options = nil
local showFilterKeyBind = nil
local hideEquippedKeyBind = nil
if PZAPI and PZAPI.ModOptions and PZAPI.ModOptions.create then
    options = PZAPI.ModOptions:create("CommonSenseRebornLootFilter", "Common Sense Reborn - Loot Filter")
    if options and options.addKeyBind then
        showFilterKeyBind = options:addKeyBind("showLootFilter", "Loot Filter Hotkey", DEFAULT_KEY)
        hideEquippedKeyBind = options:addKeyBind("hideEquippedToggle", "Toggle Hide Equipped", HIDE_EQUIPPED_DEFAULT_KEY)
    end
end

local function getBoundKey()
    if showFilterKeyBind and showFilterKeyBind.getValue then
        return showFilterKeyBind:getValue()
    end
    return DEFAULT_KEY
end

local function getHideEquippedKey()
    if hideEquippedKeyBind and hideEquippedKeyBind.getValue then
        return hideEquippedKeyBind:getValue()
    end
    return HIDE_EQUIPPED_DEFAULT_KEY
end

local function getPlayerSafe()
    return getPlayer and getPlayer() or nil
end

local function applyDefaultFilters(state)
    if not state then
        return
    end

    -- v1.8.7: ship with NO category filters enabled by default. Previously
    -- Underwear / Toiletries / ManualUnwanted shipped ON, which silently hid
    -- those items from the loot view on a freshly-looted body until the user
    -- clicked a category tab (drewthegreat87 report). Filtering must now be
    -- an explicit user opt-in.
    state.filters = state.filters or {}
    for _, filter in ipairs(FILTERS) do
        state.filters[filter.key] = false
    end
    state.enabled = false
    state.whitelistRaw = ""
    state.whitelist = {}
end

local function getState()
    local player = getPlayerSafe()
    if not player then
        return nil
    end

    local modData = player:getModData()
    modData[MODDATA_KEY] = modData[MODDATA_KEY] or {
        enabled = false, -- v1.8.7: filter master switch defaults OFF
        locked = false,
        hideEquipped = false,
        x = nil,
        y = nil,
        filters = {},
        whitelistRaw = "",
        whitelist = {},
    }

    local state = modData[MODDATA_KEY]
    state.filters = state.filters or {}
    state.whitelistRaw = state.whitelistRaw or ""
    state.whitelist = state.whitelist or {}
    if state.hideEquipped == nil then state.hideEquipped = false end
    for _, filter in ipairs(FILTERS) do
        if state.filters[filter.key] == nil then
            applyDefaultFilters(state)
            break
        end
    end

    return state
end

local function getLootPane()
    local player = getPlayerSafe()
    if not player then
        return nil
    end

    local playerNum = player:getPlayerNum()
    local lootWindow = getPlayerLoot and getPlayerLoot(playerNum) or nil
    return lootWindow and lootWindow.inventoryPane or nil
end

local refreshLootPane  -- forward declaration; defined after filter helpers

local function rebuildWhitelist(state)
    if not state then
        return
    end

    state.whitelist = {}
    local raw = state.whitelistRaw or ""
    for entry in string.gmatch(raw, "([^,]+)") do
        local clean = entry:gsub("^%s*(.-)%s*$", "%1")
        if clean ~= "" then
            state.whitelist[#state.whitelist + 1] = clean
        end
    end
end

local function isWhitelisted(item, state)
    if not item or not state or type(state.whitelist) ~= "table" or #state.whitelist == 0 then
        return false
    end

    local fullType = item.getFullType and item:getFullType() or ""
    local displayName = item.getDisplayName and item:getDisplayName() or ""
    if type(fullType) ~= "string" then
        fullType = ""
    end
    if type(displayName) ~= "string" then
        displayName = ""
    end
    local fullTypeLower = string.lower(fullType)
    local displayNameLower = string.lower(displayName)

    for _, entry in ipairs(state.whitelist) do
        local needle = type(entry) == "string" and string.lower(entry) or ""
        if needle ~= "" then
            if fullTypeLower == needle or fullTypeLower:find(needle, 1, true) or displayNameLower:find(needle, 1, true) then
                return true
            end
        end
    end

    return false
end

local function getActualItem(group)
    if not group then
        return nil
    end

    if instanceof and instanceof(group, "InventoryItem") then
        return group
    end

    local items = group.items
    if items and items[1] then
        return items[1]
    end

    return nil
end

local function matchesTerms(source, terms)
    if type(source) ~= "string" or type(terms) ~= "table" then
        return false
    end

    local lowerSource = string.lower(source)
    for _, term in ipairs(terms) do
        local lowerTerm = type(term) == "string" and string.lower(term) or nil
        if lowerTerm and lowerTerm ~= "" and lowerSource:find(lowerTerm, 1, true) then
            return true
        end
    end
    return false
end

local _clipboardNamesCache = nil
local _clipboardNamesCacheTick = -1

local function getClipboardNamesCache(player)
    local tick = getTimestampMs and getTimestampMs() or 0
    if _clipboardNamesCache and (tick - _clipboardNamesCacheTick) < 2000 then
        return _clipboardNamesCache
    end
    _clipboardNamesCache = CSR_Utils.getClipboardItemNames(player)
    _clipboardNamesCacheTick = tick
    return _clipboardNamesCache
end

local function matchesFilter(item, filter, player)
    if not item or not filter then
        return false
    end

    if filter.matcher == "unwanted" then
        return item.isUnwanted and player and item:isUnwanted(player) == true
    end

    if filter.matcher == "clipboard" then
        if not player or not CSR_Utils then return false end
        local names = getClipboardNamesCache(player)
        local displayName = item.getDisplayName and item:getDisplayName() or nil
        if displayName and type(displayName) == "string" and names[displayName] then
            return true
        end
        return false
    end

    if filter.matcher == "bodyLocContains" then
        local bodyLoc = item.getBodyLocation and item:getBodyLocation() or nil
        if bodyLoc and type(bodyLoc) ~= "string" then bodyLoc = tostring(bodyLoc) end
        return matchesTerms(bodyLoc, filter.terms)
    end

    if filter.matcher == "displayCategory" then
        local displayCategory = item.getDisplayCategory and item:getDisplayCategory() or nil
        if displayCategory and type(displayCategory) ~= "string" then displayCategory = tostring(displayCategory) end
        return matchesTerms(displayCategory, filter.terms)
    end

    if filter.matcher == "tag" then
        if not item or not item.hasTag then
            return false
        end

        for _, tag in ipairs(filter.terms) do
            if tag and item:hasTag(tag) then
                return true
            end
        end
        return false
    end

    local fullType = item.getFullType and item:getFullType() or nil
    if not fullType then
        return false
    end

    if filter.matcher == "fullTypeExact" then
        for _, term in ipairs(filter.terms) do
            if fullType == term then
                return true
            end
        end
        return false
    end

    if filter.matcher == "fullTypePrefix" then
        for _, term in ipairs(filter.terms) do
            if fullType:find(term, 1, true) == 1 then
                return true
            end
        end
    end

    return false
end

local function shouldHideItem(item)
    if not CSR_FeatureFlags.isLootFilterEnabled() then
        return false
    end

    local player = getPlayerSafe()
    local state = getState()
    if not player or not state then
        return false
    end

    -- Hide equipped items check (independent of filter enabled state)
    -- Only hide items the PLAYER has equipped, not items equipped on zombies/corpses
    if state.hideEquipped == true and item then
        local itemContainer = item.getContainer and item:getContainer() or nil
        local playerInv = player.getInventory and player:getInventory() or nil
        if itemContainer and playerInv and itemContainer == playerInv then
            if (player.isEquippedClothing and player:isEquippedClothing(item))
                or (player.getPrimaryHandItem and player:getPrimaryHandItem() == item)
                or (player.getSecondaryHandItem and player:getSecondaryHandItem() == item)
                -- Hotbar-attached items: getAttachedSlot() > -1 means the item occupies
                -- a hotbar slot (B42 API confirmed in ISHotbar.lua lines 102/389/551)
                or (item.getAttachedSlot and item:getAttachedSlot() > -1) then
                return true
            end
        end
    end

    if state.enabled ~= true then
        return false
    end

    if isWhitelisted(item, state) then
        return false
    end

    for _, filter in ipairs(FILTERS) do
        if state.filters[filter.key] == true and matchesFilter(item, filter, player) then
            return true
        end
    end

    return false
end

CSR_LootFilter.shouldHideItem = shouldHideItem

local function filterPane(pane, page, applyCategories)
    if not pane or type(pane.itemslist) ~= "table" then return end

    local searchText = ""
    if page and page.csrSearchEntry then
        searchText = string.lower(page.csrSearchEntry:getText() or "")
    end

    local state = getState()
    local doFilter = false
    if applyCategories then
        doFilter = state ~= nil and state.enabled == true
    end
    local doHideEquipped = state ~= nil and state.hideEquipped == true

    local hasSearch = searchText ~= ""
    if not hasSearch and not doFilter and not doHideEquipped then return end

    local removedCount = 0
    for i = #pane.itemslist, 1, -1 do
        local group = pane.itemslist[i]
        local actualItem = getActualItem(group)
        if actualItem then
            local hide = false

            if hasSearch then
                local nameOk, displayName = pcall(function() return actualItem:getDisplayName() end)
                if not nameOk then displayName = "" end
                if type(displayName) ~= "string" then displayName = "" end
                if not string.lower(displayName):find(searchText, 1, true) then
                    hide = true
                end
            end

            if not hide and doFilter then
                local filterOk, filterResult = pcall(shouldHideItem, actualItem)
                if filterOk and filterResult then
                    hide = true
                end
            end

            if not hide and doHideEquipped then
                local eqOk, eqResult = pcall(shouldHideItem, actualItem)
                if eqOk and eqResult then
                    hide = true
                end
            end

            if hide then
                table.remove(pane.itemslist, i)
                removedCount = removedCount + 1
            end
        end
    end

    if removedCount > 0 and type(pane.updateScrollbars) == "function" then
        pane:updateScrollbars()
    end
end

local function csrApplyAllFilters()
    if not CSR_FeatureFlags.isLootFilterEnabled() then return end

    local player = getPlayerSafe()
    if not player then return end

    -- Skip filtering while items are being dragged to prevent index desync
    if ISMouseDrag and ISMouseDrag.dragging and type(ISMouseDrag.dragging) == "table" and #ISMouseDrag.dragging > 0 then
        return
    end

    -- Skip filtering during active timed actions to avoid interference with transfers
    if ISTimedActionQueue and ISTimedActionQueue.hasAction then
        local queue = ISTimedActionQueue.getTimedActionQueue(player)
        if queue and ISTimedActionQueue.hasAction(queue) then
            return
        end
    end

    local playerNum = player:getPlayerNum()

    local lootWindow = getPlayerLoot and getPlayerLoot(playerNum) or nil
    if lootWindow then
        pcall(filterPane, lootWindow.inventoryPane, lootWindow, true)
    end

    local invWindow = getPlayerInventory and getPlayerInventory(playerNum) or nil
    if invWindow then
        pcall(filterPane, invWindow.inventoryPane, invWindow, false)
    end
end

refreshLootPane = function()
    local pane = getLootPane()
    if pane and pane.refreshContainer then
        pane:refreshContainer()
    end
    csrApplyAllFilters()
end

local LootFilterPanel = ISPanel:derive("CSR_LootFilterPanel")

function LootFilterPanel:initialise()
    ISPanel.initialise(self)
end

function LootFilterPanel:createChildren()
    ISPanel.createChildren(self)

    local state = getState()
    local y = 28
    local lastGroup = nil
    self.filterButtons = {}

    self.toggleButton = ISButton:new(10, 4, 62, 18, state and state.enabled and "ON" or "OFF", self, self.onToggleFilter)
    self.toggleButton:initialise()
    self.toggleButton:instantiate()
    self:addChild(self.toggleButton)
    CSR_Theme.applyButtonStyle(self.toggleButton, "accentGreen", state and state.enabled == true)

    self.lockButton = ISButton:new(self.width - 56, 4, 48, 18, state and state.locked and "Unlock" or "Lock", self, self.onToggleLock)
    self.lockButton:initialise()
    self.lockButton:instantiate()
    self:addChild(self.lockButton)
    CSR_Theme.applyButtonStyle(self.lockButton, "accentBlue", false)

    self.resetButton = ISButton:new(self.width - 110, 4, 48, 18, "Reset", self, self.onResetFilters)
    self.resetButton:initialise()
    self.resetButton:instantiate()
    self:addChild(self.resetButton)
    CSR_Theme.applyButtonStyle(self.resetButton, "accentAmber", false)

    local whiteLabel = ISLabel:new(10, y + 2, 16, "Whitelist", 1.0, 1.0, 1.0, 0.95, UIFont.Small, true)
    whiteLabel:initialise()
    whiteLabel:instantiate()
    self:addChild(whiteLabel)
    y = y + 16

    self.whitelistEntry = ISTextEntryBox:new(state and state.whitelistRaw or "", 10, y, self.width - 80, 20)
    self.whitelistEntry:initialise()
    self.whitelistEntry:instantiate()
    self.whitelistEntry.tooltip = "Comma-separated full types or search text to never hide. Example: Base.Whiskey, crowbar"
    self:addChild(self.whitelistEntry)

    self.applyWhitelistButton = ISButton:new(self.width - 62, y, 52, 20, "Apply", self, self.onApplyWhitelist)
    self.applyWhitelistButton:initialise()
    self.applyWhitelistButton:instantiate()
    self:addChild(self.applyWhitelistButton)
    y = y + 28

    self.hideEquippedButton = ISButton:new(10, y, self.width - 20, 20, "Hide Equipped Items", self, self.onToggleHideEquipped)
    self.hideEquippedButton.tooltip = "Hide all equipped clothing and held items from the inventory list. Hotkey: Numpad ."
    self.hideEquippedButton:initialise()
    self.hideEquippedButton:instantiate()
    self:addChild(self.hideEquippedButton)
    CSR_Theme.applyButtonStyle(self.hideEquippedButton, "accentGreen", state and state.hideEquipped == true)
    y = y + 28

    for _, filter in ipairs(FILTERS) do
        if lastGroup ~= filter.group then
            local label = ISLabel:new(10, y + 2, 16, filter.group, 1.0, 1.0, 1.0, 0.95, UIFont.Small, true)
            label:initialise()
            label:instantiate()
            self:addChild(label)
            y = y + 16
            lastGroup = filter.group
        end

        local button = ISButton:new(10, y, self.width - 20, 20, filter.key, self, self.onToggleCategory)
        button.internal = filter.key
        button.tooltip = filter.tooltip
        button:initialise()
        button:instantiate()
        self:addChild(button)
        self.filterButtons[filter.key] = button
        y = y + 24
    end

    self:setHeight(y + 8)
    self:updateButtonStates()
end

function LootFilterPanel:onToggleFilter()
    local state = getState()
    if not state then
        return
    end

    state.enabled = state.enabled ~= true
    self:updateButtonStates()
    refreshLootPane()
end

function LootFilterPanel:onToggleLock()
    local state = getState()
    if not state then
        return
    end

    state.locked = state.locked ~= true
    self:updateButtonStates()
end

function LootFilterPanel:onToggleHideEquipped()
    local state = getState()
    if not state then
        return
    end

    state.hideEquipped = state.hideEquipped ~= true
    self:updateButtonStates()
    refreshLootPane()
    -- Also refresh the player inventory pane
    local player = getPlayerSafe()
    if player then
        local playerNum = player:getPlayerNum()
        local invWindow = getPlayerInventory and getPlayerInventory(playerNum) or nil
        if invWindow and invWindow.inventoryPane and invWindow.inventoryPane.refreshContainer then
            invWindow.inventoryPane:refreshContainer()
            filterPane(invWindow.inventoryPane, invWindow, false)
        end
    end
end

function LootFilterPanel:onApplyWhitelist()
    local state = getState()
    if not state or not self.whitelistEntry then
        return
    end

    state.whitelistRaw = self.whitelistEntry:getText() or ""
    rebuildWhitelist(state)
    refreshLootPane()
end

function LootFilterPanel:onResetFilters()
    local state = getState()
    if not state then
        return
    end

    applyDefaultFilters(state)
    rebuildWhitelist(state)
    self:updateButtonStates()
    refreshLootPane()
end

function LootFilterPanel:onToggleCategory(button)
    local state = getState()
    if not state or not button or not button.internal then
        return
    end

    state.filters[button.internal] = state.filters[button.internal] ~= true
    self:updateButtonStates()
    refreshLootPane()
end

function LootFilterPanel:updateButtonStates()
    local state = getState()
    if not state then
        return
    end

    self.toggleButton:setTitle(state.enabled and "ON" or "OFF")
    CSR_Theme.applyButtonStyle(self.toggleButton, state.enabled and "accentGreen" or "accentRed", state.enabled)
    self.lockButton:setTitle(state.locked and "Unlock" or "Lock")
    CSR_Theme.applyButtonStyle(self.lockButton, state.locked and "accentAmber" or "accentBlue", state.locked)
    CSR_Theme.applyButtonStyle(self.resetButton, "accentAmber", false)
    if self.whitelistEntry then
        self.whitelistEntry:setText(state.whitelistRaw or "")
    end
    if self.hideEquippedButton then
        CSR_Theme.applyButtonStyle(self.hideEquippedButton, "accentGreen", state.hideEquipped == true)
    end

    for _, filter in ipairs(FILTERS) do
        local button = self.filterButtons[filter.key]
        if button then
            local enabled = state.filters[filter.key] == true
            local accent = "accentSlate"
            if filter.group == "Apparel" then
                accent = "accentBlue"
            elseif filter.group == "Household" then
                accent = "accentAmber"
            elseif filter.group == "Literature" then
                accent = "accentViolet"
            elseif filter.group == "Trash" then
                accent = "accentRed"
            elseif filter.group == "Personal" then
                accent = "accentGreen"
            end
            CSR_Theme.applyButtonStyle(button, accent, enabled)
        end
    end
end

function LootFilterPanel:prerender()
    ISPanel.prerender(self)
    CSR_Theme.drawPanelChrome(self, "CSR Loot Filter", 24)
end

function LootFilterPanel:onMouseDown(x, y)
    ISPanel.onMouseDown(self, x, y)
    local state = getState()
    if state and state.locked ~= true and y <= 24 then
        self.dragging = true
        self.dragX = x
        self.dragY = y
        self:bringToTop()
    end
    return true
end

function LootFilterPanel:onMouseMove(dx, dy)
    if self.dragging then
        local mouseX = getMouseX and getMouseX() or self:getX()
        local mouseY = getMouseY and getMouseY() or self:getY()
        self:setX(mouseX - self.dragX)
        self:setY(mouseY - self.dragY)
        return true
    end
    return ISPanel.onMouseMove(self, dx, dy)
end

function LootFilterPanel:onMouseMoveOutside(dx, dy)
    return self:onMouseMove(dx, dy)
end

function LootFilterPanel:onMouseUp(x, y)
    ISPanel.onMouseUp(self, x, y)
    if self.dragging then
        self.dragging = false
        local state = getState()
        if state then
            state.x = math.floor(self:getX())
            state.y = math.floor(self:getY())
        end
    end
    return true
end

function LootFilterPanel:onMouseUpOutside(x, y)
    return self:onMouseUp(x, y)
end

local function createPanel()
    if CSR_LootFilter.panel or not CSR_FeatureFlags.isLootFilterEnabled() then
        return
    end

    local state = getState()
    if not state then
        return
    end

    local core = getCore and getCore() or nil
    local screenWidth = core and core:getScreenWidth() or 1280
    local x = tonumber(state.x) or math.max(20, screenWidth - 260)
    local y = tonumber(state.y) or 120
    local panel = LootFilterPanel:new(x, y, 240, 320)
    panel:initialise()
    panel:instantiate()
    panel:addToUIManager()
    panel:setVisible(false)
    CSR_LootFilter.panel = panel
end

local function togglePanel()
    if not CSR_FeatureFlags.isLootFilterEnabled() then
        return
    end

    if not CSR_LootFilter.panel then
        createPanel()
    end

    if CSR_LootFilter.panel then
        local visible = not CSR_LootFilter.panel:getIsVisible()
        CSR_LootFilter.panel:setVisible(visible)
        if visible then
            CSR_LootFilter.panel:updateButtonStates()
            CSR_LootFilter.panel:bringToTop()
        end
    end
end

-- ─────────────────────────────────────────────────────
-- Integrated search bar + auto-apply category filters
-- ─────────────────────────────────────────────────────

local SEARCH_BAR_H = 22
local _overridesInstalled = false

local function installInventoryOverrides()
    if _overridesInstalled then return end
    if not ISInventoryPage then return end
    _overridesInstalled = true

    function ISInventoryPage:csrOnSearchChange(entry)
        if self.inventoryPane and self.inventoryPane.refreshContainer then
            self.inventoryPane:refreshContainer()
        end
        local applyCategories = not self.onCharacter
        filterPane(self.inventoryPane, self, applyCategories)
    end

    function ISInventoryPage:csrOnFilterToggle()
        togglePanel()
    end

    local _origCreateChildren = ISInventoryPage.createChildren
    function ISInventoryPage:createChildren()
        _origCreateChildren(self)

        if not CSR_FeatureFlags.isLootFilterEnabled() then return end

        local titleBarH = self:titleBarHeight()
        local availW = self.width - (self.buttonSize or 0)

        local entryW = availW - 4
        if not self.onCharacter then
            entryW = entryW - SEARCH_BAR_H - 2
        end

        self.csrSearchEntry = ISTextEntryBox:new("", 2, titleBarH, entryW, SEARCH_BAR_H)
        self.csrSearchEntry.anchorRight = true
        self.csrSearchEntry.placeholderText = "Search..."
        self.csrSearchEntry:initialise()
        self.csrSearchEntry:instantiate()
        self.csrSearchEntry.target = self
        self.csrSearchEntry.onTextChangeFunction = ISInventoryPage.csrOnSearchChange
        self:addChild(self.csrSearchEntry)

        if not self.onCharacter then
            self.csrFilterBtn = ISButton:new(2 + entryW + 2, titleBarH, SEARCH_BAR_H, SEARCH_BAR_H, "F", self, ISInventoryPage.csrOnFilterToggle)
            self.csrFilterBtn.anchorRight = true
            self.csrFilterBtn.anchorLeft = false
            self.csrFilterBtn:initialise()
            self.csrFilterBtn:instantiate()
            self.csrFilterBtn.tooltip = "Toggle category filter panel"
            self.csrFilterBtn.borderColor = {r = 0.4, g = 0.4, b = 0.4, a = 0.6}
            self.csrFilterBtn.backgroundColor = {r = 0.15, g = 0.15, b = 0.15, a = 0.8}
            self.csrFilterBtn.backgroundColorMouseOver = {r = 0.3, g = 0.3, b = 0.3, a = 0.8}
            -- v1.8.7: tint the F button red while filtering is active so the
            -- player can never lose track of why their loot view is shorter
            -- than expected (drewthegreat87 report).
            local _origPrerender = self.csrFilterBtn.prerender
            self.csrFilterBtn.prerender = function(btn)
                local st = getState()
                local hasCat = false
                if st and st.filters then
                    for _, f in ipairs(FILTERS) do
                        if st.filters[f.key] then hasCat = true; break end
                    end
                end
                local active = (st and st.enabled == true and hasCat) or (st and st.hideEquipped == true)
                if active then
                    btn.borderColor = {r = 0.95, g = 0.30, b = 0.30, a = 1.0}
                    btn.backgroundColor = {r = 0.40, g = 0.10, b = 0.10, a = 0.85}
                    btn.tooltip = "Loot filter ACTIVE -- click to open / hide hidden items"
                else
                    btn.borderColor = {r = 0.4, g = 0.4, b = 0.4, a = 0.6}
                    btn.backgroundColor = {r = 0.15, g = 0.15, b = 0.15, a = 0.8}
                    btn.tooltip = "Toggle category filter panel"
                end
                if _origPrerender then return _origPrerender(btn) end
            end
            self:addChild(self.csrFilterBtn)
        end

        if self.inventoryPane then
            self.inventoryPane:setY(titleBarH + SEARCH_BAR_H)
            self.inventoryPane:setHeight(self.inventoryPane:getHeight() - SEARCH_BAR_H)
        end
        if self.containerButtonPanel then
            self.containerButtonPanel:setY(titleBarH + SEARCH_BAR_H)
            self.containerButtonPanel:setHeight(self.containerButtonPanel:getHeight() - SEARCH_BAR_H)
        end
    end

end

local function toggleHideEquipped()
    local state = getState()
    if not state then return end

    state.hideEquipped = state.hideEquipped ~= true

    if CSR_LootFilter.panel and CSR_LootFilter.panel.updateButtonStates then
        CSR_LootFilter.panel:updateButtonStates()
    end

    -- Refresh both loot and player inventory panes
    refreshLootPane()
    local player = getPlayerSafe()
    if player then
        local playerNum = player:getPlayerNum()
        local invWindow = getPlayerInventory and getPlayerInventory(playerNum) or nil
        if invWindow and invWindow.inventoryPane and invWindow.inventoryPane.refreshContainer then
            invWindow.inventoryPane:refreshContainer()
            filterPane(invWindow.inventoryPane, invWindow, false)
        end
    end
end

local function onKeyPressed(key)
    if key == getBoundKey() then
        togglePanel()
    end
    if key == getHideEquippedKey() then
        toggleHideEquipped()
    end
end

local function onGameStart()
    installInventoryOverrides()
    local state = getState()
    rebuildWhitelist(state)
    createPanel()
end

local function onCreatePlayer()
    installInventoryOverrides()
    local state = getState()
    rebuildWhitelist(state)
    createPanel()
end

if Events then
    -- v1.8.7: defer event registration to OnGameStart and gate on the
    -- feature flag (Phoenix II). Events that fire on every container refresh
    -- and every keypress are skipped entirely on installs that disable the
    -- loot filter.
    local _csrLootFilterRegistered = false
    local function csrEnsureLootFilterRegistered()
        if _csrLootFilterRegistered then return end
        if not (CSR_FeatureFlags and CSR_FeatureFlags.isLootFilterEnabled
            and CSR_FeatureFlags.isLootFilterEnabled()) then return end
        _csrLootFilterRegistered = true
        if Events.OnKeyPressed then Events.OnKeyPressed.Add(onKeyPressed) end
        if Events.OnCreatePlayer then Events.OnCreatePlayer.Add(onCreatePlayer) end
        if Events.OnRefreshInventoryWindowContainers then Events.OnRefreshInventoryWindowContainers.Add(csrApplyAllFilters) end
        -- onGameStart still needs to install ISInventoryPage overrides; call it once now.
        onGameStart()
    end
    if Events.OnGameStart then Events.OnGameStart.Add(csrEnsureLootFilterRegistered) end
end

return CSR_LootFilter
