-- The actual native manager dispatches a second world-element pipeline after
-- the legacy menu. Both must remain unreachable while the actor has no square.
local game, root = arg[1], arg[2] or "universal-admin-core"
local checks, nativeCalls, elementCalls = 0, 0, 0
local function check(value, message)
    assert(value, message)
    checks = checks + 1
end
require = function() end
AdminCore = {}
local square = {}
local actor = {
    getCurrentSquare = function()
        return square
    end,
}
local other = {
    getCurrentSquare = function()
        return {}
    end,
}
getPlayer = function()
    return actor
end
getSpecificPlayer = function(index)
    return index == 0 and actor or index == 1 and other
end
local active = false
AdminCoreObserveCamera = {
    active = function()
        return active
    end,
}
ISContextMenu = {
    get = function(player, x, y)
        local context = { player = player, x = x, y = y }
        function context:addOption(text)
            self.option = { name = text }
            return self.option
        end
        return context
    end,
}
ISWorldObjectContextMenu = {
    createMenu = function(index, objects, x, y, test)
        nativeCalls = nativeCalls + 1
        assert(getSpecificPlayer(index):getCurrentSquare(), "Native getZ/has would crash")
        return test and true or "native-menu"
    end,
}
ISMenuContextWorld = {
    new = function()
        return {
            init = function() end,
            createMenu = function(index, object, objects, x, y, test)
                local result = ISWorldObjectContextMenu.createMenu(index, objects, x, y, test)
                elementCalls = elementCalls + 1
                assert(
                    getSpecificPlayer(index):getCurrentSquare(),
                    "Mod world-element pipeline would crash"
                )
                return result
            end,
        }
    end,
}
local blankMenu = {
    new = function()
        return { init = function() end }
    end,
}
ISMenuContextBuild, ISMenuContextInventory = blankMenu, blankMenu
Events = {
    OnGameStart = {
        Add = function(callback)
            callback()
        end,
    },
    OnFillInventoryObjectContextMenu = { Add = function() end },
}
dofile(game .. "/media/lua/client/Context/ISContextManager.lua")
dofile(root .. "/media/lua/client/AdminCore/ObserverWorldContext.lua")
local manager = ISContextManager.getInstance()
check(
    manager.createWorldMenu(0, {}, {}, 12, 34, false) == "native-menu",
    "Ordinary world menu passes through"
)
check(nativeCalls == 1 and elementCalls == 1, "Native and mod pipelines both run normally")
square = nil
local context = manager.createWorldMenu(0, {}, {}, 12, 34, false)
check(
    context.option.notAvailable and context.option.name:find("loading", 1, true),
    "Missing actor square gives useful disabled feedback"
)
check(context.x == 12 and context.y == 34, "Disabled menu preserves click coordinates")
check(
    nativeCalls == 1 and elementCalls == 1,
    "Neither unsafe native nor mod pipeline runs during travel"
)
check(
    manager.createWorldMenu(0, {}, {}, 12, 34, true) == false,
    "Controller test has no available action during travel"
)
check(
    ISWorldObjectContextMenu.createMenu(0, {}, 1, 2, true) == false,
    "Direct legacy calls are also guarded"
)
square, active = {}, true
context = manager.createWorldMenu(0, {}, {}, 12, 34, false)
check(
    context.option.name:find("Stop observing", 1, true),
    "Spectator cannot act at the remote camera's location"
)
check(nativeCalls == 1 and elementCalls == 1, "Spectator world interaction remains blocked")
check(
    manager.createWorldMenu(1, {}, {}, 12, 34, false) == "native-menu",
    "Another local player's menu remains available"
)
active = false
check(
    manager.createWorldMenu(0, {}, {}, 12, 34, false) == "native-menu",
    "Menu recovers after travel or observation stops"
)
check(manager.createWorldMenu(3, {}, {}, 12, 34, true) == false, "Missing local player is safe")
print("PASS: " .. checks .. " observer/travel world-context checks using the native manager")
