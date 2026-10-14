-- Exercise the drawing panel and click guards; native bounds are checked in Java.
local module = assert(arg[2], "Pass UAC directory")
require = function() end
local checks, calls, commands = 0, {}, {}
local function check(value, message)
    assert(value, message)
    checks = checks + 1
end
local function trim(value)
    return value:match("^%s*(.-)%s*$")
end
luautils = { trim = trim }
UIFont = { Small = 1, Medium = 2 }
Capability = { CanSetupSafehouses = 1 }
getTextManager = function()
    return {
        getFontHeight = function()
            return 16
        end,
    }
end
local permitted = true
AdminCore = {
    allowed = function()
        return permitted
    end,
    fit = function() end,
}
local W = {}
W.__index = W
function W:derive(name)
    local cls = { Type = name }
    cls.__index = cls
    return setmetatable(cls, self)
end
function W:new(x, y, w, h)
    return setmetatable({ x = x, y = y, width = w, height = h, children = {}, texts = {} }, self)
end
function W:initialise() end
function W:prerender()
    self.texts = {}
end
function W:addChild(child)
    self.children[#self.children + 1] = child
end
function W:setHeight(height)
    self.height = height
end
function W:setEnable(enabled)
    self.enable = enabled
end
function W:drawText(text)
    self.texts[#self.texts + 1] = text
end
function W:drawTextCentre() end
function W:setVisible(visible)
    self.visible = visible
end
function W:removeFromUIManager()
    self.removed = true
end
function W:onMouseUp() end
ISPanel = W:derive("ISPanel")
ISButton = W:derive("ISButton")
function ISButton:new(x, y, w, h, title, target, callback)
    local button = W.new(self, x, y, w, h)
    button.target, button.onclick = target, callback
    return button
end
ISTextEntryBox = W:derive("ISTextEntryBox")
function ISTextEntryBox:new(text, x, y, w, h)
    local entry = W.new(self, x, y, w, h)
    entry.text = text
    return entry
end
function ISTextEntryBox:getInternalText()
    return self.text
end
ISAdminPanelUI = { onOptionMouseDown = function() end }
ISPvpZonePanel = { onClick = function() end }
ISAddSafeZoneUI = {}
ISAddNonPvpZoneUI = {
    new = function()
        return {}
    end,
}
ISWorldObjectContextMenu = { disableWorldMenu = false }
Events = setmetatable({}, {
    __index = function(events, name)
        local event = { Add = function() end }
        rawset(events, name, event)
        return event
    end,
})
local player = {
    getUsername = function()
        return "owner"
    end,
    getPlayerNum = function()
        return 0
    end,
}
local houses = {}
local function house(x, y, w, h, title)
    return {
        x = x,
        y = y,
        w = w,
        h = h,
        getTitle = function()
            return title
        end,
    }
end
SafeHouse = {
    getSafehouseList = function()
        return {
            size = function()
                return #houses
            end,
        }
    end,
    getSafehouseOverlapping = function(x, y, x2, y2)
        calls[#calls + 1] = { x, y, x2, y2 }
        for _, existing in ipairs(houses) do
            if
                x < existing.x + existing.w
                and x2 > existing.x
                and y < existing.y + existing.h
                and y2 > existing.y
            then
                return existing
            end
        end
    end,
}
local highlight
addAreaHighlightForPlayer = function(...)
    highlight = { ... }
end
sendClientCommand = function(mod, command, payload)
    commands[#commands + 1] = { mod = mod, command = command, payload = payload }
end
dofile(module .. "/media/lua/client/AdminCore/WorldSafezone.lua")
local T = AdminCore
local p = ISPanel.new(AdminCoreWorldSafezone, 20, 40, 560, 430)
p.player = player
p:createChildren()
local function selection(x1, y1, x2, y2, drawing)
    p.x1, p.y1, p.x2, p.y2 = x1, y1, x2, y2
    p.drawing = drawing or false
    p:prerender()
end
local function hasText(needle)
    for _, text in ipairs(p.texts) do
        if text:find(needle, 1, true) then
            return true
        end
    end
    return false
end
local function green()
    return highlight[7] == 0.3 and highlight[8] == 1
end
local function red()
    return highlight[7] == 1 and highlight[8] == 0.2
end

selection(109, 209, 100, 200)
local query = calls[1]
check(
    query[1] == 100 and query[2] == 200 and query[3] == 110 and query[4] == 210,
    "Reverse drag uses inclusive selected tiles and exclusive native endpoints"
)
check(
    green() and p.ok.enable and hasText("No overlap"),
    "Clear locked selection is green and enabled"
)
check(highlight[2] == 100 and highlight[4] == 110, "Highlight covers the same bounds as validation")
houses = { house(103, 203, 2, 2, "Inner home") }
selection(100, 200, 109, 209)
check(
    red() and not p.ok.enable and hasText("Overlaps"),
    "Containing an existing house is red and disabled"
)
check(p.ok.tooltip:find("Inner home", 1, true), "Conflict tooltip identifies the safehouse")
local before = #commands
p.ok.onclick(p)
check(
    #commands == before and not p.removed,
    "Overlap cannot be submitted through the button callback"
)
houses = { house(90, 204, 30, 2, "Crossing home") }
selection(100, 200, 109, 209, true)
check(red() and not p.ok.enable, "Crossing overlap is found when all selection corners are outside")
houses = { house(110, 200, 10, 10, "Neighbor") }
selection(100, 200, 109, 209)
check(
    green() and p.ok.enable and hasText("Warning"),
    "Touching edges produce a warning without blocking"
)
check(
    p.ok.tooltip:find("Placement is allowed", 1, true),
    "Nearby tooltip explicitly permits placement"
)
houses = { house(110, 210, 2, 2, "Corner neighbor") }
selection(100, 200, 109, 209)
check(green() and p.ok.enable and hasText("Warning"), "Touching corners remain allowed")
houses = { house(112, 202, 2, 2, "Border neighbor") }
selection(100, 200, 109, 209)
check(
    green() and p.ok.enable and hasText("Warning"),
    "House intersecting the three-tile border warns"
)
houses = { house(113, 202, 2, 2, "Outside border") }
selection(100, 200, 109, 209)
check(
    green() and p.ok.enable and not hasText("Warning"),
    "House outside the three-tile border is clear"
)
check(p.ok.tooltip == nil, "A cleared warning removes its stale tooltip")
houses = {}
selection(100, 200, 101, 201, true)
check(
    green() and not p.ok.enable and hasText("Release"),
    "Valid dragging preview stays disabled until release"
)
local oldCalls = #calls
selection(100, 200, 100, 209)
check(red() and not p.ok.enable and hasText("Invalid size"), "One-tile width remains invalid")
check(#calls == oldCalls, "Invalid dimensions skip native list scans")
selection(100, 200, 300, 209)
check(red() and not p.ok.enable, "Selection above maximum width is invalid")
selection(100, 200, 299, 399)
check(green() and p.ok.enable, "Maximum 200-by-200 selection remains valid")
selection(100, 200, 109, 209)
houses = { house(102, 202, 2, 2, "Newly created home") }
p:prerender()
check(red() and not p.ok.enable, "Locked selection revalidates after another safehouse appears")
houses = {}
p:prerender()
check(green() and p.ok.enable, "Deleting an overlapping house clears a locked selection")
houses = { house(102, 202, 2, 2, "Late race") }
p.ok.onclick(p)
check(
    #commands == before and not p.removed,
    "Click revalidates when native list changes after the last frame"
)
houses = {}
p.titleEntry.text = "   "
p.ok.onclick(p)
check(#commands == before, "Blank title cannot be submitted by direct callback")
p.titleEntry.text = " Custom home "
p.ownerEntry.text = "   "
p:prerender()
p.ok.onclick(p)
check(not p.ok.enable and #commands == before, "Blank owner disables and guards creation")
p.ownerEntry.text = " offlineOwner "
permitted = false
p.ok.onclick(p)
check(#commands == before, "Revoked permission guards direct callback")
p:prerender()
check(p.removed and not p.visible, "Permission revocation closes the tool")
permitted, p.removed = true, nil
houses = { house(110, 200, 5, 5, "Allowed neighbor") }
p.ok.onclick(p)
local sent = commands[#commands]
check(
    #commands == before + 1
        and sent.mod == "UniversalAdminCore"
        and sent.command == "createSafehouse",
    "Nearby warning still uses authoritative server creation"
)
check(
    sent.payload.owner == "offlineOwner"
        and sent.payload.title == "Custom home"
        and sent.payload.x == 100
        and sent.payload.y == 200
        and sent.payload.w == 10
        and sent.payload.h == 10,
    "Server receives trimmed fields and exact preview bounds"
)
check(p.removed and not p.visible, "Successful request closes the drawing tool")
p.ok.tooltip = "Old warning"
p.ok.enable = true
p:resetSelection()
check(
    p.drawing and not p.x1 and not p.ok.enable and not p.ok.tooltip,
    "Redraw clears selection and feedback"
)
print("PASS: " .. checks .. " safehouse preview checks")
