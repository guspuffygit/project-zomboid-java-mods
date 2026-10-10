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
local n = 0
local function check(ok, why)
    assert(ok, why)
    n = n + 1
end
local function empty(value)
    for _ in pairs(value) do
        return false
    end
    return true
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
        getDescriptor = function(self)
            return {
                getID = function()
                    return self.bodyId or 1
                end,
            }
        end,
        getModData = function(self)
            self.modData = self.modData or {}
            return self.modData
        end,
        transmitModData = function()
            error("Mini HUD must not send complete player modData for UI identity")
        end,
    }
end
F.players = { [0] = player(0) }
local p = F.players[0]
local uuidCount = 0
getRandomUUID = function()
    uuidCount = uuidCount + 1
    local value = tostring(uuidCount)
    return "00000000-0000-0000-0000-" .. string.rep("0", 12 - #value) .. value
end
getTexture = function(path)
    if path == "media/ui/inventoryPanes/Button_Gear.png" then
        return {
            getWidth = function()
                return 20
            end,
            getHeight = function()
                return 20
            end,
        }
    end
end
ATFPlayerMiniHUDTelemetry = {
    new = function(actor)
        return { player = actor, xpRows = {} }
    end,
    update = function(state, _, xp, temperature)
        local previous = state.temperature
        state.temperature = temperature and { key = "normal", text = "Normal" } or nil
        if not xp then
            state.xpRows = {}
        end
        return (previous == nil) ~= (state.temperature == nil)
    end,
    clear = function(state)
        state.player = nil
        state.xpRows = {}
        state.temperature = nil
    end,
    onXP = function() end,
    installYoga = function() end,
}
ATFPlayerMiniHUDHealthOpener = {
    bind = function() end,
    clear = function(panel)
        panel.healthOwner = nil
    end,
    observe = function()
        local closed = F.healthClosed
        F.healthClosed = nil
        return closed
    end,
}
local sample = {
    rows = {},
    allRows = {},
    health = 100,
    status = "OK",
    pain = 0,
    painText = "No pain",
    bleeding = 0,
    blood = "No active bleeding",
    signature = "healthy",
}
local samples, treatments = 0, 0
ATFCombatHealthModel = {
    clear = function()
        F.clears = (F.clears or 0) + 1
    end,
    snapshot = function()
        samples = samples + 1
        return sample
    end,
    openTreatment = function(actor, part)
        check(actor == p and part ~= nil, "local treatment row identity")
        treatments = treatments + 1
    end,
}
local menu
ISContextMenu = ISPanel:derive("FixtureContextMenu")
local function fixtureMenu()
    local context = ISContextMenu:new(0, 0, 1, 1)
    context.options = {}
    context:initialise()
    context:instantiate()
    context:addToUIManager()
    return context
end
function ISContextMenu.get()
    menu = fixtureMenu()
    return menu
end
function ISContextMenu:clear()
    self.options = {}
end
function ISContextMenu:closeAll()
    self:setVisible(false)
    for _, option in ipairs(self.options) do
        if option.sub then
            option.sub:closeAll()
        end
    end
end
function ISContextMenu:addOption(title, target, fn)
    local o = { title = title, target = target, fn = fn }
    self.options[#self.options + 1] = o
    return o
end
function ISContextMenu:setOptionChecked(o, value)
    o.checked = value
end
function ISContextMenu:getNew()
    local sub = fixtureMenu()
    sub:setVisible(false)
    return sub
end
function ISContextMenu:addSubMenu(o, sub)
    o.sub = sub
end
ISEquippedItem = {
    initialise = function(self)
        self.nativeChildren = true
        self.healthBtn = {}
    end,
}
local H = load(root .. "/media/lua/client/ATFCombatHealth/HUD.lua")
load(root .. "/media/lua/client/ATFCombatHealth_Client.lua")
local panel = H.ensure(p)
check(
    panel and not panel:getIsVisible() and samples == 0,
    "disabled by default without health sampling"
)
check(H.ensure({
    remote = true,
    isLocalPlayer = function()
        return false
    end,
}) == nil, "remote player never creates panel")
check(H.toggle(0) and panel:getIsVisible() and samples == 1, "toggle shows local healthy HUD")
local controls = panel:numChildren()
for i = 1, 100 do
    F.now = F.now + 1
    F.emit("OnPlayerUpdate", p)
    panel:update()
    panel:prerender()
end
check(
    samples == 1 and panel:numChildren() == controls,
    "no per-frame health sampling or control growth"
)
check(uuidCount == 1, "character UI identity is generated once, not per frame")
local layoutCount = 0
local oldLayout = panel.layout
panel.layout = function(self)
    layoutCount = layoutCount + 1
    oldLayout(self)
end
for i = 1, 4 do
    F.now = F.now + 250
    F.emit("OnPlayerUpdate", p)
end
check(samples == 5 and layoutCount == 0, "unchanged sampled signature never rebuilds layout")
F.now = F.now + 11000
F.emit("OnPlayerUpdate", p)
check(panel:getIsVisible() and panel.prefs.enabled, "enabled healthy HUD never times out")
local rows = {}
for i = 1, 17 do
    rows[i] = {
        id = i,
        bodyPart = {},
        name = "Part " .. i,
        summary = "Bleeding, Scratch",
        labels = { "Bleeding", "Scratch" },
        severity = 2,
    }
end
sample = {
    rows = rows,
    allRows = rows,
    health = 70,
    status = "Injured",
    pain = 3,
    painText = "Severe pain",
    bleeding = 3,
    blood = "Bleeding",
    critical = true,
    signature = "injured",
}
F.now = F.now + 250
F.emit("OnPlayerUpdate", p)
check(
    panel:getIsVisible() and layoutCount == 1 and not panel.rowOverflow,
    "all17 injuries fit without pagination at720p"
)
check(
    panel.rows[17]:getIsVisible() and not panel.rows[18]:getIsVisible(),
    "every injured native part has a visible row"
)
check(
    panel.rows[1]:getHeight() == 21 and panel.rows[1].treat:getHeight() == 17,
    "injury and treatment heights are roughly halved"
)
check(
    panel.prevButton == nil and panel.nextButton == nil and panel.turnPage == nil,
    "old pagination controls and callbacks are removed"
)
F.click(panel.rows[1].treat)
check(treatments == 1, "explicit Treat invokes vanilla adapter only once")
check(
    not panel:onMouseWheel(-1) and panel.rowOffset == 0,
    "ordinary HUD does not consume unused wheel input"
)
panel:setPref("mode", "mini")
check(
    panel.rows[17]:getIsVisible() and not panel.rowOverflow,
    "expanded mode retains all actionable injuries"
)
F.click(panel.collapseButton)
check(
    panel:getHeight() == panel.headerHeight and not panel.rows[1]:getIsVisible(),
    "collapse keeps only header"
)
F.click(panel.collapseButton)
F.width, F.height, F.font = 640, 480, 28
panel:update()
check(panel.rowOverflow, "large-font short screen exposes an injury wheel viewport")
for i = 1, 20 do
    panel:onMouseWheel(-1)
end
local lastVisible = math.min(panel.visibleRowCount, #rows)
check(panel.rows[lastVisible].data == rows[17], "short-screen wheel viewport reaches final injury")
for i = 1, 20 do
    panel:onMouseWheel(1)
end
check(panel.rows[1].data == rows[1], "wheel viewport returns to first injury")
check(
    panel:getX() + panel:getWidth() <= F.width and panel:getY() + panel:getHeight() <= F.height,
    "large font small screen remains on screen"
)
for _, child in pairs(panel:getChildren()) do
    if child:getIsVisible() then
        check(
            child:getY() + child:getHeight() <= panel:getHeight(),
            "visible child contained: " .. tostring(child.Type)
        )
        if child.getTitle then
            check(
                getTextManager():MeasureStringX(UIFont.Small, child:getTitle()) + 10
                    <= child:getWidth(),
                "large-font button text contained: " .. child:getTitle()
            )
        end
    end
end
panel:setPref("focusFade", false)
panel:update()
check(panel.miniAppliedAlpha == panel.prefs.opacity, "focus fade can be disabled")
check(
    panel.fullButton == nil and H.openFullHealth == nil,
    "Full Health control and unused opener helper are removed"
)
local equip = { chr = p, playerNum = 0 }
ISEquippedItem.initialise(equip)
check(
    equip.nativeChildren and equip.healthBtn.onRightMouseUp(),
    "native health sidebar intact and right click menu added"
)
panel:options()
check(#menu.options == 16, "cog includes treatment preference and two damage alert settings")
local staleSetting = menu.options[3].fn
F.key, F.typing = 90, true
F.emit("OnKeyPressed", 90)
check(panel.prefs.enabled, "keybind ignored while entering text")
F.typing = false
F.emit("OnKeyPressed", 90)
check(not panel.prefs.enabled and not panel:getIsVisible(), "configured hotkey closes HUD")
H.toggle(0)
panel:setX(200)
panel:setY(100)
panel:saveMiniLayout()
F.emit("OnPlayerDeath", p)
check(
    not panel:getIsVisible() and panel.snapshot == nil and panel.rows[1].data == nil,
    "death removes health references and capture"
)
check(
    panel.player == nil and empty(panel.displayRows) and H.panels[0] == nil and F.clears == 1,
    "death releases all cached health references"
)
F.players[0] = player(0)
F.players[0].bodyId = 2
local replaced = H.ensure(F.players[0])
check(
    replaced ~= panel and replaced.player == F.players[0] and not replaced.prefs.enabled,
    "new character stays closed when keep-on-respawn is disabled"
)
check(not F.attached[panel.javaObject], "old panel detached")
local livePreferences, liveRegistration =
    H.preferences[0], ISLayoutManager.windows[replaced.layoutName]
staleSetting()
panel:setCollapsed(false)
panel:onMouseWheel(-1)
panel:close()
panel:saveMiniLayout()
H.release(panel, true)
check(
    ISLayoutManager.windows[replaced.layoutName] == liveRegistration
        and liveRegistration.target == replaced,
    "stale cog/wheel/close callbacks cannot unregister the replacement HUD"
)
check(
    H.preferences[0] == livePreferences and not replaced.prefs.enabled,
    "stale callbacks cannot overwrite replacement preferences or reopen it"
)
sample = {
    rows = {},
    allRows = {},
    health = 100,
    status = "OK",
    pain = 0,
    painText = "No pain",
    bleeding = 0,
    blood = "No active bleeding",
    signature = "new-body-healthy",
}
H.toggle(0)
check(
    replaced:getIsVisible() and #replaced.displayRows == 0,
    "new survivor never reuses old injury rows"
)
local baselineLayouts, baselineSamples = layoutCount, samples
F.now = F.now + 60000
F.emit("OnPlayerUpdate", F.players[0])
check(
    replaced:getIsVisible() and samples == baselineSamples + 1,
    "healthy HUD stays open after a minute with bounded sampling"
)
ISUIHandler = { allUIVisible = false }
replaced:setVisible(false)
F.now = F.now + 1000
F.emit("OnPlayerUpdate", F.players[0])
check(not replaced:getIsVisible(), "game Hide UI is respected")
ISUIHandler.allUIVisible = true
F.attached[replaced.javaObject] = nil
F.now = F.now + 1000
F.emit("OnPlayerUpdate", F.players[0])
check(
    replaced:getIsVisible() and F.attached[replaced.javaObject],
    "enabled window recovers after UIManager removal"
)
local attachCalls = F.attachCalls
for i = 1, 30 do
    F.now = F.now + 10
    F.emit("OnPlayerUpdate", F.players[0])
end
check(F.attachCalls == attachCalls, "recovery does not reattach every frame")
F.healthClosed = true
F.now = F.now + 200
F.emit("OnPlayerUpdate", F.players[0])
check(replaced.prefs.enabled, "full Health close leaves HUD enabled by default")
replaced:setPref("keepVisibleWithHealthClosed", false)
F.healthClosed = true
F.now = F.now + 200
F.emit("OnPlayerUpdate", F.players[0])
check(
    not replaced.prefs.enabled and not replaced:getIsVisible(),
    "optional Health closure disables HUD without auto-reopening"
)
local disabledSamples = samples
for i = 1, 100 do
    F.now = F.now + 10
    F.emit("OnPlayerUpdate", F.players[0])
end
check(samples == disabledSamples, "closed HUD does not poll health")
H.toggle(0)
replaced:setPref("keepRespawn", true)
local oldState = replaced.telemetry
F.emit("OnPlayerDeath", F.players[0])
F.players[0] = player(0)
F.players[0].bodyId = 3
local reopened = H.ensure(F.players[0])
check(reopened.prefs.enabled and reopened:getIsVisible(), "keep-on-respawn reopens an enabled HUD")
check(
    reopened.telemetry ~= oldState and oldState.player == nil and #oldState.xpRows == 0,
    "respawn drops old telemetry references and recent activity"
)
reopened:close()
F.emit("OnPlayerDeath", F.players[0])
F.players[0] = player(0)
F.players[0].bodyId = 4
local closedRespawn = H.ensure(F.players[0])
check(
    not closedRespawn.prefs.enabled,
    "manually closed HUD remains closed even with respawn enabled"
)
closedRespawn:setPref("rememberPosition", false)
closedRespawn:setX(399)
closedRespawn:setY(210)
closedRespawn:saveMiniLayout()
check(
    F.layouts[closedRespawn.layoutName].x == nil and F.layouts[closedRespawn.layoutName].y == nil,
    "remember-position off removes saved coordinates"
)
F.emit("OnDisconnect")
check(
    empty(H.panels) and empty(ISLayoutManager.windows) and F.clears >= 2,
    "disconnect unregisters and removes all local panels"
)
local reload = H.ensure(F.players[0])
check(
    reload:getX() == 80 and reload:getY() == 160 and not reload.prefs.enabled,
    "reconnect restores settings without old coordinates or reopening a closed HUD"
)
H.toggle(0)
reload:setPref("showHealth", false)
local sectionSamples = samples
F.now = F.now + 1000
F.emit("OnPlayerUpdate", F.players[0])
check(
    samples == sectionSamples and #reload.displayRows == 0,
    "hidden Health section performs no body scan"
)
reload.telemetry.xpRows = {
    { text = "Aiming +3.25 XP" },
    { text = "Reloading +1.5 XP" },
    { text = "Maintenance +0.75 XP" },
}
reload:layout()
check(
    reload.xpCount == 3 and reload.xpY ~= nil and reload.temperatureY > reload.xpY,
    "recent XP and one-line temperature stack without empty health gaps"
)
reload:prerender()
reload.telemetry.xpRows = { { text = "Aiming +4 XP" } }
reload:prerender()
check(
    #reload.displayXP == 3 and reload.displayXP[2] == "Reloading +1.5 XP",
    "XP gains and expiry between samples cannot invalidate cached render rows"
)
reload.telemetry.xpRows = {}
reload:layout()
check(reload.xpY == nil, "empty recent XP collapses by default")
reload:setPref("alwaysShowXP", true)
check(reload.xpY ~= nil, "explicit setting can retain empty XP section")
local children = reload:numChildren()
for i = 1, 100 do
    F.now = F.now + 10
    F.emit("OnPlayerUpdate", F.players[0])
    reload:update()
end
check(reload:numChildren() == children, "new sections do not create growing controls")
reload:setPref("showHealth", true)
local function injuryRow(id, signals, summary)
    local ranks = {}
    for _, signal in ipairs(signals) do
        ranks[signal] = 1
    end
    return {
        id = id,
        signals = ranks,
        labels = signals,
        name = "Part " .. id,
        summary = summary or "Injured",
        severity = 1,
        bodyPart = {},
    }
end
local function injuries(injuryRows, signature, health)
    sample = {
        rows = injuryRows,
        allRows = injuryRows,
        health = health or 90,
        status = "Injured",
        pain = 0,
        painText = "No pain",
        bleeding = 0,
        blood = "No active bleeding",
        signature = signature,
    }
    F.now = F.now + 250
    F.emit("OnPlayerUpdate", F.players[0])
end
injuries({ injuryRow(1, { "cut" }) }, "first-cut")
reload:setCollapsed(true)
injuries({ injuryRow(1, { "cut" }), injuryRow(2, { "scratch" }) }, "another-wound")
check(
    not reload.collapsed,
    "new visible injury on another body part expands an already-injured HUD"
)
reload:setCollapsed(true)
injuries({ injuryRow(1, { "cut" }), injuryRow(2, { "scratch" }) }, "numeric-change", 89)
check(reload.collapsed, "numeric health changes do not expand a collapsed injury HUD")
injuries(
    { injuryRow(1, { "cut" }, "Cut (Moderate)"), injuryRow(2, { "scratch" }) },
    "suffix-change",
    89
)
check(
    reload.collapsed,
    "visible severity suffix changes without new conditions do not repeatedly expand"
)
injuries(
    { injuryRow(1, { "cut" }), injuryRow(2, { "scratch" }), injuryRow(3, {}, "Bandaged") },
    "treatment-only",
    89
)
check(reload.collapsed, "new treatment-only row does not expand as a new injury")
local mildPain, severePain = injuryRow(1, { "cut", "pain" }), injuryRow(1, { "cut", "pain" })
severePain.signals.pain = 2
injuries({ severePain, injuryRow(2, { "scratch" }) }, "visible-severe-pain", 89)
reload:setCollapsed(true)
injuries({ mildPain, injuryRow(2, { "scratch" }) }, "visible-pain-improves", 89)
check(reload.collapsed, "improving visible pain rank does not auto-expand")
injuries(
    { injuryRow(1, { "cut", "bullet" }), injuryRow(2, { "scratch" }) },
    "new-visible-condition",
    89
)
check(not reload.collapsed, "new visible condition on an existing injury expands the HUD")
reload:setPref("autoShow", false)
reload:setCollapsed(true)
injuries(
    { injuryRow(1, { "cut", "bullet" }), injuryRow(2, { "scratch" }), injuryRow(3, { "cut" }) },
    "auto-off",
    89
)
check(reload.collapsed, "auto-expand can be disabled")
reload:setPref("autoShow", true)
reload.snapshot = nil
injuries({ injuryRow(1, {}, "Bandaged") }, "initial-treatment-only")
check(reload.collapsed, "initial treatment-only snapshot does not auto-expand")
H.cleanup()
local originalPlayer = F.players[0]
local persist = H.ensure(originalPlayer)
persist:setPref("keepRespawn", false)
persist:setPref("enabled", true)
persist:saveMiniLayout()
local originalId = persist.survivorId
H.cleanup()
local sameSurvivor = player(0)
sameSurvivor.modData = originalPlayer.modData
F.players[0] = sameSurvivor
local sameBody = H.ensure(sameSurvivor)
check(
    sameBody.survivorId == originalId and sameBody.prefs.enabled,
    "saved UI token preserves enabled state when the same survivor is provable"
)
H.cleanup()
F.players[0] = player(0)
local freshBody = H.ensure(F.players[0])
check(
    freshBody.survivorId ~= originalId and not freshBody.prefs.enabled,
    "fresh body with reused native descriptor number cannot inherit enabled state"
)
F.font = 15
freshBody:setPref("mode", "compact")
local drawn, nativeDrawText = {}, freshBody.drawText
freshBody.drawText = function(self, label, x, y, r, g, b, ...)
    drawn[label] = { x = x, y = y, r = r, g = g, b = b }
    return nativeDrawText(self, label, x, y, r, g, b, ...)
end
local function summary(health, strain)
    freshBody.snapshot = {
        rows = {},
        allRows = {},
        health = health,
        status = "Critical damage",
        pain = 0,
        painText = "No pain",
        bleeding = 0,
        blood = "No active bleeding",
        strain = strain,
    }
    drawn = {}
    freshBody:layout()
    freshBody:prerender()
end
for _, case in ipairs({
    { 50.1, 0.95, 0.94, 0.9 },
    { 50, 1, 0.85, 0.2 },
    { 25.1, 1, 0.85, 0.2 },
    { 25, 1, 0.25, 0.25 },
    { 23.1, 1, 0.25, 0.25 },
    { 0, 1, 0.25, 0.25 },
}) do
    summary(case[1])
    local value, status, prefix =
        drawn[tostring(case[1])], drawn[" - Critical damage"], drawn["Health: "]
    check(
        value and value.r == case[2] and value.g == case[3] and value.b == case[4],
        "rendered number uses requested warning color at health " .. case[1]
    )
    check(
        status
            and status.r == (case[1] <= 25 and 1 or 0.95)
            and status.g == (case[1] <= 25 and 0.25 or 0.94),
        "damage status turns red only at 25 or below"
    )
    check(prefix and prefix.g == 0.94 and prefix.b == 0.9, "Health label remains neutral")
end
summary(100)
local withoutStrain = freshBody:getHeight()
summary(100, { count = 2, text = "Minor Muscle Strain" })
check(
    drawn["Minor Muscle Strain (2)"].y == drawn["No pain"].y + F.font + 3,
    "passive muscle strain is drawn one summary line below pain"
)
check(
    #freshBody.displayRows == 0 and not freshBody.rows[1]:getIsVisible(),
    "strain-only summary has no Treat rows"
)
check(
    freshBody:getHeight() == withoutStrain + F.font + 3,
    "only one extra line is reserved for passive strain"
)
summary(100)
check(
    freshBody:getHeight() == withoutStrain and freshBody.strainLine == nil,
    "resolved strain removes its line and gap"
)
freshBody.drawText = nativeDrawText
sample = {
    rows = rows,
    allRows = rows,
    health = 23.1,
    status = "Critical damage",
    pain = 3,
    painText = "Severe pain",
    bleeding = 3,
    blood = "Bleeding",
    signature = "all-sections",
    strain = { count = 2, text = "Minor Muscle Strain" },
}
freshBody:setPref("autoShow", false)
freshBody:setPref("mode", "mini")
freshBody:setPref("enabled", true)
F.width, F.height, F.font = 1280, 720, 15
freshBody.telemetry.xpRows =
    { { text = "Aiming +3 XP" }, { text = "Reloading +2 XP" }, { text = "Maintenance +1 XP" } }
freshBody:layout()
check(
    not freshBody.rowOverflow and freshBody.rows[17]:getIsVisible(),
    "all17 injuries plus strain, three XP gains and temperature fit at720p"
)
check(freshBody:getHeight() <= F.height - 16, "full compact contents leave screen margins at720p")
F.width, F.height = 640, 480
for _, font in ipairs({ 15, 28, 36 }) do
    for _, always in ipairs({ false, true }) do
        F.font = font
        freshBody.prefs.alwaysShowXP = always
        freshBody.telemetry.xpRows = {
            { text = "Aiming +3 XP" },
            { text = "Reloading +2 XP" },
            { text = "Maintenance +1 XP" },
        }
        freshBody:layout()
        check(
            freshBody.healthStatusX
                    + getTextManager():MeasureStringX(UIFont.Small, freshBody.healthStatus)
                    + 8
                <= freshBody:getWidth(),
            "critical damage text fits at large font " .. font
        )
        check(
            freshBody:getX() + freshBody:getWidth() <= F.width
                and freshBody:getY() + freshBody:getHeight() <= F.height,
            "all sections stay on 640x480 screen at font " .. font
        )
        for _, child in pairs(freshBody:getChildren()) do
            if child:getIsVisible() then
                check(
                    child:getY() + child:getHeight() <= freshBody:getHeight(),
                    "all-section visible child contained"
                )
            end
        end
    end
end
freshBody:close()
sample = {
    rows = {},
    allRows = {},
    health = 100,
    status = "OK",
    pain = 0,
    painText = "No pain",
    bleeding = 0,
    blood = "No active bleeding",
    signature = "fade-baseline",
}
H.cleanup()
F.font, F.mouseX, F.mouseY = 15, -1, -1
local fading = H.ensure(F.players[0])
fading:setPref("focusFade", true)
fading:setPref("enabled", true)
local renderedAlpha, fadeNativeDraw = nil, fading.drawText
fading.drawText = function(self, label, x, y, r, g, b, alpha, ...)
    if label == self.healthPrefix then
        renderedAlpha = alpha
    end
    return fadeNativeDraw(self, label, x, y, r, g, b, alpha, ...)
end
local fadeSequence = 0
local function frame(health, injuryRows, critical, pain, strain)
    fadeSequence = fadeSequence + 1
    sample = {
        rows = injuryRows or {},
        allRows = injuryRows or {},
        health = health,
        status = "Body status",
        pain = pain or 0,
        painText = "Pain status",
        bleeding = 0,
        blood = "No active bleeding",
        critical = critical or false,
        strain = strain,
        signature = "fade-" .. fadeSequence,
    }
    F.now = F.now + 250
    F.emit("OnPlayerUpdate", F.players[0])
    -- Native frame ordering can render refreshed content before HUD:update.
    fading:prerender()
    local beforeUpdate = renderedAlpha
    fading:update()
    return beforeUpdate
end
local dim, fullAlpha = fading.prefs.opacity * 0.5, fading.prefs.opacity
for i = 1, 40 do
    check(
        frame(100 - i * 0.1) == dim and fading.miniAppliedAlpha == dim,
        "routine 0.1 health loss stays faded before and after update"
    )
end
for i = 1, 10 do
    check(frame(96 + i * 0.1) == dim, "routine regeneration does not pulse")
end
check(
    frame(97, nil, false, 0, { count = 2, text = "Minor Muscle Strain" }) == dim,
    "passive strain layout change preserves dim opacity"
)
fading.telemetry.xpRows = { { text = "Strength +2 XP" } }
fading.telemetry.temperature = { key = "cool", text = "Cool" }
fading:layout()
fading:prerender()
check(
    renderedAlpha == dim and fading.backgroundColor.a == 0.95 * dim,
    "XP and temperature refresh preserve text and background fade"
)
local wound = injuryRow(1, { "cut" })
check(frame(97, { wound }) == fullAlpha, "new visible wound raises a short attention pulse")
local injuryExpiry = fading.attentionUntil
local secondWound = injuryRow(2, { "scratch" })
frame(96.9, { wound, secondWound })
check(fading.attentionUntil == injuryExpiry, "burst injuries do not extend an active pulse")
for i = 1, 10 do
    frame(96.9 - i * 0.1, { wound, secondWound })
end
check(
    renderedAlpha == dim and fading.attentionUntil == injuryExpiry,
    "injury pulse ends despite continuous health ticks"
)
check(
    frame(25, { wound, secondWound }) == fullAlpha,
    "critical low-health entry can bypass ordinary cooldown"
)
local criticalExpiry = fading.attentionUntil
for i = 1, 24 do
    frame(25 - i * 0.1, { wound, secondWound }, true, 3)
end
check(
    renderedAlpha == dim and fading.attentionUntil == criticalExpiry,
    "persistent critical state cannot keep renewing attention"
)
frame(100)
F.now = F.now + 6000
check(frame(99.9, nil, true, 3) == fullAlpha, "new critical moodle still alerts")
local moodleExpiry = fading.attentionUntil
for i = 1, 24 do
    frame(99.9 - i * 0.1, nil, true, 3)
end
check(
    renderedAlpha == dim and fading.attentionUntil == moodleExpiry,
    "unchanged critical moodle expires normally"
)
frame(100)
F.now = F.now + 6000
check(frame(50) == fullAlpha, "entry into yellow health band alerts once")
F.now = F.now + 6000
frame(50.1)
check(frame(49.9) == dim, "jitter across 50 cannot repeatedly pulse")
frame(55)
check(frame(50) == dim, "yellow alert needs clear recovery to re-arm")
frame(55.1)
F.now = F.now + 6000
check(frame(50) == fullAlpha, "clear recovery re-arms a later yellow alert")
local yellowExpiry = fading.attentionUntil
frame(25)
check(
    fading.attentionUntil == yellowExpiry,
    "critical escalation never extends an already active pulse"
)
F.now = F.now + 6000
frame(25.1)
check(frame(24.9) == dim, "jitter across 25 cannot repeatedly pulse")
frame(30)
check(frame(25) == dim, "red alert needs clear recovery to re-arm")
frame(30.1)
F.now = F.now + 6000
check(frame(25) == fullAlpha, "clear recovery re-arms a later red alert")
F.now = F.now + 3000
F.mouseX, F.mouseY = fading:getAbsoluteX() + 12, fading:getAbsoluteY() + 12
fading:update()
check(fading.miniAppliedAlpha == fullAlpha, "hover still restores full configured opacity")
F.mouseX, F.mouseY = -1, -1
fading:update()
check(fading.miniAppliedAlpha == dim, "leaving hover restores fade without a data update")
fading:setPref("focusFade", false)
check(frame(24.9) == fullAlpha, "disabling focus fade keeps full configured opacity")
-- Execute installed ISButton:render, capturing only the Java drawing boundary.
local nativeTextManager = getTextManager
getTextManager = function()
    local manager = nativeTextManager()
    manager.MeasureStringY = function()
        return F.font
    end
    return manager
end
local function buttonDraw(control)
    local result, nativeDraw = nil, control.javaObject.DrawText
    control.javaObject.DrawText = function(_, font, label, x, y, r, g, b, alpha)
        result = { label = label, r = r, g = g, b = b, alpha = alpha, font = font }
    end
    control:render()
    control.javaObject.DrawText = nativeDraw
    return result
end
local function buttonAlpha(control, alpha, enabled, why)
    local result = buttonDraw(control)
    local rgb = enabled and 1 or 0.3
    check(
        result
            and result.label == control.title
            and result.alpha == alpha
            and result.r == rgb
            and result.g == rgb
            and result.b == rgb
            and result.font == UIFont.Small,
        why .. " native title retains color and faded alpha"
    )
    check(
        control.backgroundColor.a == alpha
            and control.borderColor.a == (enabled and 1 or 0.7) * alpha,
        why .. " native enabled/disabled background and border have one fade"
    )
    check(
        control.backgroundColorMouseOver.a == alpha and control.textColor.a == alpha,
        why .. " text and hover alpha do not accumulate"
    )
end
local function gearAlpha(alpha, why)
    local imageAlpha, nativeDraw = nil, fading.optionsButton.drawTextureScaledAspect
    fading.optionsButton.drawTextureScaledAspect = function(_, image, x, y, w, h, value)
        check(
            image == fading.optionsButton.image and image ~= nil and w > 0 and h > 0,
            why .. " native renderer draws configured cog image"
        )
        imageAlpha = value
    end
    fading.optionsButton:render()
    fading.optionsButton.drawTextureScaledAspect = nativeDraw
    check(imageAlpha == alpha, why .. " cog image matches window opacity")
end
local nativeEnable, enableCalls = ISButton.setEnable, 0
ISButton.setEnable = function(self, value)
    enableCalls = enableCalls + 1
    return nativeEnable(self, value)
end
fading:setPref("focusFade", true)
fading:setPref("mode", "compact")
fading.snapshot = {
    rows = rows,
    allRows = rows,
    health = 100,
    status = "OK",
    pain = 0,
    painText = "No pain",
    bleeding = 0,
    blood = "No active bleeding",
}
fading.attentionUntil = nil
for _, font in ipairs({ 15, 28 }) do
    F.font, fading.rowOffset = font, 0
    fading:layout()
    local treat = fading.rows[1].treat
    treat:setEnable(false)
    buttonAlpha(treat, dim, false, "disabled treatment at font " .. font)
    treat:setEnable(true)
    buttonAlpha(treat, dim, true, "enabled treatment at font " .. font)
    gearAlpha(dim, "dim layout at font " .. font)
    local unchangedCalls = enableCalls
    for i = 1, 8 do
        fading:layout()
    end
    check(
        enableCalls == unchangedCalls,
        "unchanged layouts never reset native button colors at font " .. font
    )
    buttonAlpha(treat, dim, true, "repeated dim treatment at font " .. font)
    treat:setEnable(false)
    buttonAlpha(treat, dim, false, "treatment state transition at font " .. font)
    check(
        treat.backgroundColorEnabled.a == 1 and treat.borderColorEnabled.a == 1,
        "native enabled-color cache retains unscaled alpha at font " .. font
    )
    F.mouseX, F.mouseY = fading:getAbsoluteX() + 12, fading:getAbsoluteY() + 12
    fading:update()
    buttonAlpha(treat, fullAlpha, false, "hovered disabled treatment at font " .. font)
    gearAlpha(fullAlpha, "hover at font " .. font)
    treat:setEnable(true)
    buttonAlpha(treat, fullAlpha, true, "hovered treatment transition at font " .. font)
    F.mouseX, F.mouseY = -1, -1
    fading:update()
    buttonAlpha(treat, dim, true, "unhovered treatment at font " .. font)
    fading.attentionUntil = F.now + 2000
    fading:layout()
    buttonAlpha(treat, fullAlpha, true, "attention treatment at font " .. font)
    gearAlpha(fullAlpha, "attention at font " .. font)
    F.now = F.now + 2001
    fading:update()
    buttonAlpha(treat, dim, true, "expired attention treatment at font " .. font)
    gearAlpha(dim, "expired attention at font " .. font)
end
-- A first disable after fading must not poison native's saved enabled colors.
local lateButton = getmetatable(fading.rows[1].treat):new(
    0,
    0,
    50,
    30,
    "Treat",
    fading,
    function() end
)
lateButton:initialise()
fading:addChild(lateButton)
MiniUICore.fade(lateButton, dim)
lateButton:setEnable(false)
buttonAlpha(lateButton, dim, false, "first disable after fade")
check(
    lateButton.borderColorEnabled.a == 1 and lateButton.backgroundColorEnabled.a == 1,
    "first native enabled-color cache uses restored unscaled colors"
)
lateButton:setEnable(true)
buttonAlpha(lateButton, dim, true, "reenable after first faded disable")
for i = 1, 10 do
    lateButton:setEnable(false)
    lateButton:setEnable(true)
end
buttonAlpha(lateButton, dim, true, "repeated native state transitions")
fading:removeChild(lateButton)
ISButton.setEnable = nativeEnable
getTextManager = nativeTextManager
fading:close()
check(
    fading.attentionUntil == nil and fading.healthWarningBand == nil,
    "close clears attention state"
)
H.cleanup()
print("PASS HUD " .. n .. " checks (native UI methods; local model fixture)")
