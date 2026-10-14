require("AdminCore/Registry")
require("DebugUIs/AdminContextMenu")
require("DebugUIs/DebugContextMenu")
require("DebugUIs/BrushTool/BrushToolManager")
require("DebugUIs/DebugMenu/ISDebugMenu")
require("BuildingObjects/ISUI/ISBuildMenu")
require("Foraging/ISSearchManager")
require("ISUI/ISContextMenu")

local C = AdminCore
if C.contextActionsInstalled then
    return
end
C.contextActionsInstalled = true

function C.debugContextAllowed()
    if isClient() then
        return C.allowed(Capability.UseDebugContextMenu)
    end
    return isDebugEnabled()
end

local function adminToolsAllowed()
    return isClient() and (isAdmin() or getAccessLevel() == "moderator")
end

local function hasCurrentSquare()
    local player = getPlayer()
    return player and player:getCurrentSquare() ~= nil
end

local function register(id, title, category, keywords, allowed, callback, args, confirmation, group)
    C.registerAction({
        id = id,
        title = title,
        category = category,
        keywords = keywords,
        group = group or { "Debug", "UIs" },
        hideUnavailable = true,
        allowed = allowed,
        available = function()
            return getPlayer() ~= nil and callback() ~= nil
        end,
        tooltip = "Uses the game's original tool and permissions.",
        run = function()
            local function execute()
                if not getPlayer() or not C.canRun(C.actions[id]) then
                    return C.message("Your role no longer permits this tool.")
                end
                local fn = callback()
                if not fn then
                    return C.message("This tool is unavailable in this game build.")
                end
                local ok, err = pcall(function()
                    fn(unpack(args()))
                end)
                if not ok then
                    print("[Universal Admin Core] Action " .. id .. " failed: " .. tostring(err))
                    C.message("The tool could not be opened. Check the client log for details.")
                end
            end
            if confirmation then
                C.confirm(confirmation, execute)
            else
                execute()
            end
        end,
    })
end

local function playerArgs()
    return { getPlayer() }
end
local function noArgs()
    return {}
end

register(
    "context.brush",
    "Brush Tool Manager...",
    "World",
    "debug tiles build paint fire brush tool",
    C.debugContextAllowed,
    function()
        return BrushToolManager and BrushToolManager.openPanel
    end,
    playerArgs
)
C.actions["context.brush"].group = { "Debug", "Brush Tool" }

-- These native callbacks need no clicked object. Resolve the current player at
-- execution time; never cache world objects from an old right-click menu.
local tools = {
    { "tiles", "Tile picker...", "onTilesPicker", "tiles sprites buildings", playerArgs },
    { "loot", "Generate loot UI...", "onGenerateLootUI", "loot distribution items", playerArgs },
    { "running", "Running debug UI...", "onRunningUI", "movement sprint", playerArgs },
    { "attachments", "Attached items UI...", "onAttachedItems", "attachments models", playerArgs },
    { "animations", "Extended animations list...", "onExtList", "animations model", playerArgs },
    { "filming", "Filming tools...", "onFilmingToolsUI", "camera film", playerArgs },
    {
        "translations",
        "Reload translations",
        "onReloadTranslations",
        "language localization",
        noArgs,
    },
    { "missing3d", "Report missing 3D items", "do3DItem", "models diagnostics missing", noArgs },
    {
        "missingClothing",
        "Report missing clothing",
        "doMissingClothingItems",
        "clothes diagnostics missing",
        noArgs,
    },
    {
        "missingItems",
        "Report missing non-clothing items",
        "doMissingItems",
        "items diagnostics missing",
        noArgs,
    },
}
for _, spec in ipairs(tools) do
    local name = spec[3]
    register(
        "context." .. spec[1],
        spec[2],
        "World",
        "debug " .. spec[4],
        C.debugContextAllowed,
        function()
            return DebugContextMenu and DebugContextMenu[name]
        end,
        spec[5]
    )
end
C.actions["context.translations"].group = { "Debug", "Main" }
for _, id in ipairs({ "missing3d", "missingClothing", "missingItems" }) do
    C.actions["context." .. id].group = { "Debug", "Reports" }
end

