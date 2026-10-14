-- Runs against the installed game's actual Admin Panel, with UI/engine boundaries stubbed.
local game = assert(arg[1], "Pass the installed game directory")
local client = "universal-admin-core/media/lua/client/AdminCore/"
require = function() end
local count = 0
local function check(value, message)
    assert(value, message)
    count = count + 1
end
local caps = {}
Capability = setmetatable({}, {
    __index = function(_, key)
        return key
    end,
})
local role = {
    hasCapability = function(_, cap)
        return caps[cap] ~= false
    end,
    hasAdminPower = function()
        return true
    end,
}
local player = {
    getRole = function()
        return role
    end,
    getUsername = function()
        return "admin"
    end,
    getCurrentSquare = function()
        return {}
    end,
    getX = function()
        return 1
    end,
    getY = function()
        return 2
    end,
    getZ = function()
        return 0
    end,
}
getPlayer = function()
    return player
end
local sw, sh, font, mx, my = 1280, 720, 16, 0, 0
getMouseX = function()
    return mx
end
getMouseY = function()
    return my
end
getCore = function()
    return {
        getScreenWidth = function()
            return sw
        end,
        getScreenHeight = function()
            return sh
        end,
    }
end
getTextManager = function()
    return {
        getFontHeight = function()
            return font
        end,
        MeasureStringX = function(_, f, t)
            return #t * font / 2
        end,
    }
end
UIFont = { Small = 1, Medium = 2 }
getText = function(text)
    return text
end
getTextOrNull = getText
string.sort = function(a, b)
    return a < b
end
local empty = {
    size = function()
        return 0
    end,
}
Faction = {
    getFactions = function()
        return empty
    end,
}
SafeHouse = {
    getSafehouseList = function()
        return empty
    end,
}
Events = setmetatable({}, {
    __index = function(t, key)
        local e = { Add = function() end }
        rawset(t, key, e)
        return e
    end,
})
local W = {}
W.__index = W
function W:derive(name)
    local cls = { Type = name }
    cls.__index = cls
    setmetatable(cls, self)
    return cls
end
function W:new(x, y, w, h)
    return setmetatable(
        { x = x, y = y, width = w, height = h, children = {}, visible = true, enable = true },
        self
    )
end
for _, name in ipairs({ "X", "Y", "Width", "Height" }) do
    local field = name:lower()
    W["get" .. name] = function(self)
        return self[field]
    end
    W["set" .. name] = function(self, value)
        if name == "Width" or name == "Height" then
            self["pending" .. name] = (self["pending" .. name] or 0) + value - self[field]
        end
        self[field] = value
    end
end
for _, axis in ipairs({ "Left", "Right", "Top", "Bottom" }) do
    W["setAnchor" .. axis] = function(self, value)
        self["anchor" .. axis] = value
    end
end
function W:setCapture(value)
    self.capture = value
end
function W:getMouseX()
    return mx - self.x - self.parent.x
end
function W:getMouseY()
    return my - self.y - self.parent.y
end
function W:getBottom()
    return self.y + self.height
