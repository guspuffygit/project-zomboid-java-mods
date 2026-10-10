-- Integration tests load the installed B42 UI and Lifestyle action/menu chunks.
-- Pass roots as arguments or use PZ_GAME_ROOT / LIFESTYLE_MOD_ROOT.
local patchRoot = arg[0]:match("^(.*)[/\\]tests[/\\][^/\\]+$") or "."
local function environment(name)
    return os and os.getenv and os.getenv(name)
end
local function sourceRoot(index, variable, message)
    local value = arg[index]
    if not value or value == "" then
        value = environment(variable)
    end
    assert(value and value ~= "", message)
    return value:gsub("[/\\]+$", "")
end
local gameRoot = sourceRoot(1, "PZ_GAME_ROOT", "Set the game root with -PgameDir or PZ_GAME_ROOT.")
local lifestyleRoot = sourceRoot(
    2,
    "LIFESTYLE_MOD_ROOT",
    "Set the Lifestyle mod root with -PlifestyleModDir or LIFESTYLE_MOD_ROOT."
)
local checks = 0
local function check(ok, message)
    assert(ok, message)
    checks = checks + 1
end
local function event()
    return { handlers = {}, Add = function(fn) end }
end
Events = setmetatable({}, {
    __index = function(self, key)
        local result = event()
        self[key] = result
        return result
    end,
})
require = function() end
local fontHeight, now, debugMode = 15, 1000, false
UIFont = { Small = "Small", Medium = "Medium" }
getTextOrNull = function(key)
    local values = {
        IGUI_perks_Yoga = "Yoga",
        IGUI_perks_Meditation = "Meditation",
        IGUI_PlayerStats_Level = "Level",
        IGUI_XP_xp = "XP",
        ContextMenu_Meditate = "Meditate",
    }
    return values[key]
end
getText = function(key)
    return getTextOrNull(key) or key
end
getTextManager = function()
    return {
        getFontHeight = function()
            return fontHeight
        end,
        MeasureStringX = function(_, _, value)
            return #value * fontHeight / 2
        end,
    }
end
getDebug = function()
    return debugMode
end
getTimestampMs = function()
    return now
end
local core = {
    getScreenWidth = function()
        return 1280
    end,
    getScreenHeight = function()
        return 720
    end,
    getGameMode = function()
        return "Sandbox"
    end,
    getOptionFontSizeReal = function()
        return 1
    end,
    getGoodHighlitedColor = function()
        return {
            getR = function()
                return 0
            end,
            getG = function()
                return 1
            end,
            getB = function()
                return 0
            end,
        }
    end,
}
getCore = function()
    return core
end
getPerformance = function()
    return {
        getUIRenderFPS = function()
            return 30
        end,
    }
end
getSoundManager = function()
    return { playUISound = function() end }
end
UIManager = {
    getMillisSinceLastRender = function()
        return 16
    end,
}
string.sort = function(a, b)
    return a > b
end
string.contains = function(a, b)
    return a:find(b, 1, true) ~= nil
end
-- These two installed loose PNGs are 48x48; unknown/missing assets are not
-- fabricated as valid textures. Lua verifies the PNG headers at runtime.
local skillTextures = {
    ["media/ui/SkillPanel/SkillUnit_Fill.png"] = true,
    ["media/ui/SkillPanel/SkillUnit_Border.png"] = true,
}
local textureCache = {}
getTexture = function(path)
    if textureCache[path] then
        return textureCache[path]
    end
    local width, height
    if io and io.open then
        local file = io.open(gameRoot .. "/" .. path, "rb")
        if not file then
            return nil
        end
        local header = file:read(24)
        file:close()
        if not header or header:sub(1, 8) ~= "\137PNG\r\n\26\n" then
            return nil
        end
        local function size(offset)
            local a, b, c, d = header:byte(offset, offset + 3)
            return ((a * 256 + b) * 256 + c) * 256 + d
        end
        width, height = size(17), size(21)
    elseif skillTextures[path] then
        -- Kahlua has no binary file API; whitelist only the verified native PNGs.
        width, height = 48, 48
    else
        return nil
    end
    local texture = {
        path = path,
        getWidth = function()
            return width
        end,
        getHeight = function()
            return height
        end,
    }
    textureCache[path] = texture
    return texture
end
getPlayerScreenTop = function()
    return 0
end
getPlayerScreenLeft = function()
    return 0
end
getPlayerScreenHeight = function()
    return 720
end
getPlayerScreenWidth = function()
    return 1280
end
JoypadState, Joypad =
    { players = {} }, {
        Texture = { AButton = {} },
        AButton = 1,
        BButton = 2,
        YButton = 3,
        LBumper = 4,
        RBumper = 5,
    }
MoodleType = { ENDURANCE = "endurance", HEAVY_LOAD = "heavy", PAIN = "pain" }
CharacterStat = { ZOMBIE_FEVER = "fever" }
isClient = function()
    return false
end
isMultiplayer = function()
    return false
end
instanceof = function()
    return false
end
ZombRand = function(first, last)
    if last then
        return first
    end
    return 0