register(
    "context.playerModels",
    "Toggle player model display...",
    "Settings",
    "debug visible invisible rendering models",
    C.debugContextAllowed,
    function()
        return DebugContextMenu and DebugContextMenu.onShowPlayerModel
    end,
    playerArgs,
    "Toggle player-model rendering on this client? This affects visibility, not the player's ghost/admin power."
)
C.actions["context.playerModels"].group = { "Debug", "Display" }
register(
    "context.spawnPoints",
    "Spawn points UI (my position)...",
    "World",
    "debug spawn points spawnpoints",
    function()
        return C.debugContextAllowed() and hasCurrentSquare()
    end,
    function()
        return DebugContextMenu and DebugContextMenu.onSpawnPoints
    end,
    function()
        return { getPlayer():getCurrentSquare(), getPlayer() }
    end
)
C.actions["context.spawnPoints"].group = { "Debug", "Main" }

register(
    "context.thunder",
    "Trigger thunder...",
    "Events",
    "weather storm thunder lightning",
    adminToolsAllowed,
    function()
        return AdminContextMenu and AdminContextMenu.onTriggerThunderUI
    end,
    playerArgs
)
C.actions["context.thunder"].group = { "Weather" }
register(
    "context.removeZombies",
    "Remove all zombies...",
    "Events",
    "cleanup zombies remove",
    function()
        return adminToolsAllowed() or C.debugContextAllowed()
    end,
    function()
        return AdminContextMenu and AdminContextMenu.OnRemoveAllZombiesClient
    end,
    noArgs,
    "Remove all zombies using the server's native admin command?"
)
C.actions["context.removeZombies"].group = { "Zombies" }

local function makeNoise(square, player, radius, volume)
    if isClient() then
        -- The server derives the square and volume. No client WorldSound packet is sent.
        sendClientCommand(player, "UniversalAdminCore", "makeNoise", { radius = radius })
    else
        AdminContextMenu.onMakeNoise(square, player, radius, volume)
    end
end

for _, radius in ipairs({ 10, 20, 50, 100, 200, 500 }) do
    local r = radius
    register(
        "context.noise." .. r,
        "Radius: " .. r .. " tiles...",
        "Events",
        "debug sound attract zombies radius",
        function()
            return C.debugContextAllowed() and hasCurrentSquare()
        end,
        function()
            if isClient() then
                return makeNoise
            end
            return AdminContextMenu and AdminContextMenu.onMakeNoise and makeNoise
        end,
        function()
            return { getPlayer():getCurrentSquare(), getPlayer(), r, 100 }
        end,
        "Make noise at your current position with a radius of " .. r .. " tiles?",
        { "Make noise at my position" }
    )
end

-- Target-free callbacks reviewed against Build 42's actual right-click menus.
local extra = {
    {
        "cursor",
        "Toggle cursor display",
        "Settings",
        { "Debug", "Display" },
        "onShowCursor",
        "mouse cursor",
    },
    {
        "animalAvatar",
        "Animal avatar UI...",
        "World",
        { "Debug", "Animals" },
        "onAvatarUI",
        "animal model avatar",
    },
    {
        "animalCheat",
        "Toggle animal cheats",
        "World",
        { "Debug", "Animals" },
        "onToggleAnimalCheat",
        "animals cheat",
    },
    {
        "animalEnclosure",
        "Add enclosure around me...",
        "World",
        { "Debug", "Animals" },
        "onAddEnclosure",
        "animals enclosure fence",
        "Create the native animal enclosure around your current position?",
    },
    {
        "randomVehicle",
        "Add random vehicle at my position...",
        "Vehicles",
        { "Debug" },
        "onAddVehicle",
        "spawn random car",
        "Spawn a random vehicle at your current position?",
    },
    {
        "removeVehicles",
        "Remove all vehicles...",
        "Vehicles",
        { "Debug" },
        "onRemoveAllVehicles",
        "cleanup vehicles",
        "Run the game's Remove All Vehicles action? This removes vehicles; it is not garage storage.",
    },
}
for _, spec in ipairs(extra) do
    local method = spec[5]
    register("context." .. spec[1], spec[2], spec[3], spec[6], C.debugContextAllowed, function()
        return DebugContextMenu and DebugContextMenu[method]
    end, playerArgs, spec[7], spec[4])
