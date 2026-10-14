-- Native B42 option callbacks plus the production client/server power paths.
local game = assert(arg[1], "Pass the installed game directory")
local root = "universal-admin-core/media/lua/"
local count, now, server = 0, 10000, false
local function check(value, message)
    assert(value, message)
    count = count + 1
end
require = function() end
local events = {}
Events = setmetatable({}, {
    __index = function(t, key)
        local event = {
            Add = function(fn)
                events[key] = events[key] or {}
                table.insert(events[key], fn)
            end,
        }
        rawset(t, key, event)
        return event
    end,
})
local function fire(event, ...)
    for _, fn in ipairs(events[event] or {}) do
        fn(...)
    end
end
Capability = setmetatable({}, {
    __index = function(t, key)
        local cap = {
            name = function()
                return key
            end,
            key = key,
        }
        rawset(t, key, cap)
        return cap
    end,
})
local caps, admin = {}, true
local role = {
    hasCapability = function(_, cap)
        return caps[cap.key] ~= false
    end,
    hasAdminPower = function()
        return admin
    end,
}
local player = {
    values = {},
    name = "admin",
    getRole = function()
        return role
    end,
    getUsername = function(self)
        return self.name
    end,
    isDead = function()
        return false
    end,
}
getPlayer = function()
    return player
end
getTimestampMs = function()
    return now
end
isServer = function()
    return server
end
isClient = function()
    return not server
end
isDebugEnabled = function()
    return false
end
getText = function(text)
    return text
end
local font = 16
UIFont = { Small = 1, Medium = 2 }
getTextManager = function()
    return {
        getFontHeight = function()
            return font
        end,
        MeasureStringX = function(_, _, text)
            return #text * font / 2
        end,
    }
end
getCore = function()
    return {
        getScreenWidth = function()
            return 1280
        end,
        getScreenHeight = function()
            return 720
        end,
    }
end
local W = {}
W.__index = W
function W:derive()
    local object = {}
    object.__index = object
    return setmetatable(object, self)
end
function W:new(x, y, width, height)
    return setmetatable(
        { x = x, y = y, width = width, height = height, children = {}, visible = true },
        self
    )
