require("ISUI/AdminPanel/ISAdminPanelUI")
require("ISUI/ISTextEntryBox")
require("AdminCore/Registry")
require("AdminCore/ActionGroups")
require("AdminCore/WorldSafezone")
require("AdminCore/Tools")
require("AdminCore/ContextActions")
require("AdminCore/OperationsClient")
require("AdminCore/MiniAdmin")
require("AdminCore/AdminPowers")
require("AdminCore/DebugTools")
require("AdminCore/SafehouseBoundary")

local C = AdminCore
if C.controlCenterInstalled then
    return
end
C.controlCenterInstalled = true
local originalCreate = ISAdminPanelUI.create
local originalUpdate = ISAdminPanelUI.updateButtons
local originalAddChild = ISAdminPanelUI.addChild

local function button(panel, title, callback)
    local b = ISButton:new(12, 12, 130, 30, title, panel, callback)
    b.uacOwned = true
    b:initialise()
    panel:addChild(b)
    return b
end

function ISAdminPanelUI:addChild(child)
    originalAddChild(self, child)
    if self.uacReady and child.Type == "ISButton" and not child.uacOwned then
        self.uacDirty = true
    end
end

function ISAdminPanelUI:uacCollect()
    self.uacEntries = {}
    for _, child in pairs(self:getChildren()) do
        if child.Type == "ISButton" and child ~= self.cancel and not child.uacOwned then
            local id = child.internal or ""
            local presentation = C.actionPresentation(
                "native." .. id,
                C.nativeSections[id] or "Server",
                C.nativeGroups[id]
            )
            -- Search captions are temporary. Never import our previous path
            -- prefix as the native tool name when extensions change the registry.
            local nativeTitle = child.uacDisplayTitle == child.title and child.uacNativeTitle
                or child.title
            child.uacNativeTitle = nativeTitle
            self.uacEntries[#self.uacEntries + 1] = {
                id = "native." .. id,
                title = presentation.displayName or nativeTitle,
                button = child,
                category = presentation.category,
                sourceCategory = presentation.sourceCategory,
                keywords = C.nativeKeywords[id],
                quick = C.quickAccess[id],
                groups = presentation.groups,
                visibleInNavigation = presentation.visibleInNavigation,
                searchable = presentation.searchable,
                hidden = presentation.hidden,
                sortOrder = presentation.sortOrder,
            }
        end
    end
    self.uacCustom = self.uacCustom or {}
    for id, action in pairs(C.actions) do
        local presentation = C.actionPresentation(id, action.category, action.group, action)
        local b = self.uacCustom[id]
        if not b then
            b = button(self, action.title, function()
                C.runAction(C.actions[id])
            end)
            self.uacCustom[id] = b
        end
        b:setTitle(action.title)
        b.tooltip = presentation.category
            .. " / "
            .. (#presentation.groups > 0 and (table.concat(presentation.groups, " / ") .. " / ") or "")
            .. action.title
            .. (action.tooltip and ("\n" .. action.tooltip) or "")
        self.uacEntries[#self.uacEntries + 1] = {
            id = id,
            title = presentation.displayName or action.title,
            button = b,
            category = presentation.category,
            sourceCategory = presentation.sourceCategory,
            groups = presentation.groups,
            keywords = action.keywords,
            quick = action.quick,
            action = action,
            visibleInNavigation = presentation.visibleInNavigation,
            searchable = presentation.searchable,
            hidden = presentation.hidden,
            sortOrder = presentation.sortOrder,
        }
    end
    table.sort(self.uacEntries, C.actionLess)
    for _, entry in ipairs(self.uacEntries) do
        if C.bindMiniPin then
            C.bindMiniPin(entry.button, entry)
        end
    end
    self.uacTree, self.uacGroupEntries = C.buildActionTree(self.uacEntries)
    self.uacGroupButtons = self.uacGroupButtons or {}
    for id, entry in pairs(self.uacGroupEntries) do
        local key = id
        local b = self.uacGroupButtons[key]
        if not b then
            b = button(self, entry.title, function(p)
                p.uacExpanded[key] = not p.uacExpanded[key]
                p:uacRefresh()
            end)
            b.uacArrowUp = getTexture("media/ui/ArrowUp.png")
            b.uacArrowDown = getTexture("media/ui/ArrowDown.png")
            local render = b.render
            b.render = function(control)
                render(control)
                local icon = self.uacExpanded[key] and control.uacArrowUp or control.uacArrowDown
                if icon then
                    control:drawTexture(
                        icon,
                        control.width - 22,
                        (control.height - icon:getHeight()) / 2,
                        1,
                        1,
                        1,
                        1
                    )
                end
            end
            b.backgroundColor = { r = 0.12, g = 0.2, b = 0.25, a = 0.9 }
            self.uacGroupButtons[key] = b
        end
        entry.button = b
    end
    self.uacVersion = C.registryVersion
    self.uacDirty = false
end

function ISAdminPanelUI:uacRefresh()
    if not self.uacReady then
        return
    end
    if self.uacDirty or self.uacVersion ~= C.registryVersion then
        self:uacCollect()
    end
    local query = self.uacSearch:getInternalText()
    self.uacExpanded = self.uacExpanded or {}
    for _, b in pairs(self.uacCustom or {}) do
        b:setVisible(false)
    end
    for _, b in pairs(self.uacGroupButtons or {}) do
        b:setVisible(false)
        if b.uacKeyboardBorder then
            b.borderColor, b.uacKeyboardBorder = b.uacKeyboardBorder, nil
        end
    end
    for _, entry in ipairs(self.uacEntries) do
        entry.button:setVisible(false)
        if entry.button.uacKeyboardBorder then
            entry.button.borderColor = entry.button.uacKeyboardBorder
            entry.button.uacKeyboardBorder = nil
        end
        if entry.action then
            entry.enabled = C.canRun(entry.action)
            entry.button:setEnable(entry.enabled)
        end
        entry.button:setTitle(
            query:match("%S")
                    and (entry.category .. (#entry.path > 0 and (" / " .. entry.path) or "") .. " / " .. entry.title)
                or entry.title
        )
        if not entry.action then
            entry.button.uacDisplayTitle = entry.button.title
        end
    end
    local visible, hierarchical =
        C.actionRows(self.uacTree, self.uacEntries, self.uacSection, query, self.uacExpanded)
    self.uacHierarchical = hierarchical
    local font = getTextManager():getFontHeight(UIFont.Small)
    local footerHeight = math.max(self.cancel.height, self.uacPrevious.height, self.uacNext.height)
    local g = C.pageGeometry(
        self.width,
        self.height,
        font,
        #visible,
        self.uacPage,
        hierarchical,
        footerHeight,
        getTextManager():getFontHeight(UIFont.Medium)
    )
    self.uacGeometry = g
    self.uacResults = visible
    self.uacSelected = math.max(1, math.min(self.uacSelected or 1, #visible))
    self.uacPage = g.page
    local navWidth = 152
    for _, name in ipairs(C.sections) do
        navWidth = math.max(navWidth, getTextManager():MeasureStringX(UIFont.Small, name) + 24)
    end
    local left = navWidth + 28
    g.left = left
    self.uacSearchLabelFits = getTextManager():MeasureStringX(UIFont.Small, "Search actions")
        <= navWidth
    local columnWidth = math.floor((self.width - left - 24 - (g.columns - 1) * 10) / g.columns)
    local first = (g.page - 1) * g.pageSize + 1
    if self.uacSelected < first or self.uacSelected >= first + g.pageSize then
        self.uacSelected = first
    end
    for i = first, math.min(#visible, first + g.pageSize - 1) do
        local entry = visible[i]
        local b = entry.button
        local indent = hierarchical and math.min(entry.depth, 5) * 18 or 0
        if entry.isGroup then
            local opened = self.uacExpanded[entry.id]
            b:setTitle(entry.title .. "  (" .. entry.count .. ")")
            b.tooltip = (opened and "Collapse " or "Expand ") .. entry.title
        end
        C.pin(b)
        local index = i - first
        b:setX(left + (index % g.columns) * (columnWidth + 10) + indent)
        b:setY(g.top + math.floor(index / g.columns) * (g.rowHeight + 8))
        b:setWidth(columnWidth - indent)
        b:setHeight(g.rowHeight)
        b:setVisible(true)
        if i == self.uacSelected then
            b.uacKeyboardBorder = b.borderColor
            b.borderColor = { r = 0.3, g = 0.75, b = 1, a = 1 }
        end
        -- Keep long third-party labels readable in their tooltip when clipped.
        if not b.tooltip then
            b.tooltip = tostring(b.title)
        end
    end
    local navHeight =
        math.max(font + 12, math.min(36, math.floor((self.height - 102) / #C.sections) - 5))
    for i, b in ipairs(self.uacNav) do
        C.pin(b)
        b:setX(12)
        b:setY(math.max(72, g.searchY + g.searchHeight + 4) + (i - 1) * (navHeight + 5))
        b:setWidth(navWidth)
        b:setHeight(navHeight)
        b.backgroundColor = self.uacSection == C.sections[i]
                and { r = 0.18, g = 0.32, b = 0.42, a = 1 }
            or { r = 0, g = 0, b = 0, a = 0.7 }
    end
    for _, control in ipairs({ self.uacSearch, self.uacPrevious, self.uacNext, self.cancel }) do
        C.pin(control)
    end
    self.uacSearch:setX(left)
    self.uacSearch:setY(g.searchY)
    self.uacSearch:setWidth(self.width - left - 24)
    self.uacSearch:setHeight(g.searchHeight)
    local previousTitle, nextTitle = "Previous", "Next"
    local previousWidth =
        math.max(80, getTextManager():MeasureStringX(UIFont.Small, previousTitle) + 16)
    local nextWidth = math.max(80, getTextManager():MeasureStringX(UIFont.Small, nextTitle) + 16)
    local closeWidth =
        math.max(200, getTextManager():MeasureStringX(UIFont.Small, self.cancel.title) + 16)
    local footerLeft = left
    if previousWidth + nextWidth + closeWidth + 20 > self.width - left - 24 then
        footerLeft = 12
    end
    if previousWidth + nextWidth + closeWidth + 20 > self.width - footerLeft - 24 then
        -- Keep navigation reachable if translations or very large fonts make
        -- the full captions too wide. Their existing tooltips retain the names.
        previousTitle, nextTitle = "<", ">"
        previousWidth =
            math.max(44, getTextManager():MeasureStringX(UIFont.Small, previousTitle) + 16)
        nextWidth = math.max(44, getTextManager():MeasureStringX(UIFont.Small, nextTitle) + 16)
    end
    self.uacPrevious:setTitle(previousTitle)
    self.uacNext:setTitle(nextTitle)
    self.uacPrevious:setX(footerLeft)
    self.uacPrevious:setY(g.footerY)
    self.uacNext:setX(footerLeft + previousWidth + 10)
    self.uacNext:setY(g.footerY)
    self.uacPrevious:setWidth(previousWidth)
    self.uacNext:setWidth(nextWidth)
    self.uacPrevious:setEnable(g.page > 1)
    self.uacNext:setEnable(g.page < g.pages)
    self.cancel:setWidth(closeWidth)
    self.cancel:setX(self.width - closeWidth - 24)
    self.cancel:setY(g.footerY)
    for _, control in ipairs({ self.uacPrevious, self.uacNext, self.cancel }) do
        control:setHeight(g.footerHeight)
    end
    self.uacHeading = query:match("%S") and "Search results" or self.uacSection
    self.uacSummary = #visible
        .. (hierarchical and " entries" or " actions")
        .. "  |  Page "
        .. g.page
        .. " / "
        .. g.pages
    g.summaryText = self.uacHeading .. "  |  " .. self.uacSummary
    if getTextManager():MeasureStringX(UIFont.Small, g.summaryText) > self.width - left - 24 then
        g.summaryText = "Page " .. g.page .. " / " .. g.pages
    end
    self.uacEmpty = #visible == 0
end

function ISAdminPanelUI:create()
    if C.operationsKeepAlive then
        C.operationsKeepAlive("full", true)
    end
    if C.importDebugPanels then
        C.importDebugPanels()
    end
    originalCreate(self)
    if self.adminPowerBtn and C.openAdminPowers then
        self.adminPowerBtn.onclick = function()
            C.openAdminPowers()
        end
    end
    self.uacSection = "Dashboard"
    self.uacPage = 1
    self.uacExpanded = {}
    self.uacNav = {}
    for _, section in ipairs(C.sections) do
        local name = section
        self.uacNav[#self.uacNav + 1] = button(self, name, function(p)
            p.uacSection = name
            p.uacPage = 1
            p.uacSelected = 1
            p.uacSearch:setText("")
            p:uacRefresh()
        end)
    end
    self.uacSearch = ISTextEntryBox:new("", 180, 42, 400, 28)
    self.uacSearch:initialise()
    if self.uacSearch.setPlaceholderText then
        self.uacSearch:setPlaceholderText("Search admin tools...")
    end
    self.uacSearch.tooltip =
        "Search actions. Up/Down selects, Enter opens, Escape closes. Ctrl+A opens this panel when you are not typing."
    self.uacSearch.onTextChange = function()
        self.uacPage = 1
        self.uacSelected = 1
        self:uacRefresh()
    end
    self.uacSearch.onPressDown = function()
        self:uacSelect(1)
    end
    self.uacSearch.onPressUp = function()
        self:uacSelect(-1)
    end
    self.uacSearch.onCommandEntered = function()
        self:uacActivate()
    end
    self.uacSearch.onOtherKey = function(_, key)
        if key == Keyboard.KEY_ESCAPE then
            self:close()
        end
    end
    self:addChild(self.uacSearch)
    self.uacPrevious = button(self, "Previous", function(p)
        p.uacPage = p.uacPage - 1
        p:uacRefresh()
    end)
    self.uacNext = button(self, "Next", function(p)
        p.uacPage = p.uacPage + 1
        p:uacRefresh()
    end)
    self.uacPrevious.tooltip = "Previous page of tools. The mouse wheel also changes pages."
    self.uacNext.tooltip = "Next page of tools. The mouse wheel also changes pages."
    self.uacReady = true
    self.uacDirty = true
    C.fit(self, math.max(self.width, 960), math.max(self.height, 600))
    C.resizable(self, "ControlCenter", 660, 490, function(p)
        p:uacRefresh()
    end)
    if self.uacSearch.focus then
        self.uacSearch:focus()
    end
end

function ISAdminPanelUI:uacSelect(delta)
    self:uacRefresh()
    local count = #self.uacResults
    if count == 0 then
        return
    end
    self.uacSelected = math.max(1, math.min(count, self.uacSelected + delta))
    local g = C.pageGeometry(
        self.width,
        self.height,
        getTextManager():getFontHeight(UIFont.Small),
        count,
        1,
        self.uacHierarchical,
        self.uacGeometry.footerHeight,
        self.uacGeometry.titleHeight
    )
    self.uacPage = math.floor((self.uacSelected - 1) / g.pageSize) + 1
    self:uacRefresh()
end

function ISAdminPanelUI:onMouseWheel(delta)
    if not self.uacReady then
        return false
    end
    self:uacRefresh()
    if self.uacGeometry.pages <= 1 or delta == 0 then
        return false
    end
    -- Native PZ controls use positive wheel deltas to advance down the content.
    self.uacPage = self.uacPage + (delta > 0 and 1 or -1)
    self:uacRefresh()
    return true
end

function ISAdminPanelUI:uacActivate()
    -- Native buttons can lose permission while the window/search remains open.
    local entry = self.uacResults[self.uacSelected or 1]
    self:updateButtons()
    if
        not entry
        or not entry.button:getIsVisible()
        or entry.button.enable == false
        or not entry.button.onclick
    then
        return
    end
    if self.uacSearch.unfocus then
        self.uacSearch:unfocus()
    end
    entry.button.onclick(entry.button.target, entry.button)
end

local originalClose = ISAdminPanelUI.close
function ISAdminPanelUI:close()
    if C.operationsKeepAlive then
        C.operationsKeepAlive("full", false)
    end
    if self.uacSearch and self.uacSearch.unfocus then
        self.uacSearch:unfocus()
    end
    return originalClose(self)
end

function C.openControlCenter()
    local player = getPlayer()
    if not player or not player:getRole() or not player:getRole():hasAdminPower() then
        return
    end
    if C.operationsKeepAlive then
        C.operationsKeepAlive("full", true)
    end
    local panel = ISAdminPanelUI.instance
    if not panel then
        panel = ISAdminPanelUI:new(100, 100, 960, 600)
        panel:initialise()
        panel:addToUIManager()
    end
    panel:setVisible(true)
    panel:bringToTop()
    panel.uacSearch:focus()
    return panel
end

function C.onControlCenterKey(key)
    if key ~= Keyboard.KEY_A or not isCtrlKeyDown() or getCore():isDoingTextEntry() then
        return
    end
    C.openControlCenter()
end
Events.OnKeyStartPressed.Add(C.onControlCenterKey)

function ISAdminPanelUI:updateButtons()
    originalUpdate(self)
    self:uacRefresh()
end

function ISAdminPanelUI:render()
    if not self.uacReady then
        return
    end
    if
        self.uacDirty
        or self.uacVersion ~= C.registryVersion
        or not self.uacGeometry
        or self.width ~= self.uacGeometry.width
        or self.height ~= self.uacGeometry.height
        or getTextManager():getFontHeight(UIFont.Small) ~= self.uacGeometry.fontHeight
        or getTextManager():getFontHeight(UIFont.Medium) ~= self.uacGeometry.titleHeight
    then
        self:uacRefresh()
    end
    self:drawText("Server control center", 12, 10, 1, 1, 1, 1, UIFont.Medium)
    if self.uacSearchLabelFits then
        self:drawText(
            "Search actions",
            12,
            self.uacGeometry.searchY + 3,
            0.75,
            0.8,
            0.85,
            1,
            UIFont.Small
        )
    end
    self:drawText(
        self.uacGeometry.summaryText,
        self.uacGeometry.left,
        self.uacGeometry.summaryY,
        0.8,
        0.85,
        0.9,
        1,
        UIFont.Small
    )
    if self.uacEmpty then
        self:drawText(
            "No actions available in this category or search.",
            self.uacGeometry.left,
            self.uacGeometry.top + 7,
            0.8,
            0.8,
            0.8,
            1,
            UIFont.Small
        )
    end
end