end
register(
    "context.removeAnimals",
    "Remove all animals...",
    "World",
    "animals cleanup",
    C.debugContextAllowed,
    function()
        return isClient() and DebugContextMenu.OnRemoveAllAnimalsClient
            or DebugContextMenu.OnRemoveAllAnimals
    end,
    noArgs,
    "Run the game's Remove All Animals action?",
    { "Debug", "Animals" }
)

for _, direction in ipairs({ "North", "South", "West", "East" }) do
    local ramp = direction:lower() .. "20"
    register(
        "context.ramp." .. ramp,
        "20 " .. direction,
        "World",
        "build ramp direction",
        C.debugContextAllowed,
        function()
            return ISBuildMenu and ISBuildMenu.onCreateRamp
        end,
        function()
            return { getPlayer():getPlayerNum(), ramp }
        end,
        nil,
        { "Debug", "Ramps" }
    )
end

local function forageMenu()
    local player = getPlayer()
    local manager = ISSearchManager.getManager(player)
    if not manager then
        return C.message("Foraging is unavailable for this player.")
    end
    local menu = ISContextMenu.get(player:getPlayerNum(), getMouseX(), getMouseY())
    ISSearchManager.createDebugContextMenu(
        player:getPlayerNum(),
        menu,
        manager,
        player:getCurrentSquare()
    )
end
register(
    "context.foraging",
    "Foraging at my position...",
    "World",
    "forage icons zone spawn",
    function()
        return C.debugContextAllowed() and hasCurrentSquare()
    end,
    function()
        return ISSearchManager and ISSearchManager.createDebugContextMenu and forageMenu
    end,
    noArgs,
    nil,
    { "Debug", "Foraging" }
)

C.registerAction({
    id = "context.targetHelp",
    category = "World",
    group = { "Debug", "World targets" },
    hideUnavailable = true,
    title = "Tools that need a world target...",
    keywords = "debug door key lock window barricade fence vehicle color blood zombie animal corpse building alarm story copy destroy tile",
    allowed = function()
        return adminToolsAllowed() or C.debugContextAllowed()
    end,
    run = function()
        C.message(
            "Right-click the actual world target for these tools:\n"
                .. "Door keys/locks; window locks/barricades; copy/destroy tile; fences; generators/fuel; compost; mannequins.\n"
                .. "Vehicle color/blood/removal; zombie/animal/corpse/player tools; building alarms and randomized stories.\n"
                .. "These depend on the clicked object or square. The original menus remain available and retain their target validation.\n"
                .. "Brush Tool Manager, tile picker, general debug windows and other target-free tools are searchable here."
        )
    end,
})

-- Read the native debug window's own button definitions. No debug window is
-- opened and no callback runs while indexing. New native panels remain searchable.
function C.importDebugPanels()
    if C.debugPanelsImported or not ISDebugMenu or not ISDebugMenu.setupButtons then
        return
    end
    local collector = {
        buttons = {},
        addButtonInfo = ISDebugMenu.addButtonInfo,
        bringToTop = ISDebugMenu.bringToTop,
    }
    local ok, err = pcall(ISDebugMenu.setupButtons, collector)
    if not ok then
        print("[Universal Admin Core] Debug panel index unavailable: " .. tostring(err))
        return
    end
    C.debugPanelsImported = true
    for index, info in ipairs(collector.buttons) do
        -- Native unit tests and recipe erasure are developer operations, not
        -- panel launchers. Keep those in the native developer menu.
        if
            info.func
            and info.title ~= getText("IGUI_DebugMenu_Dev_UnitTests")
            and info.title ~= getText("IGUI_DebugMenu_Dev_ForgetRecipes")
        then
            local entry = info
            register(
                "debug.panel." .. index,
                entry.title,
                "Settings",
                "debug " .. entry.tab .. " " .. entry.title,
                function()
                    return C.debugContextAllowed()
                        and (getCore():getDebug() or ISDebugMenu.forceEnable)
                end,
                function()
                    return entry.func
                end,
                noArgs,
                nil,
                { "Debug", entry.tab or "Panels" }
            )
            C.actions["debug.panel." .. index].tooltip =
                "Requires native Debug mode (or native force-enable) and Debug Context permission."
        end
    end
end
