require("AdminCore/Registry")
require("ISUI/ISPanelJoypad")
require("ISUI/ISCollapsableWindow")
require("DebugUIs/ISSpawnVehicleUI")
require("DebugUIs/ISSpawnHordeUI")
require("DebugUIs/ISRemoveItemTool")
local C = AdminCore
if C.toolsInstalled then
    return
end
C.toolsInstalled = true

local function open(panel)
    panel:initialise()
    panel:addToUIManager()
    -- Native dialogs own their dimensions; only keep their origin on-screen.
    panel:setX(math.max(8, math.min(panel:getX(), getCore():getScreenWidth() - panel.width - 8)))
    panel:setY(math.max(8, math.min(panel:getY(), getCore():getScreenHeight() - panel.height - 8)))
end

function C.validCommandText(text, maximum)
    return type(text) == "string"
        and #text > 0
        and #text <= (maximum or 256)
        and not text:find('[%c"\\]')
        and text:match("%S") ~= nil
end

function C.announce(text)
    if not C.allowed(Capability.DisplayServerMessage) then
        return
    end
    if not C.validCommandText(text, 256) then
        return C.message("Enter 1-256 characters without quotes, backslashes or line breaks.")
    end
    C.confirm("Broadcast this announcement to everyone?\n\n" .. text, function()
        if C.allowed(Capability.DisplayServerMessage) then
            SendCommandToServer('/servermsg "' .. text .. '"')
        end
    end)
end

C.registerAction({
    id = "core.announcement",
    category = "Server",
    title = "Broadcast announcement...",
    capability = Capability.DisplayServerMessage,
    keywords = "message restart warning broadcast",
    quick = true,
    run = function()
        local dialog = ISTextBox:new(
            0,
            0,
            480,
            200,
            "Announcement to everyone",
            "",
            nil,
            function(_, b)
                if b.internal == "OK" then
                    C.announce(b.parent.entry:getText())
                end
            end
        )
        open(dialog)
    end,
})
C.registerAction({
    id = "core.save",
    category = "Server",
    title = "Save world...",
    capability = Capability.SaveWorld,
    tooltip = "Request a world save. This does not create a separate backup.",
    run = function()
        C.confirm("Request a server world save now?", function()
            if C.allowed(Capability.SaveWorld) then
                SendCommandToServer("/save")
            end
        end)
    end,
})
C.registerAction({
    id = "core.vehicle",
    category = "Vehicles",
    title = "Spawn vehicle...",
    capability = Capability.ManipulateVehicle,
    run = function()
        open(ISSpawnVehicleUI:new(0, 0, 200, 300, getPlayer()))
    end,
})
C.registerAction({
    id = "core.horde",
    category = "Events",
    title = "Zombie / horde manager...",
    capability = Capability.CreateHorde,
    keywords = "spawn remove zombies area population",
    available = function()
        return getPlayer() and getPlayer():getCurrentSquare() ~= nil
    end,
    run = function()
        open(ISSpawnHordeUI:new(0, 0, getPlayer(), getPlayer():getCurrentSquare()))
    end,
})
C.registerAction({
    id = "core.cleanup",
    category = "World",
    title = "Remove dropped items in area...",
    capability = Capability.EditItem,
    keywords = "cleanup ground items",
    run = function()
        open(ISRemoveItemTool:new(0, 0, getPlayer()))
    end,
})
C.registerAction({
    id = "core.coordinates",
    category = "World",
    title = "Copy my coordinates",
    capability = Capability.TeleportToCoordinates,
    available = function()
        return Clipboard ~= nil
    end,
    run = function()
        local p = getPlayer()
        Clipboard.setClipboard(
            string.format(
                "%d,%d,%d",
                math.floor(p:getX()),
                math.floor(p:getY()),
                math.floor(p:getZ())
            )
        )
    end,
})
C.registerAction({
    id = "core.teleport",
    category = "World",
    title = "Teleport to coordinates...",
    capability = Capability.TeleportToCoordinates,
    keywords = "coordinate picker location",
    run = function()
        local p = getPlayer()
        local dialog = ISTextBox:new(
            0,
            0,
            430,
            200,
            "Destination: x,y,z",
            string.format("%d,%d,%d", p:getX(), p:getY(), p:getZ()),
            nil,
            function(_, b)
                if b.internal ~= "OK" then
                    return
                end
                local x, y, z =
                    b.parent.entry:getText():match("^%s*(%-?%d+)%s*,%s*(%-?%d+)%s*,%s*(%-?%d+)%s*$")
                x, y, z = tonumber(x), tonumber(y), tonumber(z)
                if
                    not x
                    or not y
                    or not z
                    or math.abs(x) > 1000000
                    or math.abs(y) > 1000000
                    or z < -32
                    or z > 31
                then
                    return C.message("Enter valid coordinates as x,y,z.")
                end
                if C.allowed(Capability.TeleportToCoordinates) then
                    if C.cancelZoneSelection then
                        C.cancelZoneSelection()
                    end
                    SendCommandToServer(string.format("/teleportto %d,%d,%d", x, y, z))
                end
            end
        )
        open(dialog)
    end,
})
C.registerAction({
    id = "core.mods",
    category = "Mods",
    title = "View active client mods",
    capability = Capability.ManipulateMods,
    tooltip = "Mods loaded by this client. Private server modules are not included.",
    run = function()
        local mods = getActivatedMods()
        local lines = { "Active client mods (not a server backend inventory):" }
        for i = 0, mods:size() - 1 do
            lines[#lines + 1] = mods:get(i)
        end
        C.message(table.concat(lines, "\n"))
    end,
})
