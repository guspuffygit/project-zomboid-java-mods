-- Real installed B42 health handlers and medical timed-action constructors.
-- Only UI attachment, inventory/BodyPart engine objects, and queue execution
-- are stubbed; production code must never call an engine damage setter itself.
local moduleRoot = arg[1] or arg[0]:match("^(.*)[/\\]tests[/\\][^/\\]+$") or "."
local gameRoot = assert(
    arg[2] or (os and os.getenv and os.getenv("PZ_GAME_ROOT")),
    "Pass the game root as argument 2"
)
local checks = 0
local function check(value, message)
    assert(value, message)
    checks = checks + 1
end
local function same(value, expected, message)
    check(value == expected, message .. " got " .. tostring(value))
end
local function loadSource(path)
    return dofile(path)
end
require = function() end
table.wipe = function(t)
    for key in pairs(t) do
        t[key] = nil
    end
end
loadSource(gameRoot .. "/media/lua/shared/ISBaseObject.lua")
loadSource(gameRoot .. "/media/lua/shared/TimedActions/ISBaseTimedAction.lua")
ISPanelJoypad, ISUIElement, ISBodyPartPanel, ISScrollingListBox =
    ISBaseObject, ISBaseObject, ISBaseObject, ISBaseObject
UIFont = { Small = "Small" }
getTextManager = function()
    return {
        getFontHeight = function()
            return 15
        end,
    }
end
getDebug, isDebugEnabled, isClient, isServer, isMultiplayer =
    function()
        return false
    end, function()
        return false
    end, function()
        return false
    end, function()
        return false
    end, function()
        return false
    end
Events = setmetatable({}, {
    __index = function()
        return { Add = function() end }
    end,
})
JoypadState = { players = {} }
Perks = { Doctor = "Doctor" }
CharacterTrait = { HEMOPHOBIC = "Hemophobic" }
BodyPartType = { Head = "Head", Torso_Upper = "Chest", Torso_Lower = "Abdomen", Groin = "Groin" }
BodyPartType.ToIndex = function()
    return 10
end
ComponentType = { FluidContainer = "FluidContainer" }
ItemTag = {
    SEWING_NEEDLE = "SewingNeedle",
    THREAD = "Thread",
    REMOVE_GLASS = "RemoveGlass",
    REMOVE_BULLET = "RemoveBullet",
    REUSABLE_BANDAGE = "ReusableBandage",
}
ItemTag.get = function(value)
    return value
end
ResourceLocation = {
    of = function(value)
        return value
    end,
}
getText = function(key)
    return key
end
getTextOrNull = function()
    return nil
end
local function list(values)
    return {
        size = function()
            return #values
        end,
        get = function(_, i)
            return values[i + 1]
        end,
    }
end
local active, nativeCompleting, setterCalls, scans, menus = nil, false, 0, 0, 0
local function item(kind, properties)
    local p = properties or {}
    local value = { kind = kind, p = p }
    function value:getFullType()
        return self.kind
    end
    function value:getType()
        return self.kind:match("[^.]+$")
    end
    function value:getModule()
        return self.kind:match("^(.*)%.")
    end
    function value:getName()
        return self.kind
    end
    function value:getContainer()
        return self.container
    end
    function value:IsInventoryContainer()
        return false
    end
    function value:getBandagePower()
        return self.p.power or 0
    end
    function value:isAlcoholic()
        return self.p.sterile == true
    end
    function value:isInfected()
        return self.p.infected == true
    end
    function value:getItemAfterCleaning()
        return self.p.cleaning
    end
    function value:getScriptItem()
        return {
            isMedicalLoot = function()
                return self.p.medical == true
            end,
        }
    end
    function value:hasTag(tag)
        return (self.p.tags or {})[tag] == true
    end
    function value:getCurrentUsesFloat()
        return self.p.uses or 1
    end
    function value:IsDrainable()
        return self.p.drain == true
    end
    function value:getAlcoholPower()
        return self.p.alcohol or 0
    end
    function value:hasComponent(component)
        return component == ComponentType.FluidContainer and self.p.fluid ~= nil
    end
    function value:getFluidContainer()
        return {
            getAmount = function()
                return self.p.fluid
            end,
            getProperties = function()
                return {
                    getAlcohol = function()
                        return self.p.fluid * self.p.fraction
                    end,
                }
            end,
        }
    end
    function value:UseAndSync()
        self.used = (self.used or 0) + 1
    end
    function value:setJobDelta() end
    return value
