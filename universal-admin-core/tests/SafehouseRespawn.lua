-- Exercise the installed B42 region, list, Next and Coop lifecycles, not replacement UI APIs.
local game = assert(arg[1], "Pass installed game directory")
local count, now, client = 0, 1000, true
local function check(value, message)
    assert(value, message)
    count = count + 1
end
require = function() end
local eventHandlers = {}
Events = setmetatable({}, {
    __index = function(t, key)
        local event = {
            Add = function(fn)
                eventHandlers[key] = eventHandlers[key] or {}
                eventHandlers[key][#eventHandlers[key] + 1] = fn
            end,
        }
        rawset(t, key, event)
        return event
    end,
})
local function fire(event, ...)
    for _, fn in ipairs(eventHandlers[event] or {}) do
        fn(...)
    end
end
UIFont = { Small = 1, Medium = 2, Large = 3 }
getTextManager = function()
    return {
        getFontHeight = function()
            return 18
        end,
    }
end
getTimestampMs = function()
    return now
end
getText = function(key)
    return key
end
isClient = function()
    return client
end
local challenge = false
local core = {
    isChallenge = function()
        return challenge
    end,
    setSelectedMap = function(self, map)
        self.selectedMap = map
    end,
}
getCore = function()
    return core
end
Core = {
    isLastStand = function()
        return false
    end,
}
OnScreenKeyboard = {
    IsVisible = function()
        return false
    end,
}
local options = { SpawnPoint = "10620,9750,0", SafehouseAllowRespawn = true }
getServerOptions = function()
    return {
        getOption = function(_, key)
            return options[key]
        end,
        getBoolean = function(_, key)
            return options[key] == true
        end,
    }
end
function string:split(sep)
    local result = {}
    for part in self:gmatch("[^" .. sep .. "]+") do
        result[#result + 1] = part
    end
    return result
end
local sent, cancelCount, marker, legacyWrites = {}, 0, nil, 0
AdminCoreRespawnBridge = {
    requestChoices = function(index, id)
        sent[#sent + 1] = { kind = "choices", playerIndex = index, requestId = id }
        return true
    end,
    requestMoreChoices = function(index, id, offset)
        sent[#sent + 1] = { kind = "more", playerIndex = index, requestId = id, offset = offset }
        return true
    end,
    choose = function(index, house, id)
        sent[#sent + 1] = { kind = "choose", playerIndex = index, house = house, requestId = id }
        return true
    end,
    cancel = function()
        cancelCount = cancelCount + 1
    end,
}
setSpawnRegion = function(value)
    marker = value
end
sendSafehouseChangeRespawn = function()
    legacyWrites = legacyWrites + 1
end
getClientUsername = function()
    return "alice"
end
SafeHouse = {
    getSafehouseList = function()
        return {
            size = function()
                return 1
            end,
            get = function()
                return {
                    isRespawnInSafehouse = function()
                        return true
                    end,
                    getPlayers = function()
                        return {
                            contains = function()
                                return true
                            end,
                        }
                    end,
                    getOwner = function()
                        return "alice"
                    end,
                    getX = function()
                        return 20
                    end,
                    getY = function()
                        return 40
                    end,
                    getW = function()
                        return 10
                    end,
                    getH = function()
                        return 12
                    end,
                }
            end,
        }
    end,
}
local world = {
    getGameMode = function()
        return "Multiplayer"
    end,
    getMap = function()
        return "Muldraugh, KY"
    end,
    setLuaPosX = function(self, v)
        self.spawnX = v
    end,
    setLuaPosY = function(self, v)
        self.spawnY = v
    end,
    setLuaPosZ = function(self, v)
        self.spawnZ = v
    end,
    setLuaPlayerDesc = function() end,
    getLuaTraits = function()
        return { clear = function() end }
    end,
}
getWorld = function()
    return world
end
ZombRand = function(max)
    return max - 1
end
getNumActivePlayers = function()
    return 0
end
getSpecificPlayer = function()
    return nil
end
IsoPlayer = {
    allPlayersDead = function()
        return true
    end,
}
-- Explicit UI engine-boundary methods used by the real native Lua methods below.
local UI = {}
function UI:derive()
    local o = {}
    setmetatable(o, { __index = self })
    o.__index = o
    return o
end
function UI:setVisible(value, joy)
    self.visible = value
    self.joyfocus = joy
end
function UI:isVisible()
    return self.visible ~= false
end
function UI:setX(value)
    self.x = value
end
function UI:setY(value)
    self.y = value
end
function UI:setWidth(value)
    self.width = value
end
function UI:setHeight(value)
    self.height = value
end
function UI:getWidth()
    return self.width
end
function UI:getHeight()
    return self.height
end
function UI:getY()
    return self.y
end
function UI:getBottom()
    return self.y + self.height
end
function UI:getRight()
    return self.x + self.width
end
function UI:setScrollHeight(value)
    self.scrollHeight = value
end
function UI:getScrollHeight()
    return self.scrollHeight or 0
end
function UI:setEnable(value)
    self.enable = value
end
function UI:clearJoypadButton() end
function UI:setISButtonForB() end
function UI:prerender() end
function UI:render() end
function UI:drawTextCentre() end
function UI:drawRectBorder() end
function UI:renderJoypadNavigateOverlay() end
function UI:paginate() end
function UI:addToUIManager()
    self.added = true
end
function UI:removeFromUIManager()
    self.added = false
end
local function widget(values)
    return setmetatable(values or { x = 0, y = 0, width = 100, height = 30 }, { __index = UI })
end
ISUIElement, ISPanel, ISPanelJoypad = UI, UI, UI
ISRichTextPanel = UI
dofile(game .. "/media/lua/client/ISUI/ISScrollingListBox.lua")
local function installedSource(path)
    if readTestSource then
        return readTestSource(path)
    end
    local file = assert(io.open(path, "r"))
    local source = file:read("*a")
    file:close()
    return source
end
local nativeMapFile = game .. "/media/lua/client/OptionScreens/MapSpawnSelect.lua"
-- Keep every native function unchanged; append only a fixture closure for its
-- private image state, since the game's Kahlua has no debug upvalue API.
local mapImage = assert(
    loadstring(
        installedSource(nativeMapFile)
            .. "\nreturn function(texture) local previous = WORLD_MAP; WORLD_MAP = texture; return previous end",
        nativeMapFile
    )
)()
dofile(game .. "/media/lua/client/OptionScreens/CoopMapSpawnSelect.lua")
dofile(game .. "/media/lua/client/OptionScreens/CoopCharacterCreation.lua")
dofile(game .. "/media/lua/client/OptionScreens/CharacterCreationMain.lua")
dofile(game .. "/media/lua/client/ISUI/UserPanel/ISSafehouseUI.lua")
-- Safehouse construction itself is covered by the existing list/edit suite;
-- preserve its real change callback and provide only its built widget boundary.
ISSafehouseUI.initialise = function(self)
    self.respawn = widget()
    self.respawn.enable = true
end
local nativeAccept = CoopCharacterCreation.accept
local initialStarts, coopStarts = 0, 0
-- Count the actual engine handoff reached by the native acceptance methods.
setPlayerMouse = function()
    coopStarts = coopStarts + 1
end
forceChangeState = function()
    initialStarts = initialStarts + 1
end
LoadingQueueState = {
    new = function()
        return {}
    end,
}
GameWindow = { doRenderEvent = function() end }
JoypadState = {
    getMainMenuJoypad = function()
        return nil
    end,
}
core.getAccountUsed = function()
    return nil
end
ISPostDeathUI = { instance = {} }
UIManager = {
    getSpeedControls = function()
        return nil
    end,
}
CoopCharacterCreation.setVisibleAllUI = function() end
local mapInfo = {
    ATF = { title = "ATF Community", description = "Community spawn", lots = {} },
    Vanilla = { title = "Muldraugh", description = "Vanilla", lots = {} },
}
getMapInfo = function(name)
    return mapInfo[name]
end
local normalRegions = {
    { name = "ATF", points = { unemployed = { { posX = 100, posY = 100, posZ = 0 } } } },
    { name = "Vanilla", points = { unemployed = { { posX = 200, posY = 200, posZ = 0 } } } },
}
SpawnRegionMgr = {
    getSpawnRegions = function()
        return normalRegions
    end,
}
MainScreen = {
    instance = {
        inGame = false,
        createWorld = false,
        charCreationProfession = widget(),
        charCreationMain = widget(),
        desc = {
            getCharacterProfession = function()
                return {
                    getName = function()
                        return "unemployed"
                    end,
                }
            end,
        },
    },
}
MainScreen.instance.charCreationMain.playButton = widget()
MainScreen.instance.charCreationMain.playButton.onclick = CharacterCreationMain.onOptionMouseDown
local earlyMapOption = MapSpawnSelect.onOptionMouseDown
local function window(coop)
    local cls = coop and CoopMapSpawnSelect or MapSpawnSelect
    local w =
        setmetatable({ x = 0, y = 0, width = 1000, height = 720, visible = true, startY = 45 }, cls)
    w.listbox = setmetatable({
        x = 10,
        y = 45,
        width = 350,
        height = 200,
        items = {},
        selected = 1,
        count = 0,
        itemheight = 30,
    }, ISScrollingListBox)
    w.mapPanel = widget({
        x = 380,
        y = 45,
        width = 600,
        height = 600,
        clear = function(self)
            self.maps = {}
        end,
        initMapData = function(self, path)
            self.maps[#self.maps + 1] = path
        end,
        hasSomethingToDisplay = function()
            return true
        end,
    })
    w.richText = widget({ x = 10, y = 100, width = 350, height = 150 })
    w.nextButton, w.backButton = widget(), widget()
    w.textEntry = widget({
        x = 60,
        y = 600,
        width = 250,
        height = 30,
        getInternalText = function()
            return "save"
        end,
        setValid = function() end,
        getText = function()
            return "save"
        end,
    })
    w.textEntry.visible = false
    w.textEntryLabel = widget()
    w.seedPanel =
        widget({ x = 0, y = 600, width = 300, height = 70, onResolutionChange = function() end })
    if coop then
        CoopMapSpawnSelect.instance = w
    else
        MapSpawnSelect.instance = w
    end
    return w
end
dofile("universal-admin-core/media/lua/client/AdminCore/SafehouseRespawn.lua")
local R = AdminSafehouseRespawn
check(
    MainScreen.instance.charCreationMain.playButton.onclick
        == CharacterCreationMain.onOptionMouseDown,
    "Already-created native Play button receives final authorization wrapper"
)
local function reply(command, values, request)
    if not request and (command == "selected" or command == "rejected") then
        for _, active in pairs(R.windows) do
            if active.uacRespawn and active.uacRespawn.chooseAfter then
                now = math.max(now, active.uacRespawn.chooseAfter, R.requestAfter)
                fire("OnTick")
            end
        end
    end
    local args = values or {}
    request = request or sent[#sent]
    args.requestId, args.playerIndex = request.requestId, request.playerIndex
    fire("OnServerCommand", "UniversalAdminRespawn", command, args)
end
local house = { id = "h1", name = "Alice <farm>", owner = "alice", x = 101, y = 202, z = 0 }
local function find(w, key)
    for i, entry in ipairs(w.listbox.items) do
        if entry.item.uacHouseId == key then
            return i
        end
    end
end
local function checkNativeOwnedRowRender(w, index, point)
    -- Exercise the installed render method's vector and image fallback branches.
    local previousMap = mapImage(widget({ width = 1000, height = 500 }))
    local oldSelected, oldZoom = w.listbox.selected, w.zoomMap
    local oldDisplay, oldShown, oldAPI =
        w.mapPanel.hasSomethingToDisplay, w.mapPanel.shownInitialLocation, w.mapPanel.mapAPI
    w.listbox.selected = index
    w.mapPanel.hasSomethingToDisplay = function()
        return false
    end
    w.zoomMap = function(_, x, y, scale)
        check(
            x == 500 and y == 250 and scale == 1,
            "Owned row uses valid whole-image coordinates in native fallback render"
        )
    end
    MapSpawnSelect.render(w)
    local transitions = 0
    w.mapPanel.hasSomethingToDisplay = function()
        return true
    end
    w.mapPanel.shownInitialLocation = true
    w.mapPanel.mapAPI = {
        getZoomF = function()
            return 12
        end,
        transitionTo = function(_, x, y, scale)
            transitions = transitions + 1
            check(
                point and x == point.x and y == point.y and scale == 12,
                "Native vector render focuses the server-confirmed safehouse point"
            )
        end,
    }
    w.selectedMapIndex = nil
    MapSpawnSelect.render(w)
    check(
        transitions == (point and 1 or 0),
        "Status row never requests an invalid vector transition"
    )
    mapImage(previousMap)
    w.listbox.selected, w.zoomMap = oldSelected, oldZoom
    w.mapPanel.hasSomethingToDisplay, w.mapPanel.shownInitialLocation, w.mapPanel.mapAPI =
        oldDisplay, oldShown, oldAPI
end
local w = window(false)
check(w:hasChoices(), "Fixed normal spawn still opens choice screen while checking safehouses")
check(sent[#sent].playerIndex == 0, "Initial join uses slot zero without a player object")
w:fillList()
check(
    w.listbox.items[1].item.region.name == "UI_mapspawn_ServerSpawnPoint",
    "Fixed default preserved, legacy automatic safehouse bypassed"
)
check(
    #w.mapPanel.maps == 0,
    "Fixed server default does not expose otherwise disallowed custom regions"
)
check(
    w.listbox.items[w.listbox.selected].item.uacHouseId == nil,
    "Pending never auto-selects safehouse"
)
checkNativeOwnedRowRender(w, #w.listbox.items)
reply(
    "choices",
    { enabled = true, rows = { house, house, { id = "bad", x = 0 / 0, y = 1, z = 0 } } }
)
check(
    #w.listbox.items == 2 and find(w, "h1") == 2,
    "Only validated unique server safehouses appended"
)
check(w.listbox.items[2].item.desc:find("Owner: alice", 1, true), "Owner shown")
check(w.listbox.items[2].item.desc:find("Location: 101, 202", 1, true), "Location shown")
check(not w.listbox.items[2].text:find("<", 1, true), "Names cannot inject rich text markup")
checkNativeOwnedRowRender(w, 2, house)
w.listbox.selected = 2
earlyMapOption(w, { internal = "NEXT" }, 0, 0)
check(
    w.visible and w.uacRespawn.choosing == "h1",
    "Native Next remains visible while async choose is pending"
)
check(
    sent[#sent].kind == "choices",
    "Choosing immediately after a page waits for rate limit spacing"
)
local beforeQueuedChoose = #sent
now = now + 199
fire("OnTick")
check(#sent == beforeQueuedChoose, "Queued choose is not sent inside the rate limit interval")
now = now + 1
fire("OnTick")
check(
    sent[#sent].kind == "choose" and #sent == beforeQueuedChoose + 1,
    "Queued choose sends once after 200 milliseconds"
)
local chooseRequest = sent[#sent]
local submissions = #sent
w:clickNext()
check(#sent == submissions, "Double Next sends only one selection")
w:prerender()
check(w.nextButton.enable == false, "Next is visibly disabled while awaiting selected confirmation")
reply(
    "selected",
    { regionKey = "UACRespawn:first", x = 102, y = 203, z = 0 },
    { requestId = "stale", playerIndex = 0 }
)
check(w.visible, "Stale reply cannot transition")
reply("selected", { regionKey = "UACRespawn:first", x = 102, y = 203, z = 0 }, chooseRequest)
check(
    not w.visible and marker == "UACRespawn:first",
    "Initial native next receives server authorization marker"
)
check(
    w.selectedRegion.points.unemployed[1].posX == 102,
    "Confirmed coordinate replaces advisory list coordinate"
)
check(MainScreen.instance.charCreationProfession.visible, "Normal profession screen opens")
local main = setmetatable({
    playButton = widget(),
    disableBtn = function(self)
        self.playButton.enable = true
    end,
    initPlayer = function() end,
}, CharacterCreationMain)
now = now + 600000
main:onOptionMouseDown({ internal = "NEXT" }, 0, 0)
check(
    initialStarts == 0 and sent[#sent].kind == "choose",
    "Final Play refreshes authorization after long customization"
)
main:onOptionMouseDown({ internal = "NEXT" }, 0, 0)
check(initialStarts == 0, "Final Play cannot double-start")
reply("selected", { regionKey = "UACRespawn:second", x = 103, y = 204, z = 0 })
check(
    initialStarts == 1 and marker == "UACRespawn:second",
    "Final Play starts once with renewed marker"
)
check(
    w.selectedRegion.points.unemployed[1].posX == 103,
    "Final creation has latest server coordinates"
)
-- Returning to choose an ordinary location cancels the temporary ticket.
w.visible = true
w.listbox.selected = 1
w:clickNext()
check(
    marker == "UI_mapspawn_ServerSpawnPoint" and not w.uacRespawn.ticket,
    "Normal choice clears one-attempt safehouse ticket"
)
check(cancelCount > 0 and legacyWrites == 0, "No persistent safehouse preference changed")
fire("OnCreatePlayer", 0)
check(R.windows[0] == nil, "Successful spawn drops client attempt references")

-- Existing custom/map-provider rows remain untouched when the server has no fixed point.
options.SpawnPoint = "0,0,0"
w = window(false)
w:hasChoices()
w:fillList()
check(
    w.listbox.items[1].text == "ATF Community" and w.listbox.items[2].text == "Muldraugh",
    "Custom community and vanilla region rows retained"
)
check(#w.mapPanel.maps == 2, "Native map data loaded for original regions")
reply("choices", { enabled = true, rows = { house } })
w.listbox:addItem("UI_mapspawn_random", { name = "UI_mapspawn_random" })
w.listbox.selected = #w.listbox.items
w:clickNext()
check(marker == "Vanilla", "Random selects only ordinary/custom regions, never safehouses")
fire("OnDisconnect")

-- Server disabled restores native behavior and leaves its saved legacy setting alone.
w = window(false)
w:hasChoices()
w:fillList()
reply("choices", { enabled = false, rows = { house } })
check(
    w.listbox.items[1].item.region.name == "UI_mapspawn_Safehouse",
    "Explicit disabled response restores legacy provider"
)
check(not find(w, "h1"), "Disabled server cannot inject a house option")
fire("OnDisconnect")

-- Timeout is driven by frontend prerender too (OnTick is not guaranteed in menus).
w = window(false)
w:hasChoices()
w:fillList()
local late = sent[#sent]
now = now + 10001
w:prerender()
check(not w.uacRespawn.loading, "Menu timeout runs without OnTick")
reply("choices", { enabled = true, rows = { house } }, late)
check(not find(w, "h1"), "Late discovery reply after timeout ignored")
fire("OnDisconnect")

-- No ordinary locations: no automatic first-safehouse selection.
SafeHouse.getSafehouseList = function()
    return {
        size = function()
            return 0
        end,
    }
end
normalRegions = {}
w = window(false)
w:hasChoices()
w:fillList()
reply("choices", { enabled = true, rows = { house } })
check(
    w.listbox.items[w.listbox.selected].item.uacStatus,
    "House-only server requires explicit selection"
)
w:prerender()
check(not w.nextButton.enable, "Prompt row cannot spawn")
w.listbox.selected = find(w, "h1")
w:clickNext()
reply("rejected", { message = "Membership changed." })
check(
    w.visible and w.uacRespawn.message == "Membership changed.",
    "Rejected selection returns useful error without losing UI"
)
fire("OnDisconnect")

-- Post-death retains native WithPlayer choices and rechecks at final Play.
MainScreen.instance.inGame = true
options.SpawnPoint = "10620,9750,0"
options.PlayerRespawnWithSelf = true
getNumActivePlayers = function()
    return 1
end
getSpecificPlayer = function()
    return {
        getX = function()
            return 55
        end,
        getY = function()
            return 66
        end,
        getZ = function()
            return 0
        end,
    }
end
local cw = window(true)
local creation = setmetatable({
    playerIndex = 0,
    mapSpawnSelect = cw,
    charCreationMain = widget(),
    charCreationProfession = widget(),
    initPlayer = function() end,
}, CoopCharacterCreation)
creation.charCreationProfession.listboxTraitSelected = { items = {} }
CoopCharacterCreation.instance = creation
cw:hasChoices()
cw:fillList()
reply("choices", { enabled = true, rows = { house } })
local withPlayer = false
for _, entry in ipairs(cw.listbox.items) do
    if entry.item.region and entry.item.region.key == "WithPlayer1" then
        withPlayer = true
    end
end
check(withPlayer, "Native post-death WithPlayer option preserved")
cw.listbox.selected = find(cw, "h1")
cw:clickNext()
reply("selected", { regionKey = "UACRespawn:coop1", x = 105, y = 205, z = 0 })
check(
    creation.charCreationProfession.visible and marker == "UACRespawn:coop1",
    "Coop native Next receives marker"
)
creation:accept()
check(
    coopStarts == 0 and creation.charCreationMain.visible,
    "Coop final Play stays visible while reauthorizing"
)
reply("rejected", { message = "Safehouse released." })
check(
    coopStarts == 0 and cw.visible and not creation.charCreationMain.visible,
    "Final rejection restores map without losing creation instance"
)
cw.listbox.selected = find(cw, "h1")
cw:clickNext()
reply("selected", { regionKey = "UACRespawn:coop2", x = 105, y = 205, z = 0 })
creation:accept()
reply("selected", { regionKey = "UACRespawn:coop3", x = 105, y = 205, z = 0 })
check(
    coopStarts == 1 and R.accepted[0] == creation,
    "Accepted Coop instance retained until final native result"
)
check(
    world.spawnX == 105 and world.spawnY == 205,
    "Native Coop accept1 uses final confirmed coordinates"
)
UIManager = {
    setVisibleAllUI = function() end,
    getUI = function()
        return {
            size = function()
                return 0
            end,
        }
    end,
}
CoopCharacterCreation.setVisibleAllUI = function() end
reply(
    "rejected",
    { creation = true, message = "Membership removed during loading." },
    { requestId = "", playerIndex = 0 }
)
check(
    R.creationErrors[0] == "Membership removed during loading.",
    "Final native rejection is accepted independently of old request nonce"
)
fire("OnCoopJoinFailed", 0)
check(
    CoopCharacterCreation.instance == creation and cw.visible and creation.added,
    "Late native denial restores existing creation and map"
)
check(cw.uacRespawn.loading, "Native denial requests fresh safehouse eligibility")
check(
    cw.uacRespawn.message == "Membership removed during loading.",
    "Native denial reason retained on restored chooser"
)
fire("OnDisconnect")

-- Legacy checkbox handshake uses an authenticated own-slot request, never preference writes.
local panel = setmetatable(
    { player = {
        getPlayerNum = function()
            return 0
        end,
    } },
    ISSafehouseUI
)
panel:initialise()
check(not panel.respawn.visible, "Persistent switch hidden while checking server feature")
panel:onClickRespawn(1, true)
check(legacyWrites == 0, "Pending checkbox cannot write preference")
reply("choices", { enabled = true, rows = {} })
check(
    not panel.respawn.visible and not panel.respawn.enable,
    "Confirmed feature removes persistent switch"
)
panel:onClickRespawn(1, true)
check(legacyWrites == 0, "Enabled feature cannot write preference")
fire("OnDisconnect")
panel:initialise()
reply("choices", { enabled = false, rows = {} })
check(panel.respawn.visible and panel.respawn.enable, "Other server restores native checkbox")
panel.safehouse = {}
panel.player.getUsername = function()
    return "alice"
end
panel:onClickRespawn(1, true)
check(legacyWrites == 1, "Disabled feature preserves native callback")
fire("OnDisconnect")

-- All pages are fetched incrementally, including beyond the former 512-row limit.
MainScreen.instance.inGame = false
options.SpawnPoint = "0,0,0"
normalRegions =
    { { name = "ATF", points = { unemployed = { { posX = 100, posY = 100, posZ = 0 } } } } }
w = window(false)
w:hasChoices()
w:fillList()
local originalMapData = w.mapPanel.maps
local previousRequest, expectedCount = nil, 0
for offset = 0, 600, 64 do
    local request = sent[#sent]
    check(request.requestId ~= previousRequest, "Every page has a new request ID")
    previousRequest = request.requestId
    if offset > 0 then
        check(
            request.kind == "more" and request.offset == offset,
            "Native source cursor passed unchanged"
        )
    end
    local rows = {}
    for index = offset + 1, math.min(offset + 64, 601) do
        -- The server source can repeat a discovered identity across page boundaries.
        local id = index >= 65 and index - 1 or index
        rows[#rows + 1] =
            { id = "page-" .. id, name = "House " .. id, owner = "alice", x = id, y = 50, z = 0 }
    end
    local following = offset + #rows
    reply("choices", {
        enabled = true,
        rows = rows,
        offset = offset,
        nextOffset = following < 601 and following or nil,
    }, request)
    expectedCount = following >= 65 and following - 1 or following
    check(#w.uacRespawn.rows == expectedCount, "Pages accumulate all unique houses")
    check(w.mapPanel.maps == originalMapData, "Page arrival never reloads native/custom map data")
    check(
        w.listbox.items[1].text == "ATF Community",
        "Normal/custom option remains available throughout paging"
    )
    if offset == 0 then
        check(
            not w.listbox.items[w.listbox.selected].item.uacHouseId,
            "First page does not auto-select a safehouse"
        )
        w:prerender()
        check(w.nextButton.enable, "Normal location usable while more pages are queued")
        w.listbox.selected = find(w, "page-2")
    else
        check(
            w.listbox.items[w.listbox.selected].item.uacHouseId == "page-2",
            "User-selected house remains selected across pages"
        )
    end
    if following < 601 then
        local before = #sent
        now = now + 199
        fire("OnTick")
        check(#sent == before, "Continuation waits at least 200 milliseconds")
        now = now + 1
        fire("OnTick")
        check(#sent == before + 1, "Continuation requested automatically after spacing interval")
        local active = w.uacRespawn.requestId
        reply("choices", { enabled = true, rows = {}, offset = offset }, request)
        check(
            w.uacRespawn.requestId == active and w.uacRespawn.awaitingChoices,
            "Stale previous page cannot end current page request"
        )
    end
end
check(
    #w.uacRespawn.rows == 600 and find(w, "page-600") ~= nil,
    "All 600 unique houses available beyond old server/client caps"
)
check(not w.uacRespawn.loading and not w.uacRespawn.nextOffset, "Last page ends fetching")
local finishedRequests = #sent
now = now + 1000
fire("OnTick")
check(#sent == finishedRequests, "Completed list makes no further requests")
fire("OnDisconnect")

local function pagedWindow()
    local result = window(false)
    result:hasChoices()
    result:fillList()
    reply("choices", { enabled = true, rows = { house }, offset = 0, nextOffset = 64 })
    return result
end
w = pagedWindow()
local cancelledPage = sent[#sent]
w.listbox.selected = 1
w:clickNext()
local cancelledRequests = #sent
now = now + 300
fire("OnTick")
check(
    #sent == cancelledRequests and not w.uacRespawn.loading,
    "Normal selection cancels queued pages"
)
reply(
    "choices",
    { enabled = true, rows = { { id = "late", x = 1, y = 1, z = 0 } }, nextOffset = 128 },
    cancelledPage
)
check(not find(w, "late"), "Response after normal selection cannot add stale rows")
fire("OnDisconnect")
w = pagedWindow()
now = now + 200
fire("OnTick")
local inFlightPage = sent[#sent]
w.listbox.selected = find(w, "h1")
w:clickNext()
local choosingRequest = w.uacRespawn.requestId
reply(
    "choices",
    { enabled = true, rows = { { id = "late", x = 1, y = 1, z = 0 } }, offset = 64 },
    inFlightPage
)
check(
    w.uacRespawn.choosing == "h1" and w.uacRespawn.requestId == choosingRequest,
    "Choosing a house stops paging and rejects its in-flight page"
)
reply("selected", { regionKey = "UACRespawn:paged", x = 101, y = 202, z = 0 })
local selectedRequests = #sent
now = now + 300
fire("OnTick")
check(
    #sent == selectedRequests and not w.uacRespawn.loading,
    "No queued page runs after confirmed selection"
)
fire("OnDisconnect")
w = pagedWindow()
now = now + 200
fire("OnTick")
local timedOutPage = sent[#sent]
now = now + 10001
w:prerender()
check(
    not w.uacRespawn.loading and find(w, "h1"),
    "Page timeout stops further requests while retaining loaded choices"
)
reply(
    "choices",
    { enabled = true, rows = { { id = "late", x = 1, y = 1, z = 0 } }, offset = 64 },
    timedOutPage
)
check(not find(w, "late"), "Timed-out page cannot mutate loaded choices")
fire("OnDisconnect")
w = pagedWindow()
now = now + 200
fire("OnTick")
reply("choices", { enabled = true, rows = {}, offset = 64, nextOffset = 64 })
check(
    not w.uacRespawn.loading and w.uacRespawn.message ~= nil,
    "Non-advancing cursor stops instead of infinite requests"
)
fire("OnDisconnect")
w = pagedWindow()
w.listbox.selected = find(w, "h1")
w:clickNext()
check(w.uacRespawn.chooseAfter ~= nil, "Recent discovery queues house selection")
backToSinglePlayer = function() end
core.ResetLua = function() end
local beforeBack = #sent
w:clickBack()
now = now + 300
fire("OnTick")
check(
    #sent == beforeBack and R.windows[0] == nil,
    "Back cancels queued choose and page continuation"
)
fire("OnDisconnect")

normalRegions = {}
client = false
w = window(false)
check(w:hasChoices() == false and w.uacRespawn == nil, "Single-player native behavior unchanged")
client = true
challenge = true
LastStandData = {
    getSpawnRegion = function()
        return normalRegions
    end,
}
w = window(false)
w:hasChoices()
check(w.uacRespawn == nil, "Challenge flow unchanged")
local handlerCount = #eventHandlers.OnServerCommand
dofile("universal-admin-core/media/lua/client/AdminCore/SafehouseRespawn.lua")
check(
    #eventHandlers.OnServerCommand == handlerCount,
    "Reload does not duplicate wrappers or handlers"
)
print("Safehouse respawn: " .. count .. " checks passed")
