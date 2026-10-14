require("AdminCore/Registry")
require("AdminCore/OperationsClient")
require("ISUI/ISTextEntryBox")
require("ISUI/ISContextMenu")
-- Optional shared UI helpers; standalone UAC keeps its existing implementation.
if getActivatedMods and getActivatedMods():contains("atf-mini-ui-core-b42") then
    require("MiniUI/Core")
end
local SharedMini = MiniUICore
local C = AdminCore
if C.miniInstalled then
    return
end
C.miniInstalled = true
C.miniDefaults = {
    "ops.observe",
    "core.teleport",
    "power.Invisible",
    "power.GodMod",
    "power.NoClip",
    "native.CHECKSTATS",
    "native.SEEUSERS",
    "native.SEESAFEHOUSES",
    "native.ZONE_EDITOR",
    "core.horde",
    "ops.flight",
    "native.ADMINPOWER",
}
C.miniPins = C.miniPins or {}
for _, id in ipairs(C.miniDefaults) do
    C.miniPins[#C.miniPins + 1] = id
end
local function save()
    if ISLayoutManager and ISLayoutManager.OnPostSave then
        pcall(ISLayoutManager.OnPostSave)
    end
end
function C.miniPinned(id)
    for _, current in ipairs(C.miniPins) do
        if current == id then
            return true
        end
    end
    return false
end
function C.setMiniPinned(id, value)
    if type(id) ~= "string" or not id:match("^[%w_.%-]+$") or #id > 160 then
        return false
    end
    for i = #C.miniPins, 1, -1 do
        if C.miniPins[i] == id then
            table.remove(C.miniPins, i)
        end
    end
    if value and #C.miniPins < 40 then
        C.miniPins[#C.miniPins + 1] = id
    end
    if C.miniPanel then
        C.miniPanel.dirty = true
    end
    save()
    return true
end
function C.miniEntryAllowed(entry)
    if not entry or entry.hidden or entry.id == "ops.mini" then
        return false
    end
    if not C.operationToolAllowed(entry.id) then
        return false
    end
    if entry.action then
        return C.canRun(entry.action)
    end
    return entry.button and entry.button.enable ~= false and entry.button.onclick ~= nil
end
function C.miniRows(entries, query)
    local rows, byId = {}, {}
    query = (query or ""):lower():match("^%s*(.-)%s*$")
    for _, entry in ipairs(entries) do
        byId[entry.id] = entry
        if
            query ~= ""
            and entry.searchable ~= false
            and C.miniEntryAllowed(entry)
            and C.matchesAction(entry.title, entry.category, entry.keywords, "", query, false)
        then
            rows[#rows + 1] = entry
        end
    end
    if query == "" then
        for _, id in ipairs(C.miniPins) do
            if C.miniEntryAllowed(byId[id]) then
                rows[#rows + 1] = byId[id]
            end
        end
    else
        table.sort(rows, C.actionLess)
    end
    return rows
end
function C.pinMenu(entry)
    if not C.miniEntryAllowed(entry) then
        return
    end
    if not C.miniPanel then
        C.ensureMiniPanel()
    end -- register persistent preferences before writing
    local menu = ISContextMenu.get(0, getMouseX(), getMouseY())
    menu:addOption(
        C.miniPinned(entry.id) and "Unpin from Mini Admin" or "Pin to Mini Admin",
        nil,
        function()
            C.setMiniPinned(entry.id, not C.miniPinned(entry.id))
        end
    )
end
function C.bindMiniPin(button, entry)
    button.onRightMouseUp = function()
        C.pinMenu(entry)
        return true
    end
end
local function sourcePanel()
    local panel = ISAdminPanelUI.instance
    if not panel then
        panel = ISAdminPanelUI:new(100, 100, 960, 600)
        panel:initialise()
        panel:addToUIManager()
        panel:setVisible(false)
        panel.uacSearch:unfocus()
        C.operationsKeepAlive("full", false)
    end
    panel:updateButtons()
    return panel
end
function C.activateMiniEntry(id)
    local panel = sourcePanel()
    for _, entry in ipairs(panel.uacEntries or {}) do
        if entry.id == id and C.miniEntryAllowed(entry) then
            if entry.action then
                C.runAction(entry.action)
            else
                entry.button.onclick(entry.button.target, entry.button)
            end
            return true
        end
    end
    C.message("This tool is no longer available for your role.")
    return false
end
local Mini = ISPanel:derive("UACMiniAdmin")
C.MiniAdmin = Mini
function Mini:new()
    local panel = ISPanel.new(self, 24, 140, 400, 400)
    panel.backgroundColor = { r = 0.06, g = 0.09, b = 0.12, a = 0.95 }
    panel.borderColor = { r = 0.3, g = 0.5, b = 0.6, a = 1 }
    panel.page, panel.expanded, panel.collapsed, panel.pinVisible = 1, false, false, false
    panel.opacity, panel.dirty, panel.lastRefresh = 1, true, 0
    return panel
end
local function add(panel, title, callback)
    local b = ISButton:new(8, 8, 60, 28, title, panel, callback)
    b:initialise()
    panel:addChild(b)
    return b
end
function Mini:createChildren()
    self.closeButton = add(self, "X", function(p)
        p:close()
    end)
    self.collapseButton = add(self, "-", function(p)
        p.collapsed = not p.collapsed
        if p.collapsed then
            p.search:unfocus()
        end
        p.dirty = true
        save()
    end)
    self.modeButton = add(self, "Expand", function(p)
        p.expanded = not p.expanded
        p.dirty = true
        save()
    end)
    self.fullButton = add(self, "Full UAC", function()
        C.openControlCenter()
    end)
    self.pinButton = add(self, "Pin Visible", function(p)
        p.pinVisible = not p.pinVisible
        p.dirty = true
        save()
    end)
    self.search = ISTextEntryBox:new("", 8, 64, 300, 28)
    self.search:initialise()
    self:addChild(self.search)
    self.search:setPlaceholderText("Search admin tools...")
    self.search.onTextChange = function()
        self.page, self.dirty = 1, true
    end
    self.previous = add(self, "<", function(p)
        p.page = math.max(1, p.page - 1)
        p.dirty = true
    end)
    self.next = add(self, ">", function(p)
        p.page = p.page + 1
        p.dirty = true
    end)
    self.toolButtons = {}
    self:refresh()
end
function Mini:refresh()
    local panel = sourcePanel()
    local rows = C.miniRows(panel.uacEntries or {}, self.search:getInternalText())
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    self:setWidth(math.min(self.expanded and 600 or 400, sw - 16))
    local rowHeight = math.max(30, getTextManager():getFontHeight(UIFont.Small) + 12)
    local rowsPerPage =
        math.max(1, math.min(self.expanded and 8 or 6, math.floor((sh - 170) / (rowHeight + 4))))
    local columns = self.width >= 390 and 2 or 1
    local size = rowsPerPage * columns
    self.page = math.max(1, math.min(self.page, math.max(1, math.ceil(#rows / size))))
    self.pages = math.max(1, math.ceil(#rows / size))
    local shownRows = math.ceil(math.min(#rows, size) / columns)
    local height = self.collapsed and 32 or 134 + math.max(1, shownRows) * (rowHeight + 4)
    self:setHeight(height)
    self:setX(math.max(8, math.min(self:getX(), sw - self.width - 8)))
    self:setY(math.max(8, math.min(self:getY(), sh - height - 8)))
    self.closeButton:setX(self.width - 32)
    self.closeButton:setY(2)
    self.closeButton:setWidth(28)
    self.collapseButton:setX(self.width - 64)
    self.collapseButton:setY(2)
    self.collapseButton:setWidth(28)
    self.collapseButton:setTitle(self.collapsed and "+" or "-")
    for i, control in ipairs({ self.modeButton, self.fullButton, self.pinButton }) do
        control:setX(8 + (i - 1) * (self.width - 16) / 3)
        control:setY(36)
        control:setWidth((self.width - 24) / 3)
        control:setVisible(not self.collapsed)
    end
    self.modeButton:setTitle(self.expanded and "Compact" or "Expand")
    self.pinButton:setTitle(self.pinVisible and "Unpin Visible" or "Pin Visible")
    self.pinButton.tooltip = "Keep full opacity while using the game."
    self.fullButton.tooltip = "Open the complete Universal Admin panel."
    self.modeButton.tooltip = "Change Mini Admin size without changing your pinned tools."
    self.search:setY(70)
    self.search:setWidth(self.width - 16)
    self.search:setVisible(not self.collapsed)
    for _, b in ipairs(self.toolButtons) do
        b:setVisible(false)
    end
    for i = 1, math.min(size, #rows - (self.page - 1) * size) do
        local entry = rows[(self.page - 1) * size + i]
        local b = self.toolButtons[i]
        if not b then
            b = add(self, "", function(_, button)
                C.activateMiniEntry(button.toolId)
            end)
            self.toolButtons[i] = b
        end
        local title = entry.title:gsub("%.%.%.$", "")
        if entry.id:sub(1, 6) == "power." and C.powerEnabled then
            title = (C.powerEnabled(entry.id:sub(7)) and "[On] " or "[Off] ") .. title
        end
        b:setTitle(title)
        b.toolId = entry.id
        b:setX(8 + ((i - 1) % columns) * (self.width - 12) / columns)
        b:setY(106 + math.floor((i - 1) / columns) * (rowHeight + 4))
        b:setWidth((self.width - 12) / columns - 4)
        b:setHeight(rowHeight)
        b:setVisible(not self.collapsed)
        b.tooltip = entry.category .. " / " .. entry.title .. "\nRight-click to unpin."
        C.bindMiniPin(b, entry)
    end
    for i, b in ipairs({ self.previous, self.next }) do
        b:setY(height - 28)
        b:setX(i == 1 and 8 or self.width - 48)
        b:setWidth(40)
        b:setHeight(24)
        b:setVisible(not self.collapsed)
    end
    self.previous:setEnable(self.page > 1)
    self.next:setEnable(self.page < self.pages)
    self.empty = #rows == 0
    self.dirty, self.lastRefresh, self.registry = false, getTimestampMs(), C.registryVersion
    self.fadeDirty = true -- apply the current fade to newly created controls
end
function Mini:onMouseDown(x, y)
    if SharedMini then
        SharedMini.beginDrag(self, x, y, 32)
        return true
    end
    if y <= 32 then
        self.drag = { x = getMouseX(), y = getMouseY(), px = self:getX(), py = self:getY() }
        self:setCapture(true)
        return true
    end
    return true
end
function Mini:onMouseMove()
    if SharedMini then
        return SharedMini.drag(self)
    end
    if not self.drag then
        return false
    end
    self:setX(
        math.max(
            8,
            math.min(
                self.drag.px + getMouseX() - self.drag.x,
                getCore():getScreenWidth() - self.width - 8
            )
        )
    )
    self:setY(
        math.max(
            8,
            math.min(
                self.drag.py + getMouseY() - self.drag.y,
                getCore():getScreenHeight() - self.height - 8
            )
        )
    )
    return true
end
Mini.onMouseMoveOutside = Mini.onMouseMove
function Mini:onMouseUp()
    if SharedMini then
        return SharedMini.endDrag(self)
    end
    if self.drag then
        self.drag = nil
        self:setCapture(false)
        save()
        return true
    end
    return false
end
Mini.onMouseUpOutside = Mini.onMouseUp
function Mini:saveMiniLayout()
    save()
end
function Mini:onMouseWheel(delta)
    if not self.collapsed then
        self.page = self.page + (delta > 0 and 1 or -1)
        self.dirty = true
    end
    return true
end
function Mini:update()
    local p = getPlayer()
    if not p or not p:getRole() or not p:getRole():hasAdminPower() then
        self:close()
        return
    end
    if
        self.dirty
        or self.registry ~= C.registryVersion
        or getTimestampMs() - self.lastRefresh > 1000
    then
        self:refresh()
    end
    local opacity = (
        self.pinVisible
        or self.drag
        or self.miniDrag
        or self:isMouseOver()
        or (self.search.isFocused and self.search:isFocused())
    )
            and 1
        or 0.3
    if self.fadeDirty or self.opacity ~= opacity then
        if SharedMini then
            self.fadeDirty = false
            self.opacity = opacity
            self.miniAppliedAlpha = nil
            SharedMini.fade(self, opacity)
            return
        end
        self.fadeDirty = false
        self.opacity = opacity
        for _, control in pairs(self:getChildren()) do
            control.miniAlpha = control.miniAlpha or {}
            for _, key in ipairs({
                "backgroundColor",
                "backgroundColorMouseOver",
                "borderColor",
                "textColor",
            }) do
                if control[key] then
                    control.miniAlpha[key] = control.miniAlpha[key] or control[key].a or 1
                    control[key].a = control.miniAlpha[key] * opacity
                end
            end
        end
        self.backgroundColor.a, self.borderColor.a = 0.95 * opacity, opacity
    end
end
function Mini:render()
    self:drawText("MINI ADMIN", 10, 8, 1, 1, 1, self.opacity, UIFont.Small)
    if not self.collapsed then
        self:drawTextCentre(
            "Page " .. self.page .. " / " .. self.pages,
            self.width / 2,
            self.height - 24,
            1,
            1,
            1,
            self.opacity,
            UIFont.Small
        )
        if self.empty then
            self:drawText(
                "No available tools. Search or pin tools in UAC.",
                8,
                106,
                1,
                1,
                1,
                self.opacity,
                UIFont.Small
            )
        end
    end
end
function Mini:close()
    self.miniDrag = nil
    self.drag = nil
    self:setCapture(false)
    self.search:unfocus()
    self:setVisible(false)
    self:removeFromUIManager()
    C.operationsKeepAlive("mini", false)
    save()
end
function C.ensureMiniPanel()
    if C.miniPanel then
        return C.miniPanel
    end
    local p = Mini:new()
    C.miniPanel = p
    p:initialise()
    p:instantiate()
    p:setVisible(false)
    ISLayoutManager.RegisterWindow("AdminCore.Mini", {
        SaveLayout = function(target, _, data)
            data.x, data.y = target:getX(), target:getY()
            data.expanded, data.collapsed, data.pinVisible =
                tostring(target.expanded), tostring(target.collapsed), tostring(target.pinVisible)
            data.favorites = #C.miniPins > 0 and table.concat(C.miniPins, ",") or "none"
        end,
        RestoreLayout = function(target, _, data)
            target:setX(tonumber(data.x) or 24)
            target:setY(tonumber(data.y) or 140)
            target.expanded, target.collapsed, target.pinVisible =
                data.expanded == "true", data.collapsed == "true", data.pinVisible == "true"
            if type(data.favorites) == "string" and #data.favorites <= 6500 then
                C.miniPins = {}
                if data.favorites ~= "none" then
                    for id in data.favorites:gmatch("[^,]+") do
                        if
                            #C.miniPins < 40
                            and #id <= 160
                            and id:match("^[%w_.%-]+$")
                            and not C.miniPinned(id)
                        then
                            C.miniPins[#C.miniPins + 1] = id
                        end
                    end
                end
            end
            target.dirty = true
        end,
    }, p)
    return p
end
function C.openMiniAdmin()
    local p = getPlayer()
    if not p or not p:getRole() or not p:getRole():hasAdminPower() then
        return
    end
    C.operationsKeepAlive("mini", true)
    local panel = C.ensureMiniPanel()
    panel:setVisible(true)
    panel:addToUIManager()
    panel:bringToTop()
    panel.dirty = true
    return panel
end
C.registerAction({
    id = "ops.mini",
    category = "Dashboard",
    title = "Compact Admin",
    keywords = "mini compact favorites pins moderation",
    sortOrder = 90,
    allowed = function()
        local p = getPlayer()
        return p and p:getRole() and p:getRole():hasAdminPower()
    end,
    run = C.openMiniAdmin,
})
