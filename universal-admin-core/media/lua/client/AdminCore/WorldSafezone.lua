require("AdminCore/WindowSizing")
require("ISUI/AdminPanel/ISAdminPanelUI")
require("ISUI/AdminPanel/ISPvpZonePanel")
require("ISUI/AdminPanel/ISAddSafeZoneUI")
require("ISUI/AdminPanel/ISAddNonPvpZoneUI")
require("ISUI/ISWorldObjectContextMenu")
local T = AdminCore

AdminCoreWorldSafezone = ISPanel:derive("AdminCoreWorldSafezone")
function T.zoneBounds(x1, y1, x2, y2)
    return math.min(x1, x2), math.min(y1, y2), math.abs(x1 - x2) + 1, math.abs(y1 - y2) + 1
end
function AdminCoreWorldSafezone:releaseMouse()
    if self.heldWorldMenu then
        ISWorldObjectContextMenu.disableWorldMenu = self.previousWorldMenu
        self.heldWorldMenu = nil
    end
end
function AdminCoreWorldSafezone:close()
    self:releaseMouse()
    self.drawing = false
    self.dragging = false
    self:removeFromUIManager()
    self:setVisible(false)
    if T.worldSafezone == self then
        T.worldSafezone = nil
    end
end
function AdminCoreWorldSafezone:resetSelection()
    self:releaseMouse()
    self.drawing = true
    self.dragging = false
    self.x1 = nil
    self.y1 = nil
    self.x2 = nil
    self.y2 = nil
end
function AdminCoreWorldSafezone:createChildren()
    local fh = getTextManager():getFontHeight(UIFont.Small)
    self.rowH = math.max(30, fh + 8)
    self.titleEntry = ISTextEntryBox:new(
        "Safezone #" .. (SafeHouse.getSafehouseList():size() + 1),
        110,
        45,
        self.width - 122,
        self.rowH
    )
    self.ownerEntry = ISTextEntryBox:new(
        self.player:getUsername(),
        110,
        45 + self.rowH + 8,
        self.width - 122,
        self.rowH
    )
    for _, entry in ipairs({ self.titleEntry, self.ownerEntry }) do
        entry:initialise()
        self:addChild(entry)
    end
    local function button(x, y, w, label, callback)
        local b = ISButton:new(x, y, w, self.rowH, label, self, callback)
        b:initialise()
        self:addChild(b)
        return b
    end
    local bottom = 45 + 6 * (self.rowH + 8)
    self.redraw = button(12, bottom, self.width - 24, "Select / redraw area with mouse", function(p)
        p:resetSelection()
    end)
    self.ok = button(12, bottom + self.rowH + 10, 120, "Add Zone", function(p)
        if not p.x1 or p.drawing or not T.allowed(Capability.CanSetupSafehouses) then
            return
        end
        local x, y, w, h = T.zoneBounds(p.x1, p.y1, p.x2, p.y2)
        sendClientCommand("UniversalAdminCore", "createSafehouse", {
            owner = luautils.trim(p.ownerEntry:getInternalText()),
            title = luautils.trim(p.titleEntry:getInternalText()),
            x = x,
            y = y,
            w = w,
            h = h,
        })
        p:close()
    end)
    self.cancel = button(self.width - 132, bottom + self.rowH + 10, 120, "Cancel", function(p)
        p:close()
    end)
    self:setHeight(bottom + 2 * self.rowH + 22)
end
function AdminCoreWorldSafezone:pickSquare(screenX, screenY)
    local z = 0
    local x = screenToIsoX(self.player:getPlayerNum(), screenX, screenY, z)
    local y = screenToIsoY(self.player:getPlayerNum(), screenX, screenY, z)
    return getCell():getGridSquare(x, y, z)
end
function AdminCoreWorldSafezone:onMouseDownOutside(x, y)
    if not self.drawing or self.dragging then
        return
    end
    local sq = self:pickSquare(x + self:getAbsoluteX(), y + self:getAbsoluteY())
    if not sq then
        return
    end
    self.x1 = sq:getX()
    self.y1 = sq:getY()
    self.x2 = self.x1
    self.y2 = self.y1
    self.dragging = true
    self.previousWorldMenu = ISWorldObjectContextMenu.disableWorldMenu
    self.heldWorldMenu = true
    ISWorldObjectContextMenu.disableWorldMenu = true
end
function AdminCoreWorldSafezone:onMouseMoveOutside()
    if not self.dragging then
        return
    end
    local sq = self:pickSquare(getMouseX(), getMouseY())
    if sq then
        self.x2 = sq:getX()
        self.y2 = sq:getY()
    end
end
function AdminCoreWorldSafezone:finishDrag()
    if not self.dragging then
        return
    end
    self.dragging = false
    self.drawing = false
    self:releaseMouse()
end
function AdminCoreWorldSafezone:onMouseUpOutside()
    self:finishDrag()
end
function AdminCoreWorldSafezone:onMouseUp(x, y)
    self:finishDrag()
    return ISPanel.onMouseUp(self, x, y)
