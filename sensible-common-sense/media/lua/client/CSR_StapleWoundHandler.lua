require "CSR_FeatureFlags"
require "CSR_Utils"
require "CSR_Config"

local _installed = false

local function installStapleHandler()
    if _installed then return end
    if not ISHealthPanel or not ISHealthPanel.doBodyPartContextMenu then return end
    _installed = true

    local _origDoBodyPartContextMenu = ISHealthPanel.doBodyPartContextMenu

    function ISHealthPanel:doBodyPartContextMenu(bodyPart, x, y)
        _origDoBodyPartContextMenu(self, bodyPart, x, y)

        if not CSR_FeatureFlags.isEquipmentQoLEnabled() then return end
        if not CSR_Utils.canStapleWound(bodyPart) then return end

        local doctor = self.otherPlayer or self.character
        local patient = self.character
        local stapler = CSR_Utils.findStapler(doctor)
        local staples = CSR_Utils.findStaples(doctor)

        if not stapler or not staples then return end

        local playerNum = self.otherPlayer and self.otherPlayer:getPlayerNum() or self.character:getPlayerNum()
        local context = getPlayerContextMenu(playerNum)
        if not context then return end

        local woundType = bodyPart:isDeepWounded() and "deep wound" or (bodyPart:isCut() and "laceration" or "scratch")
        local stapleDelta = (staples.getCurrentUsesFloat and staples:getCurrentUsesFloat()) or (staples.getDelta and staples:getDelta()) or 0
        local staplePct = math.floor(stapleDelta * 100)
        local text = "Staple " .. woundType

        local function onStapleWound()
            if not CSR_StapleWoundAction then
                require "TimedActions/CSR_StapleWoundAction"
            end
            if CSR_StapleWoundAction then
                ISTimedActionQueue.add(CSR_StapleWoundAction:new(doctor, patient, bodyPart))
            end
        end

        local option = context:addOption(text, self, onStapleWound)

        local tooltip = ISToolTip:new()
        tooltip:initialise()
        tooltip:setVisible(false)
        tooltip.description = "Use a stapler to quickly close the " .. woundType .. "."
            .. " <LINE> <LINE> <RGB:1,0.6,0.2> Warning: Higher risk of infection than suturing."
            .. " <LINE> <RGB:0.7,0.7,0.7> Staples remaining: " .. staplePct .. "%"
            .. " <LINE> Pain: Moderate to High"
        option.toolTip = tooltip
    end
end

if Events then
    if Events.OnGameStart then Events.OnGameStart.Add(installStapleHandler) end
    if Events.OnCreatePlayer then Events.OnCreatePlayer.Add(installStapleHandler) end
end
