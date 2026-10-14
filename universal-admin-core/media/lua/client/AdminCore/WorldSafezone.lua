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
function T.safehousePlacement(x, y, w, h)
    if w < 2 or h < 2 or w > 200 or h > 200 then
        return false
    end
    -- Native bounds are [x, x+w), matching the server's overlap rejection.
    -- Inspect rectangles rather than allocating grid squares for every tile.
    local overlap = SafeHouse.getSafehouseOverlapping(x, y, x + w, y + h)
    if overlap then
        return false, overlap
    end
    -- The three-tile border is an informational warning, not a minimum gap.
    local nearby = SafeHouse.getSafehouseOverlapping(x - 3, y - 3, x + w + 3, y + h + 3)
    return true, nil, nearby
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
    if self.ok then
        self.ok:setEnable(false)
        self.ok.tooltip = nil
    end
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
        local owner = luautils.trim(p.ownerEntry:getInternalText())
        local title = luautils.trim(p.titleEntry:getInternalText())
        if not T.safehousePlacement(x, y, w, h) or owner == "" or title == "" then
            return
        end
        sendClientCommand("UniversalAdminCore", "createSafehouse", {
            owner = owner,
            title = title,
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
    local status = self.drawing and "Select the two corners by dragging."
        or "Selection locked. Walk without changing its size."
    local sr, sg, sb = 0.7, 0.9, 1
    self.ok.tooltip = nil
    local lines = {
        "Hold left mouse and drag in the world.",
        "Release to lock the rectangle; then Add Zone.",
        "Size: 2-200 tiles per side. Esc cancels.",
    }
    if self.x1 then
        local x, yy, w, h = T.zoneBounds(self.x1, self.y1, self.x2, self.y2)
        local overlap, nearby
        valid, overlap, nearby = T.safehousePlacement(x, yy, w, h)
        if overlap then
            status = "Overlaps an existing safehouse. Redraw the area."
            sr, sg, sb = 1, 0.3, 0.3
            self.ok.tooltip = 'Selection overlaps "' .. overlap:getTitle() .. '".'
        elseif not valid then
            status = "Invalid size: select 2-200 tiles per side."
            sr, sg, sb = 1, 0.3, 0.3
        elseif nearby then
            status = "Warning: an existing safehouse is within the 3-tile border."
            sr, sg, sb = 1, 0.8, 0.3
            self.ok.tooltip = 'Near "' .. nearby:getTitle() .. '". Placement is allowed.'
        else
            status = self.drawing and "No overlap. Release the mouse to lock the selection."
                or "No overlap. Selection locked; Add Zone when ready."
            sr, sg, sb = 0.5, 1, 0.6
        end
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
    self:drawText(status, 12, y + 4, sr, sg, sb, 1, UIFont.Small)
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
