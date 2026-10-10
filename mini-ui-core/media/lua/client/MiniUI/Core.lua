require("ISUI/ISPanel")
require("ISUI/ISButton")
require("ISUI/ISLayoutManager")

MiniUICore = MiniUICore or {}
local C = MiniUICore
if C.installed then
    return C
end
C.installed = true

function C.pin(widget)
    widget:setAnchorLeft(true)
    widget:setAnchorRight(false)
    widget:setAnchorTop(true)
    widget:setAnchorBottom(false)
    return widget
end

function C.clamp(window, margin)
    margin = margin or 8
    local core = getCore()
    local maxX = math.max(0, core:getScreenWidth() - window:getWidth() - margin)
    local maxY = math.max(0, core:getScreenHeight() - window:getHeight() - margin)
    window:setX(math.max(math.min(margin, maxX), math.min(maxX, window:getX())))
    window:setY(math.max(math.min(margin, maxY), math.min(maxY, window:getY())))
end

-- Commit native deferred anchors before another size change can overwrite the delta.
function C.size(window, width, height)
    window:recalcSize()
    window:setWidth(width)
    window:setHeight(height)
    window:recalcSize()
    C.clamp(window)
end

function C.beginDrag(window, x, y, headerHeight)
    if
        not window:getIsVisible()
        or not (
            x >= 0
            and x < window:getWidth()
            and y >= 0
            and y < math.min(headerHeight, window:getHeight())
        )
    then
        return false
    end
    window:bringToTop()
    window.miniDrag = { x = getMouseX(), y = getMouseY(), px = window:getX(), py = window:getY() }
    window:setCapture(true)
    return true
end

function C.drag(window)
    C.updateInput(window)
    local drag = window.miniDrag
    if not drag then
        return false
    end
    local ok, reason = pcall(function()
        window:setX(drag.px + getMouseX() - drag.x)
        window:setY(drag.py + getMouseY() - drag.y)
        C.clamp(window)
    end)
    if not ok then
        C.cancelDrag(window)
        error(reason, 0)
    end
    return true
end

function C.cancelDrag(window)
    local dragged = window.miniDrag ~= nil
    window.miniDrag = nil
    if window.javaObject then
        window:setCapture(false)
    end
    return dragged
end

function C.endDrag(window)
    local dragged = C.cancelDrag(window)
    if dragged and window.saveMiniLayout then
        window:saveMiniLayout()
    end
    return dragged
end

-- Native UI skips mouse-up on hidden windows and when another UI consumes it.
function C.updateInput(window)
    if not window.javaObject then
        return
    end
    if not window.miniDrag then
        if window:getIsCaptured() then
            C.cancelDrag(window)
        end
        return
    end
    if
        not window:getIsVisible()
        or (ISUIHandler and ISUIHandler.allUIVisible == false)
        or (isMouseButtonDown and not isMouseButtonDown(0))
    then
        C.endDrag(window)
    end
end

-- Cached base colors avoid cumulative fading and allocations on each update.
function C.fade(window, alpha)
    if window.miniAppliedAlpha == alpha then
        return
    end
    window.miniAppliedAlpha = alpha
    local function apply(widget)
        widget.miniBaseAlpha = widget.miniBaseAlpha or {}
        for _, key in ipairs({
            "backgroundColor",
            "backgroundColorMouseOver",
            "borderColor",
            "textColor",
        }) do
            local color = widget[key]
            if color then
                widget.miniBaseAlpha[key] = widget.miniBaseAlpha[key] or color.a
                color.a = widget.miniBaseAlpha[key] * alpha
            end
        end
        for _, child in pairs(widget:getChildren() or {}) do
            apply(child)
        end
    end
    apply(window)
end

function C.save()
    if not ISLayoutManager.layouts then
        return
    end
    local ok, reason = pcall(ISLayoutManager.OnPostSave)
    if not ok and not C.saveWarned then
        C.saveWarned = true
        print("Mini UI: could not save layout: " .. tostring(reason))
    end
