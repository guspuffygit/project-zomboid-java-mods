require("AdminCore/WindowSizing")
require("ISUI/UserPanel/ISUserPanelUI")
require("ISUI/UserPanel/ISSafehouseUI")
local create = ISUserPanelUI.create
function ISUserPanelUI:create()
    create(self)
    -- Vanilla only creates this button if membership exists when the panel opens.
    -- Keep the entry present so later claim sync/additions can enable it.
    if not self.safehouseBtn then
        local gap = self.ticketsBtn.y - self.factionBtn.y
        local y = self.ticketsBtn.y
        for _, child in pairs(self:getChildren()) do
            if child.y >= y then
                child:setY(child.y + gap)
            end
        end
        local b = ISButton:new(
            self.factionBtn.x,
            y,
            self.factionBtn.width,
            self.factionBtn.height,
            getText("IGUI_SafehouseUI_Safehouse"),
            self,
            ISUserPanelUI.onOptionMouseDown
        )
        b.internal = "SAFEHOUSEPANEL"
        b:initialise()
        b:instantiate()
        b.borderColor = self.buttonBorderColor
        self:addChild(b)
        self.safehouseBtn = b
        self:setHeight(self.height + gap)
    end
end
local update = ISUserPanelUI.updateButtons
function ISUserPanelUI:updateButtons()
    update(self)
    if self.safehouseBtn then
        local house = SafeHouse.hasSafehouse(self.player:getUsername())
        self.safehouseBtn:setVisible(true)
        self.safehouseBtn:setEnable(house ~= nil)
        self.safehouseBtn.tooltip = house and nil or "You do not currently belong to a safehouse."
    end
end
