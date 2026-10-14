-- Actual installed User Panel, UI element, button and tickbox methods.
local game = assert(arg[1], "Pass the installed game directory")
local root = arg[2] or "universal-admin-core"
require = function() end
local count, font = 0, 15
local function check(value, message)
    assert(value, message)
    count = count + 1
end
getText = function(key)
    return key
end
UIFont = { Small = "Small", Medium = "Medium" }
getTextManager = function()
    return {
        getFontHeight = function()
            return font
        end,
        MeasureStringX = function(_, _, value)
            return #value * font / 2
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
        getOptionFontSizeReal = function()
            return 1
        end,
    }
end
getTexture = function()
    return nil
end
getISUIStackTrace = function()
    return "fixture"
end
UITransition = {
    new = function()
        return {}
    end,
}
ISDock, UIHorizontalAlignment = { None = 0 }, { Left = 0 }
local attached = {}
UIManager = {
    AddUI = function(element)
        attached[element] = true
    end,
    RemoveElement = function(element)
        attached[element] = nil
    end,
}
-- Java owns child attachment and deferred anchors; Lua geometry stays native.
local J = {}
J.__index = J
for _, name in ipairs({ "X", "Y", "Width", "Height" }) do
    local field = name:lower()
    J["get" .. name] = function(self)
        return self[field]
    end
    J["set" .. name] = function(self, value)
        self[field] = value
    end
end
for _, name in ipairs({
    "AnchorLeft",
    "AnchorRight",
    "AnchorTop",
    "AnchorBottom",
    "WantKeyEvents",
    "ConsumeMouseEvents",
    "WantExtraMouseEvents",
    "ForceCursorVisible",
}) do
    J["set" .. name] = function(self, value)
        self[name] = value
    end
end
function J:setVisible(value)
    self.visible = value
end
function J:isVisible()
    return self.visible
end
function J:isMouseOver()
    return false
