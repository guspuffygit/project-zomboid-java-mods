local root = assert(arg[2], "Pass UAC directory")
require = function() end
local checks = 0
local now, overlapCalls = 0, 0
getTimestampMs = function()
    return now
end
local function check(value, message)
    assert(value, message)
    checks = checks + 1
end
AdminCore = {
    operationsAllowed = function()
        return true
    end,
    zoneBounds = function(x, y, xx, yy)
        return math.min(x, xx), math.min(y, yy), math.abs(x - xx) + 1, math.abs(y - yy) + 1
    end,
}
AdminCoreWorldSafezone = {
    derive = function()
        return {}
    end,
}
AdminOperations = {
    authorized = function()
        return true
    end,
}
AdminOverlayManager = { registerOverlay = function() end }
ISSafehouseUI = { initialise = function() end, updateButtons = function() end }
Events =
    { OnServerCommand = { Add = function() end }, OnSafehousesChanged = { Add = function() end } }
local house = {
    x = 100,
    y = 200,
    w = 10,
    h = 10,
    owner = "owner",
    id = "same-native-id",
    members = { "owner", "member" },
}
for _, key in ipairs({ "X", "Y", "W", "H", "OnlineID" }) do
    local field = string.lower(key)
    house["set" .. key] = function(self, value)
        self[field] = value
    end
end
local excluded, overlap, near, changed = nil, nil, nil, 0
SafeHouse = {
    getSafeHouse = function(x, y, w, h)
        if x == house.x and y == house.y and w == house.w and h == house.h then
            return house
        end
    end,
    getSafehouseOverlapping = function(x, y, xx, yy, except)
        overlapCalls = overlapCalls + 1
        excluded = except
        if x == 87 then
            return near
        end
        return overlap
    end,
}
triggerEvent = function(name)
    if name == "OnSafehousesChanged" then
        changed = changed + 1
    end
end
dofile(root .. "/media/lua/client/AdminCore/SafehouseBoundary.lua")
local p = setmetatable({
    snapshot = { x = 100, y = 200, w = 10, h = 10 },
    mode = "Expand",
    x1 = 90,
    y1 = 190,
    x2 = 95,
    y2 = 195,
}, { __index = AdminSafehouseBoundary })
local rect = p:proposal()
check(
    rect.x == 90 and rect.y == 190 and rect.w == 20 and rect.h == 20,
    "Expand unions drawn area with entire old claim"
)
check(p:placement(rect) and excluded == house, "preview excludes edited claim from overlap check")
for _ = 1, 60 do
    p:placement(rect)
end
check(overlapCalls == 2, "unchanged preview does not rescan all safehouses on every render frame")
now = now + 101
overlap = {
    getTitle = function()
        return "Neighbor"
    end,
}
local valid, message, color = p:placement(rect)
check(
    not valid and message == "Overlaps: Neighbor" and color[1] == 1,
    "overlap is red with neighbor name"
)
overlap, near = nil, {
    getTitle = function()
        return "Nearby"
    end,
}
now = now + 101
valid, message, color = p:placement(rect)
check(valid and color[2] == 0.75, "near neighbor is amber but allowed")
p.mode = "Redraw"
rect = p:proposal()
check(rect.w == 6 and rect.h == 6, "Redraw uses exact drawn rectangle")
local oldMembers = house.members
AdminCore.onSafehouseBoundaryCommand("UniversalAdminCoreBoundary", "changed", {
    old = { x = 100, y = 200, w = 10, h = 10 },
    x = 90,
    y = 190,
    w = 20,
    h = 20,
    onlineId = 123,
})
check(
    house.x == 90 and house.onlineid == 123 and changed == 1,
    "server update changes native coordinates/network ID"
)
check(
    house.members == oldMembers and house.id == "same-native-id",
    "same object retains members and stable session ID"
)
AdminCore.onSafehouseBoundaryCommand("UniversalAdminCoreBoundary", "changed", {
    old = { x = 100, y = 200, w = 10, h = 10 },
    x = 90,
    y = 190,
    w = 20,
    h = 20,
    onlineId = 123,
})
check(changed == 1, "replayed update does not recreate a missing old claim")
print("Safehouse boundary preview: " .. checks .. " checks passed")
