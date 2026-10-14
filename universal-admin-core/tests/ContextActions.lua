-- Native menu definitions are read, but never executed while indexing/searching.
local game = assert(arg[1], "Game directory required")
local dir = "universal-admin-core/media/lua/client/AdminCore/"
require = function() end
local checks, effects = 0, 0
local function check(ok, message)
    assert(ok, message)
    checks = checks + 1
end
local caps = { UseDebugContextMenu = true }
Capability = { UseDebugContextMenu = "UseDebugContextMenu" }
local admin, debug, square = true, false, {}
local player = {
    getCurrentSquare = function()
        return square
    end,
    getPlayerNum = function()
        return 0
    end,
    getRole = function()
        return {
            hasCapability = function(_, c)
                return caps[c]
            end,
        }
    end,
}
getPlayer = function()
    return player
end
isClient = function()
    return true
end
isAdmin = function()
    return admin
end
getAccessLevel = function()
    return admin and "admin" or "none"
end
isDebugEnabled = function()
    return debug
end
getCore = function()
    return {
        getDebug = function()
            return debug
        end,
    }
end
getText = function(s)
    return s
end
string.sort = function(a, b)
    return a < b
end -- Game-provided localized comparison.
getTextManager = function()
    return {
        getFontHeight = function()
            return 16
        end,
    }
end
UIFont = { Small = 1 }
PZAPI = { UI = {} }
ISPanel = {
    derive = function()
        return {}
    end,
}
Events = setmetatable({}, {
    __index = function()
        return { Add = function() end }
    end,
})
-- Execute the installed menu definitions; require is stubbed at engine boundaries.
dofile(game .. "/media/lua/client/DebugUIs/AdminContextMenu.lua")
dofile(game .. "/media/lua/client/DebugUIs/DebugContextMenu.lua")
dofile(game .. "/media/lua/client/DebugUIs/DebugMenu/ISDebugMenu.lua")
local received
sendClientCommand = function(p, module, command, args)
    received = { p, module, command, args }
end
BrushToolManager = {
    openPanel = function(p)
        effects = effects + 1
        received = p
    end,
}
AdminCore = {
    allowed = function(c)
        return caps[c]
    end,
    message = function() end,
}
dofile(dir .. "Registry.lua")
dofile(dir .. "ContextActions.lua")
local C = AdminCore
C.importDebugPanels()
check(effects == 0, "Indexing does not open a window or execute an action")
local indexed = 0
for id, action in pairs(C.actions) do
    if id:find("debug.panel.", 1, true) then
        indexed = indexed + 1
        check(
            not action.title:find("UnitTests") and not action.title:find("ForgetRecipes"),
            "Destructive developer operations stay native"
        )
        check(not C.canRun(action), "Debug windows stay gated when native Debug mode is off")
    end
end
check(indexed >= 20, "Actual native menu supplies at least twenty searchable debug panels")
local version = C.registryVersion
C.importDebugPanels()
check(version == C.registryVersion, "Reopening does not duplicate debug entries")
local brush = C.actions["context.brush"]
C.runAction(brush)
check(effects == 1 and received == player, "Brush Tool receives the current player")
caps.UseDebugContextMenu = false
C.runAction(brush)
check(effects == 1, "Revoked debug permission prevents execution")
caps.UseDebugContextMenu = true
BrushToolManager.openPanel = nil
check(not C.canRun(brush), "Missing native tool is unavailable without a hard dependency")
local confirmation
C.confirm = function(_, fn)
    confirmation = fn
end
AdminContextMenu.OnRemoveAllZombiesClient = function()
    effects = effects + 1
end
C.runAction(C.actions["context.removeZombies"])
check(confirmation and effects == 1, "Global removal requires explicit confirmation")
admin = false
caps.UseDebugContextMenu = false
confirmation()
check(effects == 1, "Confirmation rechecks permission")
admin = true
caps.UseDebugContextMenu = true
AdminContextMenu.onMakeNoise = function(s, p, r, volume)
    received = { s, p, r, volume }
end
C.runAction(C.actions["context.noise.20"])
square = { changed = true }
confirmation()
check(
    received[1] == player
        and received[2] == "UniversalAdminCore"
        and received[3] == "makeNoise"
        and received[4].radius == 20
        and received[4].x == nil
        and received[4].volume == nil,
    "Noise sends the selected radius to the server without client coordinates or volume"
)
received = nil
C.runAction(C.actions["context.noise.500"])
confirmation()
check(
    received and received[4].radius == 500,
    "The 500-tile option uses the authorized command route"
)
isClient = function()
    return false
end
debug = true
C.runAction(C.actions["context.noise.20"])
confirmation()
check(
    received[1] == square and received[2] == player and received[3] == 20,
    "Single-player debug keeps the native sound callback"
)
AdminContextMenu.onMakeNoise = nil
check(
    not C.canRun(C.actions["context.noise.20"]),
    "Missing native noise callback disables the single-player tool"
)
isClient = function()
    return true
end
square = nil
check(
    not C.canRun(C.actions["context.noise.20"]),
    "Unloaded square disables location-dependent action"
)
received = nil
confirmation()
check(received == nil, "Unload while confirmation is open cannot execute a stale location")
check(
    C.actions["context.noise.20"].group[1] == "Make noise at my position",
    "Noise radius choices share one expandable parent"
)
check(C.actions["context.randomVehicle"].group[1] == "Debug", "Vehicle debug tools are categorized")
local selectedRamp
ISBuildMenu = {
    onCreateRamp = function(playerNum, ramp)
        selectedRamp = { playerNum, ramp }
    end,
}
C.runAction(C.actions["context.ramp.north20"])
check(
    selectedRamp[1] == 0 and selectedRamp[2] == "north20",
    "Ramp picker receives native direction and current player"
)
for _, id in ipairs({
    "context.animalAvatar",
    "context.animalEnclosure",
    "context.removeAnimals",
    "context.removeVehicles",
    "context.cursor",
}) do
    check(
        C.canRun(C.actions[id]) and C.actions[id].hideUnavailable,
        "Reviewed native callback exists and hides on denial: " .. id
    )
end
check(
    C.matchesAction(
        C.actions["context.targetHelp"].title,
        "World",
        C.actions["context.targetHelp"].keywords,
        "World",
        "door",
        false
    ),
    "Target-dependent tools remain discoverable with instructions"
)
print("PASS: " .. checks .. " native menu integration checks")
