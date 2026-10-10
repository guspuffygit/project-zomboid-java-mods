-- Read the actual installed vanilla UI chunk to verify label gates and treatment
-- handlers. Arguments are the module root and the game root, matching Gradle.
local moduleRoot = arg[1] or arg[0]:match("^(.*)[/\\]tests[/\\][^/\\]+$") or "."
local gameRoot = assert(
    arg[2] or (os and os.getenv and os.getenv("PZ_GAME_ROOT")),
    "Pass the game root as argument 2"
)
local function loadSource(path)
    if readTestSource then
        return assert(loadstring(readTestSource(path), "@" .. path))()
    end
    return dofile(path)
end
local checks = 0
local function check(value, message)
    assert(value, message)
    checks = checks + 1
end

require = function() end
local UI = {}
function UI:derive(name)
    local result = { Type = name }
    result.__index = result
    return setmetatable(result, { __index = self })
end
function UI:new(character)
    return setmetatable({ character = character }, { __index = self })
end
function UI:perform() end
ISPanelJoypad, ISUIElement, ISBodyPartPanel, ISScrollingListBox = UI, UI, UI, UI
ISBaseObject, ISBaseTimedAction = UI, UI
UIFont = { Small = "Small" }
getTextManager = function()
    return {
        getFontHeight = function()
            return 15
        end,
    }
end
getDebug = function()
    return false
end
isDebugEnabled = function()
    return false
end
isClient = function()
    return false
end
Events = setmetatable({}, {
    __index = function()
        return { Add = function() end }
    end,
})
JoypadState = { players = {} }
Perks = { Doctor = "Doctor" }
MoodleType = { PAIN = "Pain", BLEEDING = "Bleeding" }
BodyPartType = {
    getDisplayName = function(value)
        return value
    end,
}
ComponentType = { FluidContainer = "FluidContainer" }
ItemTag = {}
ResourceLocation = {
    of = function(value)
        return value
    end,
}
ItemTag.get = function(value)
    return value
end
getText = function(key)
    return key
end
getTextOrNull = function(key)
    local values = {
        UI_ATFCombatHealth_NoPain = "No pain",
        UI_ATFCombatHealth_NoActiveBleeding = "No active bleeding",
        UI_ATFCombatHealth_NoInjury = "No visible injury",
    }
    return values[key]
end
table.wipe = function(value)
    for key in pairs(value) do
        value[key] = nil
    end
end

local function list(values)
    return {
        size = function()
            return #values
        end,
        get = function(_, ordinal)
            return values[ordinal + 1]
        end,
    }
end
local fields = {
    getPlantainFactor = "plantain",
    getComfreyFactor = "comfrey",
    getGarlicFactor = "garlic",
    getScratchTime = "scratchTime",
    getCutTime = "cutTime",
    getDeepWoundTime = "deepTime",
    getAdditionalPain = "pain",
    getStiffness = "stiffness",
    getFractureTime = "fracture",
    getSplintFactor = "splint",
    getBandageLife = "bandageLife",
    getBurnTime = "burnTime",
    getWoundInfectionLevel = "infectionLevel",
    getStitchTime = "stitchTime",
}
local flags = {
    scratched = "scratch",
    isCut = "cut",
    deepWounded = "deep",
    isDeepWounded = "deep",
    bitten = "bite",
    bleeding = "bleedingFlag",
    bandaged = "bandage",
    stitched = "stitch",
    isInfectedWound = "infection",
    haveBullet = "bullet",
    haveGlass = "glass",
    isNeedBurnWash = "burnWash",
}
local function part(name)
    local result = { name = name }
    for method, value in pairs(fields) do
        local key = value
        result[method] = function(self)
            return self[key] or 0
        end
    end
    for method, value in pairs(flags) do
        local key = value
        result[method] = function(self)
            return self[key] == true
        end
    end
    function result:HasInjury()
        return self.scratch
            or self.cut
            or self.deep
            or self.bite
            or self.bleedingFlag
            or self.infection
            or self.bullet
            or self.glass
            or (self.fracture or 0) > 0
            or (self.burnTime or 0) > 0
    end
    function result:getType()
        return self.name
    end
    -- These private/debug getters must never be used by the model.
    function result:IsInfected()
        error("Zombie infection is private")
    end
    function result:getHealth()
        error("Individual health is debug information")
    end
    return result