end
luautils = {
    split = function(value)
        return { value }
    end,
}
MusicIntensityConfig = {
    getInstance = function()
        return { checkHealthPanelVisible = function() end }
    end,
}
HaloTextHelper = { addTextWithArrow = function() end }
LSNoteMng = { addToQueue = function() end }
forceDropHeavyItems = function() end

local UI = {}
function UI:derive(name)
    local derived = { Type = name }
    derived.__index = derived
    return setmetatable(derived, { __index = self })
end
function UI:instanceof(value)
    return value.Type == self.Type
end
function UI:new(x, y, width, height)
    return setmetatable({
        x = x,
        y = y,
        width = width,
        height = height,
        visible = true,
        children = {},
        joypadButtonsY = {},
        allJoypadButtons = {},
        texts = {},
        bars = {},
    }, { __index = self })
end
function UI:initialise() end
function UI:instantiate()
    if self.javaObject then
        return
    end
    local owner = self
    local java = {
        x = self.x,
        y = self.y,
        width = self.width,
        height = self.height,
        lastWidth = self.width,
        lastHeight = self.height,
        resizeDirty = false,
    }
    for _, field in ipairs({ "X", "Y", "Width", "Height" }) do
        local key = field:lower()
        java["get" .. field] = function(j)
            return j[key]
        end
        java["set" .. field] = function(j, value)
            if field == "Width" or field == "Height" then
                j["last" .. field] = j[key]
                if value ~= j[key] then
                    j.resizeDirty = true
                end
            end
            j[key] = value
        end
    end
    java.setVisible = function(_, value)
        owner.visible = value
    end
    java.DrawTextureScaledColor = function(_, texture, x, y, width, height, r, g, b, alpha)
        assert(texture and skillTextures[texture.path], "missing/unknown skill texture")
        owner.textureDraws = owner.textureDraws or {}
        owner.textureDraws[#owner.textureDraws + 1] = {
            texture.path,
            x,
            y,
            width,
            height,
            alpha,
            r,
            g,
            b,
        }
    end
    java.onResize = function(j)
        -- UIElement.setHeight defers anchoring until onResize; it records the
        -- previous height on EVERY setHeight, even before an earlier resize runs.
        for _, child in ipairs(owner.children) do
            if child.javaObject and j.resizeDirty then
                local cj = child.javaObject
                if child.anchorBottom and not child.anchorTop then
                    cj.y = cj.y + j.height - j.lastHeight
                end
                if child.anchorRight and not child.anchorLeft then
                    cj.x = cj.x + j.width - j.lastWidth
                end
                child.x, child.y = cj.x, cj.y
            end
        end
        j.resizeDirty, j.lastWidth, j.lastHeight = false, j.width, j.height
    end
    self.javaObject = java
