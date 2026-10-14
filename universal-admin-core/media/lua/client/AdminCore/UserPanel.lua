require("AdminCore/WindowSizing")
require("ISUI/UserPanel/ISUserPanelUI")
require("ISUI/UserPanel/ISSafehouseUI")
if ISUserPanelUI.uacUserPanelInstalled then
    return
end
ISUserPanelUI.uacUserPanelInstalled = true
local create = ISUserPanelUI.create
function ISUserPanelUI:create()
    create(self)
    local heightChange = 0
    if self.ticketsBtn then
        local tickets = self.ticketsBtn
        local gap = self.serverOptionBtn.y - tickets.y
        for _, child in pairs(self:getChildren()) do
            if child ~= tickets and child.y > tickets.y then
                child:setY(child.y - gap)
            end
        end
        tickets:setVisible(false)
        self:removeChild(tickets)
        tickets.parent = nil
        self.ticketsBtn = nil
        heightChange = heightChange - gap
    end
    -- Vanilla only creates this button if membership exists when the panel opens.
    -- Keep the entry present so later claim sync/additions can enable it.
    if not self.safehouseBtn then
        local y = self.serverOptionBtn.y
        local gap = y - self.factionBtn.y
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
        heightChange = heightChange + gap
    end
    if heightChange ~= 0 then
        self:setHeight(self.height + heightChange)
    end
end
local update = ISUserPanelUI.updateButtons
function ISUserPanelUI:updateButtons()
    update(self)
    if self.safehouseBtn then
        local house = SafeHouse.hasSafehouse(self.player:getUsername())
        self.safehouseBtn:setVisible(true)
        self.safehouseBtn:setEnable(house ~= nil)
        self.safehouseBtn.tooltip = not house and "You do not currently belong to a safehouse."
            or nil
    end
end
