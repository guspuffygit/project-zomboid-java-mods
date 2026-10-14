-- Reuse the actual native admin menu fixture, then exercise the same entries
-- from Mini Admin. No separate command implementation is supplied to the mini.
local root = arg[2] or "universal-admin-core"
-- The managed runner passes game/UAC roots as arg1/arg2. An optional local
-- integration run may additionally pass the separate Mini UI Core as arg3.
local miniCoreRoot = arg[3]
dofile(root .. "/tests/ControlCenter.lua")
if miniCoreRoot then
    dofile(miniCoreRoot .. "/media/lua/client/MiniUI/Core.lua")
end
local C, checks, enabled, clock, sends = AdminCore, 0, true, 100000, 0
local function check(value, message)
    assert(value, message)
    checks = checks + 1
end
getTimestampMs = function()
    return clock
end
C.operationToolAllowed = function(id)
    return enabled and id ~= "denied"
end
C.operationsKeepAlive = function() end
dofile(root .. "/media/lua/client/AdminCore/MiniAdmin.lua")
local nativePanel, ticket = ISAdminPanelUI.instance, nil
for _, entry in ipairs(nativePanel.uacEntries) do
    if entry.id == "native.SEETICKETS" then
        ticket = entry
    end
end
check(
    ticket and ticket.hidden and not ticket.searchable,
    "Actual native Tickets entry is hidden in shared registry"
)
C.miniPins = { "native.SEETICKETS" }
check(
    #C.miniRows(nativePanel.uacEntries, "") == 0,
    "Previously saved Tickets pin cannot restore the tool"
)
check(
    #C.miniRows(nativePanel.uacEntries, "tickets") == 0,
    "Mini Admin global search cannot restore Tickets"
)
local nativeMessage = C.message
C.message = function() end
check(
    not C.activateMiniEntry("native.SEETICKETS"),
    "Stale Mini Tickets activation cannot launch native backend"
)
C.message = nativeMessage
local executed = 0
local action = {
    id = "test.tool",
    category = "Server",
    title = "Shared Tool",
    allowed = function()
        return enabled
    end,
    run = function()
        executed = executed + 1
    end,
}
C.registerAction(action)
local entry = {
    id = "test.tool",
    title = "Shared Tool",
    category = "Server",
    keywords = "replacement",
    action = action,
}
local other = {
    id = "native.SEEUSERS",
    title = "Users",
    category = "Server",
    button = {
        enable = true,
        onclick = function()
            executed = executed + 1
        end,
    },
}
C.miniPins = { "test.tool", "native.SEEUSERS" }
check(#C.miniRows({ entry, other }, "") == 2, "Pinned tools share full registry entries")
check(C.miniRows({ entry, other }, "replacement")[1] == entry, "Global search uses keywords")
check(
    C.setMiniPinned("test.tool", false) and not C.miniPinned("test.tool"),
    "Unpin removes personal favorite"
)
check(#C.miniRows({ entry, other }, "replacement") == 1, "Unpinned tool stays searchable")
C.setMiniPinned("test.tool", true)
C.setMiniPinned("test.tool", true)
check(#C.miniPins == 2, "Pinning is idempotent")
check(not C.setMiniPinned("bad\nline", true), "Malformed persistence identifiers rejected")
entry.hidden = true
check(#C.miniRows({ entry }, "Shared") == 0, "Hidden tools cannot be found through mini search")
entry.hidden, other.button.enable = false, false
check(#C.miniRows({ other }, "Users") == 0, "Disabled native tool cannot be launched")
other.button.enable = true
local source = {
    uacEntries = { entry, other },
    updateButtons = function()
        sends = sends + 1
    end,
}
ISAdminPanelUI.instance = source
check(C.activateMiniEntry("test.tool") and executed == 1, "Mini invokes registered action")
check(
    C.activateMiniEntry("native.SEEUSERS") and executed == 2,
    "Mini invokes original native button callback"
)
enabled = false
C.message = function() end
check(
    not C.activateMiniEntry("test.tool") and executed == 2,
    "Revoked action is rechecked on click"
)
check(sends == 3, "Each execution refreshes native permission state")
enabled = true
-- Snapshot UI layout: all controls must remain above the bottom, even on a
-- small viewport and after collapsing; native event flow has separate fixtures.
local W = ISPanel
function W:removeFromUIManager() end
function W:addToUIManager() end
function W:bringToTop() end
function W:removeChild() end
function W:isMouseOver()
    return false
end
function W:setCapture(v)
    self.captured = v
end
function W:bringToTop() end
function ISTextEntryBox:setPlaceholderText() end
function ISTextEntryBox:unfocus() end
local saved
ISLayoutManager = {
    OnPostSave = function() end,
    RegisterWindow = function(_, f, target)
        saved = { f = f, target = target }
    end,
}
local m = C.MiniAdmin:new()
m:createChildren()
for _, b in ipairs(m.toolButtons) do
    check(b.y + b.height < m.height - 28, "Mini tools fit above footer")
end
m.collapsed, m.dirty = true, true
m:refresh()
check(m.height == 32 and not m.search:getIsVisible(), "Collapsed mini hides body")
m.collapsed = false
m:refresh()
m:update()
check(m.opacity == 0.3, "Mini fades during gameplay")
m.pinVisible = true
m:update()
check(m.opacity == 1, "Pin Visible keeps full opacity")
m:onMouseDown(10, 10)
check(m.captured and (m.drag ~= nil or m.miniDrag ~= nil), "Header owns dragging capture")
m:onMouseUpOutside()
check(not m.captured and m.drag == nil and m.miniDrag == nil, "Outside release clears dragging")
print("PASS: " .. checks .. " Mini Admin shared registry and layout checks")
