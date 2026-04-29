require "TimedActions/ISBaseTimedAction"
require "CSR_Config"
require "CSR_FeatureFlags"
require "CSR_Utils"

CSR_OpenAmmoBoxAction = ISBaseTimedAction:derive("CSR_OpenAmmoBoxAction")

local function performLocal(action)
    local box = CSR_Utils.findInventoryItemById(action.character, action.boxId, action.boxType) or action.box
    if not box or not CSR_Utils.isAmmoBox(box) then return end
    local info = CSR_Utils.getAmmoBoxInfo(box)
    if not info then return end

    local container = box:getContainer()
    if not container then return end

    container:Remove(box)
    local rounds = container:AddItems(info.round, info.count)
    container:setDrawDirty(true)

    if rounds and rounds:size() > 0 then
        action.character:Say("Opened box: " .. info.count .. " rounds")
    end
end

function CSR_OpenAmmoBoxAction:new(character, box)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.box = box
    o.boxId = box and box.getID and box:getID() or nil
    o.boxType = box and box.getFullType and box:getFullType() or nil
    o.maxTime = CSR_Config.OPEN_AMMO_BOX_TIME
    o.stopOnWalk = not CSR_FeatureFlags.isWalkingActionsEnabled()
    o.stopOnRun = true
    return o
end

function CSR_OpenAmmoBoxAction:isValid()
    local box = CSR_Utils.findInventoryItemById(self.character, self.boxId, self.boxType) or self.box
    return box and CSR_Utils.isAmmoBox(box)
end

function CSR_OpenAmmoBoxAction:update()
    self.character:setMetabolicTarget(Metabolics.LightDomestic)
end

function CSR_OpenAmmoBoxAction:start()
    self.box = CSR_Utils.findInventoryItemById(self.character, self.boxId, self.boxType) or self.box
    if self.stopOnWalk then
        self:setActionAnim("Loot")
    end
    self.jobType = "Open Ammo Box"
end

function CSR_OpenAmmoBoxAction:perform()
    print("[CSR] OpenAmmoBoxAction:perform() isClient=" .. tostring(isClient()) .. " boxId=" .. tostring(self.boxId))
    if isClient() then
        sendClientCommand(self.character, "CommonSenseReborn", "OpenAmmoBox", {
            boxId = self.boxId,
            boxType = self.boxType,
            requestId = CSR_Utils.makeRequestId(self.character, "OpenAmmoBox"),
        })
    else
        performLocal(self)
    end
    ISBaseTimedAction.perform(self)
end

return CSR_OpenAmmoBoxAction
