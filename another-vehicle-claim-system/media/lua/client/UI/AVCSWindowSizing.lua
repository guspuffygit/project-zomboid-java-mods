require("ISUI/ISResizeWidget")
require("ISUI/ISLayoutManager")
require("ISUI/ISTextBox")
require("ISUI/ISModalDialog")
require("ISUI/ISButton")
require("ISUI/ISRichTextPanel")

AVCS = AVCS or {}
AVCS.WindowSizing = AVCS.WindowSizing or {}
local T = AVCS.WindowSizing

function T.fit(window, width, height)
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local maxW, maxH = math.max(100, sw - 16), math.max(100, sh - 16)
    width = math.min(maxW, math.max(math.min(window.minimumWidth or 400, maxW), width))
    height = math.min(maxH, math.max(math.min(window.minimumHeight or 260, maxH), height))
    window:setWidth(math.floor(width))
    window:setHeight(math.floor(height))
    window:setX(math.max(8, math.min(window:getX(), sw - width - 8)))
    window:setY(math.max(8, math.min(window:getY(), sh - height - 8)))
    if window.avcsLayout then
        window:avcsLayout()
    end
    if window.avcsSizeButton then
        window.avcsSizeButton:setX(window.width - 140)
        window.avcsSizeButton:setY(2)
    end
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

function T.resizable(window, key, minW, minH, layout)
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
    window.resizeWidget.resizeFunction = T.fit
    if window.resizeWidget2 then
        window.resizeWidget2.resizeFunction = T.fit
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
    T.fit(window, window.width, window.height)
end
