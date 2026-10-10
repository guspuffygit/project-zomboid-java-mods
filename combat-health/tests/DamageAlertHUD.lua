-- Actual native ISUI rendering/geometry and production HUD/alert integration.
-- Health/economy are read-only model boundaries; the menu capture records real
-- option callbacks without constructing the unrelated native popup manager.
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
load(coreRoot .. "/media/lua/client/MiniUI/Core.lua")
load(root .. "/media/lua/client/ATFCombatHealth/DamageAlerts.lua")
local checks = 0
local function check(value, why)
    assert(value, why)
    checks = checks + 1
end
local function near(first, second)
    return math.abs(first - second) < 0.000001
end
getRandomUUID = function()
    return "00000000-0000-0000-0000-000000000001"
end
getTexture = function()
    return {
        getWidth = function()
            return 20
        end,
        getHeight = function()
            return 20
        end,
    }
end
local actor = { data = {} }
function actor:getPlayerNum()
    return 0
end
function actor:isLocalPlayer()
    return true
end
function actor:isDead()
    return self.dead == true
end
function actor:getModData()
    return self.data
end
F.players = { [0] = actor }
ATFPlayerMiniHUDTelemetry = {
    new = function()
        return { xpRows = {} }
    end,
    update = function()
        return false
    end,
    clear = function() end,
}
local rawHealth, injuryRows, sampleCount = 100, {}, 0
ATFCombatHealthModel = {
    clear = function() end,
    snapshot = function()
        sampleCount = sampleCount + 1
        local rounded = math.floor(rawHealth * 10 + 0.5) / 10
        return {
            rawHealth = rawHealth,
            health = rounded,
            signature = tostring(rounded) .. ":" .. #injuryRows,
            rows = injuryRows,
            allRows = injuryRows,
            status = "OK",
            pain = 0,
            painText = "No pain",
            bleeding = 0,
            blood = "No bleeding",
        }
    end,
    openTreatment = function()
        error("Damage alerts must not issue a treatment")
    end,
}
local menu
ISContextMenu = ISPanel:derive("FixtureDamageAlertContextMenu")
local function fixtureMenu()
    local context = ISContextMenu:new(0, 0, 1, 1)
    context.options, context.instanceMap = {}, {}
    context:initialise()
    context:instantiate()
    context:addToUIManager()
    return context
end
function ISContextMenu.get()
    if menu then
        menu:closeAll()
        for _, child in ipairs(menu.instanceMap) do
            child:removeFromUIManager()
        end
        menu:clear()
        menu.instanceMap = {}
    else
        menu = fixtureMenu()
    end
    menu:setVisible(true)
    return menu
end
function ISContextMenu:clear()
    self.options = {}
end
function ISContextMenu:closeAll()
    self:setVisible(false)
    for _, child in ipairs(self.instanceMap) do
        child:setVisible(false)
    end
