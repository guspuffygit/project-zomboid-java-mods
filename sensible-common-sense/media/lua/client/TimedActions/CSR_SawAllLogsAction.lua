require "TimedActions/ISBaseTimedAction"
require "CSR_Config"
require "CSR_FeatureFlags"
require "CSR_Utils"

CSR_SawAllLogsAction = ISBaseTimedAction:derive("CSR_SawAllLogsAction")

local SAW_TIME_PER_LOG = 80
local SAW_BASE_TIME = 120
local PLANKS_PER_LOG = 3
local XP_PER_LOG = 5

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
        local current = CSR_Utils.findInventoryItemById(action.character, itemId, "Base.Log") or item
        if current and current:getFullType() == "Base.Log" then
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

    local sawed = 0
    local inv = action.character:getInventory()

    local dropToGround = CSR_FeatureFlags.isSawAllDropToGroundEnabled()
    local square = dropToGround and action.character:getCurrentSquare() or nil

    for _, item in ipairs(action.items) do
        if item and item:getFullType() == "Base.Log" then
            inv:Remove(item)
            for _ = 1, PLANKS_PER_LOG do
                if dropToGround and square then
                    local plank = instanceItem("Base.Plank")
                    square:AddWorldInventoryItem(plank, 0.0, 0.0, 0.0)
                else
                    inv:AddItem("Base.Plank")
                end
            end
            sawed = sawed + 1
        end
    end

    if sawed > 0 then
        -- Degrade saw: ~1 condition per 3 logs (light degradation as per vanilla MayDegradeLight)
        local wear = math.max(1, math.floor(sawed / 3))
        action.tool:setCondition(math.max(0, action.tool:getCondition() - wear))

        -- Award carpentry XP
        local xpGained = sawed * XP_PER_LOG
        addXp(action.character, Perks.Woodwork, xpGained)

        action.character:Say("Sawed " .. sawed .. " logs into planks (+" .. xpGained .. " XP)")
    end
end

function CSR_SawAllLogsAction:new(character, items, tool, label)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.items = items
    o.tool = tool
    o.toolId = tool and tool.getID and tool:getID() or nil
    o.toolType = tool and tool.getFullType and tool:getFullType() or nil
    o.label = label or "Saw logs"
    o.maxTime = math.max(SAW_BASE_TIME, (#items * SAW_TIME_PER_LOG))
    o.stopOnWalk = true
    o.stopOnRun = true
    return o
end

function CSR_SawAllLogsAction:isValid()
    resolveItems(self)
    self.tool = CSR_Utils.findInventoryItemById(self.character, self.toolId, self.toolType) or self.tool
    return self.tool and self.tool:getCondition() > 0 and self.items and #self.items > 0
end

function CSR_SawAllLogsAction:update()
    self.character:setMetabolicTarget(Metabolics.HeavyDomestic)
    self.gruntTimer = (self.gruntTimer or 0) + 1
    if self.gruntTimer >= 100 then
        self.gruntTimer = 0
        local voiceSound = self.character:isFemale() and "VoiceFemaleExercise" or "VoiceMaleExercise"
        self.character:playSound(voiceSound)
    end
end

function CSR_SawAllLogsAction:start()
    resolveItems(self)
    self.tool = CSR_Utils.findInventoryItemById(self.character, self.toolId, self.toolType) or self.tool
    -- Prop1 = saw (primary hand), Prop2 = first log (placed on ground by SawLog anim)
    local displayLog = self.items and self.items[1] or nil
    self:setActionAnim("SawLog")
    self:setOverrideHandModels(self.tool, displayLog)
    self.jobType = self.label
    self.gruntTimer = 0
    self.sound = self.character:playSound("Sawing")
end

function CSR_SawAllLogsAction:stop()
    if self.sound and self.character:getEmitter():isPlaying(self.sound) then
        self.character:getEmitter():stopSound(self.sound)
    end
    ISBaseTimedAction.stop(self)
end

function CSR_SawAllLogsAction:perform()
    if self.sound and self.character:getEmitter():isPlaying(self.sound) then
        self.character:getEmitter():stopSound(self.sound)
    end

    local itemIdStr = buildPayload(self.items)
    if itemIdStr == "" then
        ISBaseTimedAction.perform(self)
        return
    end

    if isClient() then
        sendClientCommand(self.character, "CommonSenseReborn", "SawAllLogs", {
            itemIdStr = itemIdStr,
            toolId = self.tool:getID(),
            requestId = CSR_Utils.makeRequestId(self.character, "SawAllLogs")
        })
        -- XP is awarded server-side via addXp(player, Perks.Woodwork, ...) in handleSawAllLogs
    else
        performLocal(self)
    end

    ISBaseTimedAction.perform(self)
end

return CSR_SawAllLogsAction
