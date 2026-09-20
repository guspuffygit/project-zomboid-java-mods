require("ISUI/ISResizeWidget")
require("ISUI/ISLayoutManager")
require("ISUI/ISTextBox")
require("ISUI/ISModalDialog")
require("ISUI/ISButton")
require("ISUI/ISRichTextPanel")

AVCS = AVCS or {}
AVCS.WindowSizing = AVCS.WindowSizing or {}
local T = AVCS.WindowSizing

-- Layout-owned controls must not also move in the native deferred anchor pass.
function T.pin(widget)
    if not widget then
        return
    end
    for _, axis in ipairs({ "Left", "Top", "Right", "Bottom" }) do
        local setter = widget["setAnchor" .. axis]
        if setter then
            setter(widget, axis == "Left" or axis == "Top")
        end
    end
end

function T.fit(window, width, height, dragging)
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local maxW, maxH = math.max(100, sw - 16), math.max(100, sh - 16)
    if dragging then
        -- Dragging a bottom/right handle must leave the window origin stationary.
        maxW = math.max(1, sw - window:getX() - 8)
        maxH = math.max(1, sh - window:getY() - 8)
    end
    for _, grip in ipairs({ window.resizeWidget, window.resizeWidget2 }) do
        T.pin(grip)
    end
    width = math.min(maxW, math.max(math.min(window.minimumWidth or 400, maxW), width))
    height = math.min(maxH, math.max(math.min(window.minimumHeight or 260, maxH), height))
    window:setWidth(math.floor(width))
    window:setHeight(math.floor(height))
    if not dragging then
        window:setX(math.max(8, math.min(window:getX(), sw - width - 8)))
        window:setY(math.max(8, math.min(window:getY(), sh - height - 8)))
    end
    if window.avcsLayout then
        window:avcsLayout()
    end
    for _, grip in ipairs({ window.resizeWidget, window.resizeWidget2 }) do
        grip:setY(window.height - 24)
        grip:setHeight(24)
        if grip == window.resizeWidget then
            grip:setX(window.width - 24)
            grip:setWidth(24)
        else
            grip:setX(0)
            grip:setWidth(window.width - 24)
        end
        if grip.bringToTop then
            grip:bringToTop()
        end
    end
    if window.avcsSizeButton then
        window.avcsSizeButton:setX(window.width - 140)
        window.avcsSizeButton:setY(2)
    end
end

function T.resize(window, width, height)
    T.fit(window, width, height, true)
end

function T.sizeDialog(window)
    local dialog = ISTextBox:new(
        0,
        0,
        370,
        180,
        "Window size (example: 1000x620)",
        math.floor(window.width) .. "x" .. math.floor(window.height),
        window,
        function(target, button)
            if button.internal ~= "OK" then
                return
            end
            local w, h = button.parent.entry:getText():match("^%s*(%d+)%s*[xX]%s*(%d+)%s*$")
            if w and h then
                T.fit(target, tonumber(w), tonumber(h))
            end
        end
    )
    dialog:initialise()
    dialog:addToUIManager()
end

T.savedGeometry = T.savedGeometry or {}
local function remember(window)
    if not window.geometryKey then
        return
    end
    local old = T.savedGeometry[window.geometryKey]
    if
        old
        and old.x == window:getX()
        and old.y == window:getY()
        and old.width == window.width
        and old.height == window.height
    then
        return
    end
    T.savedGeometry[window.geometryKey] =
        { x = window:getX(), y = window:getY(), width = window.width, height = window.height }
    -- Save now, rather than waiting for a world save that may never occur on a client.
    if ISLayoutManager.OnPostSave then
        local ok = pcall(ISLayoutManager.OnPostSave)
        if not ok and not T.layoutWriteFailed then
            T.layoutWriteFailed = true
            print("Window layout could not be saved to disk; size is retained for this session.")
        end
    end
end

function T.resizable(window, key, minW, minH, layout)
    window.geometryKey = key
    window.minimumWidth, window.minimumHeight = minW, minH
    window.avcsLayout = layout
    window.moveWithMouse = true
    if window.setResizable then
        window:setResizable(true)
    end
    if not window.resizeWidget then
        window.resizeWidget =
            ISResizeWidget:new(window.width - 16, window.height - 16, 16, 16, window, false)
        window.resizeWidget:initialise()
        window:addChild(window.resizeWidget)
    end
    window.resizeWidget.resizeFunction = T.resize
    if window.resizeWidget2 then
        window.resizeWidget2.resizeFunction = T.resize
    end
    window.avcsSizeButton =
        ISButton:new(window.width - 140, 2, 65, 22, "Size...", window, T.sizeDialog)
    window.avcsSizeButton:initialise()
    window:addChild(window.avcsSizeButton)
    local functions = {
        SaveLayout = function(target, name, saved)
            saved.x, saved.y = target:getX(), target:getY()
            saved.width, saved.height = target.width, target.height
        end,
        RestoreLayout = function(target, name, saved)
            target:setX(tonumber(saved.x) or 8)
            target:setY(tonumber(saved.y) or 8)
            T.fit(
                target,
                tonumber(saved.width) or target.width,
                tonumber(saved.height) or target.height
            )
        end,
    }
    ISLayoutManager.RegisterWindow("AVCS." .. key, functions, window)
    local saved = T.savedGeometry[key]
    if saved then
        functions.RestoreLayout(window, key, saved)
    end
    if not window.geometryCloseWrapped then
        window.geometryCloseWrapped = true
        local close = window.close
        -- ISUsersList.close is a button, not a method. Preserve named controls.
        if type(close) == "function" then
            window.close = function(self, ...)
                remember(self)
                return close(self, ...)
            end
        end
        local remove = window.removeFromUIManager
        window.removeFromUIManager = function(self, ...)
            remember(self)
            if remove then
                return remove(self, ...)
            end
        end
    end
    T.fit(window, window.width, window.height)
end
