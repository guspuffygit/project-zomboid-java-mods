-- Exercise installed B42 Health creation/sizing and both native close methods.
-- Arguments match Gradle: module directory, game directory.
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
local F = load(root .. "/../mini-ui-core/test-support/NativeUI.lua")
F.install(game)
local checks = 0
local function check(value, message)
    assert(value, message)
    checks = checks + 1
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
local function player(num)
    return {
        getPlayerNum = function()
            return num
        end,
        isLocalPlayer = function(self)
            return not self.remote
        end,
        isDead = function(self)
            return self.dead
        end,
        getPerkLevel = function()
            return 0
        end,
        getBodyDamage = function()
            return {
                getBodyParts = function()
                    return list({})
                end,
                getHealth = function()
                    return 100
                end,
            }
        end,
    }
end
F.players = { [0] = player(0), [1] = player(1) }
local p = F.players[0]
local infos = {}
getPlayerInfoPanel = function(num)
    return infos[num]
end
getDebug = function()
    return false
end
isClient = function()
    return false
end
luautils = {
    remove = function(values, wanted)
        for i, value in ipairs(values) do
            if value == wanted then
                table.remove(values, i)
                return i
            end
        end
        return -1
    end,
}
Joypad = { Texture = { AButton = {} } }
JoypadState = { players = {} }
Perks = { Doctor = "Doctor" }
ISBaseTimedAction = ISBaseObject
MusicIntensityConfig = {
    getInstance = function()
        return {
            checkHealthPanelVisible = function()
                F.healthUpdates = (F.healthUpdates or 0) + 1
            end,
        }
    end,
}
local label = "Mini HUD"
local originalText = getText
getText = function(key)
    if key == "UI_ATFCombatHealth_MiniHUD" then
        return label
    end
    return originalText(key)
end

-- Java body-diagram boundary; Lua Health, button and ancestor size methods are native.
NewHealthPanel = {
    new = function()
        local java = UIElement.new()
        function java:setTable(value)
            self.owner = value
        end
        function java:setMovable() end
        function java:getDamageStatusString()
            return "OK"
        end
        return java
    end,
}
local J = getmetatable(UIElement.new())
function J:isReallyVisible()
    local parent = self
    while parent do
        if not parent.visible then
            return false
        end
        parent = parent.parent
    end
    return true
end
ISBodyPartPanel = ISPanel:derive("ISBodyPartPanel")
function ISBodyPartPanel:new(_, x, y)
    return ISPanel.new(self, x, y, 123, 302)
end
function ISBodyPartPanel:setAlphas() end
function ISBodyPartPanel:enableNodes() end
ISScrollingListBox = ISPanel:derive("ISScrollingListBox")
function ISScrollingListBox:new(x, y, width, height)
    local result = ISPanel.new(self, x, y, width, height)
    result.items = {}
    return result
end
function ISScrollingListBox:clear()
    self.items = {}
