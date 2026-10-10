local root = arg[1] or arg[0]:match("^(.*)[/\\]tests[/\\][^/\\]+$")
local game = assert(
    arg[2] or (os and os.getenv and os.getenv("PZ_GAME_ROOT")),
    "Pass the game root as argument 2"
)
local function load(path)
    if readTestSource then
        return assert(loadstring(readTestSource(path), "@" .. path))()
    end
    return dofile(path)
end
local coreRoot = root .. "/../mini-ui-core"
local F = load(coreRoot .. "/test-support/NativeUI.lua")
F.install(game)
load(game .. "/media/lua/shared/luautils.lua")
table.wipe = table.wipe
    or function(value)
        for key in pairs(value) do
            value[key] = nil
        end
    end
local nativeCore, nativeText = getCore, getTextManager
getCore = function()
    local core = nativeCore()
    core.getOptionSingleContextMenu = function()
        return F.singleMenu
    end
    core.getOptionContextMenuFont = function()
        return "Small"
    end
    return core
end
getTextManager = function()
    local manager = nativeText()
    manager.getFontFromEnum = function()
        return {
            getLineHeight = function()
                return F.font
            end,
        }
    end
    return manager
end
local nativeElement = UIElement.new
UIElement.new = function(owner)
    local element = nativeElement(owner)
    element.setScrollHeight = function(self, height)
        self.scrollHeight = height
    end
    element.getScrollHeight = function(self)
        return self.scrollHeight or self.height
    end
    element.setYScroll = function(self, value)
        self.yScroll = value
    end
    element.getYScroll = function(self)
        return self.yScroll or 0
    end
    element.setXScroll = function(self, value)
        self.xScroll = value
    end
    element.getXScroll = function(self)
        return self.xScroll or 0
    end
    return element
end
getTexture = function()
    return nil
end
JoypadState = { players = {} }
load(game .. "/media/lua/client/ISUI/ISContextMenu.lua")
local contexts = {}
getPlayerContextMenu = function(num)
    if not contexts[num] then
        local menu = ISContextMenu:new(0, 0, 1, 1, 1)
        menu:initialise()
        menu:instantiate()
        menu:addToUIManager()
        menu.parent = nil
        contexts[num] = menu
    end
    return contexts[num]
end
load(coreRoot .. "/media/lua/client/MiniUI/Core.lua")
load(root .. "/media/lua/client/ATFCombatHealth/DamageAlerts.lua")
local function player()
    return {
        getPlayerNum = function()
            return 0
        end,
        isLocalPlayer = function()
            return true
        end,
        isDead = function(self)
            return self.dead
        end,
        getModData = function(self)
            self.modData = self.modData or {}
            return self.modData
        end,
    }
end
local actor = player()
F.players = { [0] = actor }
getRandomUUID = function()
    return "00000000-0000-0000-0000-000000000001"
end
ATFPlayerMiniHUDTelemetry = {
    new = function(p)
        return { player = p, xpRows = {} }
    end,
    update = function()
        return false
    end,
    clear = function(state)
        state.player = nil
    end,
}
local part, selections, opens = {}, 0, 0
local snapshot = {
    rows = {
        { id = 1, bodyPart = part, name = "Hand", summary = "Scratch", severity = 1, signals = {} },
    },
    allRows = {},
    health = 100,
    rawHealth = 100,
    status = "OK",
    pain = 0,
    painText = "No pain",
    bleeding = 0,
    blood = "No active bleeding",
    signature = "stable",
}
local treatment, manual, supplies
ATFCombatHealthModel = {
    snapshot = function()
        return snapshot
    end,
    clear = function() end,
    openTreatment = function(p, bodyPart, x, y)
        assert(p == actor and bodyPart == part, "actual Treat passes current own row")
        opens = opens + 1
        if F.noTreatment then
            return false
        end
        treatment = ISContextMenu.get(0, x, y)
        local option = treatment:addOption("Choose Item Manually")
        manual = ISContextMenu:getNew(treatment)
        treatment:addSubMenu(option, manual)
        local category = manual:addOption("Bandage")
        supplies = ISContextMenu:getNew(manual)
        manual:addSubMenu(category, supplies)
        supplies:addOption("Clean Bandage", nil, function()
            selections = selections + 1
        end)
        return true, treatment
    end,
}
local H = load(root .. "/media/lua/client/ATFCombatHealth/HUD.lua")
local n = 0
local function check(ok, why)
    assert(ok, why)
    n = n + 1
