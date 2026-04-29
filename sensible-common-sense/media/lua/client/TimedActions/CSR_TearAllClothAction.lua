require "TimedActions/ISBaseTimedAction"
require "CSR_Utils"
require "CSR_Config"
require "CSR_FeatureFlags"

CSR_TearAllClothAction = ISBaseTimedAction:derive("CSR_TearAllClothAction")

local function resolveInventoryItem(character, itemId, expectedType)
    local inventory = character and character.getInventory and character:getInventory() or nil
    local items = inventory and inventory.getItems and inventory:getItems() or nil
    if not items then
        return nil
    end

    local fallback = nil
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item then
            if itemId ~= nil and item.getID and item:getID() == itemId then
                if not expectedType or (item.getFullType and item:getFullType() == expectedType) then
                    return item
                end
            end
            if not fallback and expectedType and item.getFullType and item:getFullType() == expectedType then
                fallback = item
            end
        end
    end

    return fallback
end

local function resolveActionItems(action)
    local resolved = {}
    for _, item in ipairs(action.items or {}) do
        local itemId = item and item.getID and item:getID() or nil
        local expectedType = item and item.getFullType and item:getFullType() or nil
        local current = resolveInventoryItem(action.character, itemId, expectedType) or item
        if current then
            table.insert(resolved, current)
        end
    end
    action.items = resolved
    return resolved
end

local function buildPayload(items)
    local ids = {}
    local expected = {}
    local outputs = {}
    local qtys = {}
    for _, item in ipairs(items) do
        local tearInfo = CSR_Utils.getTearClothInfo(item)
        if item and item.getID and tearInfo then
            ids[#ids + 1] = tostring(item:getID())
            expected[#expected + 1] = item:getFullType()
            outputs[#outputs + 1] = tearInfo.outputType
            qtys[#qtys + 1] = tostring(tearInfo.quantity)
        end
    end
    return table.concat(ids, ","), table.concat(expected, ","), table.concat(outputs, ","), table.concat(qtys, ",")
end

local function performLocal(action)
    local torn = 0
    for _, item in ipairs(resolveActionItems(action)) do
        local tearInfo = CSR_Utils.getTearClothInfo(item)
        if tearInfo then
            local container = item.getContainer and item:getContainer() or action.character:getInventory()
            if container then
                if container.DoRemoveItem then
                    container:DoRemoveItem(item)
                else
                    container:Remove(item)
                end
            end
            for _ = 1, tearInfo.quantity do
                action.character:getInventory():AddItem(tearInfo.outputType)
            end
            torn = torn + 1
        end
    end

    if action.tool and torn > 0 and action.tool.getCondition and action.tool.setCondition then
        action.tool:setCondition(math.max(0, action.tool:getCondition() - math.max(1, math.floor(torn / 3))))
    end

    if torn > 0 then
        action.character:Say("Tore " .. torn .. " clothing items into material")
    end
end

function CSR_TearAllClothAction:new(character, items, label, tool)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.items = items
    o.label = label or "Tear cloth"
    o.tool = tool
    o.maxTime = math.max(CSR_Config.CLOTH_TEAR_TIME, (#items * CSR_Config.BULK_CLOTH_TEAR_TIME_PER_ITEM))
    o.stopOnWalk = not CSR_FeatureFlags.isWalkingActionsEnabled()
    o.stopOnRun = true
    return o
end

function CSR_TearAllClothAction:isValid()
    local items = resolveActionItems(self)
    if not items or #items <= 0 then
        return false
    end

    for _, item in ipairs(items) do
        if not CSR_Utils.canTearCloth(item, self.character) then
            return false
        end
    end

    return true
end

function CSR_TearAllClothAction:update()
    self.character:setMetabolicTarget(Metabolics.LightDomestic)
end

function CSR_TearAllClothAction:start()
    resolveActionItems(self)
    self:setActionAnim("Loot")
    self.jobType = self.label
    self:setOverrideHandModels(self.tool, nil)
end

function CSR_TearAllClothAction:perform()
    resolveActionItems(self)
    local itemIdStr, expectedTypeStr, outputTypeStr, quantityStr = buildPayload(self.items)
    if itemIdStr == "" then
        ISBaseTimedAction.perform(self)
        return
    end

    if isClient() then
        sendClientCommand(self.character, "CommonSenseReborn", "TearAllCloth", {
            itemIdStr = itemIdStr,
            expectedTypeStr = expectedTypeStr,
            outputTypeStr = outputTypeStr,
            quantityStr = quantityStr,
            toolId = self.tool and self.tool:getID() or nil,
            requestId = CSR_Utils.makeRequestId(self.character, "TearAllCloth")
        })
    else
        performLocal(self)
    end

    ISBaseTimedAction.perform(self)
end

return CSR_TearAllClothAction
