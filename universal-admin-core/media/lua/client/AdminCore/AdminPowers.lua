require("AdminCore/Registry")
require("AdminCore/OperationsClient")
require("AdminCore/PowerDefinitions")
require("ISUI/ISTextEntryBox")
require("ISUI/AdminPanel/ISAdminPowerUI")
local C, D = AdminCore, AdminPowerDefinitions
if C.groupedPowersInstalled then
    return
end
C.groupedPowersInstalled = true
local pending, token = nil, 0

function C.powerAllowed(id)
    local entry, player = D.byId[id], getPlayer()
    return entry ~= nil
        and player ~= nil
        and not player:isDead()
        and D.nativeAllowed(player, entry)
        and C.operationsAllowed(entry.permission)
        and C.operationToolAllowed("power." .. id)
        and ISAdminPowerUI.OptionById[id] ~= nil
end

function C.powerEnabled(id)
    local option = ISAdminPowerUI.OptionById[id]
    if not option or not getPlayer() then
        return false
    end
    local ok, value = pcall(option.getValue, { player = getPlayer() })
    return ok and value == true
end

function C.applyPowers(values)
    if pending and getTimestampMs() - pending.time < 8000 then
        return C.message("Waiting for the server to confirm your previous power change.")
    end
    local filtered, count = {}, 0
    for id, value in pairs(values) do
        if C.powerAllowed(id) and type(value) == "boolean" then
            filtered[id] = value
            count = count + 1
        end
    end
    if count == 0 then
        return C.message("No permitted powers are available for this selection.")
    end
    token = token % 2147483647 + 1
    pending = { token = token, time = getTimestampMs(), actor = getPlayer(), values = filtered }
    sendClientCommand(
        getPlayer(),
        "UniversalAdminPowers",
        "apply",
        { token = token, values = filtered }
    )
end

function C.togglePower(id)
    if not C.powerAllowed(id) then
        return C.message("This power is not allowed for your current role.")
    end
    C.applyPowers({ [id] = not C.powerEnabled(id) })
end

