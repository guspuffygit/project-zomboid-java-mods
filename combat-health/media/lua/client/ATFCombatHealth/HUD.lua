require("MiniUI/Core")
require("ATFCombatHealth/HealthModel")
require("ATFCombatHealth/Telemetry")
require("ATFCombatHealth/SmartTreatmentResolver")
require("ATFCombatHealth/DamageAlerts")
require("ISUI/ISContextMenu")

ATFCombatHealth = ATFCombatHealth or {}
local H = ATFCombatHealth
if H.HUD then
    return H
end
local C = MiniUICore
local Model = ATFCombatHealthModel
local Telemetry = ATFPlayerMiniHUDTelemetry
local DamageAlerts = ATFCombatHealthDamageAlerts
local HUD = C.Window:derive("ATFCombatHealthHUD")
H.HUD = HUD
H.panels = H.panels or {}
H.preferences = H.preferences or {}
H.defaults = {
    enabled = false,
    mode = "compact",
    autoShow = true,
    showHealth = true,
    showXP = true,
    showTemperature = true,
    alwaysShowXP = false,
    keepRespawn = false,
    rememberPosition = true,
    keepVisibleWithHealthClosed = true,
    showTreatment = true,
    focusFade = true,
    opacity = 0.85,
    treatmentPreference = "best",
    damageAlertMode = "flash",
    damageAlertThreshold = 25,
}
local function text(key)
    return getText("UI_ATFCombatHealth_" .. key)
end
local Button = ISButton:derive("ATFCombatHealthButton")
function Button:setEnable(value)
    if self.enable == value then
        return
    end
    local base = self.miniBaseAlpha or {}
    -- Native setEnable caches enabled colors once; never let it cache faded alpha.
    for _, key in ipairs({ "backgroundColor", "borderColor" }) do
        if base[key] then
            self[key].a = base[key]
        end
    end
    ISButton.setEnable(self, value)
    local panel = self.parent
    while panel and not panel.prefs do
        panel = panel.parent
    end
    local alpha = panel and panel.miniAppliedAlpha or 1
    self.miniBaseAlpha = base
    -- Only these channels were reset by native setEnable; the others are still faded.
    for _, key in ipairs({ "backgroundColor", "borderColor", "textureColor" }) do
        base[key] = self[key].a
        self[key].a = base[key] * alpha
    end
end
function Button:drawText(label, x, y, r, g, b, alpha, font)
    -- Native disabled text keeps its gray RGB, but otherwise forces alpha to one.
    if not self.enable and label == self.title then
        alpha = self.textColor.a
    end
    return ISButton.drawText(self, label, x, y, r, g, b, alpha, font)
end
local function button(panel, title, callback)
    local widget = C.pin(Button:new(0, 0, 70, 26, title, panel, callback))
    widget:initialise()
    panel:addChild(widget)
    return widget
end

local Row = ISPanel:derive("ATFCombatHealthRow")
local rowColors = { { 0.94, 0.91, 0.84 }, { 1, 0.65, 0.55 } }
local healthWhite, healthYellow, healthRed =
    { 0.95, 0.94, 0.9 }, { 1, 0.85, 0.2 }, { 1, 0.25, 0.25 }
function Row:createChildren()
    self.treat = button(self, text("Treat"), function(row)
        local panel = row.parent
        if row.data and panel:isCurrent() and panel.prefs.enabled then
            local opened, menu = Model.openTreatment(
                panel.player,
                row.data.bodyPart,
                getMouseX(),
                getMouseY(),
                panel.prefs.treatmentPreference
            )
            if opened then
                panel:trackMenu(menu)
            end
        end
    end)
end
function Row:onMouseWheel(delta)
    return self.parent:onMouseWheel(delta)
end
function Row:prerender()
    ISPanel.prerender(self)
    if not self.data then
        return
    end
    local alpha = self.parent.miniAppliedAlpha or 1
    local right = self.treat:getIsVisible() and self.treat:getX() - 8 or self:getWidth() - 8
    self:clampStencilRectToParent(5, 2, math.max(1, right - 5), self:getHeight() - 4)
    local color = rowColors[self.data.severity >= 2 and 2 or 1]
    self:drawText(self.label, 5, 3, color[1], color[2], color[3], alpha, UIFont.Small)
    self:clearStencilRect()
end