end

function C.attach(window)
    if not UIManager.getUI():contains(window:getJavaObject()) then
        window:addToUIManager()
        window.removed = false
        return true
    end
    return false
end

function C.register(name, target, save, restore)
    ISLayoutManager.RegisterWindow(name, { SaveLayout = save, RestoreLayout = restore }, target)
    -- Carry preferences across resolution changes; positions are always clamped.
    if not target.miniLayoutRestored then
        for _, resolution in ipairs(ISLayoutManager.layouts or {}) do
            for _, layout in ipairs(resolution.windows or {}) do
                if layout.name == name then
                    restore(target, name, layout)
                    target.miniLayoutRestored = true
                    break
                end
            end
            if target.miniLayoutRestored then
                break
            end
        end
    end
end

local Window = ISPanel:derive("MiniUIWindow")
C.Window = Window
function Window:new(x, y, width, height, title)
    local o = ISPanel.new(self, x, y, width, height)
    o.title = title
    o.headerHeight = math.max(28, getTextManager():getFontHeight(UIFont.Small) + 12)
    o.backgroundColor = { r = 0.06, g = 0.07, b = 0.08, a = 0.95 }
    o.borderColor = { r = 0.52, g = 0.46, b = 0.3, a = 1 }
    return o
end
function Window:createChildren()
    local h = self.headerHeight - 6
    self.collapseButton = C.pin(ISButton:new(0, 3, h, h, "-", self, function(panel)
        C.endDrag(panel)
        if panel.setCollapsed then
            panel:setCollapsed(not panel.collapsed)
            return
        end
        panel.collapsed = not panel.collapsed
        if panel.layout then
            panel:layout()
        end
        if panel.saveMiniLayout then
            panel:saveMiniLayout()
        end
    end))
    self.closeButton = C.pin(ISButton:new(0, 3, h, h, "X", self, function(panel)
        panel:close()
    end))
    for _, button in ipairs({ self.collapseButton, self.closeButton }) do
        button:initialise()
        self:addChild(button)
    end
    self:layoutHeader()
end
function Window:layoutHeader()
    local h = self.headerHeight - 6
    self.closeButton:setX(self:getWidth() - h - 4)
    self.collapseButton:setX(self:getWidth() - h * 2 - 8)
    self.collapseButton:setTitle(self.collapsed and "+" or "-")
end
function Window:onMouseDown(x, y)
    return C.beginDrag(self, x, y, self.headerHeight)
end
function Window:onMouseMove()
    return C.drag(self)
end
function Window:onMouseMoveOutside()
    return C.drag(self)
end
function Window:onMouseUp()
    return C.endDrag(self)
end
function Window:onMouseUpOutside()
    return C.endDrag(self)
end
function Window:update()
    C.updateInput(self)
end
function Window:setVisible(visible)
    if not visible then
        C.endDrag(self)
    end
    ISPanel.setVisible(self, visible)
end
function Window:removeFromUIManager()
    C.endDrag(self)
    ISPanel.removeFromUIManager(self)
end
function Window:close()
    C.endDrag(self)
    self:setVisible(false)
    self:removeFromUIManager()
    if self.saveMiniLayout then
        self:saveMiniLayout()
    end
end
function Window:prerender()
    ISPanel.prerender(self)
    local alpha = self.miniAppliedAlpha or 1
    self:drawRect(0, 0, self:getWidth(), self.headerHeight, 0.8 * alpha, 0.12, 0.14, 0.16)
    self:clampStencilRectToParent(
        8,
        3,
        math.max(1, (self.headerTextRight or self.collapseButton:getX() - 4) - 8),
        self.headerHeight - 6
    )
    self:drawText(self.title, 8, 6, 0.95, 0.93, 0.87, alpha, UIFont.Small)
    self:clearStencilRect()
end
return C
