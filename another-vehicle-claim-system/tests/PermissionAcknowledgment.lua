local handler, sent = nil, {}
Events = { OnServerCommand = {
    Add = function(fn)
        handler = fn
    end,
} }
ISPanel = {
    derive = function()
        return {}
    end,
    close = function(self)
        self.closed = true
    end,
    prerender = function() end,
}
AVCS = {
    UI = {},
    Sync = {
        ready = function()
            return true
        end,
    },
    dbByVehicleSQLID = { [12] = {} },
}
local now = 1000
getTimestampMs = function()
    return now
end
getPlayer = function()
    return {}
end
sendClientCommand = function(_, module, command, args)
    sent[#sent + 1] = args
end
dofile("another-vehicle-claim-system/media/lua/client/UI/AVCSUserPermissionPanel.lua")
local function panel(value)
    return setmetatable({
        vehicleID = 12,
        chkBox = {
            {
                internal = "AllowDrive",
                isSelected = function()
                    return value
                end,
            },
        },
        btnConfirm = {
            setEnable = function(s, v)
                s.enabled = v
            end,
            setTitle = function(s, v)
                s.title = v
            end,
        },
    }, { __index = AVCS.UI.UserPermissionPanel })
end
local first = panel(true)
first:btnConfirm_onClick()
assert(
    not first.closed and first.btnConfirm.title == "Saving",
    "Save remains pending until server replies"
)
first:close()
local second = panel(false)
second:btnConfirm_onClick()
assert(
    #sent == 2 and sent[2].AllowDrive == false,
    "Off/on/off sends final false despite old cache already being false"
)
handler("AVCS", "permissionResult", { VehicleID = 12, requestId = sent[1].requestId, ok = true })
assert(not second.closed, "Old acknowledgment cannot close a newer edit")
handler("AVCS", "permissionResult", { VehicleID = 99, requestId = sent[2].requestId, ok = true })
assert(not second.closed, "Acknowledgment must match vehicle and request")
handler("AVCS", "permissionResult", { VehicleID = 12, requestId = sent[2].requestId, ok = true })
assert(second.closed, "Matching server confirmation closes saved panel")
local third = panel(true)
third:btnConfirm_onClick()
now = 12000
third:prerender()
assert(
    not third.closed and third.btnConfirm.enabled and third.btnConfirm.title == "Retry",
    "Timeout reports unconfirmed save and allows retry"
)
third:btnConfirm_onClick()
handler(
    "AVCS",
    "permissionResult",
    { VehicleID = 12, requestId = sent[#sent].requestId, ok = false }
)
assert(
    not third.closed and third.btnConfirm.enabled,
    "Server rejection does not look like a successful save"
)
print("PASS: 7 permission acknowledgment checks")