end
local parts = { part("Left Hand"), part("Right Hand"), part("Left Forearm") }
local health, playerNum = 100, 0
local player = { localPlayer = true, dead = false, doctor = 0, pain = 0, bleedMoodle = 0 }
function player:isLocalPlayer()
    return self.localPlayer
end
function player:isDead()
    return self.dead
end
function player:getPlayerNum()
    return playerNum
end
function player:getPerkLevel(perk)
    check(perk == Perks.Doctor, "Only the actual medical skill is read")
    return self.doctor
end
local damageReads = 0
function player:getBodyDamage()
    damageReads = damageReads + 1
    return {
        getBodyParts = function()
            return list(parts)
        end,
        getHealth = function()
            return health
        end,
    }
end
function player:getMoodles()
    return {
        getMoodleLevel = function(_, moodle)
            if moodle == MoodleType.PAIN then
                return player.pain
            end
            if moodle == MoodleType.BLEEDING then
                return player.bleedMoodle
            end
            error("Unexpected moodle")
        end,
    }
end
function player:getStats()
    error("No private infection or fever statistics")
end
function player:getModData()
    error("Snapshot must not create or modify mod data")
end
local currentPlayer = player
getSpecificPlayer = function(ordinal)
    return ordinal == playerNum and currentPlayer or nil
end
local info
getPlayerInfoPanel = function(ordinal)
    return ordinal == playerNum and info or nil
end

local inventoryItems, inventoryScans, queue = {}, 0, {}
local inventory = {
    getItems = function()
        return list(inventoryItems)
    end,
}
function player:getInventory()
    return inventory
