require("AdminCore/WindowSizing")
require("ISUI/ISWorldObjectContextMenu")
require("Context/ISContextManager")
local C = AdminCore
if C.observerWorldContextInstalled then
    return
end
C.observerWorldContextInstalled = true

local function reason(playerIndex)
    local player = getSpecificPlayer(playerIndex)
    if not player or not player:getCurrentSquare() then
        return "World is loading after travel. Wait for your character's square to load."
    end
    if player == getPlayer() and AdminCoreObserveCamera then
        local ok, active = pcall(AdminCoreObserveCamera.active)
        if ok and active then
            return "Stop observing or use Teleport To before interacting with the world."
        end
    end
end

local function unavailable(playerIndex, x, y, test, text)
    if test then
        return false
    end
    local context = ISContextMenu.get(playerIndex, x, y)
    local option = context:addOption(text, nil, nil)
    option.notAvailable = true
    return context
end

-- Guard the complete world-menu pipeline, including mod-provided elements.
-- Native DebugContextMenu/window entries assume the actor has a current square.
-- The camera's viewed square is never a substitute for the actor's position.
local manager = ISContextManager.getInstance()
local createWorldMenu = manager.createWorldMenu
manager.createWorldMenu = function(playerIndex, object, objects, x, y, test)
    local text = reason(playerIndex)
    if text then
        return unavailable(playerIndex, x, y, test, text)
    end
    return createWorldMenu(playerIndex, object, objects, x, y, test)
end

-- Some mods call the legacy entry point directly rather than the manager.
local createMenu = ISWorldObjectContextMenu.createMenu
ISWorldObjectContextMenu.createMenu = function(playerIndex, objects, x, y, test)
    local text = reason(playerIndex)
    if text then
        return unavailable(playerIndex, x, y, test, text)
    end
    return createMenu(playerIndex, objects, x, y, test)
end
