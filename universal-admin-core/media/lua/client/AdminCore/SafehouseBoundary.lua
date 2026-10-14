require("AdminCore/WorldSafezone")
require("AdminCore/OperationsClient")
require("AdminCore/OverlayManager")
require("ISUI/UserPanel/ISSafehouseUI")
require("ISUI/ISComboBox")
require("ISUI/ISModalDialog")
require("ISUI/ISScrollingListBox")
local T = AdminCore
if T.safehouseBoundaryInstalled then
    return
end
T.safehouseBoundaryInstalled = true
local module = "UniversalAdminCoreBoundary"
local function permitted()
    return T.operationsAllowed("ADMIN_SAFEHOUSE_EDIT")
end
local function send(command, args)
    sendClientCommand(module, command, args or {})
end
local function rectangle(h)
    return { x = h:getX(), y = h:getY(), w = h:getW(), h = h:getH() }
end

AdminSafehouseBoundary = AdminCoreWorldSafezone:derive("AdminSafehouseBoundary")
function AdminSafehouseBoundary:proposal()
    if not self.x1 then
        return nil
    end
    local x, y, w, h = T.zoneBounds(self.x1, self.y1, self.x2, self.y2)
    local old = self.snapshot
    if self.mode == "Expand" then
        local x2, y2 = math.max(x + w, old.x + old.w), math.max(y + h, old.y + old.h)
        x, y = math.min(x, old.x), math.min(y, old.y)
        w, h = x2 - x, y2 - y
    end
    return { x = x, y = y, w = w, h = h }
end
function AdminSafehouseBoundary:calculatePlacement(rect)
    if not rect or rect.w < 2 or rect.h < 2 or rect.w > 200 or rect.h > 200 then
        return false, "Select 2-200 tiles per side.", { 1, 0.2, 0.2, 0.8 }
    end
    local house =
        SafeHouse.getSafeHouse(self.snapshot.x, self.snapshot.y, self.snapshot.w, self.snapshot.h)
    if not house then
        return false, "Safehouse changed. Reopen Edit Boundary.", { 1, 0.2, 0.2, 0.8 }
    end
    local overlap =
        SafeHouse.getSafehouseOverlapping(rect.x, rect.y, rect.x + rect.w, rect.y + rect.h, house)
    if overlap then
        return false, "Overlaps: " .. overlap:getTitle(), { 1, 0.2, 0.2, 0.8 }
    end
    local near = SafeHouse.getSafehouseOverlapping(
        rect.x - 3,
        rect.y - 3,
        rect.x + rect.w + 3,
        rect.y + rect.h + 3,
        house
    )
    if near then
        return true, "Nearby: " .. near:getTitle() .. " (within 3 tiles)", { 1, 0.75, 0.2, 0.8 }
    end
    return true, "Valid preview. Server validates when you confirm.", { 0.2, 1, 0.35, 0.8 }
end
function AdminSafehouseBoundary:placement(rect)
    if not rect then
        return self:calculatePlacement(nil)
    end
    local now, cached = getTimestampMs(), self.preview
    if
        cached
        and now < cached.expires
        and rect.x == cached.x
        and rect.y == cached.y
        and rect.w == cached.w
        and rect.h == cached.h
    then
        return cached.valid, cached.status, cached.color
    end
    local valid, status, color = self:calculatePlacement(rect)
    self.preview = {
        x = rect.x,
        y = rect.y,
        w = rect.w,
        h = rect.h,
        expires = now + 100,
        valid = valid,
        status = status,
        color = color,
    }
    return valid, status, color
end
function AdminSafehouseBoundary:createChildren()
    self.rowH = math.max(30, getTextManager():getFontHeight(UIFont.Small) + 8)
    local function button(x, y, w, title, callback)
        local b = ISButton:new(x, y, w, self.rowH, title, self, callback)
        b:initialise()
        self:addChild(b)
        return b
    end
    local y = 72
    self.modeButton = button(12, y, 140, "Mode: Expand", function(p)
        p.mode = p.mode == "Expand" and "Redraw" or "Expand"
        p.modeButton:setTitle("Mode: " .. p.mode)
        AdminOverlayManager.invalidate("safehouse-boundary")
    end)
    self.redraw = button(162, y, self.width - 174, "Draw boundary in world", function(p)
        p:resetSelection()
    end)
    y = y + 5 * (self.rowH + 8)
    self.reasonEntry = ISTextEntryBox:new("", 12, y, self.width - 24, self.rowH)
    self.reasonEntry:initialise()
    self:addChild(self.reasonEntry)
    self.reasonEntry.tooltip = "Optional audit reason (up to 160 characters)."
    y = y + self.rowH + 10
    self.ok = button(12, y, 180, "Confirm Boundary", function(p)
        local rect = p:proposal()
        if p.submitted or p.drawing or not permitted() or not p:placement(rect) then
            return
        end
        local reason = p.reasonEntry:getInternalText()
        if #reason > 160 then
            p.message = "Reason must be 160 characters or fewer."
            return
        end
        rect.id, rect.token, rect.mode, rect.reason =
            p.snapshot.id, p.snapshot.token, p.mode, reason
        p.submitted = true
        p.message = "Waiting for server confirmation..."
        send("commit", rect)
    end)
    self.cancel = button(self.width - 132, y, 120, "Cancel", function(p)
        p:close()
    end)
    self:setHeight(y + self.rowH + 12)
