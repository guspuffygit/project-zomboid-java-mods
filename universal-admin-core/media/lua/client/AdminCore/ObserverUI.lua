require("ISUI/ISCollapsableWindow")
require("ISUI/ISPanel")
require("ISUI/ISButton")
require("ISUI/ISComboBox")
require("ISUI/ISTextEntryBox")
require("AdminCore/Registry")
local C, V = AdminCore, AdminCore.observer
if C.observerUIInstalled then
    return
end
C.observerUIInstalled = true
local Window = ISCollapsableWindow:derive("AdminObserverWindow")
local function releaseInput(window)
    if window.search then
        window.search:unfocus()
    end
    for _, combo in ipairs({ window.targets, window.filter }) do
        if combo.expanded then
            -- Native combo boxes share one popup across all windows.
            if combo.popup and combo.popup.parentCombo == combo then
                combo:hidePopup()
            end
            combo.expanded = false
        end
    end
end
local function scroll(body, delta)
    local range = math.max(0, body:getScrollHeight() - body:getScrollAreaHeight())
    local old = body:getYScroll()
    body:setYScroll(math.max(-range, math.min(0, old - delta * 36)))
    body:updateScrollbars()
    return body:getYScroll() ~= old
end
function Window:createChildren()
    ISCollapsableWindow.createChildren(self)
    -- Native collapse is hover auto-hide. Use its existing header control for
    -- explicit minimize instead, so camera input never expands the window.
    self.collapseButton.onclick = function(panel)
        panel:setMinimized(not panel.minimized)
    end
    self.collapseButton:setTooltip("Minimize observer")
    self.body = ISPanel:new(8, 28, self.width - 16, self.height - 38)
    self.body:initialise()
    self:addChild(self.body)
    self.body:setScrollChildren(true)
    self.body:addScrollBars(false)
    self.body.onMouseWheel = scroll
    self.body.prerender = function(body)
        ISPanel.prerender(body)
        body:setStencilRect(0, 0, body.width, body.height)
    end
    self.body.render = function(body)
        body:clearStencilRect()
    end
    self.widgets = {}
    self.yNext = 8
    local function row()
        local y = self.yNext
        self.yNext = y + self.rowHeight + 8
        return y
    end
    local function button(title, x, y, w, callback)
        local control = ISButton:new(x, y, w, self.rowHeight, title, self, function()
            callback()
        end)
        control:initialise()
        self.body:addChild(control)
        control.onMouseWheel = function(_, delta)
            return scroll(self.body, delta)
        end
        self.widgets[#self.widgets + 1] = control
        return control
    end
    local width = self.body.width - 28
    local y = row()
    self.search = ISTextEntryBox:new(V.query, 8, y, width * 0.6, self.rowHeight)
    self.search:initialise()
    self.body:addChild(self.search)
    self.search:setPlaceholderText("Search online players...")
    self.search.onTextChange = function()
        V.query = self.search:getText()
        C.refreshObserverRoster(true)
    end
    self.search.onMouseWheel = function(_, delta)
        return scroll(self.body, delta)
    end
    self.filter = ISComboBox:new(
        16 + width * 0.6,
        y,
        width * 0.4 - 8,
        self.rowHeight,
        self,
        function()
            V.filter = self.filter:getOptionText(self.filter.selected)
            C.refreshObserverRoster(true)
        end
    )
    self.filter:initialise()
    self.body:addChild(self.filter)
    for _, label in ipairs({ "All", "Nearby", "Faction" }) do
        self.filter:addOption(label)
    end
    y = row()
    self.targets = ISComboBox:new(8, y, width - 96, self.rowHeight, self, function()
        C.selectObserver(self.targets:getOptionText(self.targets.selected))
    end)
    self.targets:initialise()
    self.body:addChild(self.targets)
    button("Observe", width - 80, y, 88, function()
        local name = self.targets:getOptionText(self.targets.selected)
        if name and name ~= "No matching players" then
            C.startObserver(name)
        end
    end)
    y = row()
    for i, option in ipairs({
        {
            "< Previous",
            function()
                C.observerNext(-1)
            end,
        },
        {
            "Follow",
            function()
                C.observerMode("FOLLOW")
            end,
        },
        {
            "Soft",
            function()
                C.observerMode("SOFT")
            end,
        },
        {
            "Free",
            function()
                if V.id then
                    C.observerMode("FREE")
                else
                    C.startFreeCamera()
                end
            end,
        },
        {
            "Next >",
            function()
                C.observerNext(1)
            end,
        },
    }) do
        button(option[1], 8 + (i - 1) * (width + 6) / 5, y, (width - 24) / 5, option[2])
    end
    y = row()
    self.teleportButton = button("Teleport To", 8, y, (width - 12) / 3, C.observerTeleport)
    self.returnButton =
        button("Return to Origin", 14 + (width - 12) / 3, y, (width - 12) / 3, C.observerReturn)
    button("Stop / Self", 20 + 2 * (width - 12) / 3, y, (width - 12) / 3, C.stopObserve)
    y = row()
    self.facingButton = button("", 8, y, (width - 6) / 2, function()
        V.facing = not V.facing
        C.updateObserverOverlays()
    end)
    self.infoButton = button("", 14 + (width - 6) / 2, y, (width - 6) / 2, function()
        V.info = not V.info
        V.infoRefresh = 0
        self:layoutInfo()
    end)
    y = row()
    self.safehousesButton = button("", 8, y, (width - 6) / 2, function()
        V.safehouses = not V.safehouses
        C.updateObserverOverlays()
    end)
    self.weatherButton = button("", 14 + (width - 6) / 2, y, (width - 6) / 2, function()
        C.observerWeather(not V.weather)
    end)
    y = row()
    self.communityButton = button("", 8, y, width, function()
        V.community = not V.community
        C.updateObserverOverlays()
    end)
    y = row()
    self.townsButton = button("", 8, y, (width - 6) / 2, function()
        V.towns = not V.towns
        C.updateObserverOverlays()
    end)
    self.propertiesButton = button("", 14 + (width - 6) / 2, y, (width - 6) / 2, function()
        V.properties = not V.properties
        C.updateObserverOverlays()
    end)
    y = row()
    for i, name in ipairs({ "Normal", "Moderation", "Performance", "Debug" }) do
        button(name, 8 + (i - 1) * (width + 6) / 4, y, (width - 18) / 4, function()
            V.facing = name == "Moderation" or name == "Debug"
            V.info = name == "Debug"
            V.safehouses = name == "Debug"
            V.community = name == "Debug"
            V.towns = name == "Debug"
            V.properties = name == "Debug"
            C.observerWeather(name == "Performance")
            C.updateObserverOverlays()
        end)
    end
    self.textY = row()
    self.yNext = self.yNext + self.lineHeight * 9
    self.body:setScrollHeight(self.yNext)
    self.body.render = function(body)
        -- Native DrawText already applies this panel's yScroll once.
        local y0 = self.textY
        local lines = {
            "Observing: " .. tostring(V.target or "None") .. " | " .. V.mode,
            V.status,
            "WASD: pan | Shift: faster | Ctrl: slower | F: focus | Esc: stop",
            V.stream and "Camera streams a bounded area on the current floor. Origin stays loaded."
                or "Camera stays on the current floor, within loaded tiles.",
            "Facing shows replicated body direction; exact aim is unavailable.",
            "Foliage, roofs, X-ray and bone targeting are not supported.",
        }
        for i, line in ipairs(lines) do
            body:drawText(
                tostring(line),
                8,
                y0 + (i - 1) * self.lineHeight,
                0.85,
                0.86,
                0.88,
                1,
                UIFont.Small
            )
        end
        body:clearStencilRect()
    end
    self:layoutInfo()
end
function Window:updateCompactTitle()
    local title = V.id and (tostring(V.mode) .. " | " .. tostring(V.target or "Free camera"))
        or "Observe / Spectator"
    if title == self.compactCaption then
        return
    end
    self.compactCaption = title
    local available = self.width - self:titleBarHeight() * 2 - 16
    local manager, font = getTextManager(), self.titleBarFont or UIFont.Small
    if manager:MeasureStringX(font, title) > available then
        local last = #title
        repeat
            -- Remove a complete UTF-8 character, preserving non-ASCII names.
            local start = last
            while start > 1 and title:byte(start) >= 128 and title:byte(start) < 192 do
                start = start - 1
            end
            last = start - 1
        until last == 0 or manager:MeasureStringX(font, title:sub(1, last) .. "...") <= available
        title = last > 0 and title:sub(1, last) .. "..." or ""
    end
    self:setTitle(title)
end
function Window:setMinimized(value)
    if C.observePanel ~= self or self.minimized == value then
        return
    end
    self.moving = false
    self:setCapture(false)
    self.pin = true
    -- isCollapsed also suppresses native DrawText; keep the compact title live.
    self.minimized, self.isCollapsed = value, false
    if value then
        self.expandedWidth, self.expandedHeight, self.expandedTitle =
            self.width, self.height, self.title
        releaseInput(self)
        self.body:setVisible(false)
        self:setHeight(self:titleBarHeight())
        self.collapseButton:setImage(self.pinButtonTexture)
        self.collapseButton:setTooltip("Restore observer")
        self.compactCaption = nil
        self:updateCompactTitle()
    else
        self:setWidth(self.expandedWidth or self.width)
        self:setHeight(self.expandedHeight or self.height)
        self:clearMaxDrawHeight()
        self.body:setVisible(true)
        self:setTitle(self.expandedTitle or "Observe / Spectator")
        self.collapseButton:setImage(self.collapseButtonTexture)
        self.collapseButton:setTooltip("Minimize observer")
        self.compactCaption = nil
        self:layoutInfo()
    end
end
function Window:uncollapse()
    if not self.minimized then
        ISCollapsableWindow.uncollapse(self)
    end
end
function Window:layoutInfo()
    if self.minimized then
        return
    end
    local infoHeight = V.info and self.lineHeight * 4 + 12 or 0
    local top = 28 + self.lineHeight + infoHeight
    self.body:setY(top)
    self.body:setHeight(math.max(100, self.height - top - 10))
    self.body:updateScrollbars()
end
function Window:prerender()
    ISCollapsableWindow.prerender(self)
    if self.minimized or self.isCollapsed then
        return
    end
    self:setStencilRect(
        8,
        26,
        self.width - 16,
        self.lineHeight + (V.info and self.lineHeight * 4 + 12 or 0)
    )
    self:drawText(tostring(V.status or ""), 10, 26, 0.9, 0.9, 0.9, 1, UIFont.Small)
    if V.info then
        for i, line in ipairs(C.observerInformation()) do
            self:drawText(
                tostring(line),
                10,
                32 + self.lineHeight * i,
                0.75,
                0.9,
                1,
                1,
                UIFont.Small
            )
        end
    end
    self:clearStencilRect()
end
function Window:update()
    ISCollapsableWindow.update(self)
    if self.minimized then
        self:updateCompactTitle()
        return
    end
    self:layoutInfo()
    self.teleportButton:setEnable(C.selectedObserverName() ~= nil and not V.teleportPending)
    self.returnButton:setEnable(V.returnId ~= nil)
    self.facingButton:setTitle((V.facing and "[x] " or "[ ] ") .. "Facing")
    self.infoButton:setTitle((V.info and "[x] " or "[ ] ") .. "Player info")
    self.safehousesButton:setTitle((V.safehouses and "[x] " or "[ ] ") .. "Safehouses")
    self.weatherButton:setTitle((V.weather and "[x] " or "[ ] ") .. "Hide WeatherFX")
    self.communityButton:setTitle(
        (V.community and "[x] " or "[ ] ") .. "Community zones (authorized loaded state)"
    )
    self.townsButton:setTitle((V.towns and "[x] " or "[ ] ") .. "Town boundaries")
    self.propertiesButton:setTitle((V.properties and "[x] " or "[ ] ") .. "Property boundaries")
    self.safehousesButton:setEnable(V.id ~= nil and V.render == true)
    self.weatherButton:setEnable(V.id ~= nil and V.render == true)
    self.communityButton:setEnable(V.id ~= nil and V.render == true and ATFCommunity ~= nil)
    self.townsButton:setEnable(V.id ~= nil and V.render == true and ATFCommunity ~= nil)
    self.propertiesButton:setEnable(V.id ~= nil and V.render == true and ATFCommunity ~= nil)
end
function Window:close()
    if C.observePanel ~= self then
        return
    end
    releaseInput(self)
    C.stopObserve()
    V.teleportPending = nil
    C.operationsKeepAlive("observer", false)
    self:removeFromUIManager()
    C.observePanel = nil
end
function Window:removeFromUIManager()
    self.moving = false
    self:setCapture(false)
    releaseInput(self)
    ISCollapsableWindow.removeFromUIManager(self)
end
function C.refreshObserverChoices()
    local panel = C.observePanel
    if not panel or not panel.targets then
        return
    end
    local selected = panel.targets:getOptionText(panel.targets.selected) or V.selected
    local selectedIndex, observedIndex = nil, nil
    panel.targets:clear()
    for _, name in ipairs(V.roster) do
        panel.targets:addOption(name)
        if name == selected then
            selectedIndex = #panel.targets.options
        end
        if name == V.target then
            observedIndex = #panel.targets.options
        end
    end
    if #V.roster == 0 then
        panel.targets:addOption("No matching players")
    end
    panel.targets.selected = selectedIndex or observedIndex or 1
    C.selectObserver(panel.targets:getOptionText(panel.targets.selected))
end
function C.openObserverPanel(name)
    C.operationsKeepAlive("observer", true)
    if not C.observePanel then
        local font = getTextManager():getFontHeight(UIFont.Small)
        local width = math.min(700, math.max(520, getCore():getScreenWidth() - 100))
        local height = math.min(getCore():getScreenHeight() - 80, math.max(470, font * 20 + 170))
        local panel = Window:new(30, 50, width, height)
        panel.rowHeight = math.max(28, font + 12)
        panel.lineHeight = font + 6
        panel:initialise()
        panel:addToUIManager()
        panel:setTitle("Observe / Spectator")
        panel:setResizable(false)
        C.observePanel = panel
    else
        C.observePanel:setVisible(true)
        C.observePanel:bringToTop()
    end
    sendClientCommand("UniversalAdminCore", "observeStatus", {})
    C.refreshObserverRoster(true)
    if name then
        C.selectObserver(name)
        C.startObserver(name)
    end
end
C.openObserverTools = C.openObserverPanel
C.registerAction({
    id = "ops.observe",
    title = "Observe players...",
    category = "World",
    keywords = "spectator follow camera moderation players",
    allowed = function()
        return C.operationsAllowed("ADMIN_SPECTATOR")
    end,
    run = function()
        C.openObserverPanel()
    end,
})
C.registerAction({
    id = "ops.flight",
    title = "Free spectator camera...",
    category = "World",
    keywords = "flight free fly camera",
    allowed = function()
        return C.operationsAllowed("ADMIN_SPECTATOR")
    end,
    run = C.startFreeCamera,
})