end
function W:initialise() end
function W:addChild(child)
    -- Match native lazy attachment for widgets with a concrete Java peer.
    if child.instantiate and not child.javaObject then
        child:instantiate()
    end
    self.children[#self.children + 1] = child
    child.parent = self
end
function W:setVisible(value)
    self.visible = value
end
function W:addToUIManager() end
function W:removeFromUIManager() end
function W:bringToTop() end
function W:isMouseOver()
    return false
end
function W:getIsVisible()
    return self.visible
end
function W:drawRectStatic() end
function W:drawRectBorderStatic() end
function W:drawText(text)
    self.lastDrawnText = text
end
for _, field in ipairs({ "X", "Y", "Width", "Height" }) do
    local key = field:lower()
    W["set" .. field] = function(self, value)
        self[key] = value
    end
end
ISUIElement = W
UITransition = {
    new = function()
        return {}
    end,
}
getSoundManager = function()
    return { playUISound = function() end }
end
-- Only the Java text-box boundary is stubbed. The public Lua widget API,
-- constructors, setters, placeholder behavior and focus lifecycle are native.
local textPeer = {}
textPeer.__index = textPeer
function textPeer:setTable(owner)
    self.owner = owner
end
function textPeer:setEditable(editable)
    self.editable = editable
end
function textPeer:SetText(text)
    self.text = text
end
function textPeer:getText()
    return self.text
end
function textPeer:setPlaceholderText(text)
    self.placeholderText = text
end
function textPeer:getPlaceholderText()
    return self.placeholderText
end
function textPeer:focus()
    self.focused = true
end
function textPeer:unfocus()
    self.focused = false
end
function textPeer:isFocused()
    return self.focused == true
end
for _, field in ipairs({
    "X",
    "Y",
    "Width",
    "Height",
    "AnchorLeft",
    "AnchorRight",
    "AnchorTop",
    "AnchorBottom",
}) do
    textPeer["set" .. field] = function(self, value)
        self[field] = value
    end
end
UITextBox2 = {
    new = function(_, x, y, width, height, text)
        return setmetatable({ X = x, Y = y, Width = width, Height = height, text = text }, textPeer)
    end,
}
dofile(game .. "/media/lua/client/ISUI/ISPanel.lua")
dofile(game .. "/media/lua/client/ISUI/ISPanelJoypad.lua")
dofile(game .. "/media/lua/client/ISUI/ISButton.lua")
dofile(game .. "/media/lua/client/ISUI/ISTextEntryBox.lua")
for _, name in ipairs({
    "ISFastTeleportMove",
    "ISBuildMenu",
    "ISFarmingMenu",
    "ISHealthPanel",
    "ISVehicleMechanics",
    "ISMoveableDefinitions",
    "BrushToolManager",
    "ISLootZed",
    "ISLootLog",
    "AnimalContextMenu",
}) do
    _G[name] = { cheat = false }
end
local stores = {}
ModData = {
    getOrCreate = function(key)
        stores[key] = stores[key] or {}
        return stores[key]
    end,
}
dofile(root .. "shared/AdminCore/OperationsPermissions.lua")
dofile(root .. "shared/AdminCore/PowerDefinitions.lua")
for _, row in ipairs(AdminPowerDefinitions.list) do
    local entry = AdminPowerDefinitions.byId[row[1]]
    player[entry.getter] = function(self)
        return self.values[entry.id] == true
    end
    player[entry.setter] = function(self, value)
        self.values[entry.id] = value
    end
end
dofile(game .. "/media/lua/client/ISUI/AdminPanel/ISAdminPowerUI.lua")
local packets, messages, extras = {}, {}, 0
sendClientCommand = function(actor, module, command, args)
    packets[#packets + 1] = { actor = actor, module = module, command = command, args = args }
end
sendPlayerExtraInfo = function()
    extras = extras + 1
end
local lease, toolPolicy = true, {}
AdminCore = {
    actions = {},
    registryVersion = 1,
    operationsAllowed = function(key)
        return lease and AdminOperations.authorized(player, key)
    end,
    operationToolAllowed = function(id)
        return not toolPolicy[id]
    end,
    operationsKeepAlive = function() end,
    pin = function() end,
    resizable = function(panel, key, width, height, layout)
        layout(panel)
    end,
    message = function(text)
        messages[#messages + 1] = text
    end,
    registerAction = function(action)
        AdminCore.actions[action.id] = action
    end,
}
dofile(root .. "client/AdminCore/AdminPowers.lua")
local C = AdminCore
check(#AdminPowerDefinitions.list == 24, "24 explicitly supported native powers")
for _, row in ipairs(AdminPowerDefinitions.list) do
    local entry, option = AdminPowerDefinitions.byId[row[1]], ISAdminPowerUI.OptionById[row[1]]
    check(option ~= nil, "Power must exist in installed native UI: " .. row[1])
    check(
        option.capability == Capability[entry.capability],
        "Per-power native capability matches installed game"
    )
    option.setValue({ player = player }, true)
    check(
        player[entry.getter](player) == true and option.getValue({ player = player }) == true,
        "Native callback and authoritative accessor agree on enabled state"
    )
    option.setValue({ player = player }, false)
    check(
        player[entry.getter](player) == false and option.getValue({ player = player }) == false,
        "Native callback and authoritative accessor agree on disabled state"
    )
end
caps.ToggleGodModHimself = false
C.togglePower("GodMod")
check(
    #packets == 0 and not player.values.GodMod,
    "Denied native capability cannot request or optimistically apply a power"
)
lease = false
C.togglePower("Invisible")
check(#packets == 0, "Expired server lease denies even locally permitted powers")
lease = true
C.powerPreset(1)
check(
    #packets == 1
        and packets[1].args.values.GodMod == nil
        and packets[1].args.values.Invisible == true,
    "Preset includes only actual granted capabilities"
)
check(not player.values.Invisible, "Waiting for server does not change local player")
fire(
    "OnServerCommand",
    "UniversalAdminPowers",
    "state",
    { token = packets[1].args.token + 1, values = { Invisible = true } }
)
check(not player.values.Invisible, "Unsolicited or stale power reply is ignored")
fire(
    "OnServerCommand",
    "UniversalAdminPowers",
    "state",
    { token = packets[1].args.token, values = { Invisible = true, BuildCheat = true } }
)
check(
    player.values.Invisible and ISBuildMenu.cheat and extras == 1,
    "Acknowledged native callbacks synchronize player and native menu globals"
)
fire(
    "OnServerCommand",
    "UniversalAdminPowers",
    "state",
    { token = 0, values = { BuildCheat = false, GodMod = true } }
)
check(
    not ISBuildMenu.cheat and not player.values.GodMod,
    "Revocation can disable powers but cannot enable an unsolicited power"
)
check(#C.powerRows("Debug", "invisible") == 1, "Search discovers powers across groups")
toolPolicy["power.Invisible"] = true
check(
    #C.powerRows("Movement", "invisible") == 0,
    "Server-hidden tool disappears from grouped UI and search"
)
toolPolicy = {}
local nativePanel = C.openAdminPowers()
check(
    nativePanel.search.setDefaultEntryText == nil,
    "Native text entry does not invent the nonexistent placeholder API"
)
check(
    nativePanel.search:getPlaceholderText() == "Search powers..."
        and nativePanel.search:getText() == "",
    "Opening powers uses the native placeholder without populating the search query"
)
check(nativePanel.search:isFocused(), "Opening powers focuses the native text entry")
nativePanel:prerender()
check(
    nativePanel.lastDrawnText:find("Movement", 1, true) ~= nil,
    "Native panel prerender reaches the grouped status line"
)
local function click(widget)
    widget:onMouseDown(1, 1)
    widget:onMouseUp(1, 1)
end
click(nativePanel.groupButtons[4])
check(nativePanel.group == "Visibility", "Native button dispatch selects the requested group")
nativePanel.search:setText("invisible")
nativePanel.search:onTextChange()
check(
    nativePanel.count == 1 and nativePanel.rows[1].powerId == "Invisible",
    "Typing into native search finds powers across groups"
)
local powerButton = nativePanel.rows[1]
check(
    powerButton.title == "[ON] Invisible" and powerButton.backgroundColor.g == 0.34,
    "Native power button initially displays the enabled state"
)
click(powerButton)
local changePacket = packets[#packets]
check(
    changePacket.args.values.Invisible == false and player.values.Invisible == true,
    "Native button dispatch requests the change without applying it optimistically"
)
fire(
    "OnServerCommand",
    "UniversalAdminPowers",
    "state",
    { token = changePacket.args.token, values = { Invisible = false } }
)
check(
    powerButton.title == "[OFF] Invisible" and powerButton.backgroundColor.g == 0.05,
    "Native setEnable color restoration cannot hide the newly disabled state"
)
click(powerButton)
changePacket = packets[#packets]
fire(
    "OnServerCommand",
    "UniversalAdminPowers",
    "state",
    { token = changePacket.args.token, values = { Invisible = true } }
)
check(
    powerButton.title == "[ON] Invisible" and powerButton.backgroundColor.g == 0.34,
    "Re-enabling updates both native button label and selected tint"
)
click(nativePanel.closeButton)
check(
    C.powersPanel == nil and not nativePanel.search:isFocused(),
    "Native Close button removes the window and releases keyboard focus"
)
local reopened = C.openAdminPowers()
check(
    reopened ~= nativePanel and reopened.search:getText() == "" and reopened.search:isFocused(),
    "Powers can reopen with a fresh usable native search box"
)
reopened:close()
for _, fontSize in ipairs({ 12, 18, 24, 32 }) do
    font = fontSize
    local panel = C.openAdminPowers()
    for _, width in ipairs({ 620, 800, 1100 }) do
        for _, height in ipairs({ 500, 600, 704 }) do
            panel.width, panel.height = width, height
            panel:layoutPowers()
            local g = panel.geometry
            check(
                g.contentY + g.pageSize * (g.row + 6) - 6 <= g.footerY,
                "Power rows fit above footer at small bounds / large fonts"
            )
            check(
                panel.observer.y + panel.observer.height <= height,
                "Observer/close/footer remain reachable"
            )
            for _, row in ipairs(panel.rows) do
                if row.visible then
                    check(
                        row.x >= 0
                            and row.x + row.width <= width
                            and row.y + row.height <= g.footerY,
                        "Actual visible row bounds stay in viewport"
                    )
                end
            end
        end
    end
    panel:close()
end
fire("OnDisconnect")
check(C.powersPanel == nil, "Disconnect closes powers UI and pending changes")

server = true
local replies, synced = {}, 0
sendServerCommand = function(actor, module, command, args)
    replies[#replies + 1] = args
end
AdminCoreBridge = {
    syncPowers = function()
        synced = synced + 1
    end,
}
getOnlinePlayers = function()
    return {
        size = function()
            return 1
        end,
        get = function()
            return player
        end,
    }
end
dofile(root .. "server/PowerServer.lua")
local S = AdminPowerServer
local function apply(values, token)
    now = now + 1000
    S.onCommand("UniversalAdminPowers", "apply", player, { token = token or 10, values = values })
end
player.values = {}
admin = false
apply({ Invisible = true })
check(not player.values.Invisible, "Crafted ordinary player packet is rejected server-side")
admin = true
apply({ Invisible = true, GodMod = true })
check(not player.values.Invisible, "Mixed denied preset makes no partial changes")
caps.ToggleGodModHimself = true
apply({ Invisible = true, GodMod = true })
check(
    player.values.Invisible and player.values.GodMod and synced > 0,
    "Permitted powers are applied on server and replicated"
)
local audit = stores["UniversalAdminCore.OperationsAudit.v1"].rows
local auditCount = #audit
apply({ Invisible = true, GodMod = true })
check(
    #audit == auditCount,
    "Replayed boolean request is idempotent and does not repeat meaningful audit"
)
apply({ setAccessLevel = true })
check(replies[#replies].error ~= nil, "Unknown methods cannot be invoked through power packets")
local policy = AdminOperations.policy()
policy.disabled = { ADMIN_POWER_BASIC = true }
apply({ GodMod = false })
check(player.values.GodMod, "Disabled feature denies crafted requests")
S.tick()
check(
    not player.values.GodMod and not player.values.Invisible and replies[#replies].token == 0,
    "Live policy revocation disables tracked powers without restart"
)
policy.disabled = {}
policy.disabledTools = { ["power.GodMod"] = true }
apply({ GodMod = true })
check(not player.values.GodMod, "Per-tool server policy also applies to power RPC")
policy.disabledTools = nil
local original = player.setInvisible
player.setInvisible = function(self, value)
    if value then
        error("fixture setter failure")
    else
        self.values.Invisible = false
    end
end
apply({ Invisible = true, GodMod = true })
check(
    not player.values.Invisible and not player.values.GodMod and replies[#replies].error,
    "Setter failure restores earlier values instead of leaving partial preset"
)
player.setInvisible = original
local registrations = #events.OnClientCommand
dofile(root .. "server/PowerServer.lua")
check(#events.OnClientCommand == registrations, "Server reload cannot duplicate power handlers")
local panel = C.openAdminPowers()
admin = false
panel:prerender()
check(C.powersPanel == nil, "Role removal closes grouped powers and stops its permission heartbeat")

-- A real restart loses module locals and creates a new player object, but keeps
-- server ModData. Only this module's prior grants may be revoked on the new join.
admin = true
apply({ Invisible = true })
local saved = stores["UniversalAdminCore.PowerGrants.v1"].users
check(
    saved.admin.Invisible == true and saved.admin.GodMod == nil,
    "Persist only UAC-enabled IDs, not unrelated vanilla state"
)
player.values.GodMod = true -- enabled outside UAC
local online = false
getOnlinePlayers = function()
    return {
        size = function()
            return online and 1 or 0
        end,
        get = function()
            return player
        end,
    }
end
AdminPowerServer = nil
events.OnTick, events.OnClientCommand = {}, {}
dofile(root .. "server/PowerServer.lua")
S = AdminPowerServer
now = now + 3000
S.tick()
check(
    saved.admin.Invisible == true,
    "Offline grant is retained across restart until the account rejoins"
)
local returning = { values = { Invisible = true, GodMod = true } }
for key, value in pairs(player) do
    if key ~= "values" then
        returning[key] = value
    end
end
player = returning
admin, online = false, true
now = now + 3000
S.tick()
check(
    not player.values.Invisible and player.values.GodMod,
    "Restart/join revokes stale UAC grant while preserving unrelated vanilla power"
)
check(
    saved.admin == nil and replies[#replies].token == 0,
    "Last revoked ID prunes empty account and sends native/client cleanup"
)
admin = true
apply({ FastMove = true })
player.values.FastMove = false -- native state was not restored by the game
saved.admin.unknownMethod = true
saved.admin.Invisible = "true"
AdminPowerServer = nil
events.OnTick, events.OnClientCommand = {}, {}
dofile(root .. "server/PowerServer.lua")
S = AdminPowerServer
now = now + 3000
S.tick()
check(
    not player.values.FastMove,
    "Restart never auto-enables a stored grant or replays desired values"
)
check(
    saved.admin.FastMove == true
        and saved.admin.unknownMethod == nil
        and saved.admin.Invisible == nil,
    "Stored grant normalization retains only known boolean IDs"
)
apply({ FastMove = false })
check(saved.admin == nil, "Explicit disable prunes the final tracked account entry")
print("Admin power operations: " .. count .. " checks passed")