end
local function container()
    local c = { items = {} }
    function c:getItems()
        return list(self.items)
    end
    function c:contains(value)
        for _, entry in ipairs(self.items) do
            if
                entry == value
                or type(value) == "string"
                    and (entry:getType() == value or entry:getFullType() == value)
            then
                return true
            end
        end
        return false
    end
    function c:Remove(value)
        for i, entry in ipairs(self.items) do
            if entry == value then
                table.remove(self.items, i)
                return
            end
        end
    end
    function c:AddItem(kind)
        local value = type(kind) == "table" and kind or item(kind, { power = 0.5 })
        value.container = self
        self.items[#self.items + 1] = value
        return value
    end
    return c
end
local function bodyPart()
    local b = { kind = "Hand", scratch = true, bandage = false, life = 0, fracture = 0, splint = 0 }
    function b:getType()
        return self.kind
    end
    function b:getIndex()
        return 0
    end
    function b:HasInjury()
        return self.scratch
            or self.deep
            or self.glass
            or self.bullet
            or self.burn
            or self.fracture > 0
    end
    function b:bandaged()
        return self.bandage
    end
    function b:getBandageLife()
        return self.life
    end
    function b:getBandageType()
        return "Base.BandageDirty"
    end
    function b:stitched()
        return self.stitch == true
    end
    function b:isDeepWounded()
        return self.deep == true
    end
    function b:haveGlass()
        return self.glass == true
    end
    function b:haveBullet()
        return self.bullet == true
    end
    function b:getFractureTime()
        return self.fracture
    end
    function b:getSplintFactor()
        return self.splint
    end
    function b:getSplintItem()
        return "Base.Splint"
    end
    function b:isNeedBurnWash()
        return self.burn == true
    end
    function b:getPlantainFactor()
        return self.plantain or 0
    end
    function b:getComfreyFactor()
        return self.comfrey or 0
    end
    function b:getGarlicFactor()
        return self.garlic or 0
    end
    function b:manipulatingUsername()
        return nil
    end
    function b:setManipulatingUsername()
        check(nativeCompleting, "Only the real native timed action changes treatment engine state")
    end
    function b:isGetBandageXp()
        return false
    end
    return b
end
local queue = { queue = {} }
function queue:onCompleted(action)
    for i, value in ipairs(self.queue) do
        if value == action then
            table.remove(self.queue, i)
            break
        end
    end
end
ISTimedActionQueue = {
    getTimedActionQueue = function()
        return queue
    end,
    add = function(action)
        local current = queue.queue[1]
        if current and current._isAddingActions then
            table.insert(queue.queue, 2 + current._numAddedActions, action)
            current._numAddedActions = current._numAddedActions + 1
        else
            queue.queue[#queue.queue + 1] = action
        end
        return queue
    end,
    addAfter = function(previous, action)
        for i, value in ipairs(queue.queue) do
            if value == previous then
                table.insert(queue.queue, i + 1, action)
                return queue, action
            end
        end
    end,
    clear = function()
        queue.queue = {}
    end,
}
ISLogSystem = { logAction = function() end }
ISBaseTimedAction.forceComplete = function(self)
    self.completed = true
end
ISBaseTimedAction.forceStop = function(self)
    self.stopped = true
end
loadSource(gameRoot .. "/media/lua/client/TimedActions/ISQueueActionsAction.lua")
ISTimedActionQueue.queueActions = function(player, callback, ...)
    return ISTimedActionQueue.add(ISQueueActionsAction:new(player, callback, ...))
end
ISInventoryTransferUtil = {
    newInventoryTransferAction = function(player, value, source, destination)
        return {
            Type = "InventoryTransfer",
            character = player,
            item = value,
            source = source,
            destination = destination,
        }
    end,
}
ISInventoryPaneContextMenu = {
    getContainers = function(player)
        check(player == active.player, "Native inventory scan targets the actual local survivor")
        scans = scans + 1
        return list(active.containers)
    end,
}
local Menu = {}
function Menu:new(parent)
    local result = setmetatable(
        { options = {}, visible = true, parent = parent, numOptions = 1 },
        { __index = self }
    )
    result.root = parent and parent.root or result
    if not parent then
        result.instances = {}
        result.nextSub = 0
    end
    return result
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
    local result = Menu:new(parent or self)
    self.root.nextSub = self.root.nextSub + 1
    result.subOptionNums = self.root.nextSub
    self.root.instances[result.subOptionNums] = result
    return result
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
    self.visible = value
end
function Menu:getIsVisible()
    return self.visible
end
ISContextMenu = {
    get = function(playerNum, x, y)
        check(playerNum == 0, "Native UI targets local player index")
        menus = menus + 1
        active.menu, active.menuX, active.menuY = Menu:new(), x, y
        return active.menu
    end,
}
loadSource(gameRoot .. "/media/lua/client/XpSystem/ISUI/ISHealthPanel.lua")
for _, name in ipairs({
    "ISApplyBandage",
    "ISDisinfect",
    "ISStitch",
    "ISSplint",
    "ISRemoveGlass",
    "ISRemoveBullet",
    "ISCleanBurn",
    "ISPlantainCataplasm",
    "ISComfreyCataplasm",
    "ISGarlicCataplasm",
}) do
    loadSource(gameRoot .. "/media/lua/shared/TimedActions/" .. name .. ".lua")
end
ZombRandFloat = function(a)
    return a
end
syncBodyPart = function() end
instanceItem = function(kind)
    return item(kind, { power = 0.5 })
end
local function fixture(values)
    queue.queue = {}
    local f = {
        inventory = container(),
        part = bodyPart(),
        player = { alive = true, localPlayer = true },
    }
    f.parts = { f.part }
    f.containers = { f.inventory }
    local p = f.player
    function p:isLocalPlayer()
        return self.localPlayer
    end
    function p:isDead()
        return not self.alive
    end
    function p:getPlayerNum()
        return 0
    end
    function p:getUsername()
        return "survivor"
    end
    function p:getInventory()
        return f.inventory
    end
    function p:getPerkLevel()
        return 0
    end
    function p:getX()
        return 10
    end
    function p:getY()
        return 20
    end
    function p:isTimedActionInstant()
        return false
    end
    function p:isDriving()
        return false
    end
    function p:getVehicle()
        return nil
    end
    function p:getRole()
        return {
            hasCapability = function()
                return false
            end,
        }
    end
    function p:hasTrait()
        return false
    end
    function p:setIsFarming() end
    function p:getBodyDamage()
        return {
            getBodyParts = function()
                return list(f.parts)
            end,
            SetBandaged = function(_, index, bandaged, life)
                check(nativeCompleting, "Resolver never bypasses native BodyDamage treatment")
                setterCalls = setterCalls + 1
                f.part.bandage, f.part.life = bandaged, life
            end,
        }
    end
    f.pane = setmetatable(
        { character = p, doctorLevel = 0, actions = {} },
        { __index = ISHealthPanel }
    )
    function f.pane:getAbsoluteX()
        return 111
    end
    function f.pane:getAbsoluteY()
        return 222
    end
    getSpecificPlayer = function(index)
        return index == 0 and (f.currentPlayer or p) or nil
    end
    getPlayerInfoPanel = function()
        if f.missingPane then
            return nil
        end
        return { healthView = f.pane }
    end
    active = f
    function f.inventoryValues(newValues)
        f.inventory.items = newValues
        for _, value in ipairs(newValues) do
            value.container = f.inventory
        end
    end
    f.inventoryValues(values or {})
    function f.resolve(id, mode)
        return ATFSmartTreatmentResolver.resolve(p, f.part, id, mode)
    end
    function f.perform(id, mode)
        return ATFSmartTreatmentResolver.perform(p, f.part, id, mode)
    end
    function f.open(mode)
        return ATFSmartTreatmentResolver.open(p, f.part, 500, 300, mode)
    end
    return f
end
local function option(menu, label)
    for _, value in ipairs(menu.options) do
        if value.name == label then
            return value
        end
    end
end
local function invoke(value)
    return value.onSelect(
        value.target,
        value.param1,
        value.param2,
        value.param3,
        value.param4,
        value.param5,
        value.param6,
        value.param7,
        value.param8
    )
end
local function runHead()
    local action = queue.queue[1]
    check(action ~= nil, "Expected queued native action")
    if action.Type == "HealthPanelAction" then
        if not action:isValid() then
            queue:onCompleted(action)
            return action, false
        end
        action:perform()
    elseif action.Type == "ISQueueActionsAction" then
        action:start()
        ISBaseTimedAction.perform(action)
    elseif action.Type == "ISApplyBandage" then
        check(action:isValid(), "Native bandage action eligibility still applies")
        nativeCompleting = true
        action:complete()
        nativeCompleting = false
        ISBaseTimedAction.perform(action)
    elseif action.Type == "InventoryTransfer" then
        action.source:Remove(action.item)
        action.destination.items[#action.destination.items + 1] = action.item
        action.item.container = action.destination
        queue:onCompleted(action)
    else
        error("Unexpected action " .. tostring(action.Type))
    end
    return action, true
end
local beforeLoad = scans
local R = loadSource(moduleRoot .. "/media/lua/client/ATFCombatHealth/SmartTreatmentResolver.lua")
same(R, ATFSmartTreatmentResolver, "Resolver global and module agree")
same(scans, beforeLoad, "Loading resolver performs no inventory scan")

local dirtyBandage =
    item("Base.BandageDirty", { power = 0.5, medical = true, cleaning = "Base.Bandage" })
local cleanBandage = item("Base.Bandage", { power = 4, medical = true })
local sterileBandage = item("Base.AlcoholBandage", { power = 4, sterile = true, medical = true })
local cleanRag = item("Base.RippedSheets", { power = 2 })
local sterileRag = item("Base.AlcoholRippedSheets", { power = 2, sterile = true })
local f = fixture({ dirtyBandage, cleanRag, cleanBandage, sterileRag, sterileBandage })
same(f.resolve("bandage").item, sterileBandage, "Best chooses disinfected highest-grade bandage")
same(
    f.resolve("bandage", "conserve").item,
    cleanRag,
    "Conserve uses clean improvised supplies before sterile medical stock"
)
f.inventoryValues({ dirtyBandage, sterileRag, cleanRag })
same(f.resolve("bandage").item, sterileRag, "Disinfected improvised fallback wins equal grade")
f.inventoryValues({ dirtyBandage, cleanRag })
same(f.resolve("bandage").item, cleanRag, "Dirty never beats a valid clean alternative")
f.inventoryValues({ dirtyBandage })
same(
    f.resolve("bandage").item,
    dirtyBandage,
    "Dirty last resort is offered only when native permits it"
)
local modded = item("Mod.HighGradeDressing", { power = 6 })
local rejected = item("Mod.NotABandage", { power = 0, sterile = true, medical = true })
f.inventoryValues({ sterileBandage, rejected, modded })
same(
    f.resolve("bandage").item,
    modded,
    "Native-valid modded high grade beats vanilla medical-loot metadata"
)
f.inventoryValues({ rejected })
same(f.resolve("bandage"), nil, "Properties alone cannot invent a native treatment choice")
local firstOfType = item("Mod.AdaptiveDressing", { power = 4 })
local secondOfType = item("Mod.AdaptiveDressing", { power = 4, sterile = true })
f.inventoryValues({ firstOfType, secondOfType })
same(f.resolve("bandage").item, secondOfType, "Same-fullType instances are ranked by actual state")
check(f.perform("bandage"), "Explicit Bandage queues native handler")
same(queue.queue[1].Type, "HealthPanelAction", "Smart selection queues existing HealthPanelAction")
check(not f.perform("bandage"), "Repeated smart click cannot duplicate pending treatment")
local validityScans = scans
check(queue.queue[1]:isValid(), "Native bandage wrapper remains valid")
same(scans - validityScans, 1, "Native bandage queue validation scans inventory once")
runHead()
same(queue.queue[1].Type, "ISApplyBandage", "Native handler creates actual medical timed action")
same(queue.queue[1].item, secondOfType, "Native action receives the ranked same-type instance")
check(queue.queue[1].doIt, "Existing action owns bandage application")
check(not f.perform("bandage"), "Repeated click during native action cannot duplicate application")

-- The actual native menu retains eligible categories only; smart actions are
-- direct leaves, with a separate manual menu rather than callback+arrow ambiguity.
f = fixture({ dirtyBandage, sterileBandage, cleanRag })
check(f.open("best"), "Smart native menu opens")
same(f.menuX, 500, "Absolute menu X preserved")
same(f.menuY, 300, "Absolute menu Y preserved")
local bandageOption = option(f.menu, "ContextMenu_Bandage")
check(
    bandageOption.onSelect and not bandageOption.subOption,
    "Smart Bandage is one explicit leaf action"
)
check(
    not option(f.menu, "ContextMenu_Stitch") and not option(f.menu, "ContextMenu_Splint"),
    "Scratch menu cannot invent Stitch/Splint"
)
local manualRoot = option(f.menu, "Choose Item Manually")
check(
    manualRoot and manualRoot.subOption and not manualRoot.onSelect,
    "Manual choice has a separate native submenu"
)
local manual = f.menu:getSubMenu(manualRoot.subOption)
local manualBandage = option(manual, "ContextMenu_Bandage")
local manualItems = manual:getSubMenu(manualBandage.subOption)
same(#manualItems.options, 3, "All native manual item choices retained")
invoke(option(manualItems, "Base.RippedSheets"))
runHead()
same(queue.queue[1].item, cleanRag, "Manual choice preserves requested lower-grade supply")
f = fixture({ cleanRag, sterileBandage })
check(f.open("manual"), "Manual mode opens normal native menu")
bandageOption = option(f.menu, "ContextMenu_Bandage")
check(
    bandageOption.subOption and not bandageOption.onSelect,
    "Manual mode retains native category hierarchy"
)
same(option(f.menu, "Choose Item Manually"), nil, "Manual mode adds no redundant manual category")
same(
    #f.menu:getSubMenu(bandageOption.subOption).options,
    2,
    "Manual mode retains both native supplies"
)
local storedManual = f.menu:getSubMenu(bandageOption.subOption).options[1]
f.inventoryValues({ sterileBandage })
check(not invoke(storedManual), "Removed manual fullType cannot silently select a different supply")
same(#queue.queue, 0, "Stale manual item creates no action")
f = fixture({ cleanBandage })
f.open("best")
local storedSmart = option(f.menu, "ContextMenu_Bandage")
f.inventoryValues({ modded })
check(invoke(storedSmart), "Smart click reharvests mutated inventory")
runHead()
same(queue.queue[1].item, modded, "Smart menu cache cannot retain removed supply")
f.parts = { bodyPart() }
check(
    not queue.queue[1]:isValid(),
    "Body replacement also invalidates the resulting native medical action"
)

-- Unknown third-party menu categories keep their callback/parameters exactly;
-- they are never guessed into a smart category or automatically executed.
f = fixture({ cleanBandage })
local nativeBuilder = f.pane.doBodyPartContextMenu
local thirdPartyTarget, thirdPartyCalls = {}, 0
local thirdPartyCallback = function(target, value)
    same(target, thirdPartyTarget, "Unknown category retains third-party target")
    same(value, "custom-argument", "Unknown category retains third-party parameters")
    thirdPartyCalls = thirdPartyCalls + 1
end
f.pane.doBodyPartContextMenu = function(self, body, x, y)
    local previousGet, built = ISContextMenu.get, nil
    ISContextMenu.get = function(...)
        built = previousGet(...)
        return built
    end
    nativeBuilder(self, body, x, y)
    ISContextMenu.get = previousGet
    built:addOption(
        "Third-party Treatment",
        thirdPartyTarget,
        thirdPartyCallback,
        "custom-argument"
    )
end
check(f.open("best"), "Current third-party native-menu extension preserved")
local thirdPartyOption = option(f.menu, "Third-party Treatment")
same(thirdPartyOption.onSelect, thirdPartyCallback, "Unknown category callback is untouched")
same(thirdPartyCalls, 0, "Building smart menu never executes unknown treatment")
same(f.resolve("unknown"), nil, "Unknown category never becomes guessed smart action")
invoke(thirdPartyOption)
same(thirdPartyCalls, 1, "Unknown native treatment remains available on explicit selection")

-- Effectiveness is the same expression used by actual ISDisinfect.complete.
local weakAlcohol = item("Mod.WeakAlcohol", { fluid = 1, fraction = 0.4 })
local strongAlcohol = item("Mod.StrongAlcohol", { fluid = 1, fraction = 0.8 })
local medicalAlcohol = item("Base.AlcoholWipes", { drain = true, alcohol = 4 })
local invalidAlcohol = item("Mod.WeakDrink", { fluid = 1, fraction = 0.2 })
f = fixture({ weakAlcohol, strongAlcohol, invalidAlcohol, medicalAlcohol })
same(f.resolve("disinfect").item, medicalAlcohol, "Highest exposed disinfectant strength wins")
same(
    f.resolve("disinfect", "conserve").item,
    weakAlcohol,
    "Conserve chooses weakest native-adequate disinfectant"
)
f.inventoryValues({ strongAlcohol, weakAlcohol })
same(f.resolve("disinfect").item, strongAlcohol, "Valid fluid potency uses actual alcohol fraction")
f.inventoryValues({ invalidAlcohol })
same(f.resolve("disinfect"), nil, "Inadequate alcohol rejected by native handler")
f.inventoryValues({ medicalAlcohol })
check(f.perform("disinfect"), "Explicit disinfect queues normal action")
runHead()
same(queue.queue[1].Type, "ISDisinfect", "Native disinfect action used")
same(queue.queue[1].alcohol, medicalAlcohol, "Native disinfect action retains resolved supply")

local needle = item("Base.Needle")
local thread = item("Base.Thread", { tags = { Thread = true } })
local suture = item("Base.SutureNeedle")
f = fixture({ thread, needle, suture })
same(f.resolve("stitch"), nil, "Non-deep wounds never expose native Stitch")
f.part.deep = true
same(
    f.resolve("stitch").item,
    suture,
    "Best selects native suture setup with documented duration/pain advantage"
)
local setup = f.resolve("stitch", "conserve")
same(setup.args[1], "Base.Needle", "Conserve preserves suture stock with valid needle/thread setup")
same(#setup.items, 2, "Supporting needle and thread are retained")
check(f.perform("stitch", "conserve"), "Explicit Stitch queues native setup")
runHead()
same(queue.queue[1].Type, "ISStitch", "Native stitching action used")
same(queue.queue[1].item, thread, "Native stitch consumes its actual thread supply")
f = fixture({ needle, thread, suture })
f.part.deep, f.part.glass = true, true
same(f.resolve("stitch"), nil, "Glass blocks Stitch through current native rules")
f.part.glass, f.part.bandage = false, true
same(f.resolve("stitch"), nil, "Bandaged wound cannot bypass native Stitch restriction")

local properSplint = item("Base.Splint")
local plank = item("Base.Plank")
f = fixture({ cleanRag, plank, properSplint })
same(f.resolve("splint"), nil, "No fracture never exposes Splint")
f.part.fracture = 10
same(f.resolve("splint").args[1], nil, "Ready-made native splint preferred")
check(f.perform("splint"), "Explicit Splint queues native action")
runHead()
same(queue.queue[1].Type, "ISSplint", "Native splint timed action used")
same(queue.queue[1].plank, properSplint, "Native ready-made splint supply retained")
f = fixture({ cleanRag, plank })
f.part.fracture = 10
same(#f.resolve("splint").items, 2, "Native material combination supplies both sheet and plank")
for _, kind in ipairs({ "Head", "Chest", "Abdomen" }) do
    f.part.kind = kind
    same(f.resolve("splint"), nil, "Native body-part restriction excludes " .. kind)
end
local branch = item("Base.TreeBranch")
f = fixture({ cleanRag, plank, branch })
f.part.fracture = 10
check(f.perform("splint"), "Selected native material combination queued")
f.inventoryValues({ cleanRag, branch })
validityScans = scans
check(
    not queue.queue[1]:isValid(),
    "Alternate plank cannot conceal removal of selected splint fullType"
)
same(scans - validityScans, 1, "Native splint queue validation scans inventory once")

local tool = item("Mod.TaggedTool", { tags = { RemoveGlass = true, RemoveBullet = true } })
f = fixture({ tool })
f.part.glass = true
same(f.resolve("removeGlass").item, tool, "Native tag-qualified modded glass tool beats hands")
same(#queue.queue, 0, "Resolving invasive treatment never runs it")
check(f.perform("removeGlass"), "Player explicitly selects Remove Glass")
runHead()
same(queue.queue[1].Type, "ISRemoveGlass", "Actual native glass action used")
check(not queue.queue[1].handPain, "Tool selection retains native reduced-pain path")
f = fixture()
f.part.glass = true
same(f.resolve("removeGlass").args[1], "Hands", "Native hands fallback retained without tools")
f = fixture({ tool })
f.part.bullet = true
check(f.perform("removeBullet"), "Explicit native bullet treatment queued")
local bulletPending = queue.queue[1]
f.inventoryValues({})
validityScans = scans
check(
    not bulletPending:isValid(),
    "Bullet handler's menu-time item list cannot bypass removed-tool eligibility"
)
same(scans - validityScans, 1, "Cached native bullet handler receives one fresh scan")
same(#queue.queue, 1, "Invalidated handler adds no native bullet action")
f = fixture({ cleanRag, cleanBandage, dirtyBandage })
f.part.burn = true
same(f.resolve("cleanBurn").item, cleanBandage, "Burn cleaning chooses best native-valid material")
same(
    f.resolve("cleanBurn", "conserve").item,
    cleanRag,
    "Conserve cleaning uses adequate native material"
)
check(f.perform("cleanBurn"), "Explicit native burn cleaning queued")
f.inventoryValues({ dirtyBandage })
validityScans = scans
check(
    not queue.queue[1]:isValid(),
    "Burn cleaning cannot retain missing fullType after inventory change"
)
same(scans - validityScans, 1, "Cached native burn handler receives one fresh scan")

local plantain = item("Mod.PlantainCataplasm")
local comfrey = item("Base.ComfreyCataplasm")
local garlic = item("Base.WildGarlicCataplasm")
f = fixture({ plantain, comfrey, garlic })
same(f.resolve("plantain").item, plantain, "Native module-qualified poultice supported")
same(f.resolve("comfrey").item, comfrey, "Comfrey is a separate medical category")
same(f.resolve("garlic").item, garlic, "Garlic is a separate medical category")
f.part.plantain = 1
same(f.resolve("comfrey"), nil, "Native already-applied poultice gate preserved")
same(f.resolve("garlic"), nil, "Poultices cannot be combined by guessed smart logic")
for _, case in ipairs({
    { id = "plantain", values = { plantain }, action = "ISPlantainCataplasm", supply = plantain },
    { id = "comfrey", values = { comfrey }, action = "ISComfreyCataplasm", supply = comfrey },
    { id = "garlic", values = { garlic }, action = "ISGarlicCataplasm", supply = garlic },
    { id = "removeBullet", values = { tool }, action = "ISRemoveBullet", flag = "bullet" },
    {
        id = "cleanBurn",
        values = { cleanRag },
        action = "ISCleanBurn",
        flag = "burn",
        supply = cleanRag,
    },
    { id = "removeStitch", values = {}, action = "ISStitch", flag = "stitch" },
    { id = "removeSplint", values = {}, action = "ISSplint", flag = "splint" },
}) do
    f = fixture(case.values)
    if case.flag then
        f.part[case.flag] = case.flag == "splint" and 2 or true
    end
    check(f.perform(case.id), "Explicit " .. case.id .. " invokes eligible native callback")
    runHead()
    same(queue.queue[1].Type, case.action, case.id .. " creates actual native timed-action class")
    same(queue.queue[1].bodyPart, f.part, case.id .. " retains exact native body-part reference")
    same(queue.queue[1].otherPlayer, f.player, case.id .. " retains local patient")
    if case.supply then
        same(
            queue.queue[1].item or queue.queue[1].bandage,
            case.supply,
            case.id .. " retains verified native item argument"
        )
    end
    if case.id == "removeStitch" or case.id == "removeSplint" then
        check(queue.queue[1].doIt == false, case.id .. " keeps native removal flag")
    end
end

f = fixture({ cleanBandage })
local bag = container()
bag.items = { sterileBandage }
sterileBandage.container = bag
f.containers = { f.inventory, bag }
check(f.perform("bandage"), "Smart selection supports native-accessible bag supplies")
runHead()
same(
    queue.queue[1].Type,
    "InventoryTransfer",
    "Native handler queues ordinary inventory transfer first"
)
same(queue.queue[2].Type, "ISApplyBandage", "Native medical action follows its required transfer")
same(queue.queue[2].item, sterileBandage, "Bag supply chosen through actual native callback")
runHead()
check(
    queue.queue[1]:isValid(),
    "Native medical action becomes valid after actual inventory transfer"
)

-- Native removal is actually completed before the native queueActions callback
-- reharvests Bandage; replacement never edits BodyDamage in resolver code.
f = fixture({ cleanRag, sterileBandage, dirtyBandage })
f.part.bandage, f.part.life = true, 0
check(f.open("best"), "Dirty-bandage treatment menu opens")
check(option(f.menu, "Replace Bandage"), "Clean supplies enable replacement control")
local settersBefore = setterCalls
check(f.perform("replaceBandage"), "Explicit replacement starts normal removal/continuation")
same(setterCalls, settersBefore, "Queuing replacement does not mutate BodyDamage")
same(#queue.queue, 2, "Removal wrapper and deferred native queue callback queued")
check(not f.perform("replaceBandage"), "Repeated replacement click cannot duplicate continuation")
runHead()
same(queue.queue[1].Type, "ISApplyBandage", "Native removal inserted before deferred callback")
check(queue.queue[1].doIt == false, "First native medical action removes bandage")
same(queue.queue[2].Type, "ISQueueActionsAction", "Continuation waits behind actual native removal")
runHead()
check(not f.part.bandage, "Only native completion removed old bandage")
check(f.resolve("bandage") ~= nil, "Clean replacement is native-eligible after removal")
runHead()
same(
    queue.queue[1].Type,
    "HealthPanelAction",
    "Continuation freshly obtains native Bandage handler"
)
runHead()
same(
    queue.queue[1].Type,
    "ISApplyBandage",
    "Replacement uses actual native application timed action"
)
same(queue.queue[1].item, sterileBandage, "Replacement chooses best current clean supply")
check(queue.queue[1].doIt, "Replacement native action applies clean bandage")
check(f.part.bandage == false, "Queuing replacement still does not apply it instantly")

for _, scenario in ipairs({ "suppliesLost", "healed", "cancel", "newBody" }) do
    f = fixture({ cleanBandage, dirtyBandage })
    f.part.bandage, f.part.life = true, 0
    check(f.perform("replaceBandage"), scenario .. " replacement initially queued")
    runHead()
    if scenario == "cancel" then
        ISTimedActionQueue.clear(f.player)
        same(#queue.queue, 0, "Native queue cancellation drops removal and continuation")
    else
        runHead()
        if scenario == "suppliesLost" then
            f.inventoryValues({ dirtyBandage })
        elseif scenario == "healed" then
            f.part.scratch = false
        else
            f.parts = { bodyPart() }
        end
        runHead()
        same(#queue.queue, 0, scenario .. " deferred replacement adds no invalid/dirty treatment")
    end
end
f = fixture({ dirtyBandage })
f.part.bandage, f.part.life = true, 0
check(
    not f.perform("replaceBandage"),
    "Dirty-only stock cannot remove bandage for another dirty replacement"
)
same(#queue.queue, 0, "Failed clean replacement starts no removal")
f = fixture({ cleanBandage })
f.part.bandage, f.part.life = true, 1
check(not f.perform("replaceBandage"), "Clean active bandage is not automatically replaced")

-- Staleness at both menu selection and queued native execution. Nothing scans
-- on idle frames because this module installs no tick/inventory event listeners.
f = fixture({ cleanBandage })
local nativeCheckItems, overrideValidCalls = f.pane.checkItems, 0
f.pane.checkItems = function(self, current, ...)
    nativeCheckItems(self, current, ...)
    for _, handler in ipairs(current) do
        if handler.Type == "HApplyBandage" then
            handler.isValid = function(target, fullType)
                overrideValidCalls = overrideValidCalls + 1
                return target:getItemOfType(target.items.ITEMS, fullType) and target:isInjured()
            end
        end
    end
end
check(f.perform("bandage"), "Current mod override with cached eligibility can dispatch")
f.inventoryValues({})
local validityCalls = overrideValidCalls
validityScans = scans
check(not queue.queue[1]:isValid(), "Current cached override cannot retain removed supply")
same(scans - validityScans, 1, "Cached override uses one native eligibility refresh")
same(
    overrideValidCalls - validityCalls,
    2,
    "Cached override predicate is revalidated after native refresh"
)
f.inventoryValues({ cleanBandage })
validityScans = scans
check(
    queue.queue[1]:isValid(),
    "Cached override accepts returned valid supplies after fresh eligibility"
)
same(scans - validityScans, 1, "Returned supply also uses one native refresh")
f = fixture({ cleanBandage })
f.open("best")
storedSmart = option(f.menu, "ContextMenu_Bandage")
f.part.scratch = false
check(not invoke(storedSmart), "Healed wound invalidates cached smart menu")
same(#queue.queue, 0, "Healed menu dispatch adds no action")
f.part.scratch = true
check(f.perform("bandage"), "Native application wrapper queued before fullType removal")
f.inventoryValues({})
check(not queue.queue[1]:isValid(), "Queued bandage validates current inventory")
f.inventoryValues({ cleanBandage })
check(queue.queue[1]:isValid(), "Queued bandage may become valid again with native supply")
f.parts = { bodyPart() }
check(not queue.queue[1]:isValid(), "Replacement BodyDamage object invalidates queued reference")
f = fixture({ cleanBandage })
f.player.localPlayer = false
same(f.resolve("bandage"), nil, "Remote survivor rejected")
f.player.localPlayer, f.player.alive = true, false
check(not f.open("best"), "Dead survivor cannot open treatment")
f.player.alive = true
f.currentPlayer = {}
check(not f.perform("bandage"), "Obsolete survivor identity cannot dispatch treatment")
f.currentPlayer = nil
f.pane.otherPlayer = {}
check(not f.open("best"), "Health pane inspecting another survivor cannot supply treatment")
f.pane.otherPlayer, f.pane.blockingMessage = nil, "Treatment blocked"
check(not f.perform("bandage"), "Native blocking status respected")
f.pane.blockingMessage = nil
f.missingPane = true
check(not f.open("best"), "Absent native Health pane cannot supply treatment")
f.missingPane = false
local originalGet, originalCheck = ISContextMenu.get, f.pane.checkItems
f.pane.doBodyPartContextMenu = function()
    error("third-party builder error")
end
check(not f.open("best"), "Broken current native builder fails without invented fallback")
same(ISContextMenu.get, originalGet, "Temporary native menu interception restored after error")
same(
    f.pane.checkItems,
    originalCheck,
    "Temporary native inventory interception restored after error"
)
local idleScans = scans
for _ = 1, 200 do
    local noop = R
end
same(scans, idleScans, "Idle HUD work cannot scan treatment inventory")
same(setterCalls, settersBefore + 4, "Only actual completed native removals mutated bandage state")
print("PASS " .. checks .. " Smart Treatment / installed native menu and action checks")
