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
local F = load(root .. "/test-support/NativeUI.lua")
F.install(game)
local C = load(root .. "/media/lua/client/MiniUI/Core.lua")
local n = 0
local function check(ok, why)
    assert(ok, why)
    n = n + 1
end
local panel = C.Window:new(100, 100, 300, 180, "Mini")
panel:initialise()
panel:instantiate()
check(
    C.attach(panel) and not C.attach(panel) and F.attachCalls == 1,
    "attachment recovery adds a window only once"
)
panel:recalcSize()
local footer = ISButton:new(8, 150, 70, 20, "Footer")
footer:initialise()
footer:setAnchorTop(false)
footer:setAnchorBottom(true)
panel:addChild(footer)
panel:recalcSize()
panel:setHeight(140)
C.size(panel, 300, 120)
check(footer:getY() == 90, "size must commit BOTH deferred native resize deltas")
C.pin(footer)
C.size(panel, 320, 200)
check(footer:getY() == 90, "layout-owned controls must have fixed anchors")
panel:setX(8000)
panel:setY(-8000)
C.clamp(panel)
check(
    panel:getX() + panel:getWidth() <= F.width - 8 and panel:getY() == 8,
    "clamp restored geometry"
)
F.mouseX, F.mouseY = 200, 200
check(panel:onMouseDown(20, 8) and panel.javaObject.Capture, "header drag captures mouse")
F.mouseX, F.mouseY = -5000, 900
panel:onMouseMoveOutside()
check(panel:getX() == 8 and panel:getY() + panel:getHeight() == F.height - 8, "drag clamps outside")
local saved = 0
panel.saveMiniLayout = function()
    saved = saved + 1
end
panel:onMouseUpOutside()
check(
    not panel.javaObject.Capture and saved == 1,
    "release outside saves once and releases capture"
)
local base = footer.textColor.a
C.fade(panel, 0.5)
C.fade(panel, 0.5)
check(footer.textColor.a == base * 0.5, "repeated fade not cumulative")
C.fade(panel, 1)
check(footer.textColor.a == base, "focus restores original alpha")
F.click(panel.collapseButton)
check(panel.collapsed and saved == 2, "native collapse button invokes callback")
F.click(panel.closeButton)
check(
    not panel:getIsVisible() and not panel.javaObject.Capture and saved == 3,
    "native close releases and hides"
)
F.width, F.height = 280, 180
C.size(panel, 240, 140)
check(
    panel:getX() >= 0
        and panel:getX() + panel:getWidth() <= F.width
        and panel:getY() + panel:getHeight() <= F.height,
    "small resolution clamp"
)
local layout = { name = "generic", x = "9999", pref = "yes" }
ISLayoutManager.layouts = { { width = 800, height = 600, windows = { layout } } }
C.register("generic", panel, function() end, function(target, _, row)
    target.pref = row.pref
    target:setX(tonumber(row.x))
    C.clamp(target)
end)
check(
    panel.pref == "yes" and panel:getX() + panel:getWidth() <= F.width,
    "resolution fallback carries preferences and clamps"
)
local input = C.Window:new(8, 8, 240, 140, "Input")
input:initialise()
input:instantiate()
local held = true
isMouseButtonDown = function(button)
    return button == 0 and held
end
for _, pos in ipairs({ { -1, 8 }, { 240, 8 }, { 8, -1 }, { 8, input.headerHeight }, { 0 / 0, 8 } }) do
    check(
        not input:onMouseDown(pos[1], pos[2]) and not input:getIsCaptured(),
        "outside coordinates cannot start capture"
    )
end
input:setCapture(true)
check(not C.endDrag(input) and not input:getIsCaptured(), "endDrag repairs orphan native capture")
input:onMouseDown(8, 8)
input:setVisible(false)
input:setVisible(true)
check(
    not input.miniDrag and not input:getIsCaptured(),
    "hide during drag cannot restore capture on reopen"
)
C.attach(input)
input:onMouseDown(8, 8)
input:removeFromUIManager()
check(
    not input.miniDrag and not input:getIsCaptured(),
    "removing a dragged UI releases native capture"
)
C.attach(input)
input:onMouseDown(8, 8)
F.click(input.collapseButton)
check(
    input.collapsed and not input.miniDrag and not input:getIsCaptured(),
    "collapse cancels capture before resizing"
)
input:onMouseDown(8, 8)
held = false
input:update()
check(
    not input.miniDrag and not input:getIsCaptured(),
    "update repairs mouse-up consumed by another UI"
)
held = true
input:onMouseDown(8, 8)
ISUIHandler = { allUIVisible = false }
input:update()
check(not input.miniDrag and not input:getIsCaptured(), "global UI hiding cancels capture")
ISUIHandler = nil
input:onMouseDown(8, 8)
local setX = input.setX
input.setX = function()
    error("drag geometry failure")
end
local ok, reason = pcall(C.drag, input)
input.setX = setX
check(
    not ok
        and tostring(reason):find("drag geometry failure")
        and not input.miniDrag
        and not input:getIsCaptured(),
    "drag errors release capture and preserve the diagnostic"
)
print("PASS MiniCore " .. n .. " checks (native UIElement/ISButton methods)")
