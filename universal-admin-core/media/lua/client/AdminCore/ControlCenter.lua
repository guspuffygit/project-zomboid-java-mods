require("ISUI/AdminPanel/ISAdminPanelUI")
require("ISUI/ISTextEntryBox")
require("AdminCore/Registry")
require("AdminCore/WorldSafezone")
require("AdminCore/Tools")

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
        if
            child.Type == "ISButton"
            and child ~= self.cancel
            and not child.uacOwned
            and child ~= self.uacSizeButton
        then
            local id = child.internal or ""
            self.uacEntries[#self.uacEntries + 1] = {
                button = child,
                category = C.nativeSections[id] or "Mods",
                keywords = C.nativeKeywords[id],
                quick = C.quickAccess[id],
            }
        end
    end
    self.uacCustom = self.uacCustom or {}
    for id, action in pairs(C.actions) do
        local b = self.uacCustom[id]
        if not b then
            b = button(self, action.title, function()
                C.runAction(C.actions[id])
            end)
            self.uacCustom[id] = b
        end
        b:setTitle(action.title)
        b.tooltip = action.tooltip
        self.uacEntries[#self.uacEntries + 1] = {
            button = b,
            category = action.category,
            keywords = action.keywords,
            quick = action.quick,
            action = action,
        }
    end
    table.sort(self.uacEntries, function(a, b)
        local at, bt = tostring(a.button.title):lower(), tostring(b.button.title):lower()
        if at == bt then
            return a.category < b.category
        end
        return at < bt
    end)
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
    local visible = {}
    for _, entry in ipairs(self.uacEntries) do
        entry.button:setVisible(false)
        if entry.action then
            entry.button:setEnable(C.canRun(entry.action))
        end
        if
            C.matchesAction(
                tostring(entry.button.title),
                entry.category,
                entry.keywords,
                self.uacSection,
                query,
                entry.quick
            )
        then
            visible[#visible + 1] = entry
        end
    end
    local font = getTextManager():getFontHeight(UIFont.Small)
    local g = C.pageGeometry(self.width, self.height, font, #visible, self.uacPage)
    self.uacPage = g.page
    local left = 180
    local columnWidth = math.floor((self.width - left - 24 - (g.columns - 1) * 10) / g.columns)
    local first = (g.page - 1) * g.pageSize + 1
    for i = first, math.min(#visible, first + g.pageSize - 1) do
        local b = visible[i].button
        local index = i - first
        b:setX(left + (index % g.columns) * (columnWidth + 10))
        b:setY(108 + math.floor(index / g.columns) * (g.rowHeight + 8))
        b:setWidth(columnWidth)
        b:setHeight(g.rowHeight)
        b:setVisible(true)
        -- Keep long third-party labels readable in their tooltip when clipped.
        if not b.tooltip then
            b.tooltip = tostring(b.title)
        end
    end
    local navHeight = math.max(22, math.min(36, math.floor((self.height - 102) / #C.sections) - 5))
    for i, b in ipairs(self.uacNav) do
        b:setX(12)
        b:setY(72 + (i - 1) * (navHeight + 5))
        b:setWidth(152)
        b:setHeight(navHeight)
        b.backgroundColor = self.uacSection == C.sections[i]
                and { r = 0.18, g = 0.32, b = 0.42, a = 1 }
            or { r = 0, g = 0, b = 0, a = 0.7 }
    end
    self.uacSearch:setX(left)
    self.uacSearch:setY(42)
    self.uacSearch:setWidth(self.width - left - 24)
    self.uacPrevious:setX(left)
    self.uacPrevious:setY(self.height - 43)
    self.uacNext:setX(left + 90)
    self.uacNext:setY(self.height - 43)
    self.uacPrevious:setWidth(80)
    self.uacNext:setWidth(80)
    self.uacPrevious:setEnable(g.page > 1)
    self.uacNext:setEnable(g.page < g.pages)
    self.cancel:setX(self.width - self.cancel.width - 24)
    self.cancel:setY(self.height - 43)
    self.uacHeading = query:match("%S") and "Search results" or self.uacSection
    self.uacSummary = #visible .. " actions  |  Page " .. g.page .. " / " .. g.pages
    self.uacEmpty = #visible == 0
end

function ISAdminPanelUI:create()
    originalCreate(self)
    self.uacSection = "Dashboard"
    self.uacPage = 1
    self.uacNav = {}
    for _, section in ipairs(C.sections) do
        local name = section
        self.uacNav[#self.uacNav + 1] = button(self, name, function(p)
            p.uacSection = name
            p.uacPage = 1
            p.uacSearch:setText("")
            p:uacRefresh()
        end)
    end
    self.uacSearch = ISTextEntryBox:new("", 180, 42, 400, 28)
    self.uacSearch:initialise()
    self.uacSearch.tooltip =
        "Search every category by action or topic, for example weather, players or permissions."
    self.uacSearch.onTextChange = function()
        self.uacPage = 1
        self:uacRefresh()
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
    self.uacReady = true
    self.uacDirty = true
    C.resizable(self, "ControlCenter", 660, 490, function(p)
        p:uacRefresh()
    end)
    C.fit(self, math.max(self.width, 960), math.max(self.height, 600))
end

function ISAdminPanelUI:updateButtons()
    originalUpdate(self)
    self:uacRefresh()
end

function ISAdminPanelUI:render()
    if not self.uacReady then
        return
    end
    if self.uacDirty or self.uacVersion ~= C.registryVersion then
        self:uacRefresh()
    end
    self:drawText("Server control center", 12, 10, 1, 1, 1, 1, UIFont.Medium)
    self:drawText("Search actions", 12, 45, 0.75, 0.8, 0.85, 1, UIFont.Small)
    self:drawText(
        self.uacHeading .. "  |  " .. self.uacSummary,
        180,
        78,
        0.8,
        0.85,
        0.9,
        1,
        UIFont.Small
    )
    if self.uacEmpty then
        self:drawText(
            "No actions available in this category or search.",
            180,
            115,
            0.8,
            0.8,
            0.8,
            1,
            UIFont.Small
        )
    end
end
