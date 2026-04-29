require "CSR_FeatureFlags"

--[[
    CSR_WarmUp.lua
    Context menu option to warm hands when the player is cold and getting colder.
    Uses vanilla WarmHands animation. Blocked by hand injuries.
]]

local function onWorldContext(playerNum, context, worldObjects, test)
    if test then return end
    if not CSR_FeatureFlags.isWarmUpEnabled() then return end

    local player = getSpecificPlayer(playerNum)
    if not player or player:isDead() or player:isDriving() then return end

    local thermos = player:getBodyDamage() and player:getBodyDamage():getThermoregulator()
    if not thermos then return end

    local coreTemp = thermos:getCoreTemperature()
    if coreTemp >= 36.6 or thermos:getCoreHeatDelta() > 0 then return end

    local option = context:addOption("Warm Up", worldObjects, function()
        local primary = player:getPrimaryHandItem()
        local secondary = player:getSecondaryHandItem()
        if primary then
            ISTimedActionQueue.add(ISUnequipAction:new(player, primary, 50))
        end
        if secondary and secondary ~= primary then
            ISTimedActionQueue.add(ISUnequipAction:new(player, secondary, 50))
        end
        ISTimedActionQueue.add(CSR_WarmUpAction:new(player))
    end)

    local leftHand = player:getBodyDamage():getBodyPart(BodyPartType.Hand_L)
    local rightHand = player:getBodyDamage():getBodyPart(BodyPartType.Hand_R)
    if (leftHand and leftHand:HasInjury()) or (rightHand and rightHand:HasInjury()) then
        option.notAvailable = true
        local tooltip = ISWorldObjectContextMenu.addToolTip()
        tooltip.description = "Your hands are injured. You can't rub them together."
        option.toolTip = tooltip
    else
        local tooltip = ISWorldObjectContextMenu.addToolTip()
        local tempStr = string.format("%.1f", coreTemp)
        tooltip.description = "Rub your hands together to warm up. <LINE> <LINE> Core temp: <RGB:1,0.6,0.3> " .. tempStr .. " C <RGB:1,1,1> <LINE> Unequips held items first. <LINE> You can walk while warming up."
        option.toolTip = tooltip
    end
end

Events.OnFillWorldObjectContextMenu.Add(onWorldContext)