end
local function ownField(value, name)
    for key, field in pairs(value) do
        if key == name then
            return field
        end
    end
end
local panel = H.ensure(actor)
H.toggle(0)
F.now = F.now + 6000
F.mouseX, F.mouseY = -100, -100
local function frame()
    panel:update()
    panel:prerender()
    return panel.miniAppliedAlpha
end
local function dim()
    return panel.prefs.opacity * 0.5
end
local function full()
    return panel.prefs.opacity
end
local function treat()
    F.click(panel.rows[1].treat)
    check(
        panel.focusMenu == treatment and frame() == full(),
        "Treat keeps HUD bright with pointer outside it"
    )
    check(not panel.javaObject:isCapture(), "menu focus does not capture the mouse")
end
check(frame() == dim(), "idle HUD starts faded")
for _, font in ipairs({ 15, 22, 30 }) do
    F.font, F.singleMenu = font, true
    panel:layout()
    treat()
    check(
        treatment.requestX == -100 and treatment.requestY == -100,
        "Treat retains native absolute menu coordinates"
    )
    check(ownField(treatment, "clear") ~= nil, "only this native root gets a temporary reuse hook")
    check(
        ownField(manual, "clear") == nil and ownField(supplies, "clear") == nil,
        "native descendant methods stay unchanged"
    )
    treatment.mouseOver = treatment.options[1].id
    treatment:onMouseUp(5, 5)
    check(
        not treatment:getIsVisible() and manual:getIsVisible(),
        "actual single-context click hides root and opens child"
    )
    check(frame() == full(), "hidden root with visible native child retains focus at font " .. font)
    manual.mouseOver = manual:getOptionFromName("Bandage").id
    manual:onMouseUp(5, 5)
    check(
        not manual:getIsVisible() and supplies:getIsVisible() and frame() == full(),
        "nested native item submenu retains focus"
    )
    supplies.mouseOver = supplies:getOptionFromName("Clean Bandage").id
    supplies:onMouseUp(5, 5)
    check(
        selections == opens and not treatment:isAnyVisible(),
        "native item selection closes entire menu and invokes callback once"
    )
    check(
        frame() == dim() and panel.focusMenu == nil and ownField(treatment, "clear") == nil,
        "selection releases focus and restores native clear"
    )
end

F.singleMenu = false
treat()
manual:setVisible(true)
treatment:hideSelf()
check(
    not treatment:isAnyVisible() and frame() == full(),
    "linked visible descendant retains focus outside single-context mode"
)
manual:closeAll()
check(
    frame() == dim() and panel.focusMenu == nil,
    "native child closeAll releases normal-menu focus"
)

treat()
treatment:onMouseDownOutside(0, 0)
check(
    frame() == dim() and panel.focusMenu == nil,
    "actual outside click dismisses the root and releases focus"
)
treat()
local oldRoot, oldMap, oldOptions = treatment, treatment.instanceMap, treatment.options
local replacement = ISContextMenu.get(0, 400, 350)
replacement:addOption("Unrelated native menu")
check(
    replacement == oldRoot
        and replacement.options == oldOptions
        and replacement.instanceMap == oldMap,
    "native context reuses root and both tables"
)
check(
    panel.focusMenu == nil and ownField(replacement, "clear") == nil,
    "native clear releases ownership before replacement completes"
)
check(
    replacement:getIsVisible() and frame() == dim(),
    "an unrelated visible replacement never holds HUD focus"
)
replacement:closeAll()

treat()
local orphan = ISContextMenu:getNew(treatment)
orphan:addOption("Orphaned native supply")
orphan:setVisible(true)
treatment:hideSelf()
check(frame() == dim() and panel.focusMenu == nil, "an unlinked native submenu cannot hold focus")
orphan:setVisible(false)

treat()
manual:setVisible(true)
treatment:hideSelf()
manual:removeFromUIManager()
check(
    manual:getIsVisible() and not UIManager.getUI():contains(manual:getJavaObject()),
    "native removal leaves Java visibility true"
)
check(frame() == dim() and panel.focusMenu == nil, "removed descendant does not hold focus")
manual:addToUIManager()
check(manual.removed == true, "native pooled re-add retains obsolete removed flag")
manual:setVisible(false)

