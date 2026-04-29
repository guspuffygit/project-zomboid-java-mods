require "CSR_FeatureFlags"

local function hideWatermark()
    if not CSR_FeatureFlags.isHideWatermarkEnabled() then
        return
    end

    Events.OnGameStart.Remove(ISVersionWaterMark.doMsg)

    WaterMarkUI.render = function(self)
        ISPanel.render(self)
    end

    ISVersionWaterMark.doMsg = function()
        local panel = WaterMarkUI:new(0, 0, 0, 0)
        panel:initialise()
        panel:addToUIManager()
        panel:setVisible(false)
    end
end

if Events and Events.OnGameStart then
    Events.OnGameStart.Add(hideWatermark)
end
