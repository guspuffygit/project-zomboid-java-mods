require("XpSystem/ISUI/ISHealthPanel")
require("ISUI/ISContextMenu")
require("TimedActions/ISQueueActionsAction")

ATFSmartTreatmentResolver = ATFSmartTreatmentResolver or {}
local R = ATFSmartTreatmentResolver
local handlers = {
    HApplyBandage = "bandage",
    HRemoveBandage = "removeBandage",
    HDisinfect = "disinfect",
    HStitch = "stitch",
    HRemoveStitch = "removeStitch",
    HSplint = "splint",
    HRemoveSplint = "removeSplint",
    HRemoveGlass = "removeGlass",
    HRemoveBullet = "removeBullet",
    HCleanBurn = "cleanBurn",
    HApplyPlantain = "plantain",
    HApplyComfrey = "comfrey",
    HApplyGarlic = "garlic",
}
local timedTypes = {
    bandage = "ISApplyBandage",
    removeBandage = "ISApplyBandage",
    stitch = "ISStitch",
    removeStitch = "ISStitch",
    splint = "ISSplint",
    removeSplint = "ISSplint",
    disinfect = "ISDisinfect",
    removeGlass = "ISRemoveGlass",
    removeBullet = "ISRemoveBullet",
    cleanBurn = "ISCleanBurn",
    plantain = "ISPlantainCataplasm",
    comfrey = "ISComfreyCataplasm",
    garlic = "ISGarlicCataplasm",
}
local function preference(value)
    return value == "conserve" and "conserve" or value == "manual" and "manual" or "best"
end
local function call(item, method, fallback)
    if item and item[method] then
        return item[method](item)
    end
    return fallback
end
local function number(value)
    return type(value) == "number" and value == value and math.abs(value) ~= math.huge and value
        or 0
end
local function ownPane(player, bodyPart)
    if
        not player
        or not player:isLocalPlayer()
        or player:isDead()
        or getSpecificPlayer(player:getPlayerNum()) ~= player
        or not bodyPart
    then
        return nil
    end
    local parts = player:getBodyDamage():getBodyParts()
    local found = false
    for i = 0, parts:size() - 1 do
        if parts:get(i) == bodyPart then
            found = true
            break
        end
    end
    if not found then
        return nil
    end
    local info = getPlayerInfoPanel and getPlayerInfoPanel(player:getPlayerNum())
    local pane = info and info.healthView
    if pane and pane.character == player and not pane.otherPlayer and not pane.blockingMessage then
        return pane
    end
end
local function dirty(item)
    -- ISApplyBandage.complete gives every *Dirty material zero bandage life.
    -- ItemAfterCleaning additionally recognizes supported modded dirty material.
    local kind = call(item, "getType", "")
    local cleaning = call(item, "getItemAfterCleaning")
    return kind:find("Dirty", 1, true) ~= nil
        or (cleaning ~= nil and cleaning ~= "")
        or call(item, "isInfected", false)
end
local function strength(item)
    if item and item:hasComponent(ComponentType.FluidContainer) then
        local fluid = item:getFluidContainer()
        local amount = number(fluid:getAmount())
        return amount > 0 and 4 * number(fluid:getProperties():getAlcohol()) / amount or 0
    end
    return number(call(item, "getAlcoholPower", 0))
end
local function scoreItem(id, item, mode)
    if not item then
        return { 0, 0, 0, 0 }
    end
    local clean = dirty(item) and 0 or 1
    local script = call(item, "getScriptItem")
    local medical = call(script, "isMedicalLoot", false) and 1 or 0
    local power = number(call(item, "getBandagePower", 0))
    local sterile = call(item, "isAlcoholic", false) and 1 or 0
    if id == "bandage" or id == "cleanBurn" then
        -- Measured bandage grade, then disinfection, then medical metadata as
        -- a tie-breaker. Modded high-grade supplies need no vanilla loot flag.
        -- Conservation favors clean improvised material and lower usable grade.
        if mode == "conserve" then
            return { clean, -medical, -sterile, -power }
        end
        return { clean, power, sterile, medical }
    elseif id == "disinfect" then
        return { mode == "conserve" and -strength(item) or strength(item), 0, 0, 0 }
    end
    return { 0, 0, 0, 0 }
