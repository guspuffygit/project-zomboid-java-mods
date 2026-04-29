require "TimedActions/ISBaseTimedAction"
require "CSR_Config"
require "CSR_FeatureFlags"
require "CSR_Utils"

CSR_OpenAllAmmoBoxesAction = ISBaseTimedAction:derive("CSR_OpenAllAmmoBoxesAction")

local function resolveBoxes(action)
    local resolved = {}
    for _, box in ipairs(action.boxes or {}) do
        local id = box and box.getID and box:getID() or nil
        local ft = box and box.getFullType and box:getFullType() or nil
        local current = CSR_Utils.findInventoryItemById(action.character, id, ft) or box
        if current and CSR_Utils.isAmmoBox(current) then
            resolved[#resolved + 1] = current
        end
    end
    action.boxes = resolved
end

local function performLocal(action)
    resolveBoxes(action)
    local totalRounds = 0
    local boxCount = 0
    for _, box in ipairs(action.boxes) do
        local info = CSR_Utils.getAmmoBoxInfo(box)
        if info then
            local container = box:getContainer()
            if container then
                container:Remove(box)
                container:AddItems(info.round, info.count)
                container:setDrawDirty(true)
                totalRounds = totalRounds + info.count
                boxCount = boxCount + 1
            end
        end
    end
    if totalRounds > 0 then
        action.character:Say("Opened " .. boxCount .. " boxes: " .. totalRounds .. " rounds")
    end
end

function CSR_OpenAllAmmoBoxesAction:new(character, boxes, label)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.boxes = boxes
    o.label = label or "Open ammo boxes"
    o.maxTime = math.max(CSR_Config.OPEN_AMMO_BOX_TIME, #boxes * CSR_Config.BULK_OPEN_AMMO_BOX_TIME_PER_ITEM)
    o.stopOnWalk = not CSR_FeatureFlags.isWalkingActionsEnabled()
    o.stopOnRun = true
    return o
end

function CSR_OpenAllAmmoBoxesAction:isValid()
    resolveBoxes(self)
    return self.boxes and #self.boxes > 0
end

function CSR_OpenAllAmmoBoxesAction:update()
    self.character:setMetabolicTarget(Metabolics.LightDomestic)
end

function CSR_OpenAllAmmoBoxesAction:start()
    resolveBoxes(self)
    if self.stopOnWalk then
        self:setActionAnim("Loot")
    end
    self.jobType = self.label
end

function CSR_OpenAllAmmoBoxesAction:perform()
    if isClient() then
        local ids = {}
        local types = {}
        for _, box in ipairs(self.boxes) do
            if box and box.getID and box.getFullType then
                ids[#ids + 1] = tostring(box:getID())
                types[#types + 1] = box:getFullType()
            end
        end
        sendClientCommand(self.character, "CommonSenseReborn", "OpenAllAmmoBoxes", {
            boxIdStr = table.concat(ids, ","),
            boxTypeStr = table.concat(types, ","),
            requestId = CSR_Utils.makeRequestId(self.character, "OpenAllAmmoBoxes"),
        })
    else
        performLocal(self)
    end
    ISBaseTimedAction.perform(self)
end

return CSR_OpenAllAmmoBoxesAction