function HUD:new(player)
    local o = C.Window.new(self, 80, 160, 320, 200, text("Title"))
    o.player = player
    o.playerNum = player:getPlayerNum()
    o.prefs = {}
    for key, value in pairs(H.defaults) do
        o.prefs[key] = value
    end
    o.rowOffset = 0
    o.rows = {}
    o.telemetry = Telemetry.new(player)
    o.damageAlerts = DamageAlerts.new()
    o.lastSample, o.lastAttach, o.lastBind = -math.huge, -math.huge, -math.huge
    o.layoutName = "ATFCombatHealth." .. o.playerNum
    return o
end
function HUD:createChildren()
    C.Window.createChildren(self)
    self.optionsButton = button(self, "", function(panel)
        panel:options()
    end)
    self.optionsButton:setTooltip(text("Options"))
    local cog = getTexture("media/ui/inventoryPanes/Button_Gear.png")
    if cog then
        self.optionsButton:setImage(cog)
    else
        self.optionsButton:setTitle("*")
    end
    -- BodyPartType has a fixed native set; controls never grow with injury updates.
    for i = 1, 20 do
        local row = C.pin(Row:new(0, 0, 200, 21))
        row:initialise()
        row:instantiate()
        self:addChild(row)
        row:setVisible(false)
        self.rows[i] = row
    end
    self:layout()
end
function HUD:filteredRows()
    if not self.snapshot then
        return {}
    end
    return self.prefs.showHealth and self.snapshot.rows or {}
end
function HUD:layoutHeader()
    C.Window.layoutHeader(self)
    if self.optionsButton then
        local h = self.headerHeight - 6
        self.optionsButton:setX(self:getWidth() - h * 3 - 12)
        self.optionsButton:setY(3)
        self.optionsButton:setWidth(h)
        self.optionsButton:setHeight(h)
        self.optionsButton:forceImageSize(math.min(20, h - 4), math.min(20, h - 4))
        self.headerTextRight = self.optionsButton:getX() - 4
    end
