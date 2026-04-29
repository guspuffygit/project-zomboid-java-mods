require "CSR_FeatureFlags"

CSR_WalkingActions = {}

local function walkingEnabled()
    return CSR_FeatureFlags and CSR_FeatureFlags.isWalkingActionsEnabled and CSR_FeatureFlags.isWalkingActionsEnabled()
end

local function patchWearClothing()
    if not ISWearClothing or type(ISWearClothing.new) ~= "function" or ISWearClothing.__CSRWalkingPatched then
        return
    end

    local oldIsStopOnWalk = ISWearClothing.isStopOnWalk
    ISWearClothing.isStopOnWalk = function(item)
        if walkingEnabled() then
            return false
        end
        if oldIsStopOnWalk then
            return oldIsStopOnWalk(item)
        end
        return true
    end

    local oldNew = ISWearClothing.new
    ISWearClothing.new = function(self, character, item, ...)
        local o = oldNew(self, character, item, ...)
        if type(o) == "table" and walkingEnabled() then
            o.stopOnWalk = false
            o.stopOnRun = true
            o.__CSRWalkingAction = true
        end
        return o
    end

    ISWearClothing.__CSRWalkingPatched = true
end

local function patchUnequip()
    if not ISUnequipAction or type(ISUnequipAction.new) ~= "function" or ISUnequipAction.__CSRWalkingPatched then
        return
    end

    local oldNew = ISUnequipAction.new
    ISUnequipAction.new = function(self, character, item, maxTime, ...)
        local o = oldNew(self, character, item, maxTime, ...)
        if type(o) == "table" and walkingEnabled() then
            o.stopOnWalk = false
            o.stopOnRun = true
            o.__CSRWalkingAction = true
        end
        return o
    end

    ISUnequipAction.__CSRWalkingPatched = true
end

local function patchCraftAction()
    if not ISCraftAction or type(ISCraftAction.new) ~= "function" or ISCraftAction.__CSRWalkingPatched then
        return
    end

    local oldNew = ISCraftAction.new
    ISCraftAction.new = function(self, character, item, recipe, container, containersIn, ...)
        local o = oldNew(self, character, item, recipe, container, containersIn, ...)
        if type(o) == "table" and walkingEnabled() then
            o.stopOnWalk = false
            o.stopOnRun = true
            o.__CSRWalkingAction = true
        end
        return o
    end

    ISCraftAction.__CSRWalkingPatched = true
end

local function patchHandcraftAction()
    if not ISHandcraftAction or type(ISHandcraftAction.new) ~= "function" or ISHandcraftAction.__CSRWalkingPatched then
        return
    end

    local oldNew = ISHandcraftAction.new
    ISHandcraftAction.new = function(self, character, craftRecipe, containers, isoObject, craftBench, manualInputs, items, recipeItem, variableInputRatio, eatPercentage, ...)
        local o = oldNew(self, character, craftRecipe, containers, isoObject, craftBench, manualInputs, items, recipeItem, variableInputRatio, eatPercentage, ...)
        if type(o) == "table" and walkingEnabled() then
            o.stopOnWalk = false
            o.stopOnRun = true
            o.__CSRWalkingAction = true
        end
        return o
    end

    ISHandcraftAction.__CSRWalkingPatched = true
end

local function hookSprintStop()
    if CSR_WalkingActions._sprintHooked or not Events or not Events.OnPlayerUpdate then
        return
    end

    CSR_WalkingActions._sprintHooked = true
    Events.OnPlayerUpdate.Add(function(player)
        if not walkingEnabled() or not player or player:isDead() then
            return
        end

        if not ISTimedActionQueue or not ISTimedActionQueue.getTimedActionQueue then
            return
        end

        local queue = ISTimedActionQueue.getTimedActionQueue(player)
        if not queue or not queue.queue or not queue.queue[1] then
            return
        end

        local action = queue.queue[1]
        if not action.__CSRWalkingAction then
            return
        end

        if player.isSprinting and player:isSprinting() then
            if action.stop then
                action:stop()
            end
        end
    end)
end

function CSR_WalkingActions.tryPatch()
    patchWearClothing()
    patchUnequip()
    patchCraftAction()
    patchHandcraftAction()
    -- Patch reading actions to allow walking while reading
    local function patchReadAction(className)
        local action = _G[className]
        if not action or type(action.new) ~= "function" or action["__CSRWalkingPatched"] then
            return
        end
        local oldNew = action.new
        action.new = function(self, character, item, ...)
            local o = oldNew(self, character, item, ...)
            if type(o) == "table" and walkingEnabled() then
                o.stopOnWalk = false
                o.stopOnRun = true
                o.__CSRWalkingAction = true
            end
            return o
        end
        action["__CSRWalkingPatched"] = true
    end

    patchReadAction("ISReadABook")
    patchReadAction("ISReadMagazine")
    patchReadAction("ISReadNewspaper")
    patchReadAction("ISReadComic")
    patchReadAction("ISReadMap")

    -- Inventory transfer walking patch disabled — vanilla isValid() checks container
    -- proximity which fails while walking, causing "bugged action, cleared queue"

    hookSprintStop()
end

Events.OnGameStart.Add(CSR_WalkingActions.tryPatch)

return CSR_WalkingActions
