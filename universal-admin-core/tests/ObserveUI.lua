-- Installed native window/button/scroll methods with a deferred Java UI model.
local game = arg[1] or "C:/Program Files (x86)/Steam/steamapps/common/ProjectZomboid"
local root = arg[2] or "universal-admin-core"
require = function() end
local checks = 0
local function check(v, m)
    assert(v, m)
    checks = checks + 1
end
local J = {}
J.__index = J
local mouseX, mouseY, mouseDown, font, sw, sh = 0, 0, false, 14, 1280, 600
for _, name in ipairs({ "X", "Y", "Width", "Height" }) do
    local key = name:lower()
    J["get" .. name] = function(self)
        return self[key]
    end
    J["set" .. name] = function(self, value)
        self[key] = value
    end
end
for _, name in ipairs({
    "AnchorLeft",
    "AnchorRight",
    "AnchorTop",
    "AnchorBottom",
    "WantKeyEvents",
    "ConsumeMouseEvents",
    "WantExtraMouseEvents",
    "ForceCursorVisible",
    "Capture",
    "AlwaysOnTop",
}) do
    J["set" .. name] = function(self, value)
        self[name] = value
    end
end
function J:getAbsoluteX()
    return self.x + (self.parent and self.parent:getAbsoluteX() or 0)
end
function J:getAbsoluteY()
    return self.y + (self.parent and self.parent:getAbsoluteY() or 0)
end
function J:isPointOver(x, y)
    if not self.visible or (self.parent and not self.parent.visible) then
        return false
    end
    return x >= self:getAbsoluteX()
        and x < self:getAbsoluteX() + self.width
        and y >= self:getAbsoluteY()
        and y < self:getAbsoluteY() + self.height
end
function J:isMouseOver()
    return self:isPointOver(mouseX, mouseY)
end
function J:setVisible(value)
    self.visible = value
end
function J:isVisible()
    return self.visible
end
function J:isCapture()
    return self.Capture == true