end
function UI:addChild(child)
    self.children[#self.children + 1] = child
    child.parent = self
end
function UI:getWidth()
    self:instantiate()
    return self.javaObject:getWidth()
end
function UI:getHeight()
    self:instantiate()
    return self.javaObject:getHeight()
end
function UI:getX()
    self:instantiate()
    return self.javaObject:getX()
end
function UI:getY()
    self:instantiate()
    return self.javaObject:getY()
end
function UI:getRight()
    return self:getX() + self:getWidth()
end
function UI:getBottom()
    return self:getY() + self:getHeight()
end
function UI:setX(value)
    self.x = value
    if self.javaObject then
        self.javaObject:setX(value)
    end
end
function UI:setY(value)
    self.y = value
    if self.javaObject then
        self.javaObject:setY(value)
    end
end
function UI:setWidth(value)
    self.width = value
    if self.javaObject then
        self.javaObject:setWidth(value)
    end
end
function UI:setHeight(value)
    self.height = value
    if self.javaObject then
        self.javaObject:setHeight(value)
    end
end
function UI:getKeepOnScreen()
    return false
end
function UI:isMouseOver()
    return self.mouseOver == true
end
function UI:removeChild(child)
    for i = #self.children, 1, -1 do
        if self.children[i] == child then
            table.remove(self.children, i)
        end
    end
end
function UI:setScrollChildren() end
function UI:addScrollBars() end
function UI:setScrollHeight(value)
    self.scrollHeight = value
end
function UI:setStencilRect() end
function UI:clearStencilRect() end
function UI:setImage(image)
    self.image = image
end
function UI:drawTexture() end
function UI:setWidthAndParentWidth(value)
    self:setWidth(value)
end
function UI:setHeightAndParentHeight(value)
    self:setHeight(value)
end
function UI:setVisible(value)
    self.visible = value
end
function UI:getIsVisible()
    return self.visible
end
function UI:isReallyVisible()
    return self.visible
end
function UI:setEnable(value)
    self.enable = value
end
function UI:removeFromUIManager()
    self.removed = true
end
function UI:noBackground() end
function UI:paginate() end
function UI:render() end
function UI:prerender() end
function UI:update() end
function UI:drawRect() end
function UI:drawRectBorder() end
function UI:drawRectStatic()
    self.panelBackgrounds = (self.panelBackgrounds or 0) + 1
end
function UI:drawRectBorderStatic()
    self.panelBorders = (self.panelBorders or 0) + 1
end
function UI:drawTextureScaled() end
function UI:drawText(value, x, y, r, g, b, alpha, font)
    self.texts[#self.texts + 1] = {
        text = value,
        x = x,
        y = y,
        r = r,
        g = g,
        b = b,
        alpha = alpha,
        font = font,
    }
end
function UI:drawTextCentre(value, x, y)
    self:drawText(value, x, y)
end
function UI:drawProgressBar(x, y, width, height, fraction)
    self.bars[#self.bars + 1] =
        { x = x, y = y, width = width, height = height, fraction = fraction }
end
function UI:insertNewLineOfButtons(...)
    local row = { ... }
    self.joypadButtonsY[#self.joypadButtonsY + 1] = row
    return row
end
ISUIElement, ISPanelJoypad, ISScrollingListBox, ISBodyPartPanel, ISBaseObject, ISPanel =
    UI, UI, UI, UI, UI, UI
ISButton = UI:derive("ISButton")
function ISButton:new(x, y, width, height, title, target, callback)
    local result = UI.new(self, x, y, width, height)
    result.title, result.target, result.callback = title, target, callback
    result.onclick, result.enable, result.onClickArgs, result.sounds =
        callback, true, {}, { activate = "click" }
    return result
end
ISLabel = UI:derive("ISLabel")
function ISLabel:new(x, y, height)
    return UI.new(self, x, y, 100, height)
end
ISTextEntryBox = UI:derive("ISTextEntryBox")
function ISTextEntryBox:new(value, x, y, width, height)
    local result = UI.new(self, x, y, width, height)
    result.value = value
    return result
end
function ISTextEntryBox:getInternalText()
    return self.value
end
function ISTextEntryBox:setText(value)
    self.value = value
end
function ISTextEntryBox:setOnlyNumbers() end
function ISTextEntryBox:setEditable() end
ISRichTextPanel = UI
ISRadioButtons = UI:derive("ISRadioButtons")
function ISRadioButtons:new(x, y, width, height)
    local result = UI.new(self, x, y, width, height)
    result.options = {}
    return result
end
function ISRadioButtons:clear()
    self.options = {}
    self.height = 0
end
function ISRadioButtons:addOption(title, data)
    self.options[#self.options + 1] = { text = title, data = data }
    self.height = #self.options * (fontHeight + 6)
end
ISBaseTimedAction = UI:derive("ISBaseTimedAction")
function ISBaseTimedAction:stop()
    self.stopped = true
end
function ISBaseTimedAction:perform()
    self.completed = true
end

local queue = { queue = {} }
table.wipe = function(value)
    for key in pairs(value) do
        value[key] = nil
    end
end
function queue:isCurrentActionAddingOtherActions()
    return false
end
function queue:cancelQueue()
    for index = 2, #self.queue do
        self.queue[index].cancelled = true
    end
end
function queue:clearQueue()
    self:cancelQueue()
    table.wipe(self.queue)
end
ISTimedActionQueue = {
    getTimedActionQueue = function()
        return queue
    end,
    add = function(action)
        queue.queue[#queue.queue + 1] = action
    end,
    addGetUpAndThen = function(_, action)
        queue.queue[#queue.queue + 1] = action
    end,
}
local empty = {
    size = function()
        return 0
    end,
}
local data = {
    LSMoodles = {
        Embarrassed = { Level = 0 },
        Zen = { Value = 0, Level = 0 },
        WasTaughtSkill = { Value = 0 },
        MindfulState = { Value = 0 },
    },
    LSHiddenSkills = { Yoga = { 2, 125, 500 } },
}
local player = {
    sitting = false,
    dead = false,
    aiming = false,
    climbing = false,
    bored = 0,
    endurance = 1,
    x = 20,
    y = 20,
    z = 0,
    meditationLevel = 2,
    meditationXP = 175,
}
function player:getModData()
    return data
end
function player:isDead()
    return self.dead
end
function player:isSitOnGround()
    return self.sitting
end
function player:hasTimedActions()
    return #queue.queue > 0
end
function player:isSeatedInVehicle()
    return self.vehicle ~= nil
end
function player:getVehicle()
    return self.vehicle
end
function player:isAsleep()
    return self.asleep
end
function player:isSittingOnFurniture()
    return self.furniture
end
function player:isClimbing()
    return self.climbing
end
function player:isAiming()
    return self.aiming
end
function player:isTimedActionInstant()
    return false
end
function player:getX()
    return self.x
end
function player:getY()
    return self.y
end
function player:getZ()
    return self.z
end
function player:getPlayerNum()
    return 0
end
function player:getPerkLevel(perk)
    return perk == "Meditation" and self.meditationLevel or 0
end
function player:getXp()
    return {
        getXP = function()
            return player.meditationXP
        end,
        getPerkBoost = function(_, perk)
            check(perk ~= "Yoga", "Hidden Yoga never reaches native XP boost APIs")
            return player.perkBoosts and player.perkBoosts[perk] or 0
        end,
        getMultiplier = function(_, perk)
            check(perk ~= "Yoga", "Hidden Yoga never reaches native multiplier APIs")
            return 0
        end,
    }
end
function player:getWornItems()
    return empty
end
function player:getSquare()
    return {
        getObjects = function()
            return empty
        end,
    }
end
function player:reportEvent(value)
    self.reportedEvent = value
end
function player:setVariable(key, value)
    self[key] = value
end
function player:StopAllActionQueue()
    local action = queue.queue[1]
    if action and action.stop then
        action:stop()
    end
end
function player:getMoodles()
    return {
        getMoodleLevel = function()
            return 0
        end,
    }
end
function player:getVariableBoolean(value)
    return value == "sitonground" and self.sitting
end
function player:getInventory()
    return {
        contains = function()
            return true
        end,
    }
end
function player:getPrimaryHandItem()
    return nil
end
function player:getSecondaryHandItem()
    return nil
end
function player:isItemInBothHands()
    return false
end
function player:getBodyDamage()
    return {
        getHealth = function()
            return 100
        end,
    }
end
function player:getJoypadBind()
    return -1
end
function player:getStats()
    return {
        get = function()
            return 0
        end,
    }
end
function player:getReduceInfectionPower()
    return 0
end
local fitness = {
    init = function() end,
    getRegularity = function()
        return 25
    end,
    getCurrentExe = function()
        return nil
    end,
}
function player:getFitness()
    return fitness
end
getSpecificPlayer = function()
    return player
end
ISInventoryPaneContextMenu = { unequipItem = function() end }
ISFitnessAction = {
    new = function(_, character, selection, duration, exeData)
        return {
            Type = "ISFitnessAction",
            character = character,
            selection = selection,
            duration = duration,
            exeData = exeData,
        }
    end,
}
LSUtil = {
    getCharacterMood = function(character, mood)
        return mood == "Boredom" and character.bored or character.endurance
    end,
}
SandboxVars = {
    Text = { DividerMeditationNew = true },
    Yoga = { KeepBags = true },
    Meditation = { KeepBags = true },
    LSMeditation = {},
}
Perks = {
    Meditation = "Meditation",
    Fitness = "Fitness",
    Nimble = "Nimble",
    Lifestyle = "Lifestyle",
    Other = "Other",
    Example = "Example",
    None = "None",
}
local thresholds = { 50, 100, 200, 500, 1000, 2000, 3000, 4000, 5000, 6000 }
local function perk(name, parent)
    local result = {
        getType = function()
            return name
        end,
        getName = function()
            return name
        end,
        getParent = function()
            return parent
        end,
        isPassiv = function()
            return false
        end,
        getXpForLevel = function(_, level)
            return thresholds[level] or 0
        end,
    }
    for index = 1, 10 do
        local value = thresholds[index]
        result["getXp" .. index] = function()
            return value
        end
    end
    return result
end
local meditationPerk, examplePerk = perk("Meditation", "Lifestyle"), perk("Example", "Other")
PerkFactory = {
    getPerk = function(value)
        return perk(value, "None")
    end,
    PerkList = {
        size = function()
            return 2
        end,
        get = function(_, index)
            return index == 0 and meditationPerk or examplePerk
        end,
    },
}
FitnessExercises = {
    exercisesType = { squats = { name = "Squats", type = "squats", stiffness = "legs", xpMod = 1 } },
}

-- These are real installed code chunks, not copies of the patch's helpers.
dofile(gameRoot .. "/media/lua/client/ISUI/ISUIElement.lua")
UI.setHeight, UI.recalcSize = ISUIElement.setHeight, ISUIElement.recalcSize
UI.drawTextureScaled = ISUIElement.drawTextureScaled
ISUIElement = UI
dofile(gameRoot .. "/media/lua/client/ISUI/ISPanel.lua")
dofile(gameRoot .. "/media/lua/client/ISUI/ISUITextureGetter.lua")
local testButton = ISButton
dofile(gameRoot .. "/media/lua/client/ISUI/ISButton.lua")
testButton.onMouseDown, testButton.onMouseUp = ISButton.onMouseDown, ISButton.onMouseUp
ISButton = testButton
local state = {
    instance = function()
        return {}
    end,
}
ClimbThroughWindowState, ClimbOverFenceState, ClimbOverWallState = state, state, state
ClimbSheetRopeState, ClimbDownSheetRopeState, CloseWindowState, OpenWindowState =
    state, state, state, state
local testQueue = ISTimedActionQueue
dofile(gameRoot .. "/media/lua/client/TimedActions/ISTimedActionQueue.lua")
testQueue.clear = ISTimedActionQueue.clear
ISTimedActionQueue = testQueue
dofile(gameRoot .. "/media/lua/client/ISUI/ISFitnessUI.lua")
dofile(gameRoot .. "/media/lua/client/XpSystem/ISUI/ISSkillProgressBar.lua")
dofile(gameRoot .. "/media/lua/client/XpSystem/ISUI/ISCharacterInfo.lua")
dofile(lifestyleRoot .. "/common/media/lua/client/Helper/HSMng.lua")
dofile(lifestyleRoot .. "/common/media/lua/shared/TimedActions/LSYogaAction.lua")
dofile(lifestyleRoot .. "/common/media/lua/shared/TimedActions/LSMeditateAction.lua")
dofile(lifestyleRoot .. "/common/media/lua/client/ISMeditation/ZenWellnessContextMenu.lua")
local patch = patchRoot .. "/media/lua/client/ATFPatches_LifestyleHealth.lua"
dofile(patch)
local H = ATFPatches_LifestyleHealth
local broken = UI:new(0, 0, 600, 350)
broken:instantiate()
local oldFooter = UI:new(11, 318, 100, 21)
oldFooter.anchorTop, oldFooter.anchorBottom = false, true
oldFooter:instantiate()
broken:addChild(oldFooter)
broken:setHeight(250)
broken:setHeight(281)
broken:recalcSize()
check(
    oldFooter:getBottom() > broken:getHeight(),
    "Harness reproduces actual deferred-anchor footer regression"
)
local function clickAt(window, x, y)
    if x < 0 or y < 0 or x >= window:getWidth() or y >= window:getHeight() then
        return
    end
    for _, child in ipairs(window.children) do
        if
            child.onMouseDown
            and child.onMouseUp
            and child:getIsVisible()
            and x >= child:getX()
            and x < child:getRight()
            and y >= child:getY()
            and y < child:getBottom()
        then
            child:onMouseDown(x - child:getX(), y - child:getY())
            child:onMouseUp(x - child:getX(), y - child:getY())
            return child
        end
    end
end
local function clickButton(window, button)
    return clickAt(
        window,
        button:getX() + button:getWidth() / 2,
        button:getY() + button:getHeight() / 2
    )
end
local ui = ISFitnessUI:new(10, 10, 600, 350, player)
ui:initialise()
ui:render()
check(
    ui.atfYoga.title == "Do Yoga" and ui.atfMeditate.title == "Meditate",
    "Native Exercise window contains both controls"
)
check(
    #ui.exercises.options == 1 and FitnessExercises.exercisesType.Yoga == nil,
    "Native exercise data stays unchanged"
)
check(ui.atfYoga:getBottom() < ui.ok.y, "Wellness row does not overlap bottom controls")
check(
    ui.joypadButtonsY[#ui.joypadButtonsY - 1][1] == ui.atfYoga,
    "Controller navigation includes wellness before bottom row"
)
check(ui.bars[1].fraction == 0.25, "Native regularity still renders")
ui:recalcSize()
check(
    ui.close:getBottom() <= ui:getHeight() - 10 and ui.close:getRight() <= ui:getWidth() - 10,
    "Close stays inside final Exercise bounds after deferred Java resize"
)
check(
    clickButton(ui, ui.close) == ui.close and not ui:getIsVisible() and ui.removed,
    "Close is hit-testable and actual native mouse handlers close the Exercise window"
)
ui:setVisible(true)
local originalWrapped = ISFitnessUI.onClick
dofile(patch)
check(ISFitnessUI.onClick == originalWrapped, "Reload does not stack wrappers")
local otherWrapper = function(self, ...)
    return originalWrapped(self, ...)
end
ISFitnessUI.onClick = otherWrapper
H.install()
check(ISFitnessUI.onClick == otherWrapper, "Install preserves another mod's existing wrapper chain")

check(clickButton(ui, ui.ok) == ui.ok, "Native OK is hit-testable inside the Exercise window")
check(
    queue.queue[1].Type == "ISFitnessAction" and queue.queue[1].duration == 10,
    "Native OK still queues normal exercise with selected duration"
)
local nativeCancelled = false
queue.queue[1].action = {
    forceStop = function()
        nativeCancelled = true
    end,
}
ui:updateButtons(queue.queue[1])
check(
    clickButton(ui, ui.cancel) == ui.cancel and nativeCancelled,
    "Native Cancel still stops ordinary fitness through its original handler"
)
queue.queue, ui.currentExercice = {}, nil
ui.atfYoga.callback(ui, ui.atfYoga)
local action = queue.queue[1]
check(
    action.Type == "LSYogaAction" and action.skillLevel == 2 and action.poseLimit == 3,
    "Do Yoga dispatches real Lifestyle level-specific session"
)
ui:updateButtons(action)
check(
    ui.cancel.enable and not ui.ok.enable and not ui.atfMeditate.enable,
    "Active wellness action enables Cancel and prevents another start"
)
data.LSHiddenSkills.Yoga[2] = 125
action.gainedXP, action.poseCount = 10, 1
ui:onClick(ui.cancel)
check(#queue.queue == 0 and data.LSHiddenSkills.Yoga[2] == 85, "Cancel runs real Yoga stop penalty")
ui.atfYoga.callback(ui, ui.atfYoga)
local queuedYoga = queue.queue[1]
queuedYoga.gainedXP = 10
table.insert(queue.queue, 1, {
    Type = "ISUnequipAction",
    stop = function(self)
        self.stopped = true
    end,
})
local bagPreparation = queue.queue[1]
ui:onClick(ui.cancel)
check(
    bagPreparation.stopped and queuedYoga.cancelled and not queuedYoga.stopped,
    "Real queue clear stops only current bag preparation and cancels the queued Yoga session"
)
check(
    data.LSHiddenSkills.Yoga[2] == 85,
    "Queued session cancellation applies no unearned Yoga penalty"
)
player.bored = 31
ui.atfMeditate.callback(ui, ui.atfMeditate)
check(
    not ui.atfWellnessPending and #queue.queue == 0,
    "Meditation rechecks Lifestyle boredom eligibility"
)
player.bored = 0
SandboxVars.Yoga.RequiresMat = true
ui.atfYoga.callback(ui, ui.atfYoga)
check(#queue.queue == 0, "Yoga respects real Lifestyle mat requirement")
SandboxVars.Yoga.RequiresMat = false
data.LSMoodles.Embarrassed.Level = 2
ui.atfYoga.callback(ui, ui.atfYoga)
check(#queue.queue == 0, "Yoga respects embarrassment eligibility")
data.LSMoodles.Embarrassed.Level = 0
player.endurance = 0.4
ui.atfYoga.callback(ui, ui.atfYoga)
check(#queue.queue == 0, "Yoga respects endurance eligibility")
player.endurance = 1

ui.atfMeditate.callback(ui, ui.atfMeditate)
check(
    ui.atfWellnessPending and player.reportedEvent == "EventSitOnGround",
    "Meditate requests native sit event"
)
ui:update()
check(#queue.queue == 0, "Meditation waits for actual sitting state")
player.sitting = true
ui:update()
check(
    not ui.atfWellnessPending and queue.queue[1].Type == "LSMeditateAction",
    "Sitting dispatches real meditation action once"
)
check(queue.queue[1].length == 2800, "Lifestyle determines meditation duration")
ui:update()
check(#queue.queue == 1, "No repeated meditation dispatch")
data.IsMeditating = true
ui:onClick(ui.cancel)
check(#queue.queue == 0 and not data.IsMeditating, "Cancel runs real meditation cleanup")
player.sitting = false
local function pending()
    ui.visible, ui.atfWellnessPending = true, nil
    ui.atfMeditate.callback(ui, ui.atfMeditate)
    check(ui.atfWellnessPending ~= nil, "Pending sit was created")
end
pending()
ui:onClick(ui.cancel)
player.sitting = true
ui:update()
check(#queue.queue == 0, "Cancel prevents delayed meditation")
player.sitting = false
pending()
ui:onClick(ui.close)
player.sitting = true
ui:update()
check(#queue.queue == 0 and not ui.atfWellnessPending, "Close prevents delayed meditation")
player.sitting = false
pending()
ui:setVisible(false)
player.sitting = true
ui:update()
check(#queue.queue == 0, "Hiding window clears pending meditation")
player.sitting = false
pending()
player.dead = true
ui:update()
player.dead = false
player.sitting = true
ui:update()
check(#queue.queue == 0, "Death clears pending meditation")
player.sitting = false
pending()
player.x = player.x + 1
ui:update()
player.x = player.x - 1
player.sitting = true
ui:update()
check(#queue.queue == 0, "Movement clears pending meditation")
player.sitting = false
pending()
now = now + 9000
ui:update()
player.sitting = true
ui:update()
check(#queue.queue == 0, "Failed sit transition expires")
player.sitting = false
pending()
player.bored = 31
player.sitting = true
ui:update()
check(#queue.queue == 0, "Eligibility is rechecked after sitting")
player.bored = 0

-- Load the real Skills renderer at two font scales; only Yoga is added.
for _, scale in ipairs({ 15, 24 }) do
    fontHeight = scale
    dofile(gameRoot .. "/media/lua/client/XpSystem/ISUI/ISSkillProgressBar.lua")
    dofile(gameRoot .. "/media/lua/client/XpSystem/ISUI/ISCharacterInfo.lua")
    H.yogaBarClass = nil
    H.install()
    local panel = ISCharacterInfo:new(0, 0, 500, 350, 0)
    panel:createChildren()
    panel:render()
    local meditationCount, yogaCount, category = 0, 0
    for _, bar in ipairs(panel.progressBars) do
        if bar.perk == meditationPerk then
            meditationCount = meditationCount + 1
        end
        if bar == panel.atfYogaBar then
            yogaCount = yogaCount + 1
        end
    end
    for i, parent in ipairs(panel.sorted) do
        if parent:getType() == Perks.Lifestyle then
            category = i
        end
    end
    check(
        #panel.progressBars == 3 and meditationCount == 1 and yogaCount == 1,
        "Skills has one Yoga display and keeps the single native Meditation row"
    )
    check(
        #panel.perks[Perks.Lifestyle] == 1 and Perks.Yoga == nil,
        "Yoga remains hidden and adds no fake native perk"
    )
    local bar, barY, scrollHeight = panel.atfYogaBar, panel.atfYogaBar:getY(), panel.scrollHeight
    local function labelDraw(name)
        local found
        for _, draw in ipairs(panel.texts) do
            if draw.text == name then
                assert(not found, "Only one label is drawn for " .. name)
                found = draw
            end
        end
        return assert(found, "Missing Skills label " .. name)
    end
    for _, hovered in ipairs({ false, true }) do
        panel.mouseOver, bar.mouseOver = hovered, hovered
        bar.getMouseX = function()
            return 0
        end
        bar:onMouseMove(0, 0)
        check(
            hovered and bar.message and bar.message:find("Yoga", 1, true)
                or not hovered and not bar.message,
            "Inherited native bar hover keeps the Yoga tooltip at font " .. scale
        )
        panel.texts = {}
        panel:render()
        local yogaLabel, nativeLabel = labelDraw("Yoga"), labelDraw(meditationPerk:getName())
        check(
            nativeLabel.r == 0.54
                and nativeLabel.g == 0.54
                and nativeLabel.b == 0.54
                and nativeLabel.alpha == 1,
            "Actual native renderer supplies the unboosted Skills tint at font " .. scale
        )
        check(
            yogaLabel.r == nativeLabel.r
                and yogaLabel.g == nativeLabel.g
                and yogaLabel.b == nativeLabel.b
                and yogaLabel.alpha == nativeLabel.alpha
                and yogaLabel.font == nativeLabel.font,
            "Yoga matches native skill text RGBA/font with hover "
                .. tostring(hovered)
                .. ", font "
                .. scale
        )
        check(
            yogaLabel.x == nativeLabel.x and yogaLabel.y == nativeLabel.y + scale + 6,
            "Yoga uses the native skill label inset and row baseline at font " .. scale
        )
    end
    panel.mouseOver, bar.mouseOver = false, false
    bar:onMouseMoveOutside(0, 0)
    check(not bar.message, "Native hover exit clears only the Yoga tooltip")
    player.perkBoosts = { Meditation = 3 }
    panel.texts = {}
    panel:render()
    local yogaLabel, boostedLabel = labelDraw("Yoga"), labelDraw(meditationPerk:getName())
    check(
        boostedLabel.r == 1
            and boostedLabel.g == 0.83
            and boostedLabel.b == 0
            and yogaLabel.r == 0.54
            and yogaLabel.g == 0.54
            and yogaLabel.b == 0.54
            and yogaLabel.alpha == 1,
        "Yoga does not borrow another native perk's trait boost color at font " .. scale
    )
    player.perkBoosts = nil
    bar:renderPerkRect()
    check(
        bar.level == data.LSHiddenSkills.Yoga[1] and bar.xp == data.LSHiddenSkills.Yoga[2],
        "Yoga bar reads actual hidden XP at font size " .. scale
    )
    check(
        bar.background == false
            and bar.SkillUnitFilled:getWidth() == 48
            and bar.SkillUnitBorder:getHeight() == 48
            and getTexture("media/ui/SkillPanel/missing.png") == nil,
        "Yoga uses native transparent panel flags and verified skill PNGs"
    )
    bar:prerender()
    check(
        not bar.panelBackgrounds and not bar.panelBorders,
        "Native panel prerender adds no bar-wide background/border"
    )
    local savedYoga = data.LSHiddenSkills.Yoga
    local savedLevel, savedXP = player.meditationLevel, player.meditationXP
    local function sameDrawing(actual, expected, label)
        check(#actual == #expected, label .. " draw count matches native")
        for i, call in ipairs(actual) do
            for field, value in ipairs(call) do
                local reference = expected[i][field]
                assert(
                    type(value) == "number"
                            and type(reference) == "number"
                            and math.abs(value - reference) < 0.000001
                        or value == reference,
                    label .. " native draw " .. i .. " field " .. field
                )
            end
        end
    end
    for _, state in ipairs({ { 0, 0 }, { 0, 25 }, { 2, 0 }, { 2, 100 }, { 9, 3000 }, { 10, 0 } }) do
        local level, xp = state[1], state[2]
        local target = thresholds[level + 1] or 0
        data.LSHiddenSkills.Yoga = { level, xp, target }
        player.meditationLevel = level
        player.meditationXP = ISSkillProgressBar.getPreviousXpLvl(meditationPerk, level) + xp
        local nativeParent = { lastLevelUpTime = 0 }
        local native = ISSkillProgressBar:new(0, 0, 0, 0, 0, meditationPerk, nativeParent)
        native:initialise()
        native:instantiate()
        bar.level, panel.lastLeveledUpPerk, panel.lastLevelUpTime = level, nil, 0
        bar.textureDraws = {}
        bar:render()
        native:render()
        sameDrawing(
            bar.textureDraws,
            native.textureDraws,
            "Yoga level " .. level .. ", XP " .. xp .. ", font " .. scale
        )
        if level == 0 and xp == 0 then
            check(
                bar.textureDraws[1][7] == 0.4
                    and bar.textureDraws[2][4] == 0
                    and bar.textureDraws[3][7] == 0.2,
                "Zero XP outlines only the first current unit; future units are darker and unfilled"
            )
        end
    end
    -- The native renderer flashes completed points after an actual level change.
    player.meditationLevel, player.meditationXP = 2, 150
    local nativeParent = { lastLevelUpTime = 0 }
    local native = ISSkillProgressBar:new(0, 0, 0, 0, 0, meditationPerk, nativeParent)
    native:initialise()
    native:instantiate()
    player.meditationLevel, player.meditationXP = 3, 350
    data.LSHiddenSkills.Yoga = { 3, 0, 500 }
    bar.level, panel.lastLeveledUpPerk, panel.lastLevelUpTime = 2, nil, 0
    for _, fade in ipairs({ 1, 0.5, 0 }) do
        panel.lastLevelUpTime, nativeParent.lastLevelUpTime = fade, fade
        bar.textureDraws, native.textureDraws = {}, {}
        bar:render()
        native:render()
        sameDrawing(
            bar.textureDraws,
            native.textureDraws,
            "Yoga level-up fade " .. fade .. ", font " .. scale
        )
    end
    check(panel.lastLeveledUpPerk == bar, "Yoga level-up highlight uses only its display bar")
    data.LSHiddenSkills.Yoga = savedYoga
    player.meditationLevel, player.meditationXP = savedLevel, savedXP
    panel.lastLeveledUpPerk, panel.lastLevelUpTime = nil, 0
    panel.texts = {}
    panel:render()
    local labels = 0
    for _, label in ipairs(panel.texts) do
        if label.text == "Yoga" then
            labels = labels + 1
        end
    end
    check(
        labels == 1
            and #panel.progressBars == 3
            and bar:getY() == barY
            and panel.scrollHeight == scrollHeight,
        "Repeated native Skills renders neither duplicate nor move the Yoga row"
    )
    data.LSHiddenSkills.Yoga = { 3, 10, 750 }
    bar:renderPerkRect()
    bar:updateTooltip()
    check(
        bar.level == 3 and bar.xp == 10 and bar.message:find("10 / 750", 1, true),
        "Yoga observes replacement skill tables after a level change"
    )
    bar:onMouseUp()
    bar:activate()
    panel:collapseSection(panel.buttonList[category])
    panel:render()
    check(
        not panel.atfYogaBar and #panel.progressBars == 1,
        "Lifestyle collapse removes Yoga with native rows"
    )
    panel:collapseSection(panel.buttonList[category])
    panel:render()
    check(
        panel.atfYogaBar and #panel.progressBars == 3,
        "Lifestyle expansion rebuilds exactly one Yoga row"
    )
    getPlayer = function()
        return player
    end
    getNumActivePlayers = function()
        return 1
    end
    getPlayerData = function()
        return {}
    end
    getPlayerInfoPanel = function()
        return { characterView = panel }
    end
    ISCharacterInfo.onResolutionChange(1280, 720, 1600, 900)
    panel:render()
    check(
        panel.atfYogaBar and #panel.progressBars == 3,
        "Native resolution rebuild reattaches exactly one Yoga row"
    )
    SandboxVars.Text.DividerMeditationNew = false
    panel:render()
    check(
        not panel.atfYogaBar and #panel.progressBars == 2,
        "Disabling Lifestyle removes only the custom Yoga display"
    )
    SandboxVars.Text.DividerMeditationNew = true
end
fontHeight = 24
dofile(gameRoot .. "/media/lua/client/ISUI/ISFitnessUI.lua")
H.install()
local largeUI = ISFitnessUI:new(10, 10, 600, 350, player)
largeUI:initialise()
largeUI:render()
check(
    largeUI.atfMeditate:getRight() < largeUI:getWidth()
        and largeUI.atfMeditate:getBottom() < largeUI.ok.y,
    "Large-font Exercise controls fit without overlap"
)
largeUI:recalcSize()
check(
    largeUI.close:getBottom() <= largeUI:getHeight() - 10
        and clickButton(largeUI, largeUI.close) == largeUI.close
        and not largeUI:getIsVisible(),
    "Large-font Close remains inside bounds and responds to native mouse clicks"
)
check(
    largeUI.atfYoga.tooltip:find("session length", 1, true),
    "Buttons explain that Lifestyle controls session duration"
)
data.LSHiddenSkills.Yoga = { 10, 123, 9000 }
check(H.yogaProgress(player).fraction == 1, "Mastered Yoga renders all ten skill units")
SandboxVars.Text.DividerMeditationNew = false
ui.atfYoga.callback(ui, ui.atfYoga)
check(#queue.queue == 0, "Disabled Lifestyle module prevents dispatch")
local disabledUI = ISFitnessUI:new(10, 10, 600, 350, player)
disabledUI:initialise()
check(disabledUI.atfYoga == nil, "Disabled module leaves native Exercise layout alone")
SandboxVars.Text.DividerMeditationNew = true
ZenWellnessContextMenu = nil
check(not H.enabled(), "Absent Lifestyle action API leaves integration inert")
print("PASS: " .. checks .. " Lifestyle Skills / native Exercise integration checks")