end
local function betterScore(a, b)
    for i = 1, math.max(#a, #b) do
        local av, bv = a[i] or 0, b[i] or 0
        if av ~= bv then
            return av > bv
        end
    end
    return false
end
local function bestItem(items, fullType, id, mode, cleanOnly)
    local selected, selectedScore
    for _, item in ipairs(items or {}) do
        if item:getFullType() == fullType and (not cleanOnly or not dirty(item)) then
            local score = scoreItem(id, item, mode)
            if not selected or betterScore(score, selectedScore) then
                selected, selectedScore = item, score
            end
        end
    end
    return selected
end
local function itemForType(handler, fullType, id, mode, cleanOnly)
    if type(fullType) ~= "string" or fullType == "Hands" then
        return nil
    end
    local selected, selectedScore
    for _, items in pairs(handler.items or {}) do
        local item = bestItem(items, fullType, id, mode, cleanOnly)
        if item then
            local score = scoreItem(id, item, mode)
            if not selected or betterScore(score, selectedScore) then
                selected, selectedScore = item, score
            end
        end
    end
    return selected
end

-- A silent menu records the current native builder's callbacks. It implements
-- only the ordinary menu contract; it never attaches a UI or takes joypad focus.
local Menu = {}
Menu.__index = Menu
function Menu:new(parent)
    local menu =
        setmetatable({ options = {}, numOptions = 1, enabled = true, parent = parent }, self)
    menu.root = parent and parent.root or menu
    if not parent then
        menu.instances, menu.nextSub = {}, 0
    end
    return menu
end
function Menu:addOption(name, target, onSelect, ...)
    local option = { name = name, target = target, onSelect = onSelect }
    for i = 1, select("#", ...) do
        option["param" .. i] = select(i, ...)
    end
    self.options[#self.options + 1] = option
    self.numOptions = self.numOptions + 1
    return option
end
function Menu:getNew(parent)
    local menu = Menu:new(parent or self)
    self.root.nextSub = self.root.nextSub + 1
    menu.subOptionNums = self.root.nextSub
    self.root.instances[menu.subOptionNums] = menu
    return menu
end
function Menu:addSubMenu(option, submenu)
    option.subOption = submenu.subOptionNums
end
function Menu:getSubMenu(index)
    return self.root.instances[index]
end
function Menu:isEmpty()
    return #self.options == 0
end
function Menu:setVisible(value)
    self.enabled = value == true
end
function Menu:getIsVisible()
    return false
end

local function harvest(player, bodyPart, x, y, shown)
    local pane = ownPane(player, bodyPart)
    if not pane or not pane.doBodyPartContextMenu or not ISContextMenu.get then
        return nil
    end
    local originalGet, originalCheck = ISContextMenu.get, pane.checkItems
    local ownCheck = rawget(pane, "checkItems")
    local context, availableHandlers
    ISContextMenu.get = function(ordinal, ...)
        if ordinal ~= player:getPlayerNum() then
            return originalGet(ordinal, ...)
        end
        context = shown and originalGet(ordinal, ...) or Menu:new()
        return context
    end
    pane.checkItems = function(self, current, ...)
        if self == pane then
            availableHandlers = current
        end
        return originalCheck(self, current, ...)
    end
    pane.doctorLevel = player:getPerkLevel(Perks.Doctor)
    local ok, err = pcall(
        pane.doBodyPartContextMenu,
        pane,
        bodyPart,
        (x or 0) - pane:getAbsoluteX(),
        (y or 0) - pane:getAbsoluteY()
    )
    ISContextMenu.get, pane.checkItems = originalGet, ownCheck
    if not ok or not context then
        return nil, err
    end
    if shown then
        if not context:getIsVisible() then
            return nil
        end
    elseif not context.enabled then
        return nil
    end
    local choices, categories = {}, {}
    local function visit(menu, category, parentAllowed)
        for _, option in ipairs(menu.options or {}) do
            local allowed = parentAllowed and not option.notAvailable and not option.isDisabled
            local handler = option.target
            local id = handler and handlers[handler.Type]
            if
                allowed
                and id
                and handler.panel == pane
                and handler.bodyPart == bodyPart
                and option.onSelect == handler.onMenuOptionSelected
            then
                local args = {}
                for i = 1, 8 do
                    args[i] = option["param" .. i]
                end
                choices[#choices + 1] = {
                    id = id,
                    name = option.name,
                    category = category or option,
                    option = option,
                    handler = handler,
                    args = args,
                    player = player,
                    bodyPart = bodyPart,
                    pane = pane,
                }
                categories[category or option] = id
            end
            if option.subOption then
                local submenu = menu:getSubMenu(option.subOption)
                if submenu then
                    visit(submenu, category or option, allowed)
                end
            end
        end
    end
    visit(context, nil, true)
    return {
        context = context,
        choices = choices,
        categories = categories,
        handlers = availableHandlers or {},
        pane = pane,
    }
end
local function choose(data, id, mode, cleanOnly, manualArgs)
    local selected, selectedScore, selectedKey
    for _, choice in ipairs(data.choices) do
        if choice.id == id then
            local matches = true
            if manualArgs then
                for i = 1, 8 do
                    if choice.args[i] ~= manualArgs[i] then
                        matches = false
                    end
                end
            end
            if matches and choice.handler:isValid(unpack(choice.args, 1, 8)) then
                local item = itemForType(
                    choice.handler,
                    choice.args[1] or choice.args[2],
                    id,
                    mode,
                    cleanOnly
                )
                if not cleanOnly or item then
                    local score = scoreItem(id, item, mode)
                    if id == "stitch" then
                        score = {
                            (choice.args[1] == choice.args[2] and 1 or 0)
                                * (mode == "conserve" and -1 or 1),
                        }
                    elseif id == "splint" then
                        score = { choice.args[1] == nil and 1 or 0 }
                    elseif id == "removeGlass" then
                        score = { choice.args[1] == "Hands" and 0 or 1 }
                    end
                    local key = tostring(choice.args[1] or "")
                        .. "|"
                        .. tostring(choice.args[2] or "")
                    if
                        not selected
                        or betterScore(score, selectedScore)
                        or (not betterScore(selectedScore, score) and key < selectedKey)
                    then
                        choice.item, choice.items = item, {}
                        for i = 1, 8 do
                            local support =
                                itemForType(choice.handler, choice.args[i], id, mode, cleanOnly)
                            if support and support ~= choice.items[#choice.items] then
                                choice.items[#choice.items + 1] = support
                            end
                        end
                        selected, selectedScore, selectedKey = choice, score, key
                    end
                end
            end
        end
    end
    return selected
end
function R.resolve(player, bodyPart, id, mode)
    local data = harvest(player, bodyPart)
    return data and choose(data, id, preference(mode)) or nil
end
local function pending(player, bodyPart, id)
    local queue = ISTimedActionQueue.getTimedActionQueue(player).queue
    for _, action in ipairs(queue) do
        if action.atfSmartBodyPart == bodyPart and action.atfSmartTreatmentId == id then
            return true
        end
        if
            action.handler
            and action.handler.bodyPart == bodyPart
            and handlers[action.handler.Type] == id
        then
            return true
        end
        if action.bodyPart == bodyPart and action.Type == timedTypes[id] then
            if id == "bandage" or id == "stitch" or id == "splint" then
                if action.doIt ~= false then
                    return true
                end
            elseif id == "removeBandage" or id == "removeStitch" or id == "removeSplint" then
                if action.doIt == false then
                    return true
                end
            else
                return true
            end
        end
    end
    return false
end
local function dispatch(choice, mode, cleanOnly)
    local handler, player, bodyPart, pane =
        choice.handler, choice.player, choice.bodyPart, choice.pane
    local nativeValid = handler.isValid
    local nativeCheck, refreshes = handler.checkItems, 0
    handler.checkItems = function(self, ...)
        refreshes = refreshes + 1
        return nativeCheck(self, ...)
    end
    handler.isValid = function(self, ...)
        if ownPane(player, bodyPart) ~= pane then
            return false
        end
        -- A few native handlers retain their menu-time item list (bullet/burn)
        -- or validate any available splint rather than the chosen fullType.
        -- Refresh through their own checkItem rules and require those exact
        -- selected types before delegating the medical/wound rules unchanged.
        local beforeRefresh = refreshes
        local valid = nativeValid(self, ...)
        if refreshes == beforeRefresh then
            for _ in pairs(self.items or {}) do
                self:checkItems()
                valid = nativeValid(self, ...)
                break
            end
        end
        if valid == false or valid == nil then
            return valid
        end
        for i = 1, select("#", ...) do
            local fullType = select(i, ...)
            if type(fullType) == "string" and fullType ~= "Hands" then
                local found = false
                for _, items in pairs(self.items or {}) do
                    if self:getItemOfType(items, fullType) then
                        found = true
                        break
                    end
                end
                if not found then
                    return false
                end
            end
        end
        return valid
    end
    if mode ~= "manual" then
        handler.getItemOfType = function(self, items, fullType)
            return bestItem(items, fullType, choice.id, mode, cleanOnly)
        end
    end
    local nativePerform = handler.perform
    handler.perform = function(self, previous, ...)
        if ownPane(player, bodyPart) ~= pane then
            return
        end
        local actions = ISTimedActionQueue.getTimedActionQueue(player).queue
        local existing = {}
        for _, action in ipairs(actions) do
            existing[action] = true
        end
        local function pack(...)
            return { n = select("#", ...), ... }
        end
        local result = pack(nativePerform(self, previous, ...))
        -- A body replacement after HealthPanelAction finishes must not target
        -- the obsolete body through the resulting native medical action.
        for _, action in ipairs(actions) do
            if not existing[action] and action.bodyPart == bodyPart and action.isValid then
                local nativeActionValid = action.isValid
                action.isValid = function(current, ...)
                    if ownPane(player, bodyPart) ~= pane then
                        return false
                    end
                    return nativeActionValid(current, ...)
                end
            end
        end
        return unpack(result, 1, result.n)
    end
    -- The existing callback queues HealthPanelAction; that handler rechecks
    -- inventory and wound validity again when it reaches the normal queue.
    local queue = ISTimedActionQueue.getTimedActionQueue(player).queue
    local before = {}
    for _, action in ipairs(queue) do
        before[action] = true
    end
    choice.option.onSelect(handler, unpack(choice.args, 1, 8))
    for _, action in ipairs(queue) do
        if not before[action] then
            return true
        end
    end
    return false
end
local function replacement(data, player, bodyPart, mode)
    if
        not bodyPart:bandaged()
        or bodyPart:getBandageLife() > 0
        or not ISTimedActionQueue.queueActions
    then
        return nil
    end
    local remove = choose(data, "removeBandage", "manual")
    if not remove then
        return nil
    end
    for _, handler in ipairs(data.handlers) do
        if handlers[handler.Type] == "bandage" then
            for _, item in ipairs(handler.items.ITEMS or {}) do
                if not dirty(item) then
                    return remove
                end
            end
        end
    end
end
function R.perform(player, bodyPart, id, mode, cleanOnly, manualArgs)
    mode = preference(mode)
    if not ownPane(player, bodyPart) or pending(player, bodyPart, id) then
        return false
    end
    local data = harvest(player, bodyPart)
    if not data then
        return false
    end
    if id == "replaceBandage" then
        if pending(player, bodyPart, "removeBandage") or pending(player, bodyPart, "bandage") then
            return false
        end
        local remove = replacement(data, player, bodyPart, mode)
        if not remove or not dispatch(remove, "manual") then
            return false
        end
        local queue = ISTimedActionQueue.getTimedActionQueue(player).queue
        local before = {}
        for _, action in ipairs(queue) do
            before[action] = true
        end
        ISTimedActionQueue.queueActions(player, function(character)
            -- If healed, moved to a new body, or lacking clean supplies after
            -- removal, do nothing. Cancellation clears this queued continuation.
            R.perform(character, bodyPart, "bandage", mode == "manual" and "best" or mode, true)
        end)
        for _, action in ipairs(queue) do
            if not before[action] then
                action.atfSmartBodyPart, action.atfSmartTreatmentId = bodyPart, id
            end
        end
        return true
    end
    local choice = choose(data, id, mode, cleanOnly, manualArgs)
    if not choice then
        return false
    end
    return dispatch(choice, mode, cleanOnly)
end
local function label(key, fallback)
    return getTextOrNull and getTextOrNull("UI_ATFCombatHealth_" .. key) or fallback
end
local function manualOption(menu, choice)
    local option = menu:addOption(choice.name, nil, function()
        return R.perform(choice.player, choice.bodyPart, choice.id, "manual", false, choice.args)
    end)
    option.itemForTexture = choice.option.itemForTexture
    return option
end
function R.open(player, bodyPart, x, y, mode)
    mode = preference(mode)
    local data = harvest(player, bodyPart, x, y, true)
    if not data then
        return false
    end
    local context = data.context
    if mode == "manual" then
        for _, choice in ipairs(data.choices) do
            choice.option.onSelect = function()
                return R.perform(player, bodyPart, choice.id, "manual", false, choice.args)
            end
        end
    else
        local manual, manualRoot
        local categories = {}
        for _, category in ipairs(context.options) do
            if data.categories[category] then
                categories[#categories + 1] = category
            end
        end
        for _, category in ipairs(categories) do
            local id = data.categories[category]
            if category.subOption then
                if not manual then
                    manualRoot =
                        context:addOption(label("ChooseItemManually", "Choose Item Manually"), nil)
                    manual = context:getNew(context)
                    context:addSubMenu(manualRoot, manual)
                end
                local manualCategory = manual:addOption(category.name, nil)
                local submenu = manual:getNew(manual)
                manual:addSubMenu(manualCategory, submenu)
                for _, choice in ipairs(data.choices) do
                    if choice.category == category then
                        manualOption(submenu, choice)
                    end
                end
                category.subOption = nil
            end
            category.target = nil
            category.onSelect = function()
                return R.perform(player, bodyPart, id, mode)
            end
            for i = 1, 10 do
                category["param" .. i] = nil
            end
        end
    end
    if replacement(data, player, bodyPart, mode) then
        context:addOption(label("ReplaceBandage", "Replace Bandage"), nil, function()
            return R.perform(player, bodyPart, "replaceBandage", mode)
        end)
    end
    return true, context
end

return R
