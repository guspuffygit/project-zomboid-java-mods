require "TimedActions/ISBaseTimedAction"
require "CSR_Config"
require "CSR_FeatureFlags"
require "CSR_Utils"

CSR_DismantleAllWatchesAction = ISBaseTimedAction:derive("CSR_DismantleAllWatchesAction")

local DISMANTLE_TIME_PER_WATCH = 60
local DISMANTLE_BASE_TIME = 120
local XP_PER_WATCH = 3
local SCRAP_PER_WATCH = 1

local WATCH_TYPES = {
    -- B42 standalone clocks
    ["AlarmClock2"] = true,
    ["Pocketwatch"] = true,
    -- B42 wristwatches (digital)
    ["WristWatch_Right_DigitalBlack"] = true,
    ["WristWatch_Left_DigitalBlack"] = true,
    ["WristWatch_Right_DigitalRed"] = true,
    ["WristWatch_Left_DigitalRed"] = true,
    ["WristWatch_Right_DigitalDress"] = true,
    ["WristWatch_Left_DigitalDress"] = true,
    -- B42 wristwatches (analog)
    ["WristWatch_Right_ClassicBlack"] = true,
    ["WristWatch_Left_ClassicBlack"] = true,
    ["WristWatch_Right_ClassicBrown"] = true,
    ["WristWatch_Left_ClassicBrown"] = true,
    ["WristWatch_Right_ClassicMilitary"] = true,
    ["WristWatch_Left_ClassicMilitary"] = true,
    ["WristWatch_Right_ClassicGold"] = true,
    ["WristWatch_Left_ClassicGold"] = true,
    ["WristWatch_Right_Expensive"] = true,
    ["WristWatch_Left_Expensive"] = true,
}

function CSR_DismantleAllWatchesAction.isWatchItem(item)
    if not item then return false end
    return WATCH_TYPES[item:getType()] == true
end

function CSR_DismantleAllWatchesAction.findAllWatches(player)
    local watches = {}
    local inv = player:getInventory()
    if not inv then return watches end
    local items = inv:getItems()
    if not items then return watches end
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item and WATCH_TYPES[item:getType()] then
            watches[#watches + 1] = item
        end
    end
    return watches
end

local function buildPayload(items)
    local ids = {}
    for _, item in ipairs(items) do
        if item and item.getID then
            ids[#ids + 1] = tostring(item:getID())
        end
    end
    return table.concat(ids, ",")
end

local function resolveItems(action)
    local resolved = {}
    for _, item in ipairs(action.items or {}) do
        local itemId = item and item.getID and item:getID() or nil
        local current = CSR_Utils.findInventoryItemById(action.character, itemId) or item
        if current and WATCH_TYPES[current:getType()] then
            resolved[#resolved + 1] = current
        end
    end
    action.items = resolved
end

local function performLocal(action)
    resolveItems(action)
    action.tool = CSR_Utils.findInventoryItemById(action.character, action.toolId, action.toolType) or action.tool
    if not action.tool then return end

    local dismantled = 0
    local inv = action.character:getInventory()

    for _, item in ipairs(action.items) do
        if item and WATCH_TYPES[item:getType()] then
            inv:Remove(item)
            for _ = 1, SCRAP_PER_WATCH do
                inv:AddItem("Base.ElectronicsScrap")
            end
            dismantled = dismantled + 1
        end
    end

    if dismantled > 0 then
        local wear = math.max(1, math.floor(dismantled / 4))
        action.tool:setCondition(math.max(0, action.tool:getCondition() - wear))
        local xpGained = dismantled * XP_PER_WATCH
        addXp(action.character, Perks.Electricity, xpGained)
        action.character:Say("Dismantled " .. dismantled .. " watches (+" .. xpGained .. " XP)")
    end
end

function CSR_DismantleAllWatchesAction:new(character, items, tool, label)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.items = items
    o.tool = tool
    o.toolId = tool and tool.getID and tool:getID() or nil
    o.toolType = tool and tool.getFullType and tool:getFullType() or nil
    o.label = label or "Dismantle watches"
    o.maxTime = math.max(DISMANTLE_BASE_TIME, (#items * DISMANTLE_TIME_PER_WATCH))
    o.stopOnWalk = true
    o.stopOnRun = true
    return o
end

function CSR_DismantleAllWatchesAction:isValid()
    resolveItems(self)
    self.tool = CSR_Utils.findInventoryItemById(self.character, self.toolId, self.toolType) or self.tool
    return self.tool and self.tool:getCondition() > 0 and self.items and #self.items > 0
end

function CSR_DismantleAllWatchesAction:update()
    self.character:setMetabolicTarget(Metabolics.LightDomestic)
end

function CSR_DismantleAllWatchesAction:start()
    resolveItems(self)
    self.tool = CSR_Utils.findInventoryItemById(self.character, self.toolId, self.toolType) or self.tool
    self:setActionAnim("Disassemble")
    self:setOverrideHandModels(self.tool, self.items and self.items[1] or nil)
    self.jobType = self.label
end

function CSR_DismantleAllWatchesAction:stop()
    ISBaseTimedAction.stop(self)
end

function CSR_DismantleAllWatchesAction:perform()
    if isClient() then
        local itemIdStr = buildPayload(self.items)
        if itemIdStr == "" then
            ISBaseTimedAction.perform(self)
            return
        end
        sendClientCommand(self.character, "CommonSenseReborn", "DismantleAllWatches", {
            itemIdStr = itemIdStr,
            toolId = self.tool:getID(),
            requestId = CSR_Utils.makeRequestId(self.character, "DismantleAllWatches")
        })
        -- XP and feedback are awarded server-side via handleDismantleAllWatches
        -- (Journals XP pattern: server-authoritative addXp after sendClientCommand).
    else
        performLocal(self)
    end

    ISBaseTimedAction.perform(self)
end

return CSR_DismantleAllWatchesAction
