require "TimedActions/ISBaseTimedAction"
require "CSR_Config"
require "CSR_FeatureFlags"
require "CSR_Utils"

CSR_OpenAllCansAction = ISBaseTimedAction:derive("CSR_OpenAllCansAction")

local function buildPayload(items)
    local ids = {}
    local types = {}
    for _, item in ipairs(items) do
        if item and item.getID then
            local resultType = CSR_Utils.getOpenCanResult(item)
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

local function performLocal(action)
    resolveItems(action)
    action.tool = CSR_Utils.findInventoryItemById(action.character, action.toolId, action.toolType) or action.tool
    if not action.tool then
        return
    end
    local opened = 0
    local canInjuryChance = (SandboxVars and SandboxVars.CommonSenseReborn and SandboxVars.CommonSenseReborn.CanInjuryChance) or 0.05

    for _, item in ipairs(action.items) do
        local newType = CSR_Utils.getOpenCanResult(item)
        if newType then
            local oldCondition = item:getCondition()
            item:Use()
            local openedItem = action.character:getInventory():AddItem(newType)
            if openedItem then
                openedItem:setCondition(oldCondition)
            end
            opened = opened + 1

            if CSR_Utils.isKnifeItem(action.tool) and ZombRandFloat(0, 1) < canInjuryChance then
                local bodyDamage = action.character:getBodyDamage()
                local hand = ZombRand(2) == 0 and BodyPartType.Hand_L or BodyPartType.Hand_R
                bodyDamage:AddDamage(hand, 5)
            end
        end
    end

    if opened > 0 then
        action.tool:setCondition(math.max(0, action.tool:getCondition() - math.max(1, math.floor(opened / 5))))
        action.character:Say("Opened " .. opened .. " cans")
    end
end

function CSR_OpenAllCansAction:new(character, items, tool, label)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.items = items
    o.tool = tool
    o.toolId = tool and tool.getID and tool:getID() or nil
    o.toolType = tool and tool.getFullType and tool:getFullType() or nil
    o.label = label or "Open cans"
    o.maxTime = math.max(CSR_Config.BULK_OPEN_CAN_TIME, (#items * CSR_Config.BULK_OPEN_CAN_TIME_PER_ITEM))
    o.stopOnWalk = not CSR_FeatureFlags.isWalkingActionsEnabled()
    o.stopOnRun = true
    return o
end

function CSR_OpenAllCansAction:isValid()
    resolveItems(self)
    self.tool = CSR_Utils.findInventoryItemById(self.character, self.toolId, self.toolType) or self.tool
    return self.tool and self.tool:getCondition() > 0 and self.items and #self.items > 0
end

function CSR_OpenAllCansAction:update()
    self.character:setMetabolicTarget(Metabolics.LightDomestic)
end

function CSR_OpenAllCansAction:start()
    resolveItems(self)
    self.tool = CSR_Utils.findInventoryItemById(self.character, self.toolId, self.toolType) or self.tool
    self:setActionAnim("Eat")
    self:setOverrideHandModels(self.tool, nil)
    self.jobType = self.label
end

function CSR_OpenAllCansAction:perform()
    local itemIdStr, expectedTypeStr = buildPayload(self.items)
    if itemIdStr == "" then
        ISBaseTimedAction.perform(self)
        return
    end

    if isClient() then
        sendClientCommand(self.character, "CommonSenseReborn", "OpenAllCans", {
            itemIdStr = itemIdStr,
            expectedTypeStr = expectedTypeStr,
            toolId = self.tool:getID(),
            requestId = CSR_Utils.makeRequestId(self.character, "OpenAllCans")
        })
    else
        performLocal(self)
    end

    ISBaseTimedAction.perform(self)
end

return CSR_OpenAllCansAction