end
function ISScrollingListBox:addItem(name, item)
    self.items[#self.items + 1] = { name = name, item = item }
end
load(game .. "/media/lua/client/ISUI/ISPanelJoypad.lua")
load(game .. "/media/lua/client/ISUI/ISCollapsableWindow.lua")
load(game .. "/media/lua/client/XpSystem/ISUI/ISCharacterInfoWindow.lua")
local nativeInfoCreate = ISCharacterInfoWindow.createChildren
load(game .. "/media/lua/client/XpSystem/ISUI/ISHealthPanel.lua")
local nativeCreate = ISHealthPanel.createChildren
local nativeUpdate = ISHealthPanel.update
local nativeJoypad = ISHealthPanel.onJoypadDown
local nativeFocus = ISHealthPanel.onGainJoypadFocus
local path = root .. "/media/lua/client/ATFCombatHealth/HealthOpener.lua"
local O = load(path)
check(O == ATFPlayerMiniHUDHealthOpener, "module returns public opener")
check(ISHealthPanel.createChildren ~= nativeCreate, "native creation is wrapped")
check(ISHealthPanel.update == nativeUpdate, "native update remains untouched")
check(
    ISHealthPanel.onJoypadDown == nativeJoypad and ISHealthPanel.onGainJoypadFocus == nativeFocus,
    "native joypad shortcuts preserved"
)

local function panel(x, y, width, height)
    local result = ISPanel:new(x, y, width, height)
    result:initialise()
    result:instantiate()
    return result
end
local function health(actor, assignFirst)
    local info = panel(25, 30, 260, 350)
    info.playerNum, info.close = actor:getPlayerNum(), ISCharacterInfoWindow.close
    info.panel = panel(0, 20, 260, 330)
    info:addChild(info.panel)
    infos[actor:getPlayerNum()] = info
    local pane = ISHealthPanel:new(actor, 0, 20, 260, 330)
    pane:initialise()
    if assignFirst then
        info.healthView = pane
    end
    info.panel:addChild(pane)
    info.healthView = pane
    return info, pane
end
local info, pane = health(p, true)
check(
    pane.fitness and pane.listbox and pane.healthPanel and pane.bodyPartPanel,
    "original native createChildren executes"
)
local button = pane.atfMiniHUDButton
check(button ~= nil, "primary button created after native controls")
check(button:getX() > pane.fitness:getRight(), "button beside Fitness without overlap")
check(button:getY() == pane.healthPanel:getY(), "button occupies reserved native first row")
check(
    button:getHeight() == F.font + 6 and button:getTitle() == label,
    "button follows native font and localized title"
)
check(
    button.anchorTop and not button.anchorBottom and button.anchorLeft and not button.anchorRight,
    "button does not drift from native resize anchors"
)
check(
    button:getBottom() < pane.healthPanel:getY() + 10 + F.font + 6,
    "button clears native overall-status row"
)
pane:update()
check(F.healthUpdates == 1, "original installed Health update executes")
check(pane:getWidth() >= button:getRight() + 11, "native width includes button")
check(
    info:getWidth() == info.panel:getX() + info.panel:getWidth(),
    "native width propagation reaches full Health owner"
)
local smallestWidth = pane:getWidth()
for i = 1, 50 do
    pane:update()
end
check(
    pane:getWidth() == smallestWidth and F.healthUpdates == 51,
    "repeated native updates do not shrink then regrow"
)
pane:setWidthAndParentWidth(700)
check(pane:getWidth() == 700 and info:getWidth() == 700, "native width above minimum is preserved")
pane:setWidthAndParentWidth(100)
check(
    pane:getWidth() >= button:getRight() + 11,
    "small native width is clamped through original method"
)
local children = #pane.childrenInOrder
local geometryCalls = 0
local originalSetX = button.setX
button.setX = function(self, x)
    geometryCalls = geometryCalls + 1
    return originalSetX(self, x)
end
for i = 1, 50 do
    check(O.bind(0), "existing pane binds")
end
check(
    pane.atfMiniHUDButton == button and #pane.childrenInOrder == children,
    "repeated binding creates no controls"
)
check(geometryCalls == 0, "unchanged bindings do not rewrite geometry")
local wrappedCreate = ISHealthPanel.createChildren
check(
    load(path) == O and ISHealthPanel.createChildren == wrappedCreate,
    "module reload does not stack creation hooks"
)

label = "Localized Mini HUD with a considerably longer title"
F.font = 28
check(O.bind(0), "font and translation changes bind")
check(
    button:getWidth() >= getTextManager():MeasureStringX(UIFont.Small, label) + 20,
    "large-font localized label fits"
)
check(
    button:getHeight() == pane.fitness:getHeight() and pane:getWidth() >= button:getRight() + 11,
    "live font change keeps reserved native row and widens parent"
)
local widthAfterChange = pane:getWidth()
pane:update()
check(pane:getWidth() == widthAfterChange, "native sizing retains updated measured minimum")

local toggles, toggledNum = 0, nil
ATFCombatHealth = {
    toggle = function(num)
        toggles = toggles + 1
        toggledNum = num
        return true
    end,
}
check(
    button.onclick(button.target, button) and toggles == 1 and toggledNum == 0,
    "primary opener delegates to HUD toggle for own slot"
)
pane.otherPlayer = F.players[1]
check(
    not button.onclick(button.target, button) and toggles == 1 and not O.bind(0),
    "other-patient view cannot toggle local HUD"
)
check(not button:getIsVisible(), "existing button hides when pane treats somebody else")
pane.otherPlayer = nil
check(O.bind(0) and button:getIsVisible(), "own Health restores existing button")
p.remote = true
check(not O.bind(0) and not button.onclick(button.target, button), "remote actor rejected")
p.remote = false
p.dead = true
check(not O.bind(0) and not button.onclick(button.target, button), "dead actor rejected")
p.dead = false
check(not O.bind(9), "missing actor rejected")
local lateInfo, latePane = health(F.players[1], false)
check(not latePane.atfMiniHUDButton, "late healthView assignment waits for supported bind")
check(
    O.bind(1) and latePane.atfMiniHUDButton,
    "fallback binds pane created before healthView assignment"
)
check(
    latePane.atfMiniHUDButton.onclick(latePane, latePane.atfMiniHUDButton) and toggledNum == 1,
    "split-screen local slot remains independent"
)

local hud = { player = p, playerNum = 0 }
check(not O.observe(hud), "initial owner observation is baseline only")
pane:setVisible(false)
check(not O.observe(hud), "Health tab switching does not mean owner closed")
pane:setVisible(true)
info:close()
check(pane:getIsVisible(), "native attached close leaves child visible flag set")
check(O.observe(hud), "actual attached native close detected once")
check(not O.observe(hud), "closed owner does not repeatedly fire")
info:setVisible(true)
check(not O.observe(hud), "owner reopening resets transition")

local detached = panel(300, 50, pane:getWidth(), 350)
detached.close = ISCollapsableWindow.close
pane:detachFromParent()
detached:addChild(pane)
info:setVisible(false)
check(not O.observe(hud), "tear-off resets owner rather than observing hidden old owner")
check(hud.atfHealthOwner == detached, "detached ancestor owns Health visibility")
detached:close()
check(
    pane:getIsVisible() and O.observe(hud),
    "actual detached native close detected despite child visible"
)
check(not O.observe(hud), "detached close fires once")
detached:setVisible(true)
check(not O.observe(hud), "detached reopen is not a close")
pane:detachFromParent()
info.panel:addChild(pane)
detached:setVisible(false)
info:setVisible(true)
check(
    not O.observe(hud) and hud.atfHealthOwner == info,
    "reattach resets ancestry without false closure"
)

local replacement = player(0)
F.players[0] = replacement
check(
    not O.observe(hud) and hud.atfHealthOwner == nil and hud.atfHealthPane == nil,
    "survivor replacement releases stale observer references"
)
check(not button.onclick(button.target, button), "stale opener cannot act on replacement survivor")
local newInfo, newPane = health(replacement, true)
local newHUD = { player = replacement, playerNum = 0 }
check(
    newPane.atfMiniHUDButton ~= button and not O.observe(newHUD),
    "new survivor gets independent opener and baseline"
)
newInfo:setVisible(false)
check(O.observe(newHUD), "replacement owner closes normally")
O.clear(newHUD)
check(
    newHUD.atfHealthOwner == nil
        and newHUD.atfHealthPane == nil
        and newHUD.atfHealthWasVisible == nil,
    "clear drops every observer reference"
)
check(not O.observe(newHUD), "clear never creates a synthetic close")
newPane.parent = nil
check(
    not O.observe(newHUD) and newHUD.atfHealthOwner == nil,
    "destroyed/unparented health pane clears observer"
)
check(not O.observe(nil), "missing observer is ignored")

-- Large font at native initialization uses the native taller reserved row.
load(game .. "/media/lua/client/XpSystem/ISUI/ISHealthPanel.lua")
ATFPlayerMiniHUDHealthOpener = nil
local largeOpener = load(path)
local largeInfo, largePane = health(replacement, true)
local largeButton = largePane.atfMiniHUDButton
check(
    largeButton and largeButton:getHeight() == 34 and largePane.fitness:getHeight() == 34,
    "native large-font initialization matches Fitness row"
)
check(
    largeButton:getBottom() < largePane.healthPanel:getY() + 10 + F.font + 6,
    "large-font opener clears native status heading"
)
largePane:update()
check(
    largePane:getWidth() >= largeButton:getRight() + 11
        and largeInfo:getWidth() == largePane:getWidth(),
    "large-font native update includes localized button in owner width"
)
check(
    largeOpener.bind(0) and largePane.atfMiniHUDButton == largeButton,
    "large-font rebind stays idempotent"
)

-- Reproduce the actual startup path: createPlayerData builds the native
-- character window, restores its layout, then applies visibleOnStartup.
-- Other inventory/sidebar widgets are boundary stubs; character-window,
-- Health, tabs, layout manager and player-data Lua remain installed native code.
F.font = 15
local nativeCore = getCore
getCore = function()
    local core = nativeCore()
    core.isDedicated = function()
        return false
    end
    core.getOptionFontSizeReal = function()
        return 1
    end
    core.getGameMode = function()
        return F.mode or "Sandbox"
    end
    core.isKey = function(_, id, key)
        return id == "TOGGLE_HEALTH_PANEL" and key == 35
    end
    return core
end
getTexture = function()
    return nil
end
getTextOrNull = function(key)
    return key
end
getNumActivePlayers = function()
    return 1
end
getPlayerScreenLeft = function()
    return 0
end
getPlayerScreenTop = function()
    return 0
end
getPlayerScreenWidth = function()
    return F.width
end
getPlayerScreenHeight = function()
    return F.height
end
string.split = function(value, separator)
    local values = {}
    for item in value:gmatch("[^" .. separator .. "]+") do
        values[#values + 1] = item
    end
    return values
end
load(game .. "/media/lua/shared/luautils.lua")
load(game .. "/media/lua/client/ISUI/ISResizeWidget.lua")
load(game .. "/media/lua/client/ISUI/ISTabPanel.lua")
load(game .. "/media/lua/client/ISUI/ISLayoutManager.lua")
ISUIHandler = { allUIVisible = true }
getFileWriter = function()
    return { write = function() end, close = function() end }
end
xpSystemText = {
    info = "Info",
    skills = "Skills",
    health = "Health",
    protection = "Protection",
    clothingIns = "Clothing",
}
ISCharacterScreen = ISPanel:derive("FixtureCharacterScreen")
ISCharacterInfo = ISPanel:derive("FixtureCharacterInfo")
ISCharacterProtection = ISPanel:derive("FixtureCharacterProtection")
ISClothingInsPanel = ISPanel:derive("FixtureClothingPanel")
function ISClothingInsPanel:new(_, x, y, width, height)
    return ISPanel.new(self, x, y, width, height)
end
function J:setUIName(value)
    self.uiName = value
end
function J:setAlwaysOnTop(value)
    self.alwaysOnTop = value
end
function J:setEnabled(value)
    self.enabled = value
end
function J:setMaxDrawHeight(value)
    self.maxDrawHeight = value
end
UIManager.setPlayerInventory = function() end
UIManager.setPlayerInventoryTooltip = function() end
local function widget()
    return panel(0, 0, 100, 100)
end
ISInventoryPage = ISPanel:derive("FixtureInventory")
function ISInventoryPage:createChildren()
    self.collapseButton, self.pinButton = widget(), widget()
end
function ISInventoryPage:setInfo() end
function ISInventoryPage:SaveLayout(_, layout)
    ISLayoutManager.DefaultSaveWindow(self, layout)
end
function ISInventoryPage:RestoreLayout(_, layout)
    ISLayoutManager.DefaultRestoreWindow(self, layout)
end
ISButtonPrompt = { new = widget }
ISContextMenu = { new = widget }
ISBackButtonWheel = { new = widget }
ISHotbar = { new = widget }
ISVehicleMechanics = { new = widget }
ISVehicleDashboard = { new = widget }
ISDesignationZonePanel = { new = widget }
ISRadialMenu = { new = widget }
ISSleepingUI = { new = widget }
ISMiniMap = {
    IsAllowed = function()
        return false
    end,
}
ISMoveableCursor = { cursors = {} }
ISRadioWindow = { instances = {}, instancesIso = {} }
ISEquippedItem = {
    initialise = function(self)
        self.healthBtn = {}
    end,
}
launchEquippedItem = function(actor)
    local sidebar = widget()
    sidebar.chr, sidebar.playerNum = actor, actor:getPlayerNum()
    ISEquippedItem.initialise(sidebar)
    ISEquippedItem.instance = sidebar
    return sidebar
end
local startupPlayer = F.players[0]
startupPlayer.getJoypadBind = function()
    return -1
end
startupPlayer.getInventory = function()
    return {}
end
startupPlayer.getVehicle = function()
    return nil
end
startupPlayer.setSeeDesignationZone = function() end
startupPlayer.getModData = function(self)
    self.modData = self.modData or {}
    return self.modData
end
load(game .. "/media/lua/client/ISUI/PlayerData/ISPlayerDataObject.lua")
load(game .. "/media/lua/client/ISUI/PlayerData/ISPlayerData.lua")
local wrappedInfoCreate = ISCharacterInfoWindow.createChildren
local function startup(layouts, unwrapped)
    ISLayoutManager.layouts, ISLayoutManager.windows = layouts or {}, {}
    ISCharacterInfoWindow.createChildren = unwrapped and nativeInfoCreate or wrappedInfoCreate
    createPlayerData(0)
    return getPlayerInfoPanel(0)
end
local baseline = startup(nil, true)
check(
    baseline:getIsVisible() and baseline.visibleOnStartup,
    "native missing-layout bug reproduces from Java visible default"
)
local fresh = startup()
check(
    not fresh:getIsVisible() and not fresh.visibleOnStartup,
    "fresh native character window stays hidden"
)
check(
    largeOpener.bind(0) and fresh.healthView.atfMiniHUDButton,
    "hidden native Health receives opener without opening"
)
local hudProbe = { player = startupPlayer, playerNum = 0 }
check(
    not largeOpener.observe(hudProbe) and not fresh:getIsVisible(),
    "passive Health observation never opens owner"
)
local currentLayout = {
    name = "charinfowindow",
    x = "300",
    y = "100",
    visible = "false",
    pin = "true",
    tabs = "info,skills,health,clothingIns,protection",
    current = "health",
}
local function currentResolution(layout)
    return { { width = F.width, height = F.height, windows = { layout } } }
end
local savedHidden = startup(currentResolution(currentLayout))
check(not savedHidden:getIsVisible(), "explicit native saved hidden state remains hidden")
check(
    savedHidden.panel:getActiveView() == savedHidden.healthView,
    "native saved Health tab remains selected"
)
currentLayout.visible = "true"
local savedVisible = startup(currentResolution(currentLayout))
check(
    savedVisible:getIsVisible() and savedVisible.visibleOnStartup,
    "explicit native saved visible state is preserved"
)
check(
    largeOpener.bind(0) and savedVisible:getIsVisible(),
    "binding leaves legitimate visible native window open"
)
savedVisible:toggleView(xpSystemText.health)
check(not savedVisible:getIsVisible(), "native Health toggle closes normally")
savedVisible:toggleView(xpSystemText.health)
check(savedVisible:getIsVisible(), "native Health toggle reopens normally")
local newResolution =
    startup({ { width = F.width + 1, height = F.height, windows = { currentLayout } } })
check(
    not newResolution:getIsVisible(),
    "saved visible state for another resolution does not auto-open full Health"
)
currentLayout.visible, currentLayout.tabs, currentLayout.current =
    "false", "info,skills,clothingIns,protection", "info"
local floatingLayout = currentResolution(currentLayout)
floatingLayout[1].windows[2] =
    { name = "charinfowindow.health", x = "500", y = "200", visible = "true" }
local floatingInfo = startup(floatingLayout)
check(
    not floatingInfo:getIsVisible() and floatingInfo.healthView.parent ~= floatingInfo.panel,
    "native saved tear-off restores without showing main owner"
)
check(
    floatingInfo.healthView.parent:getIsVisible(),
    "legitimate saved floating Health visibility is preserved"
)
floatingLayout[1].windows[2].visible = "false"
local hiddenFloatingInfo = startup(floatingLayout)
check(
    not hiddenFloatingInfo:getIsVisible()
        and not hiddenFloatingInfo.healthView.parent:getIsVisible(),
    "saved hidden floating Health stays hidden"
)
ISLayoutManager.layouts = {}
local optedIn = ISCharacterInfoWindow:new(0, 0, 400, 400, 0)
optedIn.visibleOnStartup = true
optedIn:initialise()
optedIn:addToUIManager()
check(optedIn:getIsVisible(), "explicit third-party new-window startup opt-in is preserved")
F.mode = "Tutorial"
check(
    not startup(currentResolution({ name = "charinfowindow", visible = "true" })):getIsVisible(),
    "native Tutorial hiding remains authoritative"
)
F.mode = nil
local startupHook = ISCharacterInfoWindow.createChildren
check(
    load(path) == largeOpener and ISCharacterInfoWindow.createChildren == startupHook,
    "startup default hook is reload-idempotent"
)

-- Restore an enabled mini HUD using the actual native layout manager and
-- client lifecycle callbacks, with no alteration to the native Health owner.
ATFCombatHealth = nil
ATFCombatHealthModel = {
    snapshot = function()
        return {
            rows = {},
            allRows = {},
            health = 100,
            rawHealth = 100,
            status = "OK",
            pain = 0,
            painText = "No pain",
            bleeding = 0,
            blood = "No active bleeding",
            signature = "healthy",
        }
    end,
    clear = function() end,
}
ATFPlayerMiniHUDTelemetry = {
    new = function(actor)
        return { player = actor, xpRows = {} }
    end,
    update = function()
        return false
    end,
    clear = function() end,
    installYoga = function() end,
}
local coreRoot = root .. "/../mini-ui-core"
load(coreRoot .. "/media/lua/client/MiniUI/Core.lua")
load(root .. "/media/lua/client/ATFCombatHealth/DamageAlerts.lua")
local H = load(root .. "/media/lua/client/ATFCombatHealth/HUD.lua")
load(root .. "/media/lua/client/ATFCombatHealth_Client.lua")
ISLayoutManager.layouts =
    currentResolution({ name = "ATFCombatHealth.0", enabled = "true", keepRespawn = "true" })
ISLayoutManager.windows = {}
F.emit("OnCreatePlayer", 0, startupPlayer)
local mini, nativeInfo = H.panels[0], getPlayerInfoPanel(0)
check(
    mini and mini:getIsVisible() and mini.prefs.enabled,
    "native player creation restores enabled mini HUD"
)
check(
    not nativeInfo:getIsVisible(),
    "mini restore does not open full vanilla Health without saved visibility"
)
check(
    nativeInfo.panel:getActiveView() == nativeInfo.charScreen,
    "mini restore does not activate a different native tab"
)
F.emit("OnGameStart")
F.now = F.now + 1500
F.emit("OnPlayerUpdate", startupPlayer)
check(
    not nativeInfo:getIsVisible(),
    "game start and passive player updates keep native owner hidden"
)
H.toggle(0)
check(
    not mini:getIsVisible() and not nativeInfo:getIsVisible(),
    "mini close preserves native hidden state"
)
H.toggle(0)
check(
    mini:getIsVisible() and not nativeInfo:getIsVisible(),
    "mini re-enable leaves native window hidden"
)
local persistedNative
for _, resolution in ipairs(ISLayoutManager.layouts) do
    for _, layout in ipairs(resolution.windows) do
        if layout.name == "charinfowindow" then
            persistedNative = layout
        end
    end
end
check(
    persistedNative and persistedNative.visible == "false",
    "saving mini preferences does not persist fabricated native visibility"
)
nativeInfo:toggleView(xpSystemText.health)
check(
    nativeInfo:getIsVisible() and mini:getIsVisible(),
    "explicit native Health still opens independently"
)
load(game .. "/media/lua/server/XpSystem/XpUpdate.lua")
KeybindId = setmetatable({}, {
    __index = function(_, name)
        return name
    end,
})
getGameSpeed = function()
    return 1
end
F.emit("OnKeyPressed", 35)
check(
    not nativeInfo:getIsVisible() and mini:getIsVisible(),
    "actual native Health keybind closes native UI without closing mini"
)
F.emit("OnKeyPressed", 35)
check(
    nativeInfo:getIsVisible() and nativeInfo.panel:getActiveView() == nativeInfo.healthView,
    "actual native Health keybind still opens and selects Health"
)
currentLayout.visible, currentLayout.tabs, currentLayout.current =
    "true", "info,skills,health,clothingIns,protection", "health"
ISLayoutManager.layouts = currentResolution(currentLayout)
ISLayoutManager.layouts[1].windows[2] =
    { name = "ATFCombatHealth.0", enabled = "true", keepRespawn = "true" }
F.emit("OnCreatePlayer", 0, startupPlayer)
F.now = F.now + 1500
F.emit("OnPlayerUpdate", startupPlayer)
check(
    getPlayerInfoPanel(0):getIsVisible() and mini:getIsVisible(),
    "mini lifecycle preserves explicit saved visible native Health on UI rebuild"
)
print("HealthOpener: " .. checks .. " checks passed")
