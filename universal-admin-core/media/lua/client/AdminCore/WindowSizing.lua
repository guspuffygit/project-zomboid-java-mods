require("ISUI/ISResizeWidget")
require("ISUI/ISLayoutManager")
require("ISUI/ISModalDialog")
require("ISUI/ISButton")
require("ISUI/ISRichTextPanel")

AdminCore = AdminCore or {}
local T = AdminCore

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
    if window.uacLayout then
        window:uacLayout()
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
    window.uacFitWidth, window.uacFitHeight = window.width, window.height
end

function T.resize(window, width, height)
    T.fit(window, width, height, true)
end

local resizeIcon

-- ISResizeWidget draws nothing; show the vanilla inventory corner grip.
local function drawGrip(grip)
    resizeIcon = resizeIcon or getTexture("media/ui/ResizeIcon.png")
    grip:drawTextureScaled(resizeIcon, grip.width - 15, grip.height - 15, 14, 14, 1, 1, 1, 1)
end

-- Other mods grow these windows after fit, e.g. pvp-raids adds an admin panel row in create().
-- Keeping that growth would ratchet the saved size up on every open, so the fitted size wins.
local function restoreFittedSize(grip)
    local window = grip.target
    if window.width ~= window.uacFitWidth or window.height ~= window.uacFitHeight then
        T.fit(window, window.uacFitWidth, window.uacFitHeight)
    end
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
    window.uacLayout = layout
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
    window.resizeWidget.prerender = restoreFittedSize
    window.resizeWidget.render = drawGrip
    if window.resizeWidget2 then
        window.resizeWidget2.resizeFunction = T.resize
    end
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
    ISLayoutManager.RegisterWindow("AdminCore." .. key, functions, window)
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

local function textModal(text, yesno, action)
    local width = math.min(720, getCore():getScreenWidth() - 24)
    local height = math.min(420, getCore():getScreenHeight() - 24)
    local modal = ISModalDialog:new(0, 0, width, height, "", yesno, nil, action)
    modal:initialise()
    local body = ISRichTextPanel:new(12, 12, width - 24, height - 75)
    body:initialise()
    body.autosetheight = false
    body.clip = true
    body:addScrollBars()
    body.text = text:gsub("<", "("):gsub(">", ")"):gsub("\n", " <LINE> ")
    modal:addChild(body)
    body:paginate()
    modal:addToUIManager()
    T.fit(modal, modal.width, modal.height)
    return modal
end

function T.message(text)
    return textModal(text, false, nil)
end

function T.allowed(capability)
    local player = getPlayer()
    return player and player:getRole() and capability and player:getRole():hasCapability(capability)
end

function T.confirm(text, action)
    return textModal(text, true, function(_, button)
        if button.internal == "YES" then
            action()
        end
    end)
end

function T.submenu(context, name)
    local option = context:addOption(name, nil, nil)
    local sub = context:getNew(context)
    context:addSubMenu(option, sub)
    return sub
end
