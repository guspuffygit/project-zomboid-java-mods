-- Native mouse handlers with an intentionally deferred UI anchor pass.
local game = assert(arg[1], "Game directory required")
require = function() end
local sw, sh, mx, my = 1600, 1000, 0, 0
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
local checks = 0
local function check(ok, message)
    assert(ok, message)
    checks = checks + 1
end
local W = {}
W.__index = W
function W:derive()
    local child = {}
    child.__index = child
    return setmetatable(child, { __index = self })
end
function W:new(x, y, width, height)
    return setmetatable(
        { x = x, y = y, width = width, height = height, children = {}, visible = true },
        self
    )
end
function W:initialise()
    self.children = self.children or {}
end
function W:addChild(child)
    self.children[#self.children + 1] = child
    child.parent = self
end
function W:bringToTop()
    if not self.parent then
        return
    end
    for i, child in ipairs(self.parent.children) do
        if child == self then
            table.remove(self.parent.children, i)
            break
        end
    end
    self.parent.children[#self.parent.children + 1] = self
end
for _, name in ipairs({ "X", "Y", "Width", "Height" }) do
    local key = name:lower()
    W["get" .. name] = function(self)
        return self[key]
    end
    W["set" .. name] = function(self, value)
        if key == "width" or key == "height" then
            self["pending" .. name] = (self["pending" .. name] or 0) + value - self[key]
        end
        self[key] = value
    end
end
for _, axis in ipairs({ "Left", "Right", "Top", "Bottom" }) do
    W["setAnchor" .. axis] = function(self, value)
        self["anchor" .. axis] = value
    end
end
function W:setResizable(value)
    self.resizable = value
end
function W:setCapture(value)
    self.capture = value
end
function W:setVisible(value)
    self.visible = value
end
function W:getIsVisible()
    return self.visible ~= false
end
function W:getMouseX()
    return mx - self.x - self.parent.x
end
function W:getMouseY()
    return my - self.y - self.parent.y
end
function W:close()
    self:removeFromUIManager()
end
function W:removeFromUIManager()
    self.removed = true
end
ISPanel = W:derive()
ISButton = W:derive()
ISLayoutManager = { RegisterWindow = function() end, OnPostSave = function() end }
dofile(game .. "/media/lua/client/ISUI/ISResizeWidget.lua")
local helper = assert(arg[2], "Sizing helper required")
dofile(helper)
local T = AdminCore or AVCS.WindowSizing
local function flush(panel)
    local dw, dh = panel.pendingWidth or 0, panel.pendingHeight or 0
    panel.pendingWidth, panel.pendingHeight = 0, 0
    for _, child in ipairs(panel.children) do
        if child.anchorRight then
            if child.anchorLeft then
                child.width = child.width + dw
            else
                child.x = child.x + dw
            end
        end
        if child.anchorBottom then
            if child.anchorTop then
                child.height = child.height + dh
            else
                child.y = child.y + dh
            end
        end
    end
end
local function begin(panel, grip)
    mx, my = panel.x + grip.x + grip.width - 2, panel.y + grip.y + grip.height - 2
    grip:onMouseDown(0, 0)
    check(grip.resizing and grip.capture, "Native handle captures the drag")
end
for _, existing in ipairs({ false, true }) do
    local panel = W:new(100, 80, 900, 600)
    if existing then
        panel.resizeWidget = ISResizeWidget:new(884, 584, 16, 16, panel, false)
        panel.resizeWidget:initialise()
        panel:addChild(panel.resizeWidget)
        panel.resizeWidget2 = ISResizeWidget:new(0, 584, 884, 16, panel, true)
        panel.resizeWidget2.anchorLeft = true
        panel.resizeWidget2:initialise()
        panel:addChild(panel.resizeWidget2)
    end
    local closeButton = W:new(700, 550, 80, 24)
    panel.close = closeButton -- ISUsersList uses this field for its Close button.
    panel:addChild(closeButton)
    T.resizable(panel, "drag-" .. tostring(existing), 400, 300, function(p)
        T.pin(p.close)
        p.close:setX(p.width - 100)
        p.close:setY(p.height - 56)
    end)
    check(panel.close == closeButton, "Do not replace a named Close button with a function")
    flush(panel)
    local grip = panel.resizeWidget
    begin(panel, grip)
    for _, delta in ipairs({ { 30, 20 }, { 40, 35 }, { -60, -45 }, { 80, 50 } }) do
        local width, height = panel.width + delta[1], panel.height + delta[2]
        mx, my = mx + delta[1], my + delta[2]
        grip:onMouseMoveOutside(delta[1], delta[2])
        flush(panel)
        check(
            panel.width == width and panel.height == height,
            "Continuous drag follows each pointer delta"
        )
        check(
            grip.x == panel.width - 24 and grip.y == panel.height - 24,
            "Deferred anchors must not move the handle a second time"
        )
        check(
            panel.close.y + panel.close.height <= grip.y,
            "Footer buttons stay clear of the resize strip"
        )
        grip:onMouseMoveOutside(0, 0)
        flush(panel)
        check(
            panel.width == width and panel.height == height,
            "Stationary pointer must not jitter or undo the resize"
        )
    end
    grip:onMouseUpOutside(0, 0)
    check(not grip.capture and not grip.resizing, "Mouse release ends resize outside the window")
    if panel.resizeWidget2 then
        grip = panel.resizeWidget2
        local width, height = panel.width, panel.height
        begin(panel, grip)
        mx, my = mx + 100, my + 40
        grip:onMouseMoveOutside(100, 40)
        flush(panel)
        check(
            panel.width == width and panel.height == height + 40,
            "Bottom edge only changes height"
        )
        check(
            grip.x == 0 and grip.width == panel.width - 24,
            "Bottom handle retains its bounds after native anchor update"
        )
        grip:onMouseUpOutside(0, 0)
    end
    grip = panel.resizeWidget
    begin(panel, grip)
    mx, my = sw + 500, sh + 500
    grip:onMouseMoveOutside(500, 500)
    flush(panel)
    check(panel.x == 100 and panel.y == 80, "Screen-edge resize must not move the window origin")
    check(
        panel.x + panel.width <= sw - 8 and panel.y + panel.height <= sh - 8,
        "Resize stays on-screen"
    )
    local width, height = panel.width, panel.height
    grip:onMouseMoveOutside(0, 0)
    flush(panel)
    check(
        panel.width == width and panel.height == height,
        "Overshooting a screen edge remains stable"
    )
    grip:onMouseUpOutside(0, 0)
    panel:removeFromUIManager()
    check(
        panel.removed and T.savedGeometry[panel.geometryKey],
        "Close-button windows still persist through removal"
    )
end
print("PASS: " .. checks .. " deferred native resize checks")
