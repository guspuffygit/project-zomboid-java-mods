require "ISUI/AdminPanel/ZoneEditor/ISMultiplayerZoneEditor"
require "ZoneMarkerEditorMode"

local MODE_NAME = "ZoneMarker"
local MODE_LABEL = "Zone Marker"

--
-- Patch createChildren to register our mode
--
local originalCreateChildren = ISMultiplayerZoneEditor.createChildren

function ISMultiplayerZoneEditor:createChildren()
    originalCreateChildren(self)

    self.modeCombo:addOptionWithData(MODE_LABEL, MODE_NAME)
    self.mode[MODE_NAME] = MultiplayerZoneEditorMode_ZoneMarker:new(self)
    self:addChild(self.mode[MODE_NAME])
    self.mode[MODE_NAME]:setVisible(false)
end

--
-- Patch OnRolesReceived to include our mode in the capability check
--
local originalOnRolesReceived = ISMultiplayerZoneEditor.OnRolesReceived

function ISMultiplayerZoneEditor.OnRolesReceived()
    originalOnRolesReceived()

    if ISMultiplayerZoneEditor_instance then
        -- Add our mode for any player with debug console access
        if getPlayer():getRole():hasCapability(Capability.CanUseDebugConsole) then
            ISMultiplayerZoneEditor_instance.modeCombo:addOptionWithData(MODE_LABEL, MODE_NAME)
        end
    end
end
