require "TimedActions/ISBaseTimedAction"
require "CSR_Config"
require "CSR_FeatureFlags"
require "CSR_Utils"

CSR_BarricadeAction = ISBaseTimedAction:derive("CSR_BarricadeAction")

local function performLocal(action)
    if not action.window or not action.plank or not IsoBarricade or not IsoBarricade.AddBarricadeToObject then
        return
    end

    local barricade = IsoBarricade.AddBarricadeToObject(action.window, action.character)
    if not barricade then
        return
    end

    local container = action.plank.getContainer and action.plank:getContainer() or action.character:getInventory()
    if container then
        if container.DoRemoveItem then
            container:DoRemoveItem(action.plank)
        else
            container:Remove(action.plank)
        end
    end

    barricade:addPlank(action.character, action.plank)
    if barricade.transmitCompleteItemToClients then
        barricade:transmitCompleteItemToClients()
    end
end

function CSR_BarricadeAction:new(character, window, plank)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.window = window
    o.plank = plank
    o.maxTime = CSR_Config.BARRICADE_TIME
    o.stopOnWalk = not CSR_FeatureFlags.isWalkingActionsEnabled()
    o.stopOnRun = true
    return o
end

function CSR_BarricadeAction:isValid()
    if not self.character or not self.window or not self.plank then
        return false
    end

    if not instanceof(self.window, "IsoWindow") then
        return false
    end

    if CSR_Utils.isBarricadedForPlayer(self.window, self.character) then
        return false
    end

    if self.window.isBarricadeAllowed and self.window:isBarricadeAllowed() == false then
        return false
    end

    local square = self.window.getSquare and self.window:getSquare() or nil
    if not square then
        return false
    end

    return self.character:DistToSquared(square:getX() + 0.5, square:getY() + 0.5) <= 4
end

function CSR_BarricadeAction:update()
    self.character:faceThisObject(self.window)
    self.character:setMetabolicTarget(Metabolics.LightWork)
end

function CSR_BarricadeAction:start()
    self:setActionAnim("Build")
    self:setOverrideHandModels(self.plank, nil)
end

function CSR_BarricadeAction:perform()
    if isClient() then
        local square = self.window:getSquare()
        local sprite = self.window.getSprite and self.window:getSprite() and self.window:getSprite():getName() or ""
        sendClientCommand(self.character, "CommonSenseReborn", "BarricadeWindow", {
            x = square:getX(),
            y = square:getY(),
            z = square:getZ(),
            objectIndex = self.window.getObjectIndex and self.window:getObjectIndex() or -1,
            sprite = sprite,
            plankId = self.plank.getID and self.plank:getID() or nil,
            requestId = CSR_Utils.makeRequestId(self.character, "BarricadeWindow"),
            requestTimestamp = getTimestampMs and getTimestampMs() or os.time() * 1000,
        })
    else
        performLocal(self)
    end

    ISBaseTimedAction.perform(self)
end

return CSR_BarricadeAction
