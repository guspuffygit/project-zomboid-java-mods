-- Reopening must preserve the just-closed geometry, even before a game save.
require = function() end
local checks = 0
local function check(ok, why)
    assert(ok, why)
    checks = checks + 1
end
local sw, sh = 1600, 1000
getCore = function()
    return {
        getScreenWidth = function()
            return sw
        end,
        getScreenHeight = function()
            return sh
        end,
    }
end
local W = {}
W.__index = W
function W:new(x, y, w, h)
    return setmetatable({ x = x, y = y, width = w, height = h }, self)
end
for _, name in ipairs({ "X", "Y", "Width", "Height" }) do
    local key = string.lower(name)
    W["get" .. name] = function(self)
        return self[key]
    end
    W["set" .. name] = function(self, value)
        self[key] = value
    end
end
function W:initialise() end
function W:addChild() end
function W:setResizable() end
function W:bringToTop() end
function W:setVisible() end
function W:removeFromUIManager()
    self.removed = true
end
function W:close()
    self:removeFromUIManager()
end
ISResizeWidget = W
ISButton = W
local stale = { x = 30, y = 40, width = 600, height = 400 }
local saves = 0
ISLayoutManager = {
    RegisterWindow = function(name, functions, target)
        functions.RestoreLayout(target, name, stale)
    end,
    OnPostSave = function()
        saves = saves + 1
    end,
}
AdminCore = {}
dofile("universal-admin-core/media/lua/client/AdminCore/WindowSizing.lua")
local T = AdminCore
local function open()
    local window = W:new(0, 0, 700, 500)
    T.resizable(window, "remember-test", 300, 240, function() end)
    return window
end
local first = open()
T.fit(first, 1100, 740)
first:setX(66)
first:close()
check(saves == 1, "Close plus remove only writes geometry once")
local second = open()
check(
    second.width == 1100 and second.height == 740 and second.x == 66,
    "Reopen uses last closed size over old saved layout"
)
sw, sh = 800, 600
local third = open()
check(third.width == 784 and third.height == 584, "Remembered size clamps to changed resolution")
ISLayoutManager.OnPostSave = function()
    error("disk unavailable")
end
T.fit(third, 600, 400)
check(pcall(function()
    third:close()
end) and third.removed, "Disk error must not prevent close")
print("PASS: " .. checks .. " window persistence checks")