end
function HUD:layout()
    if not self.optionsButton then
        return
    end
    self.fontHeight = getTextManager():getFontHeight(UIFont.Small)
    self.headerHeight = math.max(28, self.fontHeight + 12)
    local core, tm = getCore(), getTextManager()
    self.title = text("Title")
    if self.collapsed and self.snapshot and self.prefs.showHealth then
        self.title = self.title
            .. " - "
            .. (
                self.snapshot.bleeding > 0
                    and self.snapshot.blood .. " (" .. self.snapshot.bleeding .. ")"
                or self.snapshot.status
            )
    end
    local desired = math.max(
        self.prefs.mode == "mini" and 360 or 300,
        tm:MeasureStringX(UIFont.Small, self.title) + self.headerHeight * 3 + 32
    )
    local width = math.min(desired, math.max(180, core:getScreenWidth() - 16))
    local line, rowHeight = self.fontHeight + 3, self.fontHeight + 6
    self.displayRows = self:filteredRows()
    local s = self.snapshot
    local strain = s and s.strain
    self.strainLine = strain
            and (strain.text .. (strain.count > 1 and " (" .. strain.count .. ")" or ""))
        or nil
    local summaryHeight = self.prefs.showHealth and (line * (self.strainLine and 4 or 3) + 8) or 0
    self.summaryHeight = summaryHeight
    self.healthPrefix = text("Health") .. ": "
    self.healthValue = s and tostring(s.health) or ""
    self.healthStatus = s and " - " .. s.status or ""
    self.healthValueX = 8 + tm:MeasureStringX(UIFont.Small, self.healthPrefix)
    self.healthStatusX = self.healthValueX + tm:MeasureStringX(UIFont.Small, self.healthValue)
    self.healthColor = s and s.health <= 25 and healthRed
        or s and s.health <= 50 and healthYellow
        or healthWhite
    self.statusColor = s and s.health <= 25 and healthRed or healthWhite
    if self.prefs.showHealth then
        local summaryWidth = self.healthStatusX
            + tm:MeasureStringX(UIFont.Small, self.healthStatus)
            + 8
        if self.strainLine then
            summaryWidth =
                math.max(summaryWidth, tm:MeasureStringX(UIFont.Small, self.strainLine) + 16)
        end
        width = math.min(math.max(width, summaryWidth), math.max(180, core:getScreenWidth() - 16))
    end
    self.temperatureLine = self.telemetry.temperature
            and text("Temperature") .. ": " .. self.telemetry.temperature.text
        or ""
    self.xpCount = self.prefs.showXP and math.min(3, #self.telemetry.xpRows) or 0
    local showEmptyXP = self.prefs.alwaysShowXP
    local function xpHeight()
        return self.prefs.showXP
                and (self.xpCount > 0 or showEmptyXP)
                and (line * (1 + math.max(1, self.xpCount)) + 8)
            or 0
    end
    local tempHeight = self.prefs.showTemperature and self.telemetry.temperature and line + 8 or 0
    local function available()
        return core:getScreenHeight()
            - 24
            - self.headerHeight
            - summaryHeight
            - xpHeight()
            - tempHeight
    end
    -- Keep injury actions usable at small resolutions and larger fonts.
    if #self.displayRows > 0 and available() < rowHeight + 2 and self.xpCount > 1 then
        self.xpCount = 1
    end
    if #self.displayRows > 0 and available() < rowHeight + 2 then
        self.xpCount = 0
        showEmptyXP = false
    end
    self.displayXP = {}
    for i = 1, self.xpCount do
        self.displayXP[i] = self.telemetry.xpRows[i].text
    end
    -- All native body parts fit at normal font/resolution. A wheel viewport
    -- preserves access on unusually short screens or with enlarged fonts.
    self.visibleRowCount =
        math.max(1, math.min(#self.rows, math.floor(available() / (rowHeight + 2))))
    self.rowOverflow = #self.displayRows > self.visibleRowCount
    if self.rowOverflow then
        self.visibleRowCount = math.max(1, math.floor((available() - line) / (rowHeight + 2)))
    end
    self.rowOffset =
        math.max(0, math.min(self.rowOffset, math.max(0, #self.displayRows - self.visibleRowCount)))
    self.recentXPLabel, self.emptyXPLabel = text("RecentXP"), text("NoRecentXP")
    local count = math.min(self.visibleRowCount, #self.displayRows)
    local y = self.headerHeight + summaryHeight
    for i, row in ipairs(self.rows) do
        row.data = i <= count and self.displayRows[self.rowOffset + i] or nil
        row.label = row.data and (row.data.name .. ": " .. row.data.summary) or ""
        row.treat:setTooltip(row.data and (row.data.name .. " <LINE> " .. row.data.summary) or nil)
        row:setVisible(not self.collapsed and i <= count)
        row:setX(8)
        row:setY(y + (i - 1) * (rowHeight + 2))
        row:setWidth(width - 16)
        row:setHeight(rowHeight)
        row:recalcSize()
        local treatWidth = math.max(40, tm:MeasureStringX(UIFont.Small, text("Treat")) + 10)
        row.treat:setX(width - 16 - treatWidth - 4)
        row.treat:setY(2)
        row.treat:setWidth(treatWidth)
        row.treat:setHeight(rowHeight - 4)
        row.treat:setVisible(
            self.prefs.showTreatment and row.data ~= nil and row.data.bodyPart ~= nil
        )
    end
    y = y + count * (rowHeight + 2)
    self.scrollHintY = self.rowOverflow and y or nil
    self.scrollHint = self.rowOverflow
            and (text("ScrollInjuries") .. " (" .. (self.rowOffset + 1) .. "-" .. (self.rowOffset + count) .. "/" .. #self.displayRows .. ")")
        or nil
    if self.rowOverflow then
        y = y + line
    end
    self.xpY = xpHeight() > 0 and y or nil
    y = y + xpHeight()
    self.temperatureY = tempHeight > 0 and y or nil
    y = y + tempHeight
    local height = y + 8
    if self.collapsed then
        height = self.headerHeight
    end
    C.size(self, width, height)
    local h = self.headerHeight - 6
    for _, control in ipairs({ self.closeButton, self.collapseButton }) do
        control:setWidth(h)
        control:setHeight(h)
    end
    self:layoutHeader()
    self:applyFade(getTimestampMs())
end
function HUD:isCurrent()
    return H.panels[self.playerNum] == self
        and self.player
        and getSpecificPlayer(self.playerNum) == self.player
        and self.player:isLocalPlayer()
        and not self.player:isDead()
end
function HUD:clearMenuFocus(dismiss)
    local menu, clear, original = self.focusMenu, self.focusMenuClear, self.focusMenuOriginalClear
    self.focusMenu, self.focusMenuClear, self.focusMenuOriginalClear = nil, nil, nil
    if menu and menu.clear == clear then
        menu.clear = original
        if dismiss then
            menu:closeAll()
        end
    end
end
function HUD:trackMenu(menu)
    self:clearMenuFocus(false)
    if not menu or not self:isCurrent() or not self.prefs.enabled then
        return
    end
    -- Native get() reuses the same root, options table, and pooled options.
    -- Its clear() call is the boundary between this menu and an unrelated one.
    -- PZ's Kahlua rawget also searches the metatable; pairs reads own fields.
    local original, nativeClear = nil, menu.clear
    for key, value in pairs(menu) do
        if key == "clear" then
            original = value
            break
        end
    end
    local owner = self
    local clear = function(context, ...)
        owner:clearMenuFocus(false)
        return nativeClear(context, ...)
    end
    self.focusMenu, self.focusMenuClear, self.focusMenuOriginalClear = menu, clear, original
    menu.clear = clear
    self:applyFade(getTimestampMs())
end
function HUD:hasMenuFocus()
    local menu = self.focusMenu
    if not menu then
        return false
    end
    if
        not self:isCurrent()
        or not self.prefs.enabled
        or menu.clear ~= self.focusMenuClear
        or not UIManager.getUI():contains(menu:getJavaObject())
    then
        self:clearMenuFocus(false)
        return false
    end
    if menu:getIsVisible() then
        return true
    end
    -- Single-menu navigation hides ancestors. Native root.instanceMap owns all
    -- descendants, including menus beyond the currently selected child.
    for _, child in ipairs(menu.instanceMap or {}) do
        if child:getIsVisible() and UIManager.getUI():contains(child:getJavaObject()) then
            local descendant = child
            -- Validate the native option links: rebuilt treatment menus leave
            -- their unused original submenus in the root's instanceMap.
            for _ = 1, 32 do
                local parent = descendant.parent
                if not parent or parent:getIndexForSubMenu(descendant) < 1 then
                    break
                end
                if parent == menu then
                    return true
                end
                descendant = parent
            end
        end
    end
    self:clearMenuFocus(false)
    return false
end
function HUD:setCollapsed(value)
    if not self:isCurrent() then
        return
    end
    C.endDrag(self)
    self.collapsed = value
    if not value and self.prefs.mode == "collapsed" then
        self.prefs.mode = "compact"
    end
    self:layout()
    self:saveMiniLayout()
end
function HUD:onMouseWheel(delta)
    if not self:isCurrent() or self.collapsed or not self.rowOverflow or delta == 0 then
        return false
    end
    self.rowOffset = math.max(
        0,
        math.min(#self.displayRows - self.visibleRowCount, self.rowOffset + (delta > 0 and -1 or 1))
    )
    self:layout()
    return true
end
function HUD:saveMiniLayout()
    if H.panels[self.playerNum] ~= self then
        return
    end
    H.capture(self)
    C.save()
end
function HUD:close()
    if not self:isCurrent() then
        return
    end
    self.prefs.enabled = false
    self:clearMenuFocus(true)
    DamageAlerts.clear(self.damageAlerts)
    self.attentionUntil, self.nextAttentionAt, self.lastAttentionPriority, self.healthWarningBand =
        nil, nil, nil, nil
    Telemetry.update(self.telemetry, getTimestampMs(), false, false)
    C.Window.close(self)
end
local function newVisibleInjury(current, previous)
    if
        current.bleeding > (previous and previous.bleeding or 0)
        or current.pain > (previous and previous.pain or 0)
    then
        return true
    end
    for _, row in ipairs(current.rows) do
        local old
        if previous then
            for _, candidate in ipairs(previous.rows) do
                if candidate.id == row.id then
                    old = candidate
                    break
                end
            end
        end
        for signal, rank in pairs(row.signals or {}) do
            local prior = old and old.signals and old.signals[signal] or 0
            if rank > prior then
                return true
            end
        end
    end
    return false
end
function HUD:refreshAttention(snapshot, previous, now)
    local band = self.healthWarningBand or 0
    -- Re-arm only after clear recovery, so 0.1 changes around a boundary do not pulse.
    if snapshot.health > 55 then
        band = 0
    elseif band == 2 and snapshot.health > 30 then
        band = 1
    end
    local current = snapshot.health <= 25 and 2 or snapshot.health <= 50 and 1 or 0
    local entered = current > band
    self.healthWarningBand = math.max(band, current)
    local critical = snapshot.critical and not (previous and previous.critical)
    if not entered and not critical and not newVisibleInjury(snapshot, previous) then
        return
    end
    local priority = (current == 2 or snapshot.critical) and 2 or 1
    if
        now < (self.nextAttentionAt or -math.huge)
        and priority <= (self.lastAttentionPriority or 0)
    then
        return
    end
    -- Never extend an active pulse. A critical escalation can bypass the ordinary cooldown.
    if (self.attentionUntil or 0) <= now then
        self.attentionUntil = now + 2000
    end
    self.nextAttentionAt, self.lastAttentionPriority = now + 5000, priority
end
function HUD:sample(now)
    if
        getSpecificPlayer(self.playerNum) ~= self.player
        or not self.player:isLocalPlayer()
        or self.player:isDead()
    then
        H.release(self, self.player and self.player:isDead())
        return
    end
    if not self.prefs.enabled or now - self.lastSample < 100 then
        return
    end
    self.lastSample = now
    if ISUIHandler and ISUIHandler.allUIVisible == false then
        return
    end
    local opener = ATFPlayerMiniHUDHealthOpener
    if opener and opener.observe(self) and not self.prefs.keepVisibleWithHealthClosed then
        self:close()
        return
    end
    local changed =
        Telemetry.update(self.telemetry, now, self.prefs.showXP, self.prefs.showTemperature)
    if self.prefs.showHealth and now - (self.lastHealth or -math.huge) >= 200 then
        self.lastHealth = now
        local snapshot = Model.snapshot(self.player)
        if snapshot then
            DamageAlerts.update(
                self.damageAlerts,
                snapshot.rawHealth or snapshot.health,
                now,
                self.prefs
            )
            self:refreshAttention(snapshot, self.snapshot, now)
            if
                self.prefs.autoShow
                and self.collapsed
                and newVisibleInjury(snapshot, self.snapshot)
            then
                self.collapsed = false
                if self.prefs.mode == "collapsed" then
                    self.prefs.mode = "compact"
                end
                changed = true
            end
            if not self.snapshot or snapshot.signature ~= self.snapshot.signature then
                self.snapshot = snapshot
                changed = true
            end
        else
            DamageAlerts.clear(self.damageAlerts)
        end
    end
    if changed then
        self:layout()
    end
    if not self:getIsVisible() then
        self:setVisible(true)
    end
    if now - self.lastAttach >= 1000 then
        self.lastAttach = now
        C.attach(self)
    end
end
function HUD:applyFade(now)
    local alert = DamageAlerts.presentation(self.damageAlerts, now, self.prefs)
    self.damageGlow = alert.glowAlpha
    local menuFocus = self:hasMenuFocus()
    local focused = self.miniDrag
        or self:isMouseOver()
        or menuFocus
        or (self.attentionUntil or 0) > now
        or alert.reveal
    local alpha = self.prefs.opacity * ((not self.prefs.focusFade or focused) and 1 or 0.5)
    C.fade(self, alpha)
    if self.optionsButton then
        self.optionsButton.textureColor.a = alpha
    end
end
function HUD:update()
    C.Window.update(self)
    local core = getCore()
    local w, h, font =
        core:getScreenWidth(), core:getScreenHeight(), getTextManager():getFontHeight(UIFont.Small)
    if self.screenWidth ~= w or self.screenHeight ~= h or self.fontHeight ~= font then
        self.screenWidth, self.screenHeight = w, h
        self:layout()
    end
    self:applyFade(getTimestampMs())
end
function HUD:prerender()
    C.Window.prerender(self)
    if (self.damageGlow or 0) > 0 then
        self:drawRect(
            0,
            0,
            self:getWidth(),
            self:getHeight(),
            self.damageGlow * 0.12,
            1,
            0.08,
            0.05
        )
        self:drawRectBorder(
            0,
            0,
            self:getWidth(),
            self:getHeight(),
            self.damageGlow * 0.95,
            1,
            0.08,
            0.05
        )
    end
    if self.collapsed then
        return
    end
    local alpha = self.miniAppliedAlpha or 1
    if self.prefs.showHealth and self.snapshot then
        local s = self.snapshot
        local y = self.headerHeight + 6
        self:clampStencilRectToParent(8, y, self:getWidth() - 16, self.summaryHeight - 6)
        self:drawText(
            self.healthPrefix,
            8,
            y,
            healthWhite[1],
            healthWhite[2],
            healthWhite[3],
            alpha,
            UIFont.Small
        )
        local color, status = self.healthColor, self.statusColor
        self:drawText(
            self.healthValue,
            self.healthValueX,
            y,
            color[1],
            color[2],
            color[3],
            alpha,
            UIFont.Small
        )
        self:drawText(
            self.healthStatus,
            self.healthStatusX,
            y,
            status[1],
            status[2],
            status[3],
            alpha,
            UIFont.Small
        )
        self:drawText(
            s.blood,
            8,
            y + self.fontHeight + 3,
            1,
            s.bleeding > 0 and 0.65 or 0.9,
            0.8,
            alpha,
            UIFont.Small
        )
        self:drawText(
            s.painText,
            8,
            y + (self.fontHeight + 3) * 2,
            0.92,
            0.9,
            0.84,
            alpha,
            UIFont.Small
        )
        if self.strainLine then
            self:drawText(
                self.strainLine,
                8,
                y + (self.fontHeight + 3) * 3,
                0.92,
                0.9,
                0.84,
                alpha,
                UIFont.Small
            )
        end
        self:clearStencilRect()
    end
    local line = self.fontHeight + 3
    if self.xpY then
        local y = self.xpY + 4
        self:drawRect(8, y, self:getWidth() - 16, 1, 0.25 * alpha, 0.52, 0.46, 0.3)
        self:clampStencilRectToParent(
            8,
            y + 3,
            self:getWidth() - 16,
            line * (1 + math.max(1, self.xpCount))
        )
        self:drawText(self.recentXPLabel, 8, y + 3, 0.95, 0.94, 0.9, alpha, UIFont.Small)
        if self.xpCount == 0 then
            self:drawText(self.emptyXPLabel, 8, y + line + 3, 0.75, 0.75, 0.75, alpha, UIFont.Small)
        else
            for i = 1, self.xpCount do
                self:drawText(
                    self.displayXP[i],
                    8,
                    y + line * i + 3,
                    0.9,
                    0.9,
                    0.9,
                    alpha,
                    UIFont.Small
                )
            end
        end
        self:clearStencilRect()
    end
    if self.temperatureY and self.telemetry.temperature then
        local y = self.temperatureY + 4
        self:drawRect(8, y, self:getWidth() - 16, 1, 0.25 * alpha, 0.52, 0.46, 0.3)
        self:clampStencilRectToParent(8, y + 3, self:getWidth() - 16, line)
        self:drawText(self.temperatureLine, 8, y + 3, 0.92, 0.9, 0.84, alpha, UIFont.Small)
        self:clearStencilRect()
    end
    if self.scrollHintY then
        self:drawText(self.scrollHint, 8, self.scrollHintY, 0.75, 0.75, 0.75, alpha, UIFont.Small)
    end
end
function HUD:onRightMouseUp()
    self:options()
    return true
end
function HUD:setPref(key, value)
    if not self:isCurrent() then
        return
    end
    if H.defaults[key] == nil then
        return
    end
    self.prefs[key] = value
    if key == "enabled" and not value then
        self:close()
        return
    end
    if key == "mode" then
        self.collapsed = value == "collapsed"
    end
    self.lastSample, self.lastAttach = -math.huge, -math.huge
    if key == "showHealth" then
        self.lastHealth = -math.huge
        if not value then
            self.snapshot = nil
            self.attentionUntil, self.nextAttentionAt, self.lastAttentionPriority, self.healthWarningBand =
                nil, nil, nil, nil
            Model.clear(self.playerNum)
            DamageAlerts.clear(self.damageAlerts)
        end
    end
    self:layout()
    self:sample(getTimestampMs())
    self:saveMiniLayout()
end
function HUD:options()
    if not self:isCurrent() then
        return
    end
    local menu = ISContextMenu.get(self.playerNum, getMouseX(), getMouseY())
    local function choice(label, key, values)
        local option = menu:addOption(label)
        local sub = ISContextMenu:getNew(menu)
        menu:addSubMenu(option, sub)
        for _, entry in ipairs(values) do
            local value, title = entry[1], entry[2]
            local item = sub:addOption(title, nil, function()
                self:setPref(key, value)
            end)
            sub:setOptionChecked(item, self.prefs[key] == value)
        end
    end
    choice(text("Display"), "mode", {
        { "compact", text("Compact") },
        { "mini", text("Mini") },
        { "collapsed", text("Collapsed") },
    })
    for _, entry in ipairs({
        { "enabled", "Enabled" },
        { "autoShow", "AutoShow" },
        { "showHealth", "ShowHealth" },
        { "showXP", "ShowXP" },
        { "showTemperature", "ShowTemperature" },
        { "keepRespawn", "KeepRespawn" },
        { "rememberPosition", "RememberPosition" },
        { "keepVisibleWithHealthClosed", "KeepVisibleWithHealthClosed" },
        { "alwaysShowXP", "AlwaysShowXP" },
        { "showTreatment", "ShowTreatment" },
        { "focusFade", "FocusFade" },
    }) do
        local key = entry[1]
        local item = menu:addOption(text(entry[2]), nil, function()
            self:setPref(key, not self.prefs[key])
        end)
        menu:setOptionChecked(item, self.prefs[key])
    end
    choice(text("Opacity"), "opacity", { { 0.6, "60%" }, { 0.85, "85%" }, { 1, "100%" } })
    choice(text("TreatmentPreference"), "treatmentPreference", {
        { "best", text("BestTreatment") },
        { "conserve", text("ConserveSupplies") },
        { "manual", text("ManualSelection") },
    })
    choice(text("DamageAlert"), "damageAlertMode", {
        { "flash", text("ThreeRedFlashes") },
        { "reveal", text("RevealHUD") },
        { "off", text("Off") },
    })
    choice(
        text("DamageThreshold"),
        "damageAlertThreshold",
        { { 10, "10" }, { 15, "15" }, { 25, "25" }, { 40, "40" } }
    )
    self:trackMenu(menu)
    return menu
end
function H.survivorId(player)
    local data = player and player.getModData and player:getModData()
    if not data or not getRandomUUID then
        return nil
    end
    local id = data.ATFPlayerMiniHUDSurvivor
    if type(id) ~= "string" or #id ~= 36 or not id:match("^[%x%-]+$") then
        id = getRandomUUID()
        data.ATFPlayerMiniHUDSurvivor = id
    end
    -- SP saves this private UI token with the survivor. On an MP reconnect the
    -- server may not retain a client-only token, so keepRespawn=false closes
    -- conservatively. Never transmit the player's entire modData for a UI key.
    return "uuid:" .. id
end
local function copyPrefs(prefs)
    local result = {}
    for key in pairs(H.defaults) do
        result[key] = prefs[key]
    end
    return result
end
function H.capture(panel)
    H.preferences[panel.playerNum] = {
        prefs = copyPrefs(panel.prefs),
        collapsed = panel.collapsed == true,
        x = panel:getX(),
        y = panel:getY(),
        survivor = panel.survivorId,
    }
end
local function saveLayout(panel, _, layout)
    if panel.prefs.rememberPosition then
        layout.x, layout.y = panel:getX(), panel:getY()
    else
        layout.x, layout.y = nil, nil
    end
    layout.collapsed = tostring(panel.collapsed == true)
    layout.survivor = panel.survivorId
    layout.hideHealthy, layout.healthyDelay = nil, nil
    for key, value in pairs(panel.prefs) do
        layout[key] = tostring(value)
    end
end
local function restoreLayout(panel, _, layout)
    panel.miniLayoutRestored = true
    for key, default in pairs(H.defaults) do
        local value = layout[key]
        if type(default) == "boolean" and (value == "true" or value == "false") then
            panel.prefs[key] = value == "true"
        end
    end
    if layout.mode == "compact" or layout.mode == "mini" or layout.mode == "collapsed" then
        panel.prefs.mode = layout.mode
    end
    if
        layout.treatmentPreference == "best"
        or layout.treatmentPreference == "conserve"
        or layout.treatmentPreference == "manual"
    then
        panel.prefs.treatmentPreference = layout.treatmentPreference
    end
    if
        layout.damageAlertMode == "flash"
        or layout.damageAlertMode == "reveal"
        or layout.damageAlertMode == "off"
    then
        panel.prefs.damageAlertMode = layout.damageAlertMode
    end
    local threshold = tonumber(layout.damageAlertThreshold)
    if threshold == 10 or threshold == 15 or threshold == 25 or threshold == 40 then
        panel.prefs.damageAlertThreshold = threshold
    end
    local opacity = tonumber(layout.opacity)
    if opacity then
        panel.prefs.opacity = math.max(0.6, math.min(1, opacity))
    end
    if
        not panel.prefs.keepRespawn
        and (not panel.survivorId or layout.survivor ~= panel.survivorId)
    then
        panel.prefs.enabled = false
    end
    panel.collapsed = layout.collapsed == "true" or panel.prefs.mode == "collapsed"
    if panel.prefs.rememberPosition then
        panel:setX(tonumber(layout.x) or 80)
        panel:setY(tonumber(layout.y) or 160)
    end
    panel:layout()
end
function H.release(panel, respawn)
    if not panel or H.panels[panel.playerNum] ~= panel then
        return
    end
    if respawn and not panel.prefs.keepRespawn then
        panel.prefs.enabled = false
    end
    panel:saveMiniLayout()
    panel:clearMenuFocus(true)
    panel.miniDrag = nil
    panel:setCapture(false)
    panel:setVisible(false)
    panel:removeFromUIManager()
    Telemetry.clear(panel.telemetry)
    DamageAlerts.clear(panel.damageAlerts)
    if ATFPlayerMiniHUDHealthOpener then
        ATFPlayerMiniHUDHealthOpener.clear(panel)
    end
    Model.clear(panel.playerNum)
    panel.snapshot, panel.displayRows, panel.displayXP, panel.player = nil, {}, {}, nil
    panel.attentionUntil, panel.nextAttentionAt, panel.lastAttentionPriority, panel.healthWarningBand =
        nil, nil, nil, nil
    panel.healthPrefix, panel.healthValue, panel.healthStatus, panel.strainLine, panel.temperatureLine =
        nil, nil, nil, nil, nil
    for _, row in ipairs(panel.rows) do
        row.data = nil
    end
    local registered = ISLayoutManager.windows[panel.layoutName]
    if registered and registered.target == panel then
        ISLayoutManager.windows[panel.layoutName] = nil
    end
    if H.panels[panel.playerNum] == panel then
        H.panels[panel.playerNum] = nil
    end
end
function H.ensure(player)
    if not player or not player:isLocalPlayer() or player:isDead() then
        return nil
    end
    local num = player:getPlayerNum()
    if getSpecificPlayer(num) ~= player then
        return nil
    end
    local existing = H.panels[num]
    if existing and existing.player == player then
        return existing
    end
    local id = H.survivorId(player)
    if existing then
        H.release(existing, not id or existing.survivorId ~= id)
    end
    local panel = HUD:new(player)
    panel.survivorId = id
    panel:initialise()
    panel:instantiate()
    panel:setVisible(false)
    H.panels[num] = panel
    C.register(panel.layoutName, panel, saveLayout, restoreLayout)
    local remembered = H.preferences[num]
    if remembered then
        panel.prefs = copyPrefs(remembered.prefs)
        if remembered.survivor ~= id and not panel.prefs.keepRespawn then
            panel.prefs.enabled = false
        end
        panel.collapsed = remembered.collapsed
        if panel.prefs.rememberPosition then
            panel:setX(remembered.x)
            panel:setY(remembered.y)
        end
        panel:layout()
    end
    panel:sample(getTimestampMs())
    return panel
end
function H.toggle(playerNum)
    local panel = H.ensure(getSpecificPlayer(playerNum))
    if not panel then
        return false
    end
    if panel.prefs.enabled then
        panel:close()
        return true
    end
    panel.prefs.enabled = true
    panel.lastSample, panel.lastHealth, panel.lastAttach = -math.huge, -math.huge, -math.huge
    panel:sample(getTimestampMs())
    panel:saveMiniLayout()
    return true
end
function H.cleanup()
    local panels = {}
    for _, panel in pairs(H.panels) do
        panels[#panels + 1] = panel
    end
    for _, panel in ipairs(panels) do
        H.release(panel, panel.player and panel.player:isDead())
    end
    H.preferences = {}
    Model.clear()
end
return H