end
function ISContextMenu:addOption(name, target, onSelect)
    local option = { name = name, target = target, onSelect = onSelect }
    self.options[#self.options + 1] = option
    return option
end
function ISContextMenu:getNew()
    local child = fixtureMenu()
    child:setVisible(false)
    menu.instanceMap[#menu.instanceMap + 1] = child
    return child
end
function ISContextMenu:addSubMenu(option, submenu)
    option.submenu = submenu
end
function ISContextMenu:setOptionChecked(option, checked)
    option.checkMark = checked
end
local H = load(root .. "/media/lua/client/ATFCombatHealth/HUD.lua")
local panel = H.ensure(actor)
check(panel and not panel.prefs.enabled, "HUD still defaults to disabled")
H.toggle(0)
check(
    panel.prefs.damageAlertMode == "flash" and panel.prefs.damageAlertThreshold == 25,
    "HUD exposes correct damage defaults"
)

local function choose(section, value)
    F.click(panel.optionsButton)
    local submenu
    for _, option in ipairs(menu.options) do
        if option.name == section then
            submenu = option.submenu
        end
    end
    check(submenu ~= nil, "cog contains " .. section)
    for _, option in ipairs(submenu.options) do
        if option.name == value then
            -- Native onMouseUp closes the full menu before invoking a callback.
            menu:closeAll()
            option.onSelect(option.target)
            return
        end
    end
    error("Missing cog choice " .. section .. ": " .. value)
end
local function checked(section, value)
    F.click(panel.optionsButton)
    for _, option in ipairs(menu.options) do
        if option.name == section then
            for _, entry in ipairs(option.submenu.options) do
                if entry.name == value then
                    menu:closeAll()
                    return entry.checkMark
                end
            end
        end
    end
end
for _, threshold in ipairs({ 10, 15, 25, 40 }) do
    choose("DamageThreshold", tostring(threshold))
    check(
        panel.prefs.damageAlertThreshold == threshold,
        "cog callback sets threshold " .. threshold
    )
    check(checked("DamageThreshold", tostring(threshold)), "current threshold is checked")
    check(
        F.layouts[panel.layoutName].damageAlertThreshold == tostring(threshold),
        "threshold is saved in native layout data"
    )
    H.release(panel, false)
    H.preferences = {}
    panel = H.ensure(actor)
    check(panel.prefs.damageAlertThreshold == threshold, "threshold restores from saved layout")
end
for _, entry in ipairs({
    { "reveal", "RevealHUD" },
    { "off", "Off" },
    { "flash", "ThreeRedFlashes" },
}) do
    choose("DamageAlert", entry[2])
    check(
        panel.prefs.damageAlertMode == entry[1] and checked("DamageAlert", entry[2]),
        "cog sets and checks alert mode"
    )
    check(
        F.layouts[panel.layoutName].damageAlertMode == entry[1],
        "mode persists through layout serialization"
    )
    H.release(panel, false)
    H.preferences = {}
    panel = H.ensure(actor)
    check(panel.prefs.damageAlertMode == entry[1], "mode restores without in-memory preferences")
end
choose("DamageThreshold", "25")

local function reset(health)
    panel:close()
    rawHealth = health or 100
    injuryRows = {}
    F.now = F.now + 6000
    H.toggle(0)
    panel:update()
end
local function sample(health, elapsed)
    rawHealth = health
    F.now = F.now + (elapsed or 200)
    panel:sample(F.now)
    panel:update()
end
local function glowDraws()
    local draws = {}
    local native = panel.javaObject.DrawTextureScaledColor
    panel.javaObject.DrawTextureScaledColor = function(
        java,
        texture,
        x,
        y,
        width,
        height,
        r,
        g,
        b,
        alpha
    )
        if near(r, 1) and near(g, 0.08) and near(b, 0.05) and alpha > 0 then
            draws[#draws + 1] = { x = x, y = y, width = width, height = height, alpha = alpha }
        end
        return native(java, texture, x, y, width, height, r, g, b, alpha)
    end
    panel:prerender()
    panel.javaObject.DrawTextureScaledColor = native
    return draws
end
reset()
check(near(panel.miniAppliedAlpha, panel.prefs.opacity * 0.5), "unfocused HUD starts faded")
sample(75.04)
check(
    panel.damageAlerts.startedAt == nil,
    "rounded display loss cannot cause an early damage alert"
)
sample(75)
local started = F.now
check(panel.damageAlerts.startedAt == started, "exact raw25 loss starts actual HUD attention")
check(
    near(panel.miniAppliedAlpha, panel.prefs.opacity),
    "rapid damage temporarily restores configured full opacity"
)
check(
    panel.prefs.focusFade == true and F.layouts[panel.layoutName].focusFade == "true",
    "temporary reveal leaves saved focusFade enabled"
)
F.now = started + 333
panel:update()
local draws = glowDraws()
check(#draws == 5, "flash renders one red fill and four native border segments")
for _, draw in ipairs(draws) do
    check(
        draw.x >= 0
            and draw.y >= 0
            and draw.x + draw.width <= panel:getWidth()
            and draw.y + draw.height <= panel:getHeight(),
        "red drawing remains inside HUD bounds"
    )
    check(draw.alpha > 0 and draw.alpha <= 1, "native glow alpha remains valid")
end
panel:setCollapsed(true)
check(#glowDraws() == 5, "collapsed HUD still draws damage glow before early return")
check(
    panel:getHeight() == panel.headerHeight,
    "collapsed alert never expands or distorts the window"
)
panel:setCollapsed(false)
F.now = started + 2000
panel:update()
check(
    #glowDraws() == 0 and near(panel.miniAppliedAlpha, panel.prefs.opacity * 0.5),
    "after two seconds glow and temporary reveal expire"
)

reset()
sample(90)
sample(100)
sample(85)
check(
    panel.damageAlerts.startedAt == nil,
    "healing clears prior15 damage instead of summing separate periods"
)
sample(75)
check(panel.damageAlerts.startedAt == F.now, "fresh25 damage after healing still alerts")
choose("DamageAlert", "Off")
check(
    panel.damageAlerts.startedAt == nil and #glowDraws() == 0,
    "off clears active damage alert and drawing immediately"
)
reset()
sample(75)
check(panel.damageAlerts.startedAt == nil and #glowDraws() == 0, "off suppresses new rapid damage")
choose("DamageAlert", "RevealHUD")
reset()
sample(75)
F.now = F.now + 333
panel:update()
check(
    near(panel.miniAppliedAlpha, panel.prefs.opacity) and #glowDraws() == 0,
    "reveal mode unfades actual HUD without red drawing"
)
choose("DamageAlert", "ThreeRedFlashes")
reset()
for i = 1, 50 do
    sample(100 - i * 0.1)
    check(
        panel.damageAlerts.startedAt == nil and #glowDraws() == 0,
        "ordinary0.1 health ticks never flash"
    )
end
check(
    near(panel.miniAppliedAlpha, panel.prefs.opacity * 0.5),
    "slow damage above warning bands leaves ordinary focus fade intact"
)

reset()
sample(75)
panel:close()
panel:update()
check(
    not panel:getIsVisible() and not panel.prefs.enabled and panel.damageAlerts.startedAt == nil,
    "close clears active attention and disables HUD"
)
check(panel.damageGlow == 0, "closed HUD retains no stale glow")
reset()
sample(75)
panel:setPref("showHealth", false)
check(
    panel.damageAlerts.startedAt == nil and panel.damageGlow == 0,
    "hiding health clears damage attention"
)
panel:setPref("showHealth", true)
reset()
sample(75)
actor.dead = true
panel:sample(F.now + 200)
check(
    H.panels[0] == nil and panel.damageAlerts.startedAt == nil and not panel:getIsVisible(),
    "death releases HUD and clears damage state"
)
actor.dead = false
panel = H.ensure(actor)
check(panel.damageAlerts.startedAt == nil, "replacement HUD starts with fresh damage state")
reset()

for i = 1, 17 do
    injuryRows[i] = {
        id = i,
        name = "Body part " .. i,
        summary = "A long injury summary",
        severity = 1,
        bodyPart = {},
    }
end
sample(100)
check(
    panel.prevButton == nil and panel.nextButton == nil,
    "compact layout has no old pagination buttons"
)
check(
    not panel.rowOverflow and panel.rows[17]:getIsVisible(),
    "all17 native body parts fit at normal720p font"
)
for _, size in ipairs({ { 1280, 720, 15 }, { 640, 480, 28 } }) do
    F.width, F.height, F.font = size[1], size[2], size[3]
    panel:update()
    check(
        panel:getX() >= 0
            and panel:getY() >= 0
            and panel:getX() + panel:getWidth() <= F.width
            and panel:getY() + panel:getHeight() <= F.height,
        "compact HUD stays on screen across resolution/font changes"
    )
    for _, row in ipairs(panel.rows) do
        if row:getIsVisible() then
            check(
                row:getY() >= panel.headerHeight
                    and row:getY() + row:getHeight() <= panel:getHeight(),
                "visible compact injury row remains inside content"
            )
            check(
                row.treat:getX() >= 0
                    and row.treat:getX() + row.treat:getWidth() <= row:getWidth()
                    and row.treat:getY() + row.treat:getHeight() <= row:getHeight(),
                "Treat control fits its single-line injury row"
            )
        end
    end
end
check(panel.rowOverflow, "large font uses bounded injury viewport")
for i = 1, 25 do
    panel:onMouseWheel(-1)
end
local last
for _, row in ipairs(panel.rows) do
    if row:getIsVisible() then
        last = row.data
    end
end
check(last == injuryRows[17], "mouse wheel reaches final injury at large fonts")
local reads = sampleCount
for i = 1, 30 do
    panel:update()
end
check(sampleCount == reads, "render updates do not add health reads")
print("DamageAlertHUD: " .. checks .. " checks passed")