end
function J:AddChild(child)
    child.parent = self
    self.children[#self.children + 1] = child
end
dofile(root .. "/tests/fixtures/NativeChildren.lua")(J)
function J:bringToTop() end
function J:setScrollChildren(value)
    self.scrollChildren = value
end
function J:getScrollChildren()
    return self.scrollChildren
end
function J:setScrollWithParent(value)
    self.scrollWithParent = value
end
function J:getScrollWithParent()
    return self.scrollWithParent
end
function J:setScrollHeight(value)
    self.scrollHeight = value
end
function J:getScrollHeight()
    return self.scrollHeight or 0
end
function J:setYScroll(value)
    self.scroll = value
end
function J:getYScroll()
    return self.scroll or 0
end
function J:setXScroll(value)
    self.xScroll = value
end
function J:getXScroll()
    return self.xScroll or 0
end
function J:getScrollWidth()
    return 0
end
function J:setMaxDrawHeight(value)
    self.maxDrawHeight = value
end
function J:clearMaxDrawHeight()
    self.maxDrawHeight = nil
end
function J:DrawText(_, text, x, y)
    self.owner.drawn = self.owner.drawn or {}
    self.owner.drawn[#self.owner.drawn + 1] = { text = text, x = x, y = y + self:getYScroll() }
end
J.DrawTextCentre = J.DrawText
function J:DrawTextureScaledColor() end
function J:DrawTextureScaled() end
function J:setStencilRect() end
function J:clearStencilRect() end
UIElement = {
    new = function(owner)
        return setmetatable({
            owner = owner,
            x = 0,
            y = 0,
            width = 0,
            height = 0,
            lastWidth = owner.width or 0,
            lastHeight = owner.height or 0,
            visible = true,
            children = {},
        }, J)
    end,
}
UITextBox2 = {
    new = function(_, x, y, width, height, text)
        local entry = UIElement.new({ width = width, height = height })
        entry.x, entry.y, entry.width, entry.height, entry.text = x, y, width, height, text
        entry.setTable = function(self, owner)
            self.owner = owner
        end
        entry.setEditable = function() end
        entry.setPlaceholderText = function(self, value)
            self.placeholder = value
        end
        entry.SetText = function(self, value)
            self.text = value
        end
        entry.getText = function(self)
            return self.text
        end
        entry.getInternalText = entry.getText
        entry.isFocused = function(self)
            return self.focused == true
        end
        entry.unfocus = function(self)
            self.focused, self.owner.unfocused = false, true
        end
        return entry
    end,
}
local attached = {}
UIManager = {
    AddUI = function(element)
        attached[element] = true
    end,
    RemoveElement = function(element)
        attached[element] = nil
    end,
}
ISDock, UIHorizontalAlignment = { None = 0 }, { Left = 0 }
ISUITextureGetter = {
    checkGetTexture = function(texture)
        return texture
    end,
}
UITransition = {
    new = function()
        return {}
    end,
}
getISUIStackTrace = function()
    return "fixture"
end
getTexture = function()
    return nil
end
getMouseX = function()
    return mouseX
end
getMouseY = function()
    return mouseY
end
isMouseButtonDown = function()
    return mouseDown
end
getGameTime = function()
    return {
        getMultiplier = function()
            return 1
        end,
        getTrueMultiplier = function()
            return 1
        end,
    }
end
getSoundManager = function()
    return { playUISound = function() end }
end
ISMouseDrag = {}
UIFont = { Small = 1 }
getTextManager = function()
    return {
        getFontHeight = function()
            return font
        end,
        MeasureStringX = function(_, _, text)
            return #text * font / 2
        end,
        getFontFromEnum = function()
            return {
                getLineHeight = function()
                    return font
                end,
            }
        end,
    }
end
getCore = function()
    return {
        getScreenWidth = function()
            return sw
        end,
        getScreenHeight = function()
            return sh
        end,
        getOptionFontSizeReal = function()
            return 1
        end,
    }
end
local commands, leases = {}, {}
sendClientCommand = function(_, command, args)
    commands[#commands + 1] = { command = command, args = args }
end
local now, loaded = 10000, true
getTimestampMs = function()
    return now
end
Keyboard = {
    KEY_ESCAPE = 1,
    KEY_F = 33,
    KEY_D = 32,
    KEY_A = 30,
    KEY_S = 31,
    KEY_W = 17,
    KEY_LSHIFT = 42,
    KEY_LCONTROL = 29,
}
local heldKey
isKeyDown = function(key)
    return key == heldKey
end
Events = setmetatable({}, {
    __index = function(t, key)
        local event = { handlers = {} }
        event.Add = function(handler)
            event.handlers[#event.handlers + 1] = handler
        end
        rawset(t, key, event)
        return event
    end,
})
AdminOperations = {
    capable = function()
        return true
    end,
    authorized = function()
        return true
    end,
}
AdminOverlayManager = { enableOverlay = function() end }
local target = {
    getX = function()
        return 120.5
    end,
    getY = function()
        return 240.5
    end,
    getZ = function()
        return 0
    end,
    isDead = function()
        return false
    end,
    getCurrentSquare = function()
        return loaded and {} or nil
    end,
    getPrimaryHandItem = function()
        return {
            getDisplayName = function()
                return "Baseball Bat"
            end,
        }
    end,
}
getPlayerFromUsername = function(name)
    return name == "guest" and target or nil
end
getPlayer = function()
    return target
end
AdminCore = {
    operationsKeepAlive = function(owner, enabled)
        leases[#leases + 1] = { owner, enabled }
    end,
    operationsAllowed = function()
        return true
    end,
    registerAction = function() end,
}
for _, file in ipairs({
    "shared/ISBaseObject.lua",
    "shared/luautils.lua",
    "client/ISUI/Layout/ISBounds.lua",
    "client/ISUI/ISUIElement.lua",
    "client/ISUI/ISPanel.lua",
    "client/ISUI/ISPanelJoypad.lua",
    "client/ISUI/ISButton.lua",
    "client/ISUI/ISScrollBar.lua",
    "client/ISUI/ISScrollingListBox.lua",
    "client/ISUI/ISResizeWidget.lua",
    "client/ISUI/ISCollapsableWindow.lua",
    "client/ISUI/ISTextEntryBox.lua",
    "client/ISUI/ISComboBox.lua",
}) do
    dofile(game .. "/media/lua/" .. file)
end
dofile(root .. "/media/lua/client/AdminCore/ObserverClient.lua")
AdminCore.refreshObserverRoster = function()
    AdminCore.observer.roster = { "guest" }
    if AdminCore.refreshObserverChoices then
        AdminCore.refreshObserverChoices()
    end
end
dofile(root .. "/media/lua/client/AdminCore/ObserverUI.lua")
AdminCore.openObserverPanel()
local panel = AdminCore.observePanel
local body = panel.body
check(body:getScrollChildren() == true, "Scrolling is enabled after native panel creation")
local range = body:getScrollHeight() - body:getScrollAreaHeight()
check(range > 0, "Compact observer fixture actually overflows")
body:setYScroll(-range)
body:render()
check(body.drawn[1].y == panel.textY - range, "Native text offset is applied exactly once")
local last = body.drawn[#body.drawn].y
check(last >= 0 and last < body.height, "Bottom guidance is reachable at compact size")
local old = body:getYScroll()
panel.widgets[1]:onMouseWheel(-1)
check(body:getYScroll() > old, "Wheel over a child button scrolls the parent viewport")
AdminCore.observer.info = true
panel:layoutInfo()
panel:prerender()
local position, held = nil, nil
for _, line in ipairs(panel.drawn) do
    if line.text:find("Position: 120.5, 240.5", 1, true) then
        position = line
    end
    if line.text:find("Visible held item: Baseball Bat", 1, true) then
        held = line
    end
end
check(
    position and held and not AdminCore.observer.id,
    "Information reads the actual selected player's position and held item without spectating"
)
check(
    position.y > 26 and held.y < panel.body.y,
    "Information is visible in a fixed header above the scrolled controls"
)
panel.drawn = {}
loaded = false
now = now + 300
panel:prerender()
local unloaded = false
for _, line in ipairs(panel.drawn) do
    if line.text:find("outside loaded cells", 1, true) then
        unloaded = true
    end
end
check(
    unloaded,
    "Information explains unavailable selected-player state instead of rendering nothing"
)
AdminCore.observer.roster = { "guest", "guest-two" }
AdminCore.observer.target = "guest-two"
AdminCore.refreshObserverChoices()
check(
    panel.targets:getOptionText(panel.targets.selected) == "guest",
    "Refreshing roster does not replace explicit menu selection with observed target"
)
panel.targets:clear()
panel.targets:addOption("No matching players")
AdminCore.selectObserver(nil)
local noSelection = AdminCore.observerInformation()
check(
    noSelection[2]:find("Select an online player", 1, true),
    "Information shows useful feedback when no player is selected"
)
panel:close()
check(
    panel.search.unfocused == true and panel.removed and AdminCore.observePanel == nil,
    "Closing unfocuses search and releases observer UI"
)

local function click(button)
    button:onMouseDown(2, 2)
    button:onMouseUp(2, 2)
end
local function tick()
    now = now + 100
    for _, handler in ipairs(Events.OnTick.handlers) do
        handler()
    end
end
local pans, stops = {}, 0
AdminCoreObserveCamera = {
    active = function()
        return true
    end,
    ready = function()
        return true
    end,
    pan = function(dx, dy)
        pans[#pans + 1] = { dx, dy }
    end,
    stop = function()
        stops = stops + 1
    end,
}
loaded = true
for _, scale in ipairs({ 14, 22, 30 }) do
    font = scale
    AdminCore.openObserverPanel()
    panel, body = AdminCore.observePanel, AdminCore.observePanel.body
    local V = AdminCore.observer
    V.id, V.mode, V.target, V.expires, V.stream, V.info =
        59, "FREE", "guest", now + 30000, false, false
    V.lastPan, V.lastHeartbeat = now, now - 2000
    local width, height, x, y = panel.width, panel.height, panel:getX(), panel:getY()
    local childCount, commandCount, leaseCount = panel:numChildren(), #commands, #leases
    local originalTitle = panel.title
    panel.search.javaObject.focused = true
    heldKey = Keyboard.KEY_D
    local oldPans = #pans
    tick()
    check(
        #pans == oldPans and commands[#commands].command == "observeHeartbeat",
        "real observer tick retains heartbeat while search owns keyboard"
    )
    commandCount = #commands
    panel.targets.expanded = true
    panel.targets.popup.parentCombo = panel.targets
    panel.targets.popup:addToUIManager()
    panel:setCapture(true)
    click(panel.collapseButton)
    panel:update()
    panel.javaObject:onResize()
    check(
        panel.minimized and panel.height == panel:titleBarHeight() and panel.width == width,
        "native header click creates sticky bar at font " .. scale
    )
    check(
        panel.height <= 31 and not body:getIsVisible() and not panel.search:isFocused(),
        "minimize hides full body and frees text focus"
    )
    check(
        not attached[panel.targets.popup.javaObject] and not panel.targets.expanded,
        "minimize dismisses the own native shared dropdown"
    )
    check(
        V.id == 59
            and V.mode == "FREE"
            and V.target == "guest"
            and #leases == leaseCount
            and #commands == commandCount,
        "minimize never stops observation, requests modes, or releases lease"
    )
    check(
        panel:getX() == x
            and panel:getY() == y
            and panel.title:find("FREE", 1, true)
            and panel.title:find("guest", 1, true),
        "compact caption preserves position and shows actual mode/target"
    )
    check(
        panel.collapseButton:getX() >= 0
            and panel.collapseButton:getX() + panel.collapseButton:getWidth() <= panel.width
            and panel.collapseButton:getY() + panel.collapseButton:getHeight() <= panel.height,
        "restore control stays inside native bar after deferred anchor pass"
    )
    mouseX, mouseY = x + width / 2, y + panel.height + 30
    check(
        not panel:isMouseOver() and not body:isMouseOver() and not panel.javaObject:isCapture(),
        "minimized window does not hit-test or capture outside visible bar"
    )
    mouseX, mouseY = x + width / 2, y + 3
    panel:onMouseMove(0, 0)
    panel:onMouseMoveOutside(0, 0)
    panel:uncollapse()
    check(
        panel.minimized and panel.height == panel:titleBarHeight(),
        "native hover never restores sticky minimized window"
    )
    panel.drawn = {}
    panel:prerender()
    check(
        #panel.drawn == 1 and panel.drawn[1].text == panel.title,
        "native prerender keeps compact title without expanded status/info"
    )
    oldPans = #pans
    tick()
    check(
        #pans == oldPans + 1
            and math.abs(pans[#pans][1] - 0.6) < 0.000001
            and pans[#pans][2] == 0
            and V.id == 59,
        "real observer WASD pan continues after minimize"
    )
    V.mode = "FOLLOW"
    panel:update()
    oldPans = #pans
    tick()
    check(
        #pans == oldPans and V.id == 59 and panel.title:find("FOLLOW", 1, true),
        "Follow remains active and updates minimized title without free panning"
    )
    V.mode, V.target = "SOFT", string.rep("\195\169", 100)
    panel:update()
    check(
        panel.title:find("SOFT", 1, true)
            and panel.title:sub(-3) == "..."
            and getTextManager():MeasureStringX(panel.titleBarFont, panel.title) <= width - panel:titleBarHeight() * 2 - 16
            and not (panel.title:byte(#panel.title - 3) == 195),
        "long UTF-8 target fits between native header controls without splitting characters"
    )
    V.mode, V.target = "FREE", "guest"
    panel:update()
    local movedX, movedY = x + 20, y + 10
    panel:onMouseDown(width / 2, 3)
    panel:onMouseMove(20, 10)
    panel:onMouseUpOutside(0, 0)
    check(
        panel:getX() == movedX and panel:getY() == movedY and not panel.moving,
        "native title dragging works while minimized"
    )
    click(panel.collapseButton)
    panel:update()
    panel.javaObject:onResize()
    check(
        not panel.minimized
            and body:getIsVisible()
            and panel.width == width
            and panel.height == height
            and panel:getX() == movedX
            and panel:getY() == movedY
            and panel.title == originalTitle,
        "restore returns expanded size and retains current bar position"
    )
    check(
        body:getYScroll() == 0 and panel:numChildren() == childCount and V.id == 59,
        "restore does not rebuild controls or restart observation"
    )
    local unrelated = {}
    panel.targets.popup.parentCombo = unrelated
    panel.targets.popup:addToUIManager()
    panel.targets.expanded = true
    click(panel.collapseButton)
    check(
        attached[panel.targets.popup.javaObject] and not panel.targets.expanded,
        "minimize never removes another window's native shared popup"
    )
    panel.targets.popup:removeFromUIManager()
    for _ = 1, 10 do
        click(panel.collapseButton)
        panel:update()
    end
    check(
        panel.minimized
            and panel.expandedWidth == width
            and panel.expandedHeight == height
            and panel:numChildren() == childCount,
        "repeated toggles preserve expanded geometry and fixed controls"
    )
    local stale = panel
    local oldStops = stops
    click(panel.closeButton)
    check(
        V.id == nil
            and AdminCore.observePanel == nil
            and panel.removed
            and not attached[panel.javaObject]
            and stops == oldStops + 1
            and not panel.javaObject:isCapture(),
        "native close while minimized retains Stop/Self and removes UI"
    )
    check(
        leases[#leases][1] == "observer" and leases[#leases][2] == false,
        "close still releases observer operation lease"
    )
    AdminCore.openObserverPanel()
    panel = AdminCore.observePanel
    stale:setMinimized(false)
    stale:close()
    check(
        AdminCore.observePanel == panel and not panel.minimized,
        "stale bar callbacks cannot change or close replacement window"
    )
    panel.search.javaObject.focused = true
    panel.moving = true
    for _, handler in ipairs(Events.OnDisconnect.handlers) do
        handler()
    end
    check(
        AdminCore.observePanel == nil
            and panel.removed
            and not panel.search:isFocused()
            and not panel.moving,
        "actual disconnect removal frees keyboard and drag state without close callback"
    )
end
print("PASS: " .. checks .. " observer native layout, minimize, camera input and lifecycle checks")
