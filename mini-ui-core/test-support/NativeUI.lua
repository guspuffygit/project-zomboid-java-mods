-- Load native Lua UI methods with a deferred Java resize model. Unknown Java
-- methods fail, so misspelled or unsupported runtime calls cannot pass silently.
local F = { width = 1280, height = 720, font = 15, now = 1000, mouseX = -1, mouseY = -1, attached = {}, layouts = {} }
function F.load(path)
    if readTestSource then return assert(loadstring(readTestSource(path), "@" .. path))() end
    return dofile(path)
end
function F.install(game)
    require = function() end
    UIFont = { Small = "Small", Medium = "Medium" }
    ISDock = { None = 0 }
    UIHorizontalAlignment = { Left = 0 }
    getISUIStackTrace = function() return "fixture" end
    getText = function(key)
        local t = { UI_ATFCombatHealth_Title = "Combat Health", UI_ATFCombatHealth_Options = "HUD Options" }
        return t[key] or key:gsub("UI_ATFCombatHealth_", "")
    end
    getTextManager = function()
        return { getFontHeight = function() return F.font end, MeasureStringX = function(_, _, str) return #str * F.font / 2 end }
    end
    getCore = function()
        return { getScreenWidth = function() return F.width end, getScreenHeight = function() return F.height end,
            getGameMode = function() return "Sandbox" end, getKey = function() return F.key or 0 end,
            isDoingTextEntry = function() return F.typing end }
    end
    getTimestampMs = function() return F.now end
    getMouseX = function() return F.mouseX end
    getMouseY = function() return F.mouseY end
    getSoundManager = function() return { playUISound = function() end } end
    UITransition = { new = function() return { init = function() end } end }
    getSpecificPlayer = function(num) return F.players and F.players[num] end
    Events = setmetatable({}, { __index = function(self, key)
        local event = { handlers = {} }
        event.Add = function(fn) event.handlers[#event.handlers + 1] = fn end
        self[key] = event
        return event
    end })
    ISBaseObject = {}
    function ISBaseObject:derive(name)
        local o = { Type = name }; o.__index = o
        return setmetatable(o, { __index = self })
    end
    F.load(game .. "/media/lua/client/ISUI/Layout/ISBounds.lua")
    local J = {}
    J.__index = J
    for _, field in ipairs({ "X", "Y", "Width", "Height" }) do
        local key = field:lower()
        J["get" .. field] = function(self) return self[key] end
        J["set" .. field] = function(self, value)
            if field == "Width" or field == "Height" then
                self["last" .. field] = self[key]
                if value ~= self[key] then self.dirty = true end
            end
            self[key] = value
        end
    end
    for _, key in ipairs({ "AnchorLeft", "AnchorRight", "AnchorTop", "AnchorBottom", "Capture", "WantKeyEvents", "ConsumeMouseEvents", "WantExtraMouseEvents", "ForceCursorVisible" }) do
        J["set" .. key] = function(self, value) self[key] = value end
    end
    function J:getAbsoluteX() return self.x + (self.parent and self.parent:getAbsoluteX() or 0) end
    function J:isCapture() return self.Capture == true end
    function J:getAbsoluteY() return self.y + (self.parent and self.parent:getAbsoluteY() or 0) end
    function J:isPointOver(x, y) return x >= self:getAbsoluteX() and x < self:getAbsoluteX() + self.width and y >= self:getAbsoluteY() and y < self:getAbsoluteY() + self.height end
    function J:isMouseOver() return self:isPointOver(F.mouseX, F.mouseY) end
    function J:setVisible(value) self.visible = value end
    function J:isVisible() return self.visible end
    function J:getScrollHeight() return self.height end
    function J:getYScroll() return 0 end
    function J:getXScroll() return 0 end
    function J:AddChild(child) child.parent = self; self.children[#self.children + 1] = child end
    function J:RemoveChild(child) child.parent = nil end
    function J:bringToTop() end
    function J:onResize()
        if self.dirty then
            local dh, dw = self.height - self.lastHeight, self.width - self.lastWidth
            for _, child in ipairs(self.children) do
                if child.AnchorBottom and not child.AnchorTop then child.y = child.y + dh end
                if child.AnchorRight and not child.AnchorLeft then child.x = child.x + dw end
            end
        end
        self.dirty, self.lastHeight, self.lastWidth = false, self.height, self.width
    end
    for _, key in ipairs({ "DrawTextureScaledColor", "DrawText", "DrawTextCentre", "setStencilRect", "clearStencilRect" }) do J[key] = function() F.draws = (F.draws or 0) + 1 end end
    UIElement = { new = function(owner)
        return setmetatable({ owner = owner, x = 0, y = 0, width = 0, height = 0,
            lastWidth = 0, lastHeight = 0, children = {}, visible = true }, J)
    end }
    UIManager = { AddUI = function(java) F.attached[java] = true; F.attachCalls = (F.attachCalls or 0) + 1 end,
        RemoveElement = function(java) F.attached[java] = nil end,
        getUI = function() return { contains = function(_, java) return F.attached[java] == true end } end }
    F.load(game .. "/media/lua/client/ISUI/ISUIElement.lua")
    F.load(game .. "/media/lua/client/ISUI/ISPanel.lua")
    F.load(game .. "/media/lua/client/ISUI/ISButton.lua")
    ISLayoutManager = { windows = {}, layouts = {} }
    function ISLayoutManager.RegisterWindow(name, funcs, target)
        ISLayoutManager.windows[name] = { funcs = funcs, target = target }
        if F.layouts[name] then funcs.RestoreLayout(target, name, F.layouts[name]) end
    end
    function ISLayoutManager.OnPostSave()
        F.saves = (F.saves or 0) + 1
        for name, entry in pairs(ISLayoutManager.windows) do
            local layout = {}; entry.funcs.SaveLayout(entry.target, name, layout); F.layouts[name] = layout
        end
    end
end
function F.click(button)
    button:onMouseDown(2, 2)
    button:onMouseUp(2, 2)
end
function F.emit(name, ...)
    for _, handler in ipairs(Events[name].handlers) do handler(...) end
end
return F