function C.powerRows(group, query)
    local rows = {}
    query = (query or ""):lower():match("^%s*(.-)%s*$")
    for _, row in ipairs(D.list) do
        local entry = D.byId[row[1]]
        local matches = query ~= ""
            and (entry.title .. " " .. entry.group .. " " .. entry.id):lower():find(query, 1, true)
        if C.powerAllowed(entry.id) and ((query == "" and entry.group == group) or matches) then
            rows[#rows + 1] = entry
        end
    end
    return rows
end

function C.powerPreset(index)
    local values = {}
    for _, id in ipairs(D.presets[index].ids) do
        if C.powerAllowed(id) then
            values[id] = true
        end
    end
    C.applyPowers(values)
end

-- Pagination deliberately avoids nested native scroll viewports. Footer and
-- section controls remain reachable at the smallest supported window size.
function C.powerGeometry(width, height, font, count, page)
    local row = math.max(30, font + 12)
    local columns = math.max(1, math.min(5, math.floor((width - 24) / math.max(140, font * 8))))
    local groupsHeight = math.ceil(#D.groups / columns) * (row + 6)
    local searchY = font + 26
    local groupsY = searchY + row + 8
    local presetY = groupsY + groupsHeight
    local contentY = presetY + (row + 6) * 2 + font + 8
    local footerY = height - (row + 8) * 2 - 8
    local compact = contentY + row + 6 > footerY
    if compact then
        presetY = groupsY + row + 6
        contentY = presetY + (row + 6) * 2 + font + 8
    end
    local size = math.max(1, math.floor((footerY - 6 - contentY) / (row + 6)))
    local pages = math.max(1, math.ceil(count / size))
    return {
        row = row,
        columns = columns,
        compact = compact,
        searchY = searchY,
        groupsY = groupsY,
        presetY = presetY,
        contentY = contentY,
        footerY = footerY,
        pageSize = size,
        pages = pages,
        page = math.max(1, math.min(page or 1, pages)),
    }
end

local Panel = ISPanel:derive("UACGroupedAdminPowers")
C.AdminPowersPanel = Panel
local function button(panel, text, callback)
    local b = ISButton:new(12, 12, 100, 30, text, panel, callback)
    b:initialise()
    panel:addChild(b)
    C.pin(b)
    return b
end
local function place(widget, x, y, width, height)
    widget:setX(x)
    widget:setY(y)
    widget:setWidth(width)
    widget:setHeight(height)
end

function Panel:initialise()
    ISPanel.initialise(self)
    self.search = ISTextEntryBox:new("", 12, 40, 500, 30)
    self.search:initialise()
    self:addChild(self.search)
    C.pin(self.search)
    self.search:setPlaceholderText("Search powers...")
    self.search.onTextChange = function()
        self.page = 1
        self:layoutPowers()
    end
    self.groupButtons = {}
    for _, group in ipairs(D.groups) do
        local selectedGroup = group
        self.groupButtons[#self.groupButtons + 1] = button(self, group, function()
            if self.geometry and self.geometry.compact then
                for i, name in ipairs(D.groups) do
                    if name == self.group then
                        self.group = D.groups[i % #D.groups + 1]
                        break
                    end
                end
            else
                self.group = selectedGroup
            end
            self.page = 1
            self.search:setText("")
            self:layoutPowers()
        end)
    end
    self.preset = button(self, "Preset: Normal Admin", function()
        self.presetIndex = self.presetIndex % #D.presets + 1
        self:layoutPowers()
    end)
    self.preset.tooltip =
        "Choose a preset. Presets enable only powers you already have; other powers remain unchanged."
    self.apply = button(self, "Apply preset", function()
        C.powerPreset(self.presetIndex)
    end)
    self.enable = button(self, "Enable section", function()
        self:setSection(true)
    end)
    self.reset = button(self, "Reset section", function()
        self:setSection(false)
    end)
    self.enable.tooltip =
        "Enable permitted powers in this section. Each power is checked again by the server."
    self.reset.tooltip = "Disable permitted powers in this section. Other sections are unchanged."
    self.previous = button(self, "Previous", function()
        self.page = self.page - 1
        self:layoutPowers()
    end)
    self.next = button(self, "Next", function()
        self.page = self.page + 1
        self:layoutPowers()
    end)
    self.closeButton = button(self, "Close", function()
        self:close()
    end)
    self.observer = button(self, "Observer tools...", function()
        if C.openObserverTools then
            C.openObserverTools()
        else
            C.message("Choose Observe in the player list to configure observer overlays.")
        end
    end)
    self.observer.tooltip =
        "Facing/aim lines, bounds and rendering controls belong to the active Observe session."
    self.rows = {}
end

function Panel:setSection(enabled)
    local values = {}
    for _, entry in ipairs(C.powerRows(self.group, "")) do
        values[entry.id] = enabled
    end
    C.applyPowers(values)
end

function Panel:layoutPowers()
    if not self.search then
        return
    end
    local font = getTextManager():getFontHeight(UIFont.Small)
    local entries = C.powerRows(self.group, self.search:getText())
    local g = C.powerGeometry(self.width, self.height, font, #entries, self.page)
    self.geometry, self.page = g, g.page
    local width = self.width - 24
    place(self.search, 12, g.searchY, width, g.row)
    local gw = (width - (g.columns - 1) * 6) / g.columns
    for i, b in ipairs(self.groupButtons) do
        b:setVisible(not g.compact or i == 1)
        b:setTitle(g.compact and ("Section: " .. self.group .. " >") or D.groups[i])
        if g.compact then
            place(b, 12, g.groupsY, width, g.row)
        else
            place(
                b,
                12 + ((i - 1) % g.columns) * (gw + 6),
                g.groupsY + math.floor((i - 1) / g.columns) * (g.row + 6),
                gw,
                g.row
            )
        end
        b.backgroundColor = self.group == D.groups[i] and { r = 0.18, g = 0.32, b = 0.39, a = 1 }
            or { r = 0.05, g = 0.05, b = 0.05, a = 1 }
    end
    place(self.preset, 12, g.presetY, width * 0.6 - 3, g.row)
    self.preset:setTitle("Preset: " .. D.presets[self.presetIndex].title)
    place(self.apply, 15 + width * 0.6, g.presetY, width * 0.4 - 3, g.row)
    place(self.enable, 12, g.presetY + g.row + 6, width / 2 - 3, g.row)
    place(self.reset, 15 + width / 2, g.presetY + g.row + 6, width / 2 - 3, g.row)
    for _, b in ipairs(self.rows) do
        b:setVisible(false)
    end
    local first = (self.page - 1) * g.pageSize + 1
    for index = 1, g.pageSize do
        local entry = entries[first + index - 1]
        if entry then
            local b = self.rows[index]
            if not b then
                b = button(self, "", function(_, clicked)
                    C.togglePower(clicked.powerId)
                end)
                self.rows[index] = b
            end
            b.powerId = entry.id
            local enabled = C.powerEnabled(entry.id)
            b:setTitle((enabled and "[ON] " or "[OFF] ") .. entry.title)
            -- Native setEnable restores its cached colors. Apply the live power
            -- state afterwards so a later toggle also updates the selected tint.
            b:setEnable(not pending)
            b.backgroundColor = enabled and { r = 0.16, g = 0.34, b = 0.26, a = 1 }
                or { r = 0.05, g = 0.05, b = 0.05, a = 1 }
            b.tooltip = (ISAdminPowerUI.OptionById[entry.id].tooltip or entry.title)
                .. "\nCurrent state: "
                .. (enabled and "enabled" or "disabled")
                .. "\n"
                .. entry.group
                .. " / "
                .. entry.permission
            b:setVisible(true)
            place(b, 12, g.contentY + (index - 1) * (g.row + 6), width, g.row)
        end
    end
    place(self.previous, 12, g.footerY, width / 3 - 4, g.row)
    place(self.next, 14 + width / 3, g.footerY, width / 3 - 4, g.row)
    place(self.closeButton, 16 + width * 2 / 3, g.footerY, width / 3 - 4, g.row)
    place(self.observer, 12, g.footerY + g.row + 6, width, g.row)
    self.previous:setEnable(self.page > 1)
    self.next:setEnable(self.page < g.pages)
    self.observer:setEnable(C.operationsAllowed("ADMIN_SPECTATOR"))
    self.apply:setEnable(not pending)
    self.enable:setEnable(not pending)
    self.reset:setEnable(not pending)
    self.count = #entries
    self.lastLayout = getTimestampMs()
    self.version = C.registryVersion
    if self.resizeWidget then
        self.resizeWidget:bringToTop()
    end
end

function Panel:prerender()
    local player = getPlayer()
    if
        not player
        or player:isDead()
        or not player:getRole()
        or not player:getRole():hasAdminPower()
    then
        self:close()
        return
    end
    ISPanel.prerender(self)
    if pending and (pending.actor ~= getPlayer() or getTimestampMs() - pending.time >= 8000) then
        pending = nil
    end
    if getTimestampMs() - (self.lastLayout or 0) >= 1000 or self.version ~= C.registryVersion then
        self:layoutPowers()
    end
    self:drawText("Admin Powers", 12, 10, 1, 1, 1, 1, UIFont.Medium)
    local g = self.geometry
    if g then
        local text = pending and "Waiting for server..."
            or self.group .. " | " .. self.count .. " powers | " .. g.page .. " / " .. g.pages
        self:drawText(
            text,
            12,
            g.contentY - getTextManager():getFontHeight(UIFont.Small) - 6,
            0.8,
            0.85,
            0.9,
            1,
            UIFont.Small
        )
    end
end

function Panel:close()
    C.operationsKeepAlive("powers", false)
    if self.search and self.search.unfocus then
        self.search:unfocus()
    end
    self:setVisible(false)
    self:removeFromUIManager()
    if C.powersPanel == self then
        C.powersPanel = nil
    end
end

function C.openAdminPowers()
    local player = getPlayer()
    if not player or not player:getRole() or not player:getRole():hasAdminPower() then
        return C.message("Admin Powers are not available for your current role.")
    end
    C.operationsKeepAlive("powers", true)
    if C.powersPanel then
        C.powersPanel:setVisible(true)
        C.powersPanel:bringToTop()
        return C.powersPanel
    end
    local font = getTextManager():getFontHeight(UIFont.Small)
    local width = math.min(getCore():getScreenWidth() - 16, math.max(620, font * 32))
    local height = math.min(getCore():getScreenHeight() - 16, math.max(560, font * 23))
    local panel = Panel:new(24, 50, width, height)
    panel.group, panel.page, panel.presetIndex = "Movement", 1, 1
    panel:initialise()
    panel:addToUIManager()
    C.resizable(
        panel,
        "AdminPowers",
        math.min(width, 620),
        math.min(height, 500),
        Panel.layoutPowers
    )
    C.powersPanel = panel
    panel:layoutPowers()
    panel.search:focus()
    return panel
end

Events.OnServerCommand.Add(function(module, command, args)
    if
        module ~= "UniversalAdminPowers"
        or command ~= "state"
        or type(args) ~= "table"
        or type(args.values) ~= "table"
    then
        return
    end
    local revoke = args.token == 0
    if
        not revoke and (not pending or args.token ~= pending.token or pending.actor ~= getPlayer())
    then
        return
    end
    local requested = pending and pending.values or {}
    if not revoke then
        pending = nil
    end
    local player = getPlayer()
    if not player then
        return
    end
    for id, value in pairs(args.values) do
        local option = ISAdminPowerUI.OptionById[id]
        if
            option
            and type(value) == "boolean"
            and ((revoke and not value) or requested[id] ~= nil)
            and (not value or C.powerAllowed(id))
        then
            -- Vanilla owns the menu globals (ISBuildMenu.cheat, etc.). Reuse its
            -- explicit callbacks only after the server acknowledged this player.
            pcall(option.setValue, { player = player }, value)
        end
    end
    if not revoke and not args.error then
        sendPlayerExtraInfo(player)
    end
    if args.error then
        C.message(tostring(args.error))
    end
    if C.powersPanel then
        C.powersPanel:layoutPowers()
    end
end)

local function cleanup()
    pending = nil
    if C.powersPanel then
        C.powersPanel:close()
    end
end
Events.OnDisconnect.Add(cleanup)
Events.OnMainMenuEnter.Add(cleanup)

for _, row in ipairs(D.list) do
    local id, entry = row[1], D.byId[row[1]]
    C.registerAction({
        id = "power." .. id,
        title = entry.title,
        category = "Dashboard",
        group = { "Admin Powers", entry.group },
        visibleInNavigation = false,
        keywords = "power toggle " .. entry.group,
        tooltip = "Toggle " .. entry.title .. ". Confirmed by the server before applying.",
        allowed = function()
            return C.powerAllowed(id)
        end,
        isSelected = function()
            return C.powerEnabled(id)
        end,
        run = function()
            C.togglePower(id)
        end,
    })
end