treat()
treatment:removeFromUIManager()
check(
    treatment:getIsVisible() and frame() == dim(),
    "removed root releases focus even if native visibility remains true"
)
treatment:addToUIManager()
treatment:closeAll()
check(frame() == dim(), "re-adding a released root does not restore focus")

local clearCalls = 0
local nativeClear = ISContextMenu.clear
treatment.clear = function(context)
    clearCalls = clearCalls + 1
    nativeClear(context)
    return "native-result", 7
end
local originalClear = treatment.clear
treat()
local first, second = treatment:clear()
check(
    first == "native-result" and second == 7 and clearCalls == 2,
    "reuse hook preserves instance override and multiple results"
)
check(
    treatment.clear == originalClear and panel.focusMenu == nil,
    "release restores the exact original instance override"
)
treatment:closeAll()
treatment.clear = nil

treat()
local throwingClear = function(context)
    nativeClear(context)
    error("native clear failure")
end
treatment.clear = throwingClear
panel:trackMenu(treatment)
local success, failure = pcall(function()
    treatment:clear()
end)
check(
    not success and tostring(failure):find("native clear failure", 1, true),
    "reuse hook propagates existing clear errors"
)
check(
    panel.focusMenu == nil and treatment.clear == throwingClear,
    "throwing clear still releases focus and restores original override"
)
treatment.clear = nil
treatment:closeAll()

treat()
local laterOverride = function(context)
    return nativeClear(context)
end
treatment.clear = laterOverride
check(
    frame() == dim() and panel.focusMenu == nil and treatment.clear == laterOverride,
    "later instance override is retained when ownership becomes uncertain"
)
treatment.clear = nil
treatment:closeAll()

treat()
panel:setPref("opacity", 0.6)
check(
    frame() == 0.6 and treatment:getIsVisible(),
    "layout and opacity changes retain active-menu brightness"
)
check(
    panel.rows[1].treat.textColor.a == 0.6 and panel.optionsButton.textColor.a == 0.6,
    "menu brightness propagates to controls without alpha accumulation"
)
treatment:closeAll()
check(frame() == 0.3, "dismissal returns to half of the current configured opacity")
panel:setPref("opacity", 0.85)
check(ISContextMenu.clear == nativeClear, "native class is unchanged by every menu lifetime")

F.noTreatment = true
F.click(panel.rows[1].treat)
check(panel.focusMenu == nil and frame() == dim(), "failed or healed treatment never adds focus")
F.noTreatment = false

local options = panel:options()
check(options == treatment and frame() == full(), "cog menu holds the same temporary focus")
F.singleMenu = true
options.mouseOver = options.options[1].id
options:onMouseUp(5, 5)
local display = options:getSubMenu(options.options[1].subOption)
check(
    display:getIsVisible() and not options:getIsVisible() and frame() == full(),
    "native cog submenu retains focus while root is hidden"
)
display:closeAll()
check(frame() == dim() and panel.focusMenu == nil, "cog submenu dismissal restores fade")

treat()
panel:close()
check(
    panel.focusMenu == nil and not treatment:isAnyVisible() and ownField(treatment, "clear") == nil,
    "HUD close dismisses its menu and restores native method"
)
check(
    not panel.prefs.enabled and not panel:getIsVisible(),
    "focus never overrides explicit HUD closure"
)
H.toggle(0)
F.now = F.now + 6000
check(frame() == dim(), "reopened HUD starts without stale menu focus")
treat()
actor.dead = true
panel:sample(F.now)
check(
    H.panels[0] == nil
        and panel.player == nil
        and panel.focusMenu == nil
        and not treatment:isAnyVisible(),
    "death releases menu, actor, and HUD references"
)
check(ownField(treatment, "clear") == nil, "death restores native root method")

actor = player()
F.players[0] = actor
panel = H.ensure(actor)
H.toggle(0)
F.now = F.now + 6000
treat()
local stale = panel
actor = player()
F.players[0] = actor
panel = H.ensure(actor)
check(
    stale.focusMenu == nil and stale.player == nil and not treatment:isAnyVisible(),
    "new body releases previous HUD menu lifetime"
)
stale:trackMenu(treatment)
check(
    stale.focusMenu == nil and panel.focusMenu == nil,
    "stale HUD cannot reacquire focus on the new body"
)
H.cleanup()
check(ownField(treatment, "clear") == nil, "cleanup leaves no native menu hook installed")
print("PASS " .. n .. " Treatment Focus / installed native context menu lifecycle checks")
