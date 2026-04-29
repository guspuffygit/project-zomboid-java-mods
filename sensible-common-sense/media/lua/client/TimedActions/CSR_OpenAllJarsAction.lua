require "TimedActions/ISBaseTimedAction"
require "CSR_Config"
require "CSR_FeatureFlags"
require "CSR_Utils"

CSR_OpenAllJarsAction = ISBaseTimedAction:derive("CSR_OpenAllJarsAction")

local function buildPayload(items)
    local ids = {}
    local types = {}
    for _, item in ipairs(items) do
        if item and item.getID then
            local resultType = CSR_Utils.getOpenJarResult(item)
            if resultType then
                ids[#ids + 1] = tostring(item:getID())
                types[#types + 1] = item:getFullType()
            end
        end
    end
    return table.concat(ids, ","), table.concat(types, ",")
end

local function resolveItems(action)
    local resolved = {}
    for _, item in ipairs(action.items or {}) do
        local itemId = item and item.getID and item:getID() or nil
        local expectedType = item and item.getFullType and item:getFullType() or nil
        local current = CSR_Utils.findInventoryItemById(action.character, itemId, expectedType) or item
        if current then
            resolved[#resolved + 1] = current
        end
    end
    action.items = resolved
end

local function addLidIfAvailable(character)
    local lidType = CSR_Utils.getJarLidType()
    if lidType then
        character:getInventory():AddItem(lidType)
    end
end

local function performLocal(action)
    resolveItems(action)
    local opened = 0

    for _, item in ipairs(action.items) do
        local newType = CSR_Utils.getOpenJarResult(item)
        if newType then
            local oldCondition = item.getCondition and item:getCondition() or nil
            item:Use()
            local openedItem = action.character:getInventory():AddItem(newType)
            if openedItem and oldCondition and openedItem.setCondition then
                openedItem:setCondition(oldCondition)
            end
            addLidIfAvailable(action.character)
            opened = opened + 1
        end
    end

    if opened > 0 then
        action.character:Say("Opened " .. opened .. " jars")
    end
end

function CSR_OpenAllJarsAction:new(character, items, label)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.items = items
    o.label = label or "Open jars"
    o.maxTime = math.max(CSR_Config.BULK_OPEN_JAR_TIME, (#items * CSR_Config.BULK_OPEN_JAR_TIME_PER_ITEM))
    o.stopOnWalk = not CSR_FeatureFlags.isWalkingActionsEnabled()
    o.stopOnRun = true
    return o
end

function CSR_OpenAllJarsAction:isValid()
    resolveItems(self)
    return self.items and #self.items > 0
end

function CSR_OpenAllJarsAction:update()
    self.character:setMetabolicTarget(Metabolics.LightDomestic)
end

function CSR_OpenAllJarsAction:start()
    resolveItems(self)
    self:setActionAnim("Loot")
    self:setOverrideHandModels(nil, nil)
    self.jobType = self.label
end

function CSR_OpenAllJarsAction:perform()
    local itemIdStr, expectedTypeStr = buildPayload(self.items)
    if itemIdStr == "" then
        ISBaseTimedAction.perform(self)
        return
    end

    if isClient() then
        sendClientCommand(self.character, "CommonSenseReborn", "OpenAllJars", {
            itemIdStr = itemIdStr,
            expectedTypeStr = expectedTypeStr,
            requestId = CSR_Utils.makeRequestId(self.character, "OpenAllJars")
        })
    else
        performLocal(self)
    end

    ISBaseTimedAction.perform(self)
end

return CSR_OpenAllJarsAction
