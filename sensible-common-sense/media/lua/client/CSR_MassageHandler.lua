require "CSR_FeatureFlags"
require "CSR_Utils"

local _installed = false

local function installMassageHandler()
    if _installed then return end
    if not ISHealthPanel or not ISHealthPanel.doBodyPartContextMenu then return end
    _installed = true

    local _origDoBodyPartContextMenu = ISHealthPanel.doBodyPartContextMenu

    function ISHealthPanel:doBodyPartContextMenu(bodyPart, x, y)
        _origDoBodyPartContextMenu(self, bodyPart, x, y)

        if not CSR_FeatureFlags.isMassageEnabled() then return end
        if not isClient() then return end -- MP only

        -- Only available when examining another player (otherPlayer = the one doing the action)
        local doctor = self.otherPlayer
        local patient = self.character
        if not doctor or doctor == patient then return end

        -- Check body part has muscle strain
        if not CSR_MassageAction then
            require "TimedActions/CSR_MassageAction"
        end
        if not CSR_MassageAction or not CSR_MassageAction.hasStrain(bodyPart) then return end

        -- Check doctor has oil or butter
        local oil = CSR_MassageAction.findOilOrButter(doctor)

        local playerNum = doctor:getPlayerNum()
        local context = getPlayerContextMenu(playerNum)
        if not context then return end

        local stiffness = bodyPart.getStiffness and math.floor(bodyPart:getStiffness()) or 0
        local text = "Massage"

        local function onMassage()
            local currentOil = CSR_MassageAction.findOilOrButter(doctor)
            if currentOil and CSR_MassageAction then
                ISTimedActionQueue.add(CSR_MassageAction:new(doctor, patient, bodyPart, currentOil))
            end
        end

        local option = context:addOption(text, self, onMassage)

        local tooltip = ISToolTip:new()
        tooltip:initialise()
        tooltip:setVisible(false)

        local desc = "Massage this body part to relieve muscle strain."
            .. " <LINE> <LINE> <RGB:0.7,0.7,0.7> Requires: Butter or Cooking Oil"
            .. " <LINE> Strain level: " .. stiffness
        if oil then
            desc = desc .. " <LINE> <RGB:0.5,1,0.5> Using: " .. oil:getDisplayName()
        else
            desc = desc .. " <LINE> <RGB:1,0.4,0.4> No oil or butter available!"
            option.notAvailable = true
        end

        tooltip.description = desc
        option.toolTip = tooltip
    end
end

if Events then
    if Events.OnGameStart then Events.OnGameStart.Add(installMassageHandler) end
    if Events.OnCreatePlayer then Events.OnCreatePlayer.Add(installMassageHandler) end
end