end
function AdminCoreWorldSafezone:prerender()
    ISPanel.prerender(self)
    self:drawTextCentre("ADD SAFEZONE", self.width / 2, 12, 1, 1, 1, 1, UIFont.Medium)
    local y = 45
    self:drawText("Title:", 12, y + 4, 1, 1, 1, 1, UIFont.Small)
    y = y + self.rowH + 8
    self:drawText("Owner:", 12, y + 4, 1, 1, 1, 1, UIFont.Small)
    y = y + self.rowH + 8
    local valid = false
    local lines = {
        "Hold left mouse and drag in the world.",
        "Release to lock the rectangle; then Add Zone.",
        "Size: 2-200 tiles per side. Esc cancels.",
    }
    if self.x1 then
        local x, yy, w, h = T.zoneBounds(self.x1, self.y1, self.x2, self.y2)
        valid = w >= 2 and h >= 2 and w <= 200 and h <= 200
        lines = {
            "Starting coordinate: " .. self.x1 .. " x " .. self.y1,
            "Ending coordinate: " .. self.x2 .. " x " .. self.y2,
            "Zone size: " .. w .. " x " .. h .. " (" .. (w * h) .. " tiles)",
        }
        addAreaHighlightForPlayer(
            self.player:getPlayerNum(),
            x,
            yy,
            x + w,
            yy + h,
            0,
            valid and 0.3 or 1,
            valid and 1 or 0.2,
            0.5,
            0.7
        )
    end
    for _, line in ipairs(lines) do
        self:drawText(line, 12, y + 4, 1, 1, 1, 1, UIFont.Small)
        y = y + self.rowH + 8
    end
    self:drawText(
        self.drawing and "Select the two corners by dragging."
            or "Selection locked. Walk without changing its size.",
        12,
        y + 4,
        0.7,
        0.9,
        1,
        1,
        UIFont.Small
    )
    self.ok:setEnable(
        valid
            and not self.drawing
            and luautils.trim(self.titleEntry:getInternalText()) ~= ""
            and luautils.trim(self.ownerEntry:getInternalText()) ~= ""
    )
    if not T.allowed(Capability.CanSetupSafehouses) then
        self:close()
    end
end

function T.cancelZoneSelection()
    if T.worldSafezone then
        T.worldSafezone:close()
    end
    for _, panel in pairs({ ISAddSafeZoneUI.instance, T.legacyNonPvp }) do
        if panel then
            panel.creatingZone = false
            panel:setVisible(false)
            panel:removeFromUIManager()
            if panel.parentUI then
                panel.parentUI:setVisible(true)
            end
        end
    end
    ISAddSafeZoneUI.instance = nil
    T.legacyNonPvp = nil
end
function T.openWorldSafezone()
    if not T.allowed(Capability.CanSetupSafehouses) then
        return
    end
    T.cancelZoneSelection()
    local p = ISPanel.new(
        AdminCoreWorldSafezone,
        20,
        40,
        math.min(560, getCore():getScreenWidth() - 24),
        430
    )
    p.player = getPlayer()
    p.moveWithMouse = true
    p:initialise()
    p:addToUIManager()
    p:resetSelection()
    T.worldSafezone = p
    T.fit(p, p.width, p.height)
end
local adminClick = ISAdminPanelUI.onOptionMouseDown
function ISAdminPanelUI:onOptionMouseDown(button, ...)
    if button.internal == "SAFEZONE" then
        T.openWorldSafezone()
        return
    end
    return adminClick(self, button, ...)
end
-- Retain the original Non-PVP dialog and its walking-based selection.
local nonPvpNew = ISAddNonPvpZoneUI.new
function ISAddNonPvpZoneUI:new(...)
    T.cancelZoneSelection()
    local p = nonPvpNew(self, ...)
    T.legacyNonPvp = p
    return p
end
local zoneClick = ISPvpZonePanel.onClick
function ISPvpZonePanel:onClick(button, ...)
    if button.internal == "TELEPORTTOZONE" then
        T.cancelZoneSelection()
    end
    return zoneClick(self, button, ...)
end
local lastX, lastY, lastZ
Events.OnTick.Add(function()
    -- No per-frame work or allocations while no zone tool is active.
    if not T.worldSafezone and not T.legacyNonPvp then
        lastX = nil
        return
    end
    local p = getPlayer()
    if not p then
        lastX = nil
        return
    end
    local x, y, z = p:getX(), p:getY(), p:getZ()
    if lastX then
        local dx, dy = x - lastX, y - lastY
        if dx * dx + dy * dy > 400 or math.abs(z - lastZ) > 1 then
            T.cancelZoneSelection()
        end
    end
    lastX, lastY, lastZ = x, y, z
end)
Events.OnKeyPressed.Add(function(key)
    if key == Keyboard.KEY_ESCAPE then
        T.cancelZoneSelection()
    end
end)
Events.OnDisconnect.Add(function()
    T.cancelZoneSelection()
    lastX = nil
end)