end
function AdminSafehouseBoundary:close()
    AdminCoreWorldSafezone.close(self)
    if T.boundaryEditor == self then
        T.boundaryEditor = nil
    end
    AdminOverlayManager.enableOverlay("safehouse-boundary", false)
end
function AdminSafehouseBoundary:prerender()
    ISPanel.prerender(self)
    if not permitted() then
        self:close()
        return
    end
    self:drawTextCentre("EDIT SAFEHOUSE BOUNDARY", self.width / 2, 12, 1, 1, 1, 1, UIFont.Medium)
    self:drawText(
        self.snapshot.title .. " | Owner: " .. self.snapshot.owner,
        12,
        43,
        1,
        1,
        1,
        1,
        UIFont.Small
    )
    local rect = self:proposal()
    local valid, status, color = self:placement(rect)
    local oldArea = self.snapshot.w * self.snapshot.h
    local proposedArea = rect and rect.w * rect.h or 0
    local lines = {
        "Blue outline: existing claim. "
            .. (
                self.mode == "Expand" and "Expand keeps every existing tile."
                or "Redraw can remove claimed tiles."
            ),
        "Current: "
            .. oldArea
            .. " | Proposed: "
            .. proposedArea
            .. " | Area change: "
            .. (proposedArea - oldArea),
        self.message or (self.drawing and "Drag two corners in the world, then release." or status),
        "Optional reason:",
    }
    local y = 72 + self.rowH + 8
    for _, line in ipairs(lines) do
        self:drawText(line, 12, y, color[1], color[2], color[3], 1, UIFont.Small)
        y = y + self.rowH + 8
    end
    local changed = rect
        and (
            rect.x ~= self.snapshot.x
            or rect.y ~= self.snapshot.y
            or rect.w ~= self.snapshot.w
            or rect.h ~= self.snapshot.h
        )
    self.ok:setEnable(valid and changed and not self.drawing and not self.submitted)
end

function T.openSafehouseBoundary(house)
    if not permitted() or not house then
        return
    end
    T.cancelZoneSelection()
    T.boundaryPending = rectangle(house)
    send("snapshot", T.boundaryPending)
end
local function openSnapshot(snapshot)
    if not permitted() then
        return
    end
    T.cancelZoneSelection()
    local p = ISPanel.new(
        AdminSafehouseBoundary,
        20,
        40,
        math.min(690, getCore():getScreenWidth() - 24),
        440
    )
    p.player, p.snapshot, p.mode, p.moveWithMouse = getPlayer(), snapshot, "Expand", true
    p.x1, p.y1, p.x2, p.y2 =
        snapshot.x, snapshot.y, snapshot.x + snapshot.w - 1, snapshot.y + snapshot.h - 1
    p.drawing = false
    p:initialise()
    p:addToUIManager()
    T.boundaryEditor, T.worldSafezone = p, p
    T.fit(p, p.width, p.height)
    AdminOverlayManager.enableOverlay("safehouse-boundary", true)
end
AdminOverlayManager.registerOverlay("safehouse-boundary", {
    permission = "ADMIN_SAFEHOUSE_EDIT",
    refreshMs = 100,
    maxRows = 2,
    active = function()
        return T.boundaryEditor ~= nil
    end,
    collect = function()
        local p = T.boundaryEditor
        if not p then
            return {}
        end
        local rows =
            { { rect = p.snapshot, color = { 0.3, 0.7, 1, 0.8 }, label = "Existing safehouse" } }
        local rect = p:proposal()
        if rect then
            local _, _, color = p:placement(rect)
            rows[2] = { rect = rect, color = color, label = p.mode .. " preview" }
        end
        return rows
    end,
    renderWorld = function(ui, rows, manager)
        for _, row in ipairs(rows) do
            local c = row.color
            manager.drawRect(ui, row.rect, { r = c[1], g = c[2], b = c[3], a = c[4] }, row.label)
        end
    end,
})