end
function J:AddChild(child)
    self.children[#self.children + 1] = child
    child.parent = self
end
dofile(root .. "/tests/fixtures/NativeChildren.lua")(J)
function J:DrawText() end
UIElement = {
    new = function(owner)
        return setmetatable({
            x = 0,
            y = 0,
            width = 0,
            height = 0,
            lastWidth = owner.width,
            lastHeight = owner.height,
            children = {},
            visible = true,
        }, J)
    end,
}
dofile(game .. "/media/lua/shared/ISBaseObject.lua")
dofile(game .. "/media/lua/shared/luautils.lua")
dofile(game .. "/media/lua/client/ISUI/Layout/ISBounds.lua")
dofile(game .. "/media/lua/client/ISUI/ISUIElement.lua")
dofile(game .. "/media/lua/client/ISUI/ISPanel.lua")
dofile(game .. "/media/lua/client/ISUI/ISButton.lua")
dofile(game .. "/media/lua/client/ISUI/ISTickBox.lua")
local house, factionMember, canCreate, factionsEnabled, publicOptions = nil, false, true, true, true
local actor = {
    getUsername = function()
        return "guest"
    end,
    getRole = function()
        return {
            hasCapability = function()
                return publicOptions
            end,
        }
    end,
}
getPlayer = function()
    return actor
end
Capability = { SeePublicServerOptions = "SeePublicServerOptions" }
SafeHouse = {
    hasSafehouse = function(value)
        check(
            value == actor or value == "guest",
            "Native and wrapped membership checks use the own player"
        )
        return house
    end,
}
Faction = {
    isAlreadyInFaction = function()
        return factionMember
    end,
    canCreateFaction = function()
        return canCreate
    end,
    getPlayerFaction = function()
        return "native-faction"
    end,
}
getServerOptions = function()
    return {
        getBoolean = function(_, key)
            check(key == "Faction", "Native faction setting preserved")
            return factionsEnabled
        end,
        getInteger = function()
            return 3
        end,
    }
end
local connectionInfo, serverInfo = false, false
isShowConnectionInfo = function()
    return connectionInfo
end
isShowServerInfo = function()
    return serverInfo
end
setShowConnectionInfo = function(value)
    connectionInfo = value
end
setShowServerInfo = function(value)
    serverInfo = value
end
local safehouseOpens, optionsOpens, factionOpens, createFactionOpens = 0, 0, 0, 0
local function modal()
    return { initialise = function() end, addToUIManager = function() end }
end
ISSafehouseUI = {
    new = function(_, x, y, w, h, claim, player)
        check(
            claim == house and player == actor,
            "Native safehouse click resolves current own membership"
        )
        safehouseOpens = safehouseOpens + 1
        return modal()
    end,
}
ISServerOptions = {
    new = function()
        optionsOpens = optionsOpens + 1
        return modal()
    end,
}
ISFactionUI = {
    new = function()
        factionOpens = factionOpens + 1
        return modal()
    end,
}
ISCreateFactionUI = {
    new = function()
        createFactionOpens = createFactionOpens + 1
        return modal()
    end,
}
local function contains(values, wanted)
    for _, value in pairs(values) do
        if value == wanted then
            return true
        end
    end
    return false
end
for _, scale in ipairs({ 15, 28 }) do
    font = scale
    dofile(game .. "/media/lua/client/ISUI/UserPanel/ISUserPanelUI.lua")
    local nativeCreate, nativeUpdate, nativeClick =
        ISUserPanelUI.create, ISUserPanelUI.updateButtons, ISUserPanelUI.onOptionMouseDown
    local baseline = {}
    for _, member in ipairs({ false, true }) do
        house = member and {} or nil
        local p = ISUserPanelUI:new(10, 10, 300, 300, actor)
        p:initialise()
        baseline[member] = p:getHeight()
    end
    ISUserPanelUI.create = function(self)
        nativeCreate(self)
        self.nativeTickets, self.nativeSafehouse = self.ticketsBtn, self.safehouseBtn
    end
    dofile("universal-admin-core/media/lua/client/AdminCore/UserPanel.lua")
    local wrappedCreate, wrappedUpdate = ISUserPanelUI.create, ISUserPanelUI.updateButtons
    dofile("universal-admin-core/media/lua/client/AdminCore/UserPanel.lua")
    check(
        ISUserPanelUI.create == wrappedCreate and ISUserPanelUI.updateButtons == wrappedUpdate,
        "Reload does not stack user-panel wrappers"
    )
    check(
        ISUserPanelUI.onOptionMouseDown == nativeClick and wrappedUpdate ~= nativeUpdate,
        "Native click dispatcher and ticket backend remain unchanged"
    )
    for _, member in ipairs({ false, true }) do
        house, factionMember, canCreate, factionsEnabled, publicOptions =
            member and {} or nil, false, true, true, true
        connectionInfo, serverInfo = false, false
        local p = ISUserPanelUI:new(10, 10, 300, 300, actor)
        p:initialise()
        p:recalcSize()
        check(
            p.ticketsBtn == nil
                and not p.nativeTickets:getIsVisible()
                and p.nativeTickets.parent == nil,
            "Tickets reference and visibility are removed from native User Panel"
        )
        check(
            not contains(p:getChildren(), p.nativeTickets)
                and not contains(p:getChildrenInOrder(), p.nativeTickets)
                and not contains(p.javaObject.children, p.nativeTickets.javaObject),
            "Tickets is detached from native Lua and Java child collections"
        )
        check(
            p:numChildren() == 6,
            "Remaining user controls have no duplicate safehouse or ticket rows"
        )
        local gap = font + 6 + 10
        local controls = {
            p.factionBtn,
            p.safehouseBtn,
            p.serverOptionBtn,
            p.showConnectionInfo,
            p.showServerInfo,
            p.cancel,
        }
        for i, control in ipairs(controls) do
            check(
                control:getY() == p.factionBtn:getY() + (i - 1) * gap,
                "Native rows are compact and ordered at font " .. font
            )
            check(
                control:getY() + control:getHeight() <= p:getHeight() and control.parent == p,
                "Remaining native control stays within panel and attached"
            )
            check(
                control.anchorTop and not control.anchorBottom,
                "Native top anchoring is retained"
            )
        end
        check(
            p:getHeight() == p.cancel:getY() + font + 6 + 11,
            "Native footer padding remains after removing the row"
        )
        check(
            p:getHeight() == baseline[member] - (member and gap or 0),
            "Existing safehouse panel shrinks one row; missing membership fills the removed slot"
        )
        check(
            not member or p.safehouseBtn == p.nativeSafehouse,
            "Existing native safehouse control is retained"
        )
        check(
            p.safehouseBtn.onclick == nativeClick and p.safehouseBtn.internal == "SAFEHOUSEPANEL",
            "Inserted safehouse uses the native callback"
        )
        p:render()
        check(
            p.safehouseBtn:getIsVisible() and p.safehouseBtn.enable == member,
            "Native render updates safely after Tickets removal"
        )
        house = {}
        p:updateButtons()
        check(
            p.safehouseBtn.enable and p.safehouseBtn.tooltip == nil,
            "Membership arriving later enables safehouse"
        )
        local opens = safehouseOpens
        p.safehouseBtn.onclick(p, p.safehouseBtn)
        check(safehouseOpens == opens + 1, "Enabled safehouse opens the native details dialog")
        house = nil
        p:updateButtons()
        p.safehouseBtn.onclick(p, p.safehouseBtn)
        check(
            not p.safehouseBtn.enable
                and p.safehouseBtn.tooltip ~= nil
                and safehouseOpens == opens + 1,
            "Lost membership disables entry and native callback rechecks before opening"
        )
        factionsEnabled = false
        p:updateButtons()
        check(
            not p.factionBtn.enable and p.factionBtn.tooltip == getText("IGUI_FactionUI_Disabled"),
            "Native faction-disabled permission state survives"
        )
        factionsEnabled, canCreate = true, false
        p:updateButtons()
        check(
            not p.factionBtn.enable
                and p.factionBtn.tooltip == getText("IGUI_FactionUI_FactionSurvivalDay"),
            "Native faction survival requirement survives"
        )
        canCreate = true
        p:updateButtons()
        check(
            p.factionBtn.enable and p.factionBtn.tooltip == nil,
            "Native faction eligibility recovers"
        )
        local created = createFactionOpens
        p.factionBtn.onclick(p, p.factionBtn)
        check(createFactionOpens == created + 1, "Native create-faction action survives")
        factionMember = true
        p:updateButtons()
        check(
            p.factionBtn.title == getText("UI_userpanel_factionpanel"),
            "Native membership title refresh survives"
        )
        local factionOpened = factionOpens
        p.factionBtn.onclick(p, p.factionBtn)
        check(factionOpens == factionOpened + 1, "Native faction details action survives")
        local optionsOpened = optionsOpens
        p.serverOptionBtn.onclick(p, p.serverOptionBtn)
        check(optionsOpens == optionsOpened + 1, "Native server-options action survives")
        check(
            p.showConnectionInfo.changeOptionMethod == ISUserPanelUI.onShowConnectionInfo
                and p.showServerInfo.changeOptionMethod == ISUserPanelUI.onShowServerInfo,
            "Both native information toggles retain their callbacks"
        )
        p:onShowConnectionInfo(1, true)
        p:onShowServerInfo(1, true)
        check(connectionInfo and serverInfo, "Native information preferences still update")
        p:addToUIManager()
        p.cancel.onclick(p, p.cancel)
        check(
            not p.javaObject:isVisible()
                and not attached[p.javaObject]
                and ISUserPanelUI.instance == nil,
            "Native Close still hides and detaches the panel"
        )
        publicOptions = false
        local denied = ISUserPanelUI:new(10, 10, 300, 300, actor)
        denied:initialise()
        check(
            not denied.serverOptionBtn.enable,
            "Native public-server-options capability is preserved"
        )
    end
end
print("PASS: " .. count .. " User Panel checks (actual native create/update/render/actions)")
