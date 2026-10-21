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
            return #t * 8
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
        local e = { handlers = {} }
        e.Add = function(fn)
            e.handlers[#e.handlers + 1] = fn
        end
        rawset(t, key, e)
        return e
    end,
})
local ctrl = false
Keyboard = { KEY_E = 18, KEY_LCONTROL = 29, KEY_RCONTROL = 157 }
isKeyDown = function(key)
    return ctrl and key == Keyboard.KEY_LCONTROL
end
local W = {}
W.__index = W
function W:derive(name)
    local cls = { Type = name }
    cls.__index = cls
    setmetatable(cls, self)
    return cls
end
function W:new(x, y, w, h)
    return setmetatable({
        x = x,
        y = y,
        width = w,
        height = h,
        children = {},
        visible = true,
        enable = true,
        javaObject = { setVisible = function() end },
    }, self)
end
function W:addToUIManager()
    self.added = true
end
function W:removeFromUIManager()
    self.added = false
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
function W:setWantMouseEvents(value)
    self.wantMouse = value
end
function W:drawText() end
ISPanel = W:derive("ISPanel")
ISButton = W:derive("ISButton")
function ISButton:new(x, y, w, h, title, target, onclick)
    local b = W.new(self, x, y, w, h)
    b.title = title
    b.target = target
    b.onclick = onclick
    return b
end
function ISButton:forceClick()
    if self:getIsVisible() and self.enable then
        self.onclick(self.target, self)
    end
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
function ISTextEntryBox:focus()
    self.focused = true
end
function ISTextEntryBox:isFocused()
    return self.focused == true
end
dofile(game .. "/media/lua/client/ISUI/AdminPanel/ISAdminPanelUI.lua")
dofile(client .. "WindowSizing.lua")
dofile(client .. "Registry.lua")
dofile(client .. "Tools.lua")
dofile(client .. "ControlCenter.lua")
local C = AdminCore
local commands = {}
SendCommandToServer = function(command)
    commands[#commands + 1] = command
end
local p = ISAdminPanelUI:new(10, 10, 400, 400)
p:create()
check(#p.uacNav == 10, "All requested control-center categories exist")
check(#commands == 0, "Opening control center must not perform a server action")
local native = 0
for _, e in ipairs(p.uacEntries) do
    if not e.action then
        native = native + 1
    end
end
check(native == 17, "All 17 native admin actions survive extraction")
check(p.seeUsersBtn.visible, "User List is a dashboard shortcut")
check(not p.itemListBtn.visible, "World inventory spawning stays out of dashboard")
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
p.climateOptionsBtn.onclick(p.climateOptionsBtn.target, p.climateOptionsBtn)
check(climateCalls == 1, "Native action retains original callback")
caps.ClimateManager = false
p:updateButtons()
check(not p.climateOptionsBtn.enable, "Native capability changes still disable action")
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
p.uacSection = "Mods"
p.uacSearch:setText("")
p:uacRefresh()
check(
    added.visible and not added.enable and added.tooltip == "Original tooltip",
    "Late third-party controls retain state and appear in Mods"
)
for i = 1, 90 do
    C.registerAction({
        id = "test." .. i,
        title = "Extra " .. i,
        category = "Mods",
        capability = "Test",
        run = function() end,
    })
end
p.uacDirty = true
for _, screen in ipairs({ { 1280, 720, 16 }, { 1280, 720, 28 }, { 800, 600, 28 } }) do
    sw, sh, font = screen[1], screen[2], screen[3]
    C.fit(p, 960, 600)
    p.uacSection = "Mods"
    p.uacPage = 1
    p.uacSearch:setText("")
    p:uacRefresh()
    local seen = {}
    repeat
        for _, e in ipairs(p.uacEntries) do
            local b = e.button
            if b.visible then
                seen[b] = true
                check(b.x >= 180 and b.x + b.width <= p.width - 12, "Action fits horizontally")
                check(b.y >= 108 and b.y + b.height <= p.height - 50, "Action stays above footer")
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
    check(reached == 92, "Pagination keeps all native and extension actions reachable")
end
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
local keys = Events.OnKeyPressed.handlers
check(#keys == 1, "Control center registers one hotkey handler")
local function press(key)
    for _, fn in ipairs(keys) do
        fn(key)
    end
end
press(Keyboard.KEY_E)
check(ISAdminPanelUI.instance == reopened, "Plain E leaves the panel alone")
ctrl = true
press(Keyboard.KEY_E)
check(ISAdminPanelUI.instance == nil and reopened.added == false, "Ctrl+E closes an open panel")
role.hasAdminTool = function()
    return false
end
press(Keyboard.KEY_E)
check(ISAdminPanelUI.instance == nil, "Hotkey requires the admin tool")
role.hasAdminTool = function()
    return true
end
press(Keyboard.KEY_E)
local opened = ISAdminPanelUI.instance
check(
    opened and opened.added and opened.uacSearch.focused,
    "Ctrl+E opens the panel with the search focused"
)
opened.uacSearch:setText("no such action anywhere")
opened:uacRefresh()
opened.uacSearch.onCommandEntered()
check(ISAdminPanelUI.instance == opened, "Enter with no matches keeps the panel open")
local mark = opened.uacEnterMark
check(
    mark and not mark.visible and mark.wantMouse == false,
    "Enter mark hides when nothing matches"
)
opened.uacSearch:setText("")
opened.uacSearch.onTextChange()
local shown = opened:uacShown()
check(#shown >= 3, "Dashboard shows enough actions to walk with the arrow keys")
opened.uacSearch.onPressDown()
opened.uacSearch.onPressDown()
check(
    mark.x == shown[3].x and mark.y == shown[3].y,
    "Down arrow moves the selection along the page"
)
opened.uacSearch.onPressUp()
check(mark.x == shown[2].x and mark.y == shown[2].y, "Up arrow moves the selection back")
for _ = 1, 5 do
    opened.uacSearch.onPressUp()
end
check(mark.x == shown[1].x and mark.y == shown[1].y, "Selection stops at the first action")
for _ = 1, #shown + 5 do
    opened.uacSearch.onPressDown()
end
check(mark.x == shown[#shown].x and mark.y == shown[#shown].y, "Selection stops at the last action")
opened.uacSearch:setText("weather")
opened.uacSearch.onTextChange()
check(opened.uacSelected == 1, "Typing resets the selection to the first match")
local first
for _, e in ipairs(opened.uacEntries) do
    if e.button:getIsVisible() then
        first = e.button
        break
    end
end
check(
    mark.visible
        and mark.x == first.x
        and mark.y == first.y
        and mark.width == first.width
        and mark.height == first.height,
    "Enter mark covers the first visible action"
)
local clicks = 0
first.onclick = function()
    clicks = clicks + 1
end
first.enable = false
opened.uacSearch.onCommandEntered()
check(clicks == 0 and ISAdminPanelUI.instance == opened, "Enter skips a disabled first action")
first.enable = true
opened.uacSearch.onCommandEntered()
check(
    clicks == 1 and ISAdminPanelUI.instance == nil,
    "Enter runs the first action and closes the panel"
)
print("PASS: " .. count .. " control-center integration/layout checks")