end
function W:addChild(child)
    self.children[#self.children + 1] = child
    child.parent = self
end
function W:getChildren()
    return self.children
end
function W:initialise()
    self.children = self.children or {}
end
function W:instantiate() end
function W:setVisible(value)
    self.visible = value
end
function W:getIsVisible()
    return self.visible ~= false
end
function W:setEnable(value)
    self.enable = value
end
function W:setTitle(value)
    self.title = value
end
function W:drawText() end
function W:render() end
local drawnIcon
function W:drawTexture(icon)
    drawnIcon = icon
end
getTexture = function(path)
    return {
        path = path,
        getHeight = function()
            return 8
        end,
    }
end
ISPanel = W:derive("ISPanel")
ISButton = W:derive("ISButton")
function ISButton:new(x, y, w, h, title, target, onclick)
    local b = W.new(self, x, y, w, h)
    b.title = title
    b.target = target
    b.onclick = onclick
    return b
end
dofile(game .. "/media/lua/client/ISUI/ISResizeWidget.lua")
ISLayoutManager = { RegisterWindow = function() end }
ISTextEntryBox = W:derive("ISTextEntryBox")
function ISTextEntryBox:new(text, x, y, w, h)
    local e = W.new(self, x, y, w, h)
    e.text = text
    return e
end
function ISTextEntryBox:getInternalText()
    return self.text
end
function ISTextEntryBox:setText(text)
    self.text = text
end
dofile(game .. "/media/lua/client/ISUI/AdminPanel/ISAdminPanelUI.lua")
dofile(client .. "WindowSizing.lua")
dofile(client .. "Registry.lua")
dofile(client .. "ActionGroups.lua")
dofile(client .. "Tools.lua")
dofile(client .. "ControlCenter.lua")
local C = AdminCore
local commands = {}
SendCommandToServer = function(command)
    commands[#commands + 1] = command
end
local p = ISAdminPanelUI:new(10, 10, 400, 400)
p:create()
check(#p.uacNav == 4, "The default navigation has four sections")
for i, section in ipairs({ "Dashboard", "World", "Zones", "Server" }) do
    check(p.uacNav[i].title == section, "Default section order matches the requested layout")
end
check(#commands == 0, "Opening control center must not perform a server action")
local native = 0
for _, e in ipairs(p.uacEntries) do
    if not e.action then
        native = native + 1
    end
end
check(native == 17, "All 17 native admin actions survive extraction")
local dashboard = {
    "native.ADMINPOWER",
    "native.CHECKSTATS",
    "native.MINISCOREBOARD",
    "native.ITEMLIST",
    "native.SAFEZONE",
    "core.vehicle",
    "native.SANDBOX",
    "native.SEEOPTIONS",
}
check(#p.uacResults == #dashboard, "Dashboard contains exactly the eight requested tools")
for i, id in ipairs(dashboard) do
    check(p.uacResults[i].id == id, "Dashboard tools keep the requested order")
end
check(
    p.itemListBtn.visible and p.safezoneBtn.visible,
    "Items and Add Safehouse are direct dashboard tools"
)
check(
    not p.seeUsersBtn.visible and not p.showStatisticsBtn.visible,
    "Users and statistics leave Dashboard"
)
check(not p.seeSafehousesBtn.visible, "Safehouse List is not duplicated on Dashboard")
check(not p.uacCustom["core.announcement"].visible, "Broadcast is not duplicated on Dashboard")
local function section(name)
    p.uacSection, p.uacPage, p.uacSelected = name, 1, 1
    p.uacSearch:setText("")
    p:uacRefresh()
end
section("Server")
check(
    p.seeUsersBtn.visible and p.seeRolesBtn.visible and p.showStatisticsBtn.visible,
    "Users, roles and statistics are direct Server tools"
)
check(
    p.uacCustom["core.mods"].visible and p.uacCustom["core.announcement"].visible,
    "Client mods and broadcast are direct Server tools"
)
section("Zones")
check(
    p.seeSafehousesBtn.visible and p.seeFactionBtn.visible,
    "Safehouse and Faction Lists remain in Zones"
)
section("World")
check(p.uacCustom["core.horde"].visible, "Horde manager is a direct World tool")
for _, name in ipairs({ "Dashboard", "World", "Zones", "Server" }) do
    section(name)
    check(
        not p.pvpLogTool.visible and not p.seeTicketsBtn.visible,
        "PVP Log and Tickets are absent from visible navigation"
    )
end
p.uacSearch:setText("pvplog")
p:uacRefresh()
check(p.pvpLogTool.visible, "PVP Log survives navigation cleanup through global search")
local ticketsCalls = 0
ISAdminTicketsUI = {
    new = function()
        ticketsCalls = ticketsCalls + 1
        return { initialise = function() end, addToUIManager = function() end }
    end,
}
p.uacSearch:setText("tickets")
p:uacRefresh()
check(not p.seeTicketsBtn.visible and #p.uacResults == 0, "Tickets is absent from global search")
local ticketEntry
for _, entry in ipairs(p.uacEntries) do
    if entry.id == "native.SEETICKETS" then
        ticketEntry = entry
    end
end
check(
    ticketEntry
        and ticketEntry.hidden
        and not ticketEntry.searchable
        and not ticketEntry.visibleInNavigation,
    "Tickets is retained only as a hidden native control for permission updates"
)
caps.AnswerTickets = false
p.uacSearch.onCommandEntered()
check(
    ticketsCalls == 0 and not p.seeTicketsBtn.enable,
    "Removing Tickets preserves native permission refresh without opening it"
)
caps.AnswerTickets = true
p.uacSearch.onCommandEntered()
check(
    ticketsCalls == 0 and p.seeTicketsBtn.enable and not p.seeTicketsBtn.visible,
    "Authorized admins cannot recover Tickets through search or Enter"
)
for _, query in ipairs({ "reports", "seetickets" }) do
    p.uacSearch:setText(query)
    p:uacRefresh()
    check(not p.seeTicketsBtn.visible, "Tickets keyword aliases remain hidden")
    for _, result in ipairs(p.uacResults) do
        check(result.id ~= "native.SEETICKETS", "Tickets never appears among global-search results")
    end
end
local climateCalls = 0
ISAdminWeather = {
    OnOpenPanel = function()
        climateCalls = climateCalls + 1
        return { onMadeActive = function() end }
    end,
}
p.uacSearch:setText("weather")
p:uacRefresh()
check(p.climateOptionsBtn.visible, "Search finds native actions by topic across categories")
-- Extensions can register while search captions include a native group's path.
-- Recollecting must retain the base title rather than treating that caption as
-- another permanent group prefix.
local climateGroups = C.nativeGroups.CLIMATE
C.nativeGroups.CLIMATE = { "Weather fixture" }
p.uacDirty = true
p:uacRefresh()
local climateCaption = "World / Weather fixture / " .. getText("IGUI_Adm_Weather_ClimateControl")
check(p.climateOptionsBtn.title == climateCaption, "Search captions show a native group path once")
C.registerAction({
    id = "refresh.unrelated",
    title = "Registry refresh fixture",
    category = "Server",
    capability = "Compatibility",
    hidden = true,
    run = function() end,
})
p:uacRefresh()
check(
    p.climateOptionsBtn.title == climateCaption,
    "Registering an extension during search does not duplicate native title prefixes"
)
for _, entry in ipairs(p.uacEntries) do
    if entry.id == "native.CLIMATE" then
        check(
            entry.title == getText("IGUI_Adm_Weather_ClimateControl")
                and entry.path == "Weather fixture",
            "Registry refresh preserves the native base title and group path"
        )
    end
end
C.nativeGroups.CLIMATE = climateGroups
p.uacDirty = true
p:uacRefresh()
p.climateOptionsBtn.onclick(p.climateOptionsBtn.target, p.climateOptionsBtn)
check(climateCalls == 1, "Native action retains original callback")
p.uacSearch.onCommandEntered()
check(climateCalls == 2, "Enter invokes the selected native action")
caps.ClimateManager = false
p:updateButtons()
check(not p.climateOptionsBtn.enable, "Native capability changes still disable action")
p.uacSearch.onCommandEntered()
check(climateCalls == 2, "Enter cannot bypass revoked native permission")
check(
    not C.matchesAction("Save", "Server", "", "Server", "[", false),
    "Search treats Lua patterns literally"
)
check(
    not pcall(
        C.registerAction,
        { id = "unsafe", title = "Unsafe", category = "Server", run = function() end }
    ),
    "Extension requires explicit permission gate"
)
local ran = 0
local action = {
    id = "test.permission",
    title = "Test gated action",
    category = "Security",
    capability = "Test",
    run = function()
        ran = ran + 1
    end,
}
C.registerAction(action)
C.message = function() end
C.runAction(action)
caps.Test = false
C.runAction(action)
check(ran == 1, "Revoked permission is checked again when action executes")
local options = { visibleInNavigation = true, searchable = false, hidden = true, sortOrder = 7 }
local suppliedGroups = { "Original group" }
local presentation = C.actionPresentation("native.PVPLOGTOOL", "Server", suppliedGroups, options)
check(
    presentation.visibleInNavigation
        and not presentation.searchable
        and presentation.hidden
        and presentation.sortOrder == 7,
    "Explicit presentation metadata overrides default tool layout"
)
check(
    presentation.groups ~= suppliedGroups and presentation.groups[1] == "Original group",
    "Presentation copies group paths without mutating the registration"
)
local vehicles = C.actionPresentation("legacy.vehicle", "Vehicles")
local mods = C.actionPresentation("legacy.mod", "Mods")
check(
    vehicles.category == "Server"
        and vehicles.groups[1] == "Vehicles"
        and mods.category == "Server"
        and mods.groups[1] == "Mod tools",
    "Ungrouped legacy extensions keep useful navigation groups"
)
local legacyCategories = {
    Vehicles = "Server",
    Events = "World",
    Mods = "Server",
    Settings = "Server",
    Security = "Server",
    Logs = "Server",
}
for category, mapped in pairs(legacyCategories) do
    local groups = { "Compatibility", "Legacy tools" }
    local legacy = {
        id = "compatibility." .. category,
        title = "Compatibility " .. category,
        category = category,
        group = groups,
        keywords = "legacy registration fixture",
        capability = "Compatibility",
        run = function() end,
    }
    C.registerAction(legacy)
    check(
        legacy.category == category and legacy.group == groups,
        "Legacy registration retains the extension's category and group table"
    )
    local metadata = C.actionPresentation(legacy.id, legacy.category, legacy.group, legacy)
    check(metadata.category == mapped, "Legacy categories map into the four-section layout")
    check(
        table.concat(metadata.groups, "/") == "Compatibility/Legacy tools",
        "Explicit legacy group paths survive category mapping"
    )
end
p.uacSearch:setText("legacy registration fixture")
p:uacRefresh()
check(#p.uacResults == 6, "Global search retains tools registered under all removed categories")
for _, entry in ipairs(p.uacResults) do
    check(
        entry.category == legacyCategories[entry.action.category]
            and entry.path == "Compatibility / Legacy tools",
        "Legacy search results use the mapped section and preserved group path"
    )
end
local metadataRuns = 0
for _, fixture in ipairs({
    { id = "search", visibleInNavigation = false, searchable = true },
    { id = "hidden", hidden = true, searchable = true },
    { id = "navigation", visibleInNavigation = true, searchable = false },
}) do
    fixture.id = "metadata." .. fixture.id
    fixture.title = "Metadata fixture " .. fixture.id
    fixture.category = "Server"
    fixture.capability = "Metadata"
    fixture.run = function()
        metadataRuns = metadataRuns + 1
    end
    C.registerAction(fixture)
end
section("Server")
check(
    not p.uacCustom["metadata.search"].visible and not p.uacCustom["metadata.hidden"].visible,
    "Search-only and entirely hidden extension tools do not appear in navigation"
)
-- Server may paginate once third-party fixtures are registered. Membership in
-- the result list, rather than only the first page, represents navigation access.
local navigationOnly = false
for _, entry in ipairs(p.uacResults) do
    navigationOnly = navigationOnly or entry.id == "metadata.navigation"
end
check(navigationOnly, "A navigation-only extension remains in its section")
p.uacSearch:setText("metadata fixture")
p:uacRefresh()
check(
    #p.uacResults == 1 and p.uacResults[1].id == "metadata.search",
    "Global search includes search-only tools and excludes hidden/non-searchable tools"
)
p:uacActivate()
check(metadataRuns == 1, "Search-only extensions keep their registered implementation")
caps.Metadata = false
p:uacActivate()
check(metadataRuns == 1, "Search-only extension execution rechecks permission")
caps.Metadata = true
local disabledRuns = 0
C.registerAction({
    id = "metadata.disabled",
    title = "Suspended tool",
    category = "Server",
    capability = "Metadata",
    disabled = true,
    run = function()
        disabledRuns = disabledRuns + 1
    end,
})
p.uacSearch:setText("suspended tool")
p:uacRefresh()
check(
    #p.uacResults == 1 and not p.uacResults[1].button.enable,
    "Disabled tools stay discoverable with a disabled control"
)
p:uacActivate()
C.runAction(C.actions["metadata.disabled"])
check(disabledRuns == 0, "Disabled tools cannot execute through keyboard or registered callbacks")
-- The real panel displays collapsed groups, searches their leaves and keeps native permissions.
local noiseRuns = 0
for _, radius in ipairs({ 10, 20, 50, 100, 200, 500 }) do
    C.registerAction({
        id = "noise." .. radius,
        title = "Radius: " .. radius,
        category = "Events",
        group = { "Make noise" },
        capability = "Noise",
        hideUnavailable = true,
        run = function()
            noiseRuns = noiseRuns + 1
        end,
    })
end
p.uacSection, p.uacPage, p.uacSelected = "World", 1, 1
p.uacSearch:setText("")
p:uacRefresh()
local noiseGroup = p.uacGroupEntries["World\31Make noise"]
check(
    noiseGroup.button.visible and not p.uacCustom["noise.10"].visible,
    "Six noise choices start collapsed behind one group"
)
noiseGroup.button:render()
check(drawnIcon.path:find("ArrowDown", 1, true), "Closed group displays downward caret")
noiseGroup.button.onclick(p, noiseGroup.button)
check(
    p.uacCustom["noise.10"].visible and noiseRuns == 0,
    "Opening a group reveals choices without executing one"
)
noiseGroup.button:render()
check(drawnIcon.path:find("ArrowUp", 1, true), "Open group displays upward caret")
local function columnLeft(button)
    local columns = p.uacGeometry.columns
    local left = p.uacGeometry.left
    local columnWidth = math.floor((p.width - left - 24 - (columns - 1) * 10) / columns)
    return left + math.floor((button.x - left) / (columnWidth + 10)) * (columnWidth + 10)
end
check(
    p.uacCustom["noise.10"].x - columnLeft(p.uacCustom["noise.10"])
        > noiseGroup.button.x - columnLeft(noiseGroup.button),
    "Choices are visibly indented within their column"
)
noiseGroup.button.onclick(p, noiseGroup.button)
p.uacSearch:setText("make noise")
p:uacRefresh()
check(
    #p.uacResults == 6 and not noiseGroup.button.visible,
    "Search finds leaves inside closed groups without duplicate headers"
)
p:uacActivate()
check(noiseRuns == 1, "Keyboard activates a matched nested choice")
caps.Noise = false
p.uacSearch:setText("")
p:uacRefresh()
check(not noiseGroup.button.visible, "An unavailable group is hidden instead of red")

local debugAvailable = false
C.registerAction({
    id = "nested.debug",
    title = "Animation viewer",
    category = "Settings",
    group = { "Debug", "UIs" },
    allowed = function()
        return debugAvailable
    end,
    hideUnavailable = true,
    run = function()
        error("Not clicked")
    end,
})
p.uacSection = "Server"
p:uacRefresh()
check(
    not p.uacGroupEntries["Server\31Debug"].button.visible,
    "Unavailable developer panels do not leave empty Debug groups"
)
debugAvailable = true
p:uacRefresh()
local debugGroup = p.uacGroupEntries["Server\31Debug"]
debugGroup.button.onclick(p, debugGroup.button)
local uiGroup = p.uacGroupEntries["Server\31Debug\31UIs"]
check(
    uiGroup.button.visible and not p.uacCustom["nested.debug"].visible,
    "Nested categories expand one level at a time"
)
uiGroup.button.onclick(p, uiGroup.button)
check(p.uacCustom["nested.debug"].visible, "Nested category reveals its tools")
debugGroup.button.onclick(p, debugGroup.button)
check(not p.uacCustom["nested.debug"].visible, "Closing parent hides all nested tools")
-- If a hidden-on-denial result disappears, Enter must not run the following result.
local replacementRuns = 0
for _, id in ipairs({ "first", "second" }) do
    local key = id
    C.registerAction({
        id = "revoke." .. id,
        title = "Revoke " .. id,
        category = "Security",
        allowed = function()
            return key == "second" or debugAvailable
        end,
        hideUnavailable = true,
        run = function()
            replacementRuns = replacementRuns + 1
        end,
    })
end
p.uacSearch:setText("revoke")
p.uacSelected = 1
p:uacRefresh()
debugAvailable = false
p:uacActivate()
check(replacementRuns == 0, "Revocation cannot make Enter run a different result")
Keyboard = { KEY_A = 30, KEY_ESCAPE = 1 }
local opened, typing, ctrl = 0, false, true
local core = getCore
getCore = function()
    local c = core()
    c.isDoingTextEntry = function()
        return typing
    end
    return c
end
isCtrlKeyDown = function()
    return ctrl
end
local opener = C.openControlCenter
C.openControlCenter = function()
    opened = opened + 1
end
C.onControlCenterKey(Keyboard.KEY_A)
typing = true
C.onControlCenterKey(Keyboard.KEY_A)
typing, ctrl = false, false
C.onControlCenterKey(Keyboard.KEY_A)
check(opened == 1, "Ctrl+A opens once; text selection and ordinary A are preserved")
C.openControlCenter = opener
local confirm
C.confirm = function(_, fn)
    confirm = fn
end
C.announce('hello"\n/quit')
check(not confirm and #commands == 0, "Announcement rejects parser injection")
C.announce("Restart in 10 minutes")
check(confirm ~= nil and #commands == 0, "Announcement waits for confirmation")
caps.DisplayServerMessage = false
confirm()
check(#commands == 0, "Permission revoked during confirmation prevents broadcast")
caps.DisplayServerMessage = true
C.announce("Restart in 10 minutes")
confirm()
check(
    commands[1] == '/servermsg "Restart in 10 minutes"',
    "Confirmed message uses native server command"
)
local added = ISButton:new(0, 0, 100, 30, "Third-party tool", nil, function() end)
added.internal = "UNKNOWN_EXTENSION"
added.enable = false
added.tooltip = "Original tooltip"
p:addChild(added)
section("Server")
local thirdPartyEntry
for _, entry in ipairs(p.uacResults) do
    if entry.button == added then
        thirdPartyEntry = entry
    end
end
check(
    thirdPartyEntry and thirdPartyEntry.category == "Server",
    "Late third-party native controls remain reachable in Server navigation"
)
p.uacSearch:setText("third-party tool")
p:uacRefresh()
check(
    added.visible and not added.enable and added.tooltip == "Original tooltip",
    "Late third-party controls retain state and appear in Server"
)
for i = 1, 90 do
    C.registerAction({
        id = "test." .. i,
        title = "Extra " .. i,
        category = "Mods",
        group = { "Pagination fixtures" },
        capability = "Test",
        run = function() end,
    })
end
p.uacDirty = true
for _, screen in ipairs({ { 1280, 720, 16 }, { 1280, 720, 28 }, { 800, 600, 28 } }) do
    sw, sh, font = screen[1], screen[2], screen[3]
    C.fit(p, 960, 600)
    p.uacSection = "Server"
    p.uacExpanded["Server\31Pagination fixtures"] = true
    p.uacPage = 1
    p.uacSearch:setText("")
    p:uacRefresh()
    local seen = {}
    local expected = #p.uacResults
    repeat
        for _, e in ipairs(p.uacEntries) do
            local b = e.button
            if b.visible then
                seen[b] = true
                check(b.x >= 180 and b.x + b.width <= p.width - 12, "Action fits horizontally")
                check(b.y >= 108 and b.y + b.height <= p.height - 50, "Action stays above footer")
            end
        end
        for _, e in pairs(p.uacGroupEntries) do
            if e.button.visible then
                seen[e.button] = true
            end
        end
        if not p.uacNext.enable then
            break
        end
        p.uacNext.onclick(p, p.uacNext)
    until false
    local reached = 0
    for _ in pairs(seen) do
        reached = reached + 1
    end
    check(
        reached == expected,
        "Pagination keeps every displayed native, extension and group row reachable"
    )
    check(
        seen[p.seeUsersBtn] and seen[p.seeRolesBtn] and seen[p.showStatisticsBtn],
        "Pagination includes native Server tools alongside extension tools"
    )
    check(seen[added], "Pagination includes late third-party native controls")
    for i = 1, 90 do
        check(
            seen[p.uacCustom["test." .. i]],
            "Every legacy Mods registration is reachable in Server"
        )
    end
    p.uacPage, p.uacSelected = 1, 1
    for i = 1, expected - 1 do
        p:uacSelect(1)
    end
    check(
        p.uacSelected == expected and p.uacResults[expected].button.visible,
        "Arrow keys reach results across pages"
    )
end
-- Mixed/nested groups must use the same width-dependent grid as Dashboard.
-- Exercise every section at its minimum height, with a large font, while
-- visiting every page: a result hidden on the first page must remain reachable.
for _, name in ipairs(C.sections) do
    for i = 1, 36 do
        C.registerAction({
            id = "responsive." .. name .. "." .. i,
            title = "Responsive " .. name .. " tool " .. i,
            category = name,
            group = i % 2 == 0 and { "Responsive", "Nested choices", "Deep choices" }
                or { "Responsive" },
            capability = "Responsive",
            run = function() end,
        })
    end
end
for _, geometry in ipairs({
    { 1040, 680, 16 },
    { 960, 490, 28 },
    { 900, 490, 28 },
    { 899, 490, 28 },
    { 660, 490, 16 },
    { 660, 490, 44 },
    { 660, 490, 50 },
}) do
    sw, sh, font = 1600, 1000, geometry[3]
    C.fit(p, geometry[1], geometry[2])
    for _, name in ipairs(C.sections) do
        section(name)
        for id in pairs(p.uacGroupEntries) do
            p.uacExpanded[id] = true
        end
        p:uacRefresh()
        check(p.uacHierarchical, "Responsive fixture includes expandable groups")
        check(
            p.uacGeometry.columns == (p.width >= 900 and 2 or 1),
            "Every section reflows at the same width even when it has groups"
        )
        local seen = {}
        local expected = #p.uacResults
        repeat
            local footerY = math.min(p.uacPrevious.y, p.uacNext.y, p.cancel.y)
            check(
                p.uacSearch.y + p.uacSearch.height < p.uacGeometry.summaryY,
                "Large-font search does not cover the page summary"
            )
            check(
                p.uacSearch.y >= 10 + p.uacGeometry.titleHeight + 12,
                "Large-font window title does not cover the search controls"
            )
            check(
                getTextManager():MeasureStringX(UIFont.Small, p.uacGeometry.summaryText)
                    <= p.width - p.uacGeometry.left - 24,
                "Page summary stays readable within the available width at large fonts"
            )
            for _, control in ipairs({ p.uacPrevious, p.uacNext, p.cancel }) do
                check(
                    control.x >= 0
                        and control.x + control.width <= p.width
                        and control.y >= 0
                        and control.y + control.height <= p.height - 24,
                    "Page and Close controls remain within the window above the resize grip"
                )
                check(
                    control.height >= font + 6
                        and control.width
                            >= getTextManager():MeasureStringX(UIFont.Small, control.title) + 16,
                    "Page and Close captions fit at the actual selected font size"
                )
            end
            check(
                p.uacPrevious.x + p.uacPrevious.width + 10 <= p.uacNext.x
                    and p.uacNext.x + p.uacNext.width + 10 <= p.cancel.x,
                "Measured footer captions never overlap each other"
            )
            if font == 50 then
                check(
                    p.uacPrevious.title == "<"
                        and p.uacNext.title == ">"
                        and p.uacPrevious.tooltip:find("Previous", 1, true)
                        and p.uacNext.tooltip:find("Next", 1, true),
                    "Very large fonts use compact page captions with descriptive tooltips"
                )
            end
            for _, control in ipairs(p.uacNav) do
                check(
                    control.x + control.width <= p.uacSearch.x
                        and control.y + control.height <= footerY,
                    "All four section tabs remain reachable in compact windows"
                )
                check(
                    control.height >= font + 12
                        and control.width
                            >= getTextManager():MeasureStringX(UIFont.Small, control.title) + 24,
                    "Section tabs fit both the text height and measured text width"
                )
            end
            for _, entry in ipairs(p.uacResults) do
                local b = entry.button
                if b.visible then
                    check(
                        b.x >= 180 and b.x + b.width <= p.width - 24 and b.width > 0,
                        "Mixed group/action rows stay inside their column"
                    )
                    check(
                        b.y >= p.uacGeometry.top and b.y + b.height <= footerY - 8,
                        "Nested group/action rows never cover the footer when the window shrinks"
                    )
                    seen[b] = true
                end
            end
            if not p.uacNext.enable then
                break
            end
            p.uacNext.onclick(p, p.uacNext)
        until false
        local reached = 0
        for _ in pairs(seen) do
            reached = reached + 1
        end
        check(reached == expected, "Every expanded tool and group is reachable through pagination")
        check(
            p:onMouseWheel(-1) and p.uacPage == math.max(1, p.uacGeometry.pages - 1),
            "Mouse wheel can move back through compact pages"
        )
        check(
            p:onMouseWheel(1) and p.uacPage == p.uacGeometry.pages,
            "Mouse wheel can reach the final compact page again"
        )
        p.uacSelected = expected
        p:uacRefresh()
        for id in pairs(p.uacExpanded) do
            p.uacExpanded[id] = false
        end
        p:uacRefresh()
        check(
            p.uacPage <= p.uacGeometry.pages
                and p.uacSelected <= #p.uacResults
                and p.uacResults[p.uacSelected].button.visible,
            "Collapsing groups on a later page clamps page and keyboard selection"
        )
    end
end
-- Native/UI-scale size changes do not necessarily use our drag callback.
-- Rendering must repair a stale grid before drawing children at their old positions.
sw, sh, font = 1600, 1000, 16
C.fit(p, 1040, 680)
section("Server")
p:setWidth(660)
p:setHeight(490)
p:render()
check(
    p.uacGeometry.width == 660 and p.uacGeometry.height == 490 and p.uacGeometry.columns == 1,
    "External resize also recalculates page capacity and the column count"
)
font = 44
p:render()
check(
    p.uacGeometry.fontHeight == 44 and p.uacSearch.height >= 50 and p.cancel.height >= 50,
    "An open panel adapts its controls and page capacity after a font change"
)
-- Exercise the real control-center layout and native mouse handler between
-- deferred anchor updates, rather than only calling the layout at fixed sizes.
sw, sh, font = 1600, 1000, 16
C.fit(p, 960, 600)
p.pendingWidth, p.pendingHeight = 0, 0
local grip = p.resizeWidget
mx, my = p.x + grip.x + 20, p.y + grip.y + 20
grip:onMouseDown(0, 0)
for _, delta in ipairs({ { 80, 60 }, { -40, -20 }, { 60, 30 } }) do
    local width, height = p.width + delta[1], p.height + delta[2]
    mx, my = mx + delta[1], my + delta[2]
    grip:onMouseMoveOutside(delta[1], delta[2])
    for _, child in pairs(p:getChildren()) do
        if child.anchorRight then
            if child.anchorLeft then
                child.width = child.width + (p.pendingWidth or 0)
            else
                child.x = child.x + (p.pendingWidth or 0)
            end
        end
        if child.anchorBottom then
            if child.anchorTop then
                child.height = child.height + (p.pendingHeight or 0)
            else
                child.y = child.y + (p.pendingHeight or 0)
            end
        end
    end
    p.pendingWidth, p.pendingHeight = 0, 0
    check(
        grip.x == width - 24 and grip.y == height - 24,
        "Admin handle stays on its corner after deferred resize"
    )
    check(p.cancel.y + p.cancel.height <= grip.y, "Admin Close button stays above the drag strip")
    grip:onMouseMoveOutside(0, 0)
    check(
        p.width == width and p.height == height,
        "Admin drag does not jitter with a stationary pointer"
    )
end
grip:onMouseUpOutside(0, 0)
ISLayoutManager.RegisterWindow = function(_, functions, target)
    functions.RestoreLayout(target, "ControlCenter", { x = 40, y = 50, width = 800, height = 520 })
end
local reopened = ISAdminPanelUI:new(10, 10, 400, 400)
reopened:create()
check(
    reopened.width == 800 and reopened.height == 520,
    "Admin defaults must not overwrite restored compact geometry"
)
print("PASS: " .. count .. " control-center integration/layout checks")