local initialise = ISSafehouseUI.initialise
function ISSafehouseUI:initialise(...)
    initialise(self, ...)
    if not AdminOperations.authorized(self.player, "ADMIN_SAFEHOUSE_EDIT") then
        return
    end
    T.operationsKeepAlive("safehouse-details", true)
    local h = math.max(30, getTextManager():getFontHeight(UIFont.Small) + 8)
    self.boundaryButton = ISButton:new(
        11,
        self.height + 4,
        180,
        h,
        "Edit Boundary",
        self,
        function(p)
            T.openSafehouseBoundary(p.safehouse)
        end
    )
    self.boundaryButton:initialise()
    self:addChild(self.boundaryButton)
    self.boundaryButton:setVisible(permitted())
    self.boundaryHistory = ISButton:new(
        201,
        self.height + 4,
        self.width - 212,
        h,
        "Boundary history",
        self,
        function()
            if permitted() then
                send("history", {})
            end
        end
    )
    self.boundaryHistory:initialise()
    self:addChild(self.boundaryHistory)
    self.boundaryHistory:setVisible(permitted())
    self:setHeight(self.height + h + 15)
end
local closeDetails = ISSafehouseUI.close
function ISSafehouseUI:close(...)
    T.operationsKeepAlive("safehouse-details", false)
    return closeDetails(self, ...)
end
local updateButtons = ISSafehouseUI.updateButtons
function ISSafehouseUI:updateButtons(...)
    updateButtons(self, ...)
    if self.boundaryButton then
        self.boundaryButton:setVisible(permitted())
        self.boundaryHistory:setVisible(permitted())
    end
end

function T.onSafehouseBoundaryCommand(mod, command, args)
    if mod ~= module or type(args) ~= "table" then
        return
    end
    if command == "changed" and args.old then
        local old = args.old
        local house = SafeHouse.getSafeHouse(old.x, old.y, old.w, old.h)
        if house then
            house:setX(args.x)
            house:setY(args.y)
            house:setW(args.w)
            house:setH(args.h)
            house:setOnlineID(args.onlineId)
            triggerEvent("OnSafehousesChanged")
        end
    elseif command == "snapshot" and T.boundaryPending then
        local pending = T.boundaryPending
        if
            pending.x ~= args.x
            or pending.y ~= args.y
            or pending.w ~= args.w
            or pending.h ~= args.h
        then
            return
        end
        T.boundaryPending = nil
        openSnapshot(args)
    elseif command == "result" then
        if T.boundaryEditor then
            T.boundaryEditor:close()
        end
        T.boundaryPending = nil
        local modal = ISModalDialog:new(
            0,
            0,
            540,
            180,
            args.message or "Boundary request complete.",
            false,
            nil,
            nil
        )
        modal:initialise()
        modal:addToUIManager()
    elseif command == "history" and permitted() then
        local width, height =
            math.min(900, getCore():getScreenWidth() - 24),
            math.min(550, getCore():getScreenHeight() - 24)
        local modal = ISModalDialog:new(
            0,
            0,
            width,
            height,
            "Recent boundary edits (last 25)",
            false,
            nil,
            nil
        )
        modal:initialise()
        modal:addToUIManager()
        local list = ISScrollingListBox:new(12, 52, width - 24, height - 105)
        list:initialise()
        modal:addChild(list)
        list.font = UIFont.Small
        local fh = getTextManager():getFontHeight(UIFont.Small)
        list.itemheight = fh * 4 + 12
        function list:doDrawItem(y, item)
            for i, line in ipairs(item.item) do
                self:drawText(line, 8, y + 4 + (i - 1) * fh, 1, 1, 1, 1, UIFont.Small)
            end
            return y + self.itemheight
        end
        for _, row in ipairs(args.rows or {}) do
            list:addItem(row.id, {
                os.date("%Y-%m-%d %H:%M", row.at / 1000)
                    .. " | "
                    .. row.admin
                    .. " | Owner: "
                    .. row.owner,
                row.mode
                    .. " ("
                    .. row.old.x
                    .. ","
                    .. row.old.y
                    .. ","
                    .. row.old.w
                    .. ","
                    .. row.old.h
                    .. ") -> ("
                    .. row.new.x
                    .. ","
                    .. row.new.y
                    .. ","
                    .. row.new.w
                    .. ","
                    .. row.new.h
                    .. ")",
                "Reason: " .. (row.reason ~= "" and row.reason or "None given"),
                "Property: " .. row.propertyId,
            })
        end
    end
end
Events.OnServerCommand.Add(T.onSafehouseBoundaryCommand)
Events.OnSafehousesChanged.Add(function()
    if T.boundaryEditor then
        T.boundaryEditor.preview = nil
    end
    AdminOverlayManager.invalidate("safehouse-boundary")
end)
