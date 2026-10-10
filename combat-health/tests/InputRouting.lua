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
local core = getCore
getCore = function()
    local value = core()
    value.getGoodHighlitedColor = function()
        return { r = 1, g = 1, b = 1, a = 1 }
    end
    return value
end
load(game .. "/media/lua/client/ISUI/ISInventoryPane.lua")
local C = load(coreRoot .. "/media/lua/client/MiniUI/Core.lua")
local n = 0
local function check(ok, why)
    assert(ok, why)
    n = n + 1
end
local held = false
isMouseButtonDown = function(button)
    return button == 0 and held
end
instanceof = function()
    return false
end
isShiftKeyDown = function()
    return false
end
isCtrlKeyDown = function()
    return false
end
ISMouseDrag = {}
F.players = { [0] = { nullifyAiming = function() end } }

-- Construction-only fixture; hover and caret clicks use the installed game's functions.
local inventory = ISPanel:new(600, 60, 400, 300)
setmetatable(inventory, ISInventoryPane)
inventory.createChildren = function() end
inventory.player, inventory.column2, inventory.column3 = 0, 30, 140
inventory.headerHgt, inventory.itemHgt, inventory.mouseOverOption = 16, 20, 0
inventory.items = { { name = "Bandages", items = { {}, {}, {} } } }
inventory.collapsed, inventory.selected = { Bandages = true }, {}
inventory.refreshContainer = function(self)
    self.refreshed = (self.refreshed or 0) + 1
end
local button = { setVisible = function() end }
inventory.contextButton1, inventory.contextButton2, inventory.contextButton3 =
    button, button, button
inventory:initialise()
inventory:instantiate()
local mini = C.Window:new(80, 160, 300, 180, "Combat Health")
mini:initialise()
mini:instantiate()
local elements = { inventory, mini }

-- UIManager.updateMouseMove and UIElement.onMouseMove dispatch contract from B42.21:
-- visible captured roots receive movement outside their bounds and consume it.
local function move(x, y)
    F.mouseX, F.mouseY = x, y
    local consumed = false
    for i = #elements, 1, -1 do
        local ui = elements[i]
        if ui:getIsVisible() then
            if ui.javaObject:isPointOver(x, y) or ui:getIsCaptured() then
                if not consumed then
                    ui:onMouseMove(0, 0)
                    consumed = ui.javaObject.ConsumeMouseEvents == true
                end
            elseif ui.onMouseMoveOutside then
                ui:onMouseMoveOutside(0, 0)
            end
        end
    end
end
local function caret()
    inventory.mouseOverOption = 0
    move(610, 86)
    check(inventory.mouseOverOption == 1, "native inventory receives hover outside the visible HUD")
    local previous = inventory.collapsed.Bandages
    inventory:onMouseDown(10, 26)
    check(
        inventory.collapsed.Bandages ~= previous,
        "native inventory stack caret expands/collapses"
    )
end
caret()
check(
    mini.javaObject.width == mini:getWidth() and mini.javaObject.height == mini:getHeight(),
    "native Java hit bounds equal the mini window's committed size"
)
held = true
F.mouseX, F.mouseY = 88, 168
mini:onMouseDown(8, 8)
check(mini:getIsCaptured(), "header dragging captures normally")
held = false
mini:update()
caret()
check(
    not mini:getIsCaptured() and not mini.miniDrag,
    "a missed mouse-up releases before inventory input"
)
held = true
mini:onMouseDown(8, 8)
mini:setVisible(false)
held = false
-- Native UIManager skips hidden roots, so there is no mouse-up callback here.
mini:setVisible(true)
caret()
check(not mini:getIsCaptured(), "hide and reopen do not retain drag capture")
held = true
mini:onMouseDown(8, 8)
C.cancelDrag(mini)
F.click(mini.collapseButton)
held = false
caret()
check(
    mini.collapsed and not mini:getIsCaptured(),
    "collapse preserves normal button behavior and inventory input"
)
mini:setCapture(true)
mini:update()
caret()
check(not mini:getIsCaptured(), "orphan Java capture is repaired without a stored drag")
held = true
mini:onMouseDown(8, 8)
mini:removeFromUIManager()
held = false
check(not mini:getIsCaptured(), "removal releases capture before attachment recovery")
caret()
print("PASS InputRouting " .. n .. " checks (native inventory hover/caret and mini UI methods)")