end
ISInventoryPaneContextMenu = {
    getContainers = function(character)
        check(character == player, "Native treatment scans only the current local inventory")
        inventoryScans = inventoryScans + 1
        return list({ inventory })
    end,
}
ISTimedActionQueue = {
    getTimedActionQueue = function()
        return { queue = queue }
    end,
    add = function(action)
        queue[#queue + 1] = action
    end,
    addAfter = function(previous, action)
        queue[#queue + 1] = action
    end,
}
ISApplyBandage = {
    new = function(_, doctor, patient, item, bodyPart, applying)
        return {
            Type = "ISApplyBandage",
            doctor = doctor,
            patient = patient,
            item = item,
            bodyPart = bodyPart,
            applying = applying,
        }
    end,
}
local Menu = {}
function Menu:new()
    return setmetatable({ options = {}, visible = true }, { __index = self })
end
function Menu:addOption(name, target, callback, ...)
    local option = { name = name, target = target, onSelect = callback }
    for index = 1, select("#", ...) do
        option["param" .. index] = select(index, ...)
    end
    self.options[#self.options + 1] = option
    return option
end
function Menu:getNew()
    return Menu:new()
end
function Menu:addSubMenu(option, submenu)
    option.submenu = submenu
    option.subOption = submenu
end
function Menu:getSubMenu(submenu)
    return submenu
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
local lastMenu, menuCount, menuX, menuY
menuCount = 0
ISContextMenu = {
    get = function(ordinal, x, y)
        check(ordinal == playerNum, "Menu is opened for the current local player")
        menuCount, menuX, menuY = menuCount + 1, x, y
        lastMenu = Menu:new()
        return lastMenu
    end,
}

loadSource(gameRoot .. "/media/lua/client/XpSystem/ISUI/ISHealthPanel.lua")
local pane = setmetatable(
    { character = player, doctorLevel = 0, actions = {} },
    { __index = ISHealthPanel }
)
function pane:getAbsoluteX()
    return 111
end
function pane:getAbsoluteY()
    return 222
end
pane.healthPanel = {
    javaObject = {
        getDamageStatusString = function()
            return "Native status"
        end,
    },
}
info = { healthView = pane }
ISHealthPanel.instance = "preserved instance"
loadSource(moduleRoot .. "/media/lua/client/ATFCombatHealth/SmartTreatmentResolver.lua")
local Model = loadSource(moduleRoot .. "/media/lua/client/ATFCombatHealth/HealthModel.lua")
check(Model == ATFCombatHealthModel, "Returned module and global API agree")

local function row(snapshot, id)
    for _, value in ipairs(snapshot.rows) do
        if value.id == id then
            return value
        end
    end
end
local function hasLabel(value, label)
    if not value then
        return false
    end
    for _, text in ipairs(value.labels) do
        if text == label then
            return true
        end
    end
    return false
end
local function nativeLabels(bodyPart)
    pane.doctorLevel = player.doctor
    local found = {}
    local box = {
        parent = pane,
        width = 400,
        selected = -1,
        drawText = function(_, label)
            if label:sub(1, 2) == "- " then
                found[#found + 1] = label:sub(3):gsub("%s+", " "):gsub("%s+$", "")
            end
        end,
    }
    ISHealthBodyPartListBox.doDrawItem(box, 0, { item = { bodyPart = bodyPart }, itemindex = 1 })
    return found
end
local function nativeAgreement(bodyPart, id, message)
    local snapshot = Model.snapshot(player)
    local result, expected = row(snapshot, id), {}
    for _, label in ipairs(nativeLabels(bodyPart)) do
        -- Native strain is deliberately moved to the passive summary rather
        -- than included in this comparison of treatment row labels.
        if
            label ~= getText("IGUI_health_MinorStiffness")
            and label ~= getText("IGUI_health_Stiffness")
        then
            expected[#expected + 1] = label
        end
    end
    if #expected == 0 then
        check(
            result == nil,
            message .. " has no actionable native labels after excluding passive strain"
        )
        return result, snapshot
    end
    check(
        result and #result.labels == #expected,
        message .. " actionable label count matches installed Health UI"
    )
    for ordinal, label in ipairs(expected) do
        check(
            result.labels[ordinal] == label,
            message .. " label " .. ordinal .. " matches installed Health UI"
        )
    end
    return result, snapshot
end

local snapshot = Model.snapshot(player)
check(
    #snapshot.rows == 0 and snapshot.status == "Native status",
    "Healthy snapshot stays empty and uses native status"
)
check(
    #snapshot.allRows == #parts,
    "Showing healthy body parts includes the complete native body-part list"
)
for ordinal, value in ipairs(snapshot.allRows) do
    check(
        value.id == ordinal - 1
            and value.bodyPart == parts[ordinal]
            and value.name == parts[ordinal].name,
        "Healthy rows retain native identity and display names"
    )
    check(
        value.severity == 0
            and value.summary == "No visible injury"
            and value.labels[1] == "No visible injury",
        "Healthy rows use a localized presentation placeholder"
    )
end
check(
    snapshot.health == 100 and snapshot.bleeding == 0 and snapshot.blood == "No active bleeding",
    "No invented blood-volume value"
)
check(
    snapshot.pain == 0 and snapshot.painText == "No pain" and not snapshot.critical,
    "Healthy native moodles remain quiet"
)
check(
    Model.snapshot(player).signature == snapshot.signature,
    "Unchanged state has a deterministic signature"
)
check(snapshot.strain == nil, "Healthy survivors have no passive strain summary")
check(
    inventoryScans == 0 and menuCount == 0 and #queue == 0,
    "Snapshot never scans inventory or creates treatment UI/actions"
)

local healthySignature = snapshot.signature
parts[1].stiffness = 4.999
check(#pane:getDamagedParts() == 0, "Native normal Health list conceals sub-threshold strain")
snapshot = Model.snapshot(player)
check(
    snapshot.strain == nil and #snapshot.rows == 0 and snapshot.signature == healthySignature,
    "Sub-threshold strain does not create rows, summary, or cache changes"
)
parts[1].stiffness = 5
check(#pane:getDamagedParts() == 0, "Native strain-only list gate is strictly greater than five")
check(Model.snapshot(player).strain == nil, "Standalone strain at exactly five remains concealed")
parts[1].stiffness = 5.001
check(#pane:getDamagedParts() == 1, "Native Health list includes strain above five")
check(
    nativeLabels(parts[1])[1] == "IGUI_health_MinorStiffness",
    "Installed renderer supplies the native minor strain label"
)
local _, minorStrain = nativeAgreement(parts[1], 0, "Strain-only body part")
check(
    #minorStrain.rows == 0
        and minorStrain.strain.count == 1
        and minorStrain.strain.text == "IGUI_health_MinorStiffness",
    "Strain-only survivors retain only one passive summary"
)
check(
    minorStrain.allRows[1].summary == "No visible injury"
        and minorStrain.allRows[1].severity == 0
        and minorStrain.allRows[1].signals.stiffness == nil,
    "Passive strain supplies neither an actionable label nor injury signal or emphasis"
)
local strainScans, strainMenus = inventoryScans, menuCount
check(
    not Model.openTreatment(player, parts[1], 10, 20),
    "Strain-only body parts cannot dispatch native treatment"
)
check(
    inventoryScans == strainScans and menuCount == strainMenus and #queue == 0,
    "Rejecting passive strain performs no inventory scan, menu, or timed action"
)
check(minorStrain.signature ~= healthySignature, "Visible strain enters the snapshot signature")
parts[1].stiffness = 19.999
check(
    Model.snapshot(player).signature == minorStrain.signature,
    "Invisible changes within the minor strain grade stay cached"
)
parts[1].stiffness = 20
check(
    nativeLabels(parts[1])[1] == "IGUI_health_Stiffness",
    "Installed renderer changes grade at exactly twenty"
)
local strongStrain = Model.snapshot(player)
check(
    strongStrain.strain.count == 1
        and strongStrain.strain.text == "IGUI_health_Stiffness"
        and strongStrain.signature ~= minorStrain.signature,
    "Native strain grade changes update the passive summary and signature"
)
parts[2].stiffness = 6
local multipleStrain = Model.snapshot(player)
check(
    multipleStrain.strain.count == 2
        and multipleStrain.strain.text == "IGUI_health_Stiffness"
        and #multipleStrain.rows == 0
        and multipleStrain.signature ~= strongStrain.signature,
    "Affected body parts are counted once and the worst visible native grade wins"
)
parts[1].stiffness = 0
local recoveringStrain = Model.snapshot(player)
check(
    recoveringStrain.strain.count == 1
        and recoveringStrain.strain.text == "IGUI_health_MinorStiffness"
        and recoveringStrain.signature ~= multipleStrain.signature,
    "Strain recovery updates count and worst grade"
)
parts[2].stiffness = 0
snapshot = Model.snapshot(player)
check(
    snapshot.strain == nil and snapshot.signature == healthySignature,
    "Removing the last strain restores the healthy summary and signature"
)

parts[1].cut, parts[1].stiffness = true, 5
check(
    #pane:getDamagedParts() == 1,
    "An actual wound keeps its body part in the native list at the exact strain boundary"
)
local mixed, mixedSnapshot = nativeAgreement(parts[1], 0, "Mixed wound and boundary strain")
check(
    #mixedSnapshot.rows == 1
        and hasLabel(mixed, "IGUI_health_Cut")
        and not hasLabel(mixed, "IGUI_health_MinorStiffness")
        and mixed.signals.cut == 1
        and mixed.signals.stiffness == nil,
    "A mixed wound retains its native actionable label and signal without strain"
)
check(
    mixedSnapshot.strain.count == 1 and mixedSnapshot.strain.text == "IGUI_health_MinorStiffness",
    "Strain at exactly five is visible on an otherwise visible wounded part"
)
parts[1].bleedingFlag, parts[1].stiffness = true, 20
mixed, mixedSnapshot = nativeAgreement(parts[1], 0, "Mixed bleeding wound and strong strain")
check(
    #mixedSnapshot.rows == 1
        and hasLabel(mixed, "IGUI_health_Cut")
        and hasLabel(mixed, "IGUI_health_Bleeding")
        and mixed.severity == 2
        and mixed.signals.bleeding == 1
        and mixedSnapshot.strain.text == "IGUI_health_Stiffness",
    "Strain leaves native bleeding and treatment-row severity intact"
)
parts[1].cut, parts[1].bleedingFlag = false, false
check(
    not Model.openTreatment(player, parts[1], 10, 20) and menuCount == strainMenus,
    "A previously injured cached body part cannot open treatment after only strain remains"
)
parts[1].cut, parts[1].bleedingFlag, parts[1].stiffness = false, false, 0
check(
    Model.snapshot(player).signature == healthySignature,
    "Mixed injury regression leaves the fixture healthy"
)

local initialReads = damageReads
player.localPlayer = false
check(Model.snapshot(player) == nil, "Remote health is rejected")
check(not Model.openTreatment(player, parts[1], 10, 20), "Remote treatment is rejected")
player.localPlayer = true
currentPlayer = {}
check(Model.snapshot(player) == nil, "An obsolete character is rejected after reconnect")
check(
    not Model.openTreatment(player, parts[1], 10, 20),
    "An obsolete character cannot open treatment"
)
currentPlayer = player
player.dead = true
check(Model.snapshot(player) == nil, "Dead character is rejected")
player.dead = false
check(damageReads == initialReads, "Rejected characters are not read")

parts[3].cut, parts[3].cutTime, parts[3].bleedingFlag = true, 19, true
local injury, bleedingSnapshot = nativeAgreement(parts[3], 2, "Exposed laceration")
check(
    #bleedingSnapshot.allRows == #parts and bleedingSnapshot.allRows[3] == injury,
    "Injured rows are shared between filtered rows and the full body-part set"
)
check(
    injury.id == 2 and injury.bodyPart == parts[3] and injury.name == "Left Forearm",
    "Rows retain stable native ordinal and live body-part reference"
)
check(
    injury.severity == 2 and bleedingSnapshot.bleeding == 1,
    "Only the affected bleeding row has stronger presentation emphasis"
)
local beforeSignature = bleedingSnapshot.signature
parts[3].cutTime = 18
check(
    Model.snapshot(player).signature == beforeSignature,
    "Invisible healing timer changes do not rebuild the UI"
)
player.doctor = 3
injury = nativeAgreement(parts[3], 2, "Skilled laceration assessment")
check(
    hasLabel(injury, "IGUI_health_Cut (IGUI_health_Severe)"),
    "Native doctor skill gates assessment text"
)
parts[3].cutTime = 16
injury = nativeAgreement(parts[3], 2, "Native assessment boundary")
check(
    hasLabel(injury, "IGUI_health_Cut (IGUI_health_Moderate)"),
    "Crossing a visible vanilla assessment boundary refreshes the label"
)
parts[3].bleedingFlag, parts[3].bandage, parts[3].bandageLife = false, true, 1
parts[3].infection, parts[3].infectionLevel = true, 10
parts[3].glass, parts[3].bullet, parts[3].burnTime, parts[3].burnWash = true, true, 15, true
injury = nativeAgreement(parts[3], 2, "Bandage privacy")
for _, label in ipairs({
    "IGUI_health_Infected",
    "IGUI_health_LodgedBullet",
    "IGUI_health_LodgedGlassShards",
    "IGUI_health_Burned",
}) do
    check(not hasLabel(injury, label), "A bandage hides " .. label)
end
check(hasLabel(injury, "IGUI_health_Bandaged"), "Clean bandage is visible")
local cleanSignature = Model.snapshot(player).signature
parts[3].bandageLife = 0
injury = nativeAgreement(parts[3], 2, "Dirty bandage")
check(
    hasLabel(injury, "IGUI_health_DirtyBandage")
        and Model.snapshot(player).signature ~= cleanSignature,
    "Bandage state changes refresh the visible row"
)

parts = { part("Left Hand") }
parts[1].infection, parts[1].infectionLevel = true, 0.24
player.doctor = 0
check(#Model.snapshot(player).rows == 0, "Undetectable wound infection is not disclosed")
check(
    Model.snapshot(player).allRows[1].summary == "No visible injury",
    "Full body-part display also conceals undetectable wound infection"
)
parts[1].infectionLevel = 0.25
injury = nativeAgreement(parts[1], 0, "Unskilled infection detection threshold")
check(hasLabel(injury, "IGUI_health_Infected"), "Native infection threshold is inclusive")
parts[1].infectionLevel = 0.149
player.doctor = 1
check(
    #Model.snapshot(player).rows == 0,
    "Medical skill uses the native adjusted infection threshold"
)
parts[1].infectionLevel = 0.15
nativeAgreement(parts[1], 0, "Skilled infection detection threshold")
parts[1].infectionLevel, player.doctor = 0, 9
nativeAgreement(parts[1], 0, "Highest medical skill infection detection")

parts[1].plantain, parts[1].comfrey, parts[1].garlic = 1, 1, 1
parts[1].scratch, parts[1].scratchTime, parts[1].deep, parts[1].deepTime = true, 20, true, 12
parts[1].bite, parts[1].pain, parts[1].stiffness = true, 51, 25
parts[1].fracture, parts[1].stitch, parts[1].stitchTime = 60, true, 41
parts[1].glass, parts[1].bullet, parts[1].burnTime, parts[1].burnWash = true, true, 10, true
nativeAgreement(parts[1], 0, "Supported native injury and treatment labels")
parts[1].splint = 5
nativeAgreement(parts[1], 0, "Splinted fracture")

player.pain, player.bleedMoodle = 3, 4
snapshot = Model.snapshot(player)
check(
    snapshot.painText == "Moodles_Pain_lvl3" and snapshot.critical,
    "Critical visibility uses existing moodle warnings"
)
local function hasSignal(row, signal)
    return row.signals[signal] ~= nil
end
check(
    hasSignal(snapshot.rows[1], "scratch"),
    "visible injury signals retain stable condition families"
)
parts[1].bandage, parts[1].bandageLife = true, 1
local bandagedSignals = Model.snapshot(player).rows[1]
check(
    not hasSignal(bandagedSignals, "bullet") and not hasSignal(bandagedSignals, "burn"),
    "injury signals never expose bullet or burn conditions hidden by native bandage rules"
)
check(
    not hasSignal(bandagedSignals, "bandaged") and not hasSignal(bandagedSignals, "splinted"),
    "treatment labels do not become new injury signals"
)
parts[1].bandage = false
player.pain, player.bleedMoodle = 0, 0
health = 85.049
check(Model.snapshot(player).health == 85, "Native overall health is rounded to one decimal")
local roundedSignature = Model.snapshot(player).signature
health = 85.04
check(
    Model.snapshot(player).signature == roundedSignature,
    "Sub-display health changes do not invalidate cached rows"
)
local stale = parts[1]
parts[1] = part("Left Hand")
parts[1].cut = true
parts[1].stiffness = 20
check(
    not Model.openTreatment(player, stale, 500, 300),
    "Treatment rejects a replaced cached body-part reference"
)

local scanBefore = inventoryScans
check(
    not Model.openTreatment(player, parts[1], 500, 300, "manual"),
    "A wound with passive strain delegates to native eligibility, with no supplies returning unavailable"
)
check(
    inventoryScans == scanBefore + 1 and menuCount == 1,
    "Treatment performs one native inventory scan on explicit request"
)
check(
    menuX == 500 and menuY == 300,
    "Absolute screen coordinates are preserved through native pane offsets"
)
check(
    lastMenu:isEmpty() and not lastMenu.visible,
    "No eligible inventory produces no invented treatment options"
)
check(
    ISHealthPanel.instance == "preserved instance",
    "Treatment preserves the native panel singleton"
)
local bandage = { name = "Clean Bandage" }
function bandage:getBandagePower()
    return 4
end
function bandage:getType()
    return "Bandage"
end
function bandage:getFullType()
    return "Base.Bandage"
end
function bandage:getName()
    return self.name
end
function bandage:getContainer()
    return inventory
end
function bandage:hasComponent()
    return false
end
function bandage:IsDrainable()
    return false
end
function bandage:IsInventoryContainer()
    return false
end
function bandage:hasTag()
    return false
end
inventoryItems = { bandage }
check(
    Model.openTreatment(player, parts[1], 510, 320, "manual"),
    "Treatment is rebuilt against changed inventory"
)
local bandageOption
for _, option in ipairs(lastMenu.options) do
    if option.name == "ContextMenu_Bandage" then
        bandageOption = option
    end
end
check(
    bandageOption and #bandageOption.submenu.options == 1,
    "The real vanilla handler supplies an eligible Bandage action"
)
local option = bandageOption.submenu.options[1]
option.onSelect(
    option.target,
    option.param1,
    option.param2,
    option.param3,
    option.param4,
    option.param5,
    option.param6,
    option.param7,
    option.param8
)
check(
    #queue == 1 and queue[1].Type == "HealthPanelAction",
    "Native selection queues the actual HealthPanelAction"
)
local pending = queue[1]
inventoryItems = {}
check(
    not pending:isValid(),
    "The native action rejects an inventory item removed after menu creation"
)
inventoryItems = { bandage }
check(pending:isValid(), "The native action remains valid with the required inventory")
pending:perform()
check(
    #queue == 2 and queue[2].Type == "ISApplyBandage",
    "The native handler executes the existing medical timed action"
)
check(
    queue[2].doctor == player and queue[2].patient == player and queue[2].bodyPart == parts[1],
    "Treatment retains the correct survivor and native body part"
)
check(queue[2].item == bandage and queue[2].applying, "The existing action owns bandage mechanics")
parts[1].cut, parts[1].bandage, parts[1].bandageLife = false, true, 1
snapshot = Model.snapshot(player)
check(
    hasLabel(snapshot.rows[1], "IGUI_health_Bandaged")
        and not hasLabel(snapshot.rows[1], "IGUI_health_Cut"),
    "The snapshot reflects treatment completion without mutating health"
)

pane.otherPlayer = {}
check(
    not Model.openTreatment(player, parts[1], 10, 20),
    "A pane inspecting another survivor cannot supply local treatment"
)
snapshot = Model.snapshot(player)
check(snapshot.status ~= "Native status", "Status also refuses a pane inspecting another survivor")
pane.otherPlayer = nil
info = nil
check(not Model.openTreatment(player, parts[1], 10, 20), "Missing native pane fails gracefully")
check(
    Model.snapshot(player).health == 85,
    "Read-only health still works while native pane is absent"
)
parts[1] = part("Left Hand")
local healthySnapshot = Model.snapshot(player)
parts[1].scratchTime = 15
check(
    Model.snapshot(player).signature == healthySnapshot.signature,
    "Invisible body-part state does not alter its reference identity in Kahlua"
)
parts[1] = part("Left Hand")
snapshot = Model.snapshot(player)
check(
    #snapshot.rows == 0 and #snapshot.allRows == 1,
    "Recovered body parts remain optional without creating injury rows"
)
check(
    snapshot.signature ~= healthySnapshot.signature,
    "Replacing a healthy body-part reference invalidates the full-list cache"
)
local clearReads, clearScans = damageReads, inventoryScans
Model.clear(playerNum + 1)
check(
    damageReads == clearReads and inventoryScans == clearScans,
    "Clearing presentation identities neither reads health nor scans inventory"
)
check(
    Model.snapshot(player).signature == snapshot.signature,
    "Clearing a different local slot preserves the current survivor's cached identity"
)
Model.clear(playerNum)
local cleared = Model.snapshot(player)
check(
    cleared.signature ~= snapshot.signature
        and cleared.allRows[1].bodyPart == parts[1]
        and cleared.allRows[1].summary == snapshot.allRows[1].summary,
    "Clearing a local slot releases identities and refreshes references without altering visible health"
)
Model.clear()
check(
    Model.snapshot(player).signature ~= cleared.signature,
    "Clearing all local slots refreshes presentation identities"
)
check(
    inventoryScans > 0 and ISHealthPanel.cheat == false,
    "The installed native non-cheat treatment branch was exercised"
)
print("PASS: " .. checks .. " combat health model / installed vanilla UI checks")
