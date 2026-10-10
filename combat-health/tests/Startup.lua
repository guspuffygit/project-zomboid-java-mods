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
local function check(ok, why)
    assert(ok, why)
    checks = checks + 1
end
local core = getCore()
local keys = {}
getCore = function()
    return core
end
core.getOptionSidebarSize = function()
    return 1
end
core.getOptionFontSizeReal = function()
    return 1
end
core.getDebug = function()
    return false
end
core.isAzerty = function()
    return false
end
core.getOptionUpdateSneakButton = function()
    return false
end
core.reinitKeyMaps = function()
    keys = {}
end
core.addKeyBinding = function(_, id, key)
    keys[id] = key
end
core.getKey = function(_, id)
    if type(id) == "table" then
        id = id:getId()
    end
    return keys[id] or 0
end
core.isKey = function()
    return false
end
luautils = {
    stringStarts = function(value, prefix)
        return value:sub(1, #prefix) == prefix
    end,
}
string.split = function(value, separator)
    local parts = {}
    for part in (value .. separator):gmatch("(.-)" .. separator) do
        parts[#parts + 1] = part
    end
    return parts
end
cacheFileExists = function()
    return false
end
isSystemMacOS = function()
    return false
end
Mouse = { LMB = 100, RMB = 101, MMB = 102 }
local savedBinding = 0
getFileReader = function()
    local lines = { "VERSION=2", "ATFCombatHealthToggle=key:" .. savedBinding }
    local index = 0
    return {
        readLine = function()
            index = index + 1
            return lines[index]
        end,
        close = function() end,
    }
end
local keyboardIndex = 0
Keyboard = setmetatable({
    getKeyName = function(key)
        return tostring(key)
    end,
}, {
    __index = function(self, name)
        keyboardIndex = keyboardIndex + 1
        self[name] = keyboardIndex
        return self[name]
    end,
})
KeybindId = setmetatable({}, {
    __index = function(self, name)
        local id = {
            getId = function()
                return name
            end,
        }
        self[name] = id
        return id
    end,
})
getKeyName = Keyboard.getKeyName
ISBrush = { Solid = {} }
ISPanelJoypad = ISPanel
load(game .. "/media/lua/client/ISUI/Style/ISStyle.lua")
load(game .. "/media/lua/client/ISUI/ISLabel.lua")
load(game .. "/media/lua/shared/keyBinding.lua")
load(game .. "/media/lua/client/OptionScreens/MainOptions.lua")
local B = load(root .. "/media/lua/client/ATFCombatHealth/KeyBinding.lua")
local function countBinding()
    local n = 0
    for _, entry in ipairs(keyBinding) do
        if entry.value == "ATFCombatHealthToggle" then
            n = n + 1
        end
    end
    return n
end
check(countBinding() == 1, "client bootstrap registers the binding")
B.register()
load(root .. "/media/lua/client/ATFCombatHealth/KeyBinding.lua")
check(countBinding() == 1, "reload never duplicates the binding")
-- Exercise native keyBinding table replacement, then native Options copying.
load(game .. "/media/lua/shared/keyBinding.lua")
check(countBinding() == 0, "native reload replaces the bindings table")
MainOptions.loadKeys()
check(
    countBinding() == 1 and keys.ATFCombatHealthToggle == 0,
    "Options repairs registration and starts unbound"
)
savedBinding = 90
MainOptions.loadKeys()
check(keys.ATFCombatHealthToggle == 90, "native loading preserves a saved custom hotkey")
local binding
for _, entry in ipairs(MainOptions.keys) do
    if entry.value == "ATFCombatHealthToggle" then
        binding = entry
    end
end
check(binding and binding.key == 90, "native keyboard page receives the registered binding")
-- Render only our group through the real keyboard page builder. Other vanilla
-- groups exercise unrelated tick boxes and are covered by the game itself.
MainOptions.keys = { { value = "[ATFCombatHealth]" }, binding }
MainOptions.keyText = {}
local J = getmetatable(UIElement.new({}))
function J:setScrollHeight(value)
    self.scrollHeight = value
end
function J:setYScroll(value)
    self.yScroll = value
end
function J:ignoreWidthChange()
    self.ignoreWidth = true
end
function J:ignoreHeightChange()
    self.ignoreHeight = true
end
local options = ISPanel.new(MainOptions, 0, 0, 1000, 600)
options:initialise()
options.addPage = function(self)
    self.mainPanel = ISPanel:new(0, 0, 1000, 600)
    self.mainPanel:initialise()
end
options.addHorizontalLine = function(self, _, title)
    self.groupTitle = title
end
options:addKeybindingPanel()
local rendered = MainOptions.keyText[2]
check(
    rendered and rendered.btn.internal == "ATFCombatHealthToggle" and rendered.keyCode == 90,
    "real Options page creates the configurable hotkey button"
)
check(
    rendered.txt.translation == getText("UI_optionscreen_binding_ATFCombatHealthToggle"),
    "real Options page uses the translated HUD binding label"
)

getTexture = function()
    return {
        getWidth = function()
            return 48
        end,
        getHeight = function()
            return 48
        end,
    }
end
ColorInfo = {
    new = function(r, g, b, a)
        return { r = r, g = g, b = b, a = a }
    end,
}
isClient = function()
    return false
end
ISDebugMenu = { forceEnable = false }
ISWorldMap = {
    IsAllowed = function()
        return false
    end,
}
getPlayerInventory = function() end
getPlayerLoot = function() end
getPlayerInfoPanel = function() end
load(game .. "/media/lua/client/ISUI/ISImage.lua")
load(game .. "/media/lua/client/Moveables/ISMoveablesIconToolTip.lua")
load(game .. "/media/lua/client/ISUI/ISEquippedItem.lua")
local player = {
    getPlayerNum = function()
        return 0
    end,
    getSafety = function()
        return {}
    end,
}
local sidebar = ISEquippedItem:new(10, 10, 100, 250, player)
sidebar:initialise()
check(
    sidebar.healthBtn and not sidebar.healthBtn.atfCombatHealthBound,
    "native initialise creates the heart before mod bootstrap"
)
local nativeClick = sidebar.healthBtn.onclick
local priorCalls = 0
sidebar.healthBtn.onRightMouseUp = function()
    priorCalls = priorCalls + 1
end
local panel = { prefs = { enabled = false }, options = function() end }
ATFPlayerMiniHUDTelemetry = { installYoga = function() end }
ATFPlayerMiniHUDHealthOpener = { bind = function() end }
local toggles, lastMenu = 0, nil
ATFCombatHealth = {
    ensure = function(actor)
        return actor == player and panel or nil
    end,
    panels = {},
    cleanup = function() end,
    toggle = function()
        toggles = toggles + 1
    end,
}
ISContextMenu = {
    get = function()
        lastMenu = {
            options = {},
            addOption = function(self, title, target, callback)
                local option = { title = title, target = target, callback = callback }
                self.options[#self.options + 1] = option
                return option
            end,
            setOptionChecked = function(_, option, value)
                option.checked = value
            end,
        }
        return lastMenu
    end,
}
load(root .. "/media/lua/client/ATFCombatHealth_Client.lua")
check(
    sidebar.healthBtn.atfCombatHealthBound and sidebar.healthBtn:onRightMouseUp(2, 2),
    "already existing native heart gets the Combat Health menu"
)
check(
    priorCalls == 1 and sidebar.healthBtn.onclick == nativeClick,
    "native left click and earlier right handler remain intact"
)
check(
    #lastMenu.options == 2 and lastMenu.options[1].checked == false,
    "heart menu shows the HUD state without Full Health"
)
lastMenu.options[1].callback()
check(toggles == 1, "heart menu actually toggles the HUD")
toggles = 0
local right = sidebar.healthBtn.onRightMouseUp
F.emit("OnGameStart")
F.emit("OnCreatePlayer", 0, player)
check(sidebar.healthBtn.onRightMouseUp == right, "lifecycle events do not stack heart callbacks")
local future = ISEquippedItem:new(10, 10, 100, 250, player)
future:initialise()
check(
    future.healthBtn.atfCombatHealthBound and future.healthBtn:onRightMouseUp(2, 2),
    "future native heart gets its menu after real initialise completes"
)
load(root .. "/media/lua/client/ATFCombatHealth_Client.lua")
check(
    future.healthBtn.onclick == nativeClick,
    "reloading bootstrap leaves native left click intact"
)
F.typing = true
F.emit("OnKeyPressed", 90)
check(toggles == 0, "saved hotkey ignores text entry")
F.typing = false
F.emit("OnKeyPressed", 90)
check(toggles == 1, "saved native hotkey invokes the HUD toggle")
print(
    "PASS Startup "
        .. checks
        .. " checks (native sidebar initialise and Options keybinding builder)"
)
