local game = assert(arg[1], "Pass game directory")
local module = arg[2] or "universal-admin-core"
require = function() end
local checks = 0
local function check(value, message)
    assert(value, message)
    checks = checks + 1
end

local font, screenHeight = 28, 720
UIFont = { Small = 1, Medium = 2, NewSmall = 3 }
getTextManager = function()
    return {
        getFontHeight = function()
            return font
        end,
        MeasureStringX = function(_, _, text)
            return #text * 8
        end,
    }
end
getText = function(text)
    return text
end
getCore = function()
    return {
        getScreenWidth = function()
            return 1280
        end,
        getScreenHeight = function()
            return screenHeight
        end,
        getOptionFontSizeReal = function()
            return 1
        end,
    }
end
Capability = { CanSetupSafehouses = 1, FactionCheat = 2, TeleportToCoordinates = 3 }
local permissions = { [1] = true, [2] = true, [3] = true }
local role = {
    hasCapability = function(_, capability)
        return permissions[capability] == true
    end,
}
local teleports, commands, viewed = {}, {}, {}
local player = {
    getRole = function()
        return role
    end,
    teleportTo = function(_, x, y, z)
        teleports[#teleports + 1] = { x, y, z }
    end,
}
getPlayer = function()
    return player
end
isClient = function()
    return true
end
SendCommandToServer = function(command)
    commands[#commands + 1] = command
end

local W = {}
W.__index = W
function W:derive(name)
    local class = { Type = name }
    class.__index = class
    return setmetatable(class, self)
end
function W:new(x, y, width, height)
    return setmetatable({
        x = x,
        y = y,
        width = width,
        height = height,
        children = {},
        items = {},
        selected = 0,
        visible = true,
        borderColor = { r = 0.4, g = 0.4, b = 0.4, a = 1 },
    }, self)
end
for _, axis in ipairs({ "X", "Y", "Width", "Height" }) do
    local key = axis:lower()
    W["set" .. axis] = function(self, value)
        self[key] = value
    end
    W["get" .. axis] = function(self)
        return self[key]
    end
end
function W:initialise() end
function W:instantiate() end
function W:enableCancelColor() end
function W:addToUIManager() end
function W:removeFromUIManager() end
function W:drawRect() end
function W:drawRectBorder() end
function W:drawText() end
function W:getBottom()
    return self.y + self.height
end
function W:getRight()
    return self.x + self.width
end
function W:addChild(child)
    self.children[#self.children + 1] = child
    child.parent = self
end
function W:getChildren()
    return self.children
end
function W:setEnable(value)
    self.enable = value
end
function W:setVisible(value)
    self.visible = value
end
function W:getIsVisible()
    return self.visible
end
function W:clear()
    self.items = {}
    self.selected = 1
end
function W:addItem(text, object, tooltip)
    local row = {
        text = text,
        item = object,
        tooltip = tooltip,
        index = #self.items + 1,
        itemindex = #self.items + 1,
    }
    self.items[#self.items + 1] = row
    return row
end
function W:setScrollHeight(value)
    self.scrollHeight = value
end
function W:setYScroll(value)
    self.scroll = value
end
function W:ensureVisible(index)
    self.ensured = index
end
ISPanel = W:derive("ISPanel")
ISScrollingListBox = W:derive("ISScrollingListBox")
ISButton = W:derive("ISButton")
function ISButton:new(x, y, width, height, title, target, callback)
    local button = W.new(self, x, y, width, height)
    button.title, button.target, button.onclick = title, target, callback
    return button
end
ISTextEntryBox = W:derive("ISTextEntryBox")
function ISTextEntryBox:new(text, x, y, width, height)
    local entry = W.new(self, x, y, width, height)
    entry.text = text
    return entry
end
function ISTextEntryBox:getInternalText()
    return self.text
end
function ISTextEntryBox:setText(text)
    self.text = text
end
function ISTextEntryBox:setPlaceholderText(text)
    self.placeholder = text
end
ISLabel = W:derive("ISLabel")
function ISLabel:new(x, y, height, name)
    local label = W.new(self, x, y, 0, height)
    label.name = name
    return label
end
function ISLabel:setName(name)
    self.name = name
end
for _, name in ipairs({ "ISSafehouseUI", "ISFactionUI" }) do
    local class = W:derive(name)
    function class:new(x, y, width, height, object)
        viewed[#viewed + 1] = object
        return W.new(self, x, y, width, height)
    end
    _G[name] = class
end
Events = setmetatable({}, {
    __index = function(events, name)
        local callbacks = {}
        local event = {
            Add = function(callback)
                callbacks[#callbacks + 1] = callback
            end,
            trigger = function(...)
                for _, callback in ipairs(callbacks) do
                    callback(...)
                end
            end,
        }
        rawset(events, name, event)
        return event
    end,
})
AdminCore = {
    fit = function(panel, width, height)
        panel:setWidth(math.min(width, 1264))
        panel:setHeight(math.min(height, screenHeight - 16))
        panel:setY(math.max(8, math.min(panel.y, screenHeight - panel.height - 8)))
    end,
}

local nativeReads = 0
local function list(rows)
    return {
        size = function()
            return #rows
        end,
        get = function(_, index)
            nativeReads = nativeReads + 1
            return rows[index + 1]
        end,
    }
end
local function record(index, faction)
    local object = {
        name = (faction and "Faction " or "Safehouse ") .. string.format("%04d", index),
        owner = "Owner" .. string.format("%04d", index),
        tag = index == 1 and "VIP" or nil,
        x = index * 10,
        y = index * 20,
    }
    function object:getTitle()
        return self.name
    end
    object.getName = object.getTitle
    function object:getOwner()
        return self.owner
    end
    function object:getTag()
        return self.tag
    end
    function object:getPlayers()
        return list({})
    end
    function object:getX()
        return self.x
    end
    function object:getY()
        return self.y
    end
    function object:getW()
        return 10
    end
    function object:getH()
        return 20
    end
    return object
end
local houses, factions = {}, {}
for index = 600, 1, -1 do
    houses[#houses + 1] = record(index, false)
end
for index = 400, 1, -1 do
    factions[#factions + 1] = record(index, true)
end
SafeHouse = {
    getSafehouseList = function()
        return list(houses)
    end,
}
Faction = {
    getFactions = function()
        return list(factions)
    end,
}
dofile(game .. "/media/lua/client/ISUI/AdminPanel/ISSafehousesList.lua")
dofile(game .. "/media/lua/client/ISUI/AdminPanel/ISFactionsList.lua")
dofile(module .. "/media/lua/client/AdminCore/ListSearch.lua")
local installedPopulate = ISSafehousesList.populateList
dofile(module .. "/media/lua/client/AdminCore/ListSearch.lua")
check(
    installedPopulate == ISSafehousesList.populateList,
    "Repeated loading does not install wrappers twice"
)

local function search(panel, text)
    panel.uacListSearch:setText(text)
    panel.uacListSearch.onTextChange()
end
local function selectObject(panel, object)
    for index, row in ipairs(panel.datas.items) do
        if row.item == object then
            panel.datas.selected = index
            panel.datas.doDrawItem(panel.datas, 0, row, false)
            return
        end
    end
    error("Target object is absent from visible rows")
end
local function replace(rows, old, replacement)
    for index, object in ipairs(rows) do
        if object == old then
            rows[index] = replacement
            return
        end
    end
    error("Target object is absent from source collection")
end
local function remove(rows, target)
    for index, object in ipairs(rows) do
        if object == target then
            table.remove(rows, index)
            return
        end
    end
    error("Target object is absent from source collection")
end

for _, kind in ipairs({ "safehouse", "faction" }) do
    local isHouse = kind == "safehouse"
    local class = isHouse and ISSafehousesList or ISFactionsList
    local records = isHouse and houses or factions
    local initialCount = isHouse and 600 or 400
    local selectedField = isHouse and "selectedSafehouse" or "selectedFaction"
    local capability = isHouse and Capability.CanSetupSafehouses or Capability.FactionCheat
    local panel = class:new(50, 50, 600, 600, player)
    panel:initialise()
    check(
        #panel.datas.items == initialCount,
        "Native constructor retains all " .. initialCount .. " " .. kind .. " records"
    )
    check(
        panel.datas.items[1].item.name:find("0001", 1, true) ~= nil,
        "Alphabetical order applied to " .. kind
    )
    check(
        records[1].name:find(tostring(initialCount), 1, true) ~= nil,
        "Sorting never changes native collection order"
    )
    check(
        panel.datas.selected == 0 and not panel.viewBtn.enable,
        "Opening does not select an arbitrary first row"
    )
    check(
        panel.uacListSearch:getBottom() < panel.uacListCount.y,
        "Large-font entry does not overlap count"
    )
    check(panel.uacListCount:getBottom() < panel.datas.y, "Large-font count does not overlap list")
    check(panel.datas:getBottom() <= panel.no.y - 10, "Large-font list stays above native footer")

    local scanCount = nativeReads
    search(panel, " owner0001 ")
    check(
        #panel.datas.items == 1 and panel.datas.items[1].item.owner == "Owner0001",
        "Trimmed owner search"
    )
    check(nativeReads == scanCount, "Typing only filters cached local rows")
    local target = panel.datas.items[1].item
    selectObject(panel, target)
    search(panel, isHouse and "SAFEHOUSE 0001" or "FACTION 0001")
    check(
        panel[selectedField] == target and panel.datas.selected == 1 and panel.viewBtn.enable,
        "Matching object remains selected"
    )
    panel.viewBtn.onclick(panel, panel.viewBtn)
    check(viewed[#viewed] == target, "Native View callback receives the correct filtered object")
    search(panel, "absent")
    local previousViews = #viewed
    panel.viewBtn.onclick(panel, panel.viewBtn)
    check(
        panel[selectedField] == nil and panel.datas.selected == 0 and not panel.viewBtn.enable,
        "Hidden selection is cleared"
    )
    check(
        #viewed == previousViews and panel.uacListCount.name:find("No matching", 1, true) ~= nil,
        "No-result View cannot open stale object"
    )
    search(panel, "[")
    check(#panel.datas.items == 0, "Pattern characters are searched literally")
    panel.uacListClear.onclick(panel)
    check(
        #panel.datas.items == initialCount and panel.uacListSearch.text == "",
        "Clear restores full sorted list"
    )

    if not isHouse then
        search(panel, "vip")
        check(
            #panel.datas.items == 1 and panel.datas.items[1].item == target,
            "Faction tags are searchable"
        )
    else
        search(panel, "safehouse 0001")
        selectObject(panel, target)
        panel.teleportBtn.onclick(panel, panel.teleportBtn)
        check(
            commands[#commands] == "/teleportto 10,20,0",
            "Filtered teleport retains the native command"
        )
        check(
            teleports[#teleports][1] == 10 and teleports[#teleports][2] == 20,
            "Native local teleport uses selected bounds"
        )
        permissions[Capability.TeleportToCoordinates] = false
        panel:prerender()
        local previousCommands = #commands
        panel.teleportBtn.onclick(panel, panel.teleportBtn)
        check(
            not panel.teleportBtn.enable and #commands == previousCommands,
            "Revoked teleport capability disables and blocks action"
        )
        permissions[Capability.TeleportToCoordinates] = true
    end

    search(panel, isHouse and "safehouse 0001" or "faction 0001")
    selectObject(panel, target)
    local replacement = record(1, not isHouse)
    replace(records, target, replacement)
    if isHouse then
        Events.OnSafehousesChanged.trigger()
    else
        Events.SyncFaction.trigger(replacement.name)
    end
    check(
        panel[selectedField] == replacement and panel.datas.selected == 1,
        "Data event resolves replacement live object"
    )
    check(
        panel.uacListSearch.text:find("0001", 1, true) ~= nil and #panel.datas.items == 1,
        "Data event preserves query"
    )
    local latestReplacement = record(1, not isHouse)
    replace(records, replacement, latestReplacement)
    panel.viewBtn.onclick(panel, panel.viewBtn)
    check(
        viewed[#viewed] == latestReplacement,
        "Click revalidates replacement before a refresh event arrives"
    )

    permissions[capability] = false
    panel:prerender()
    panel.datas.doDrawItem(panel.datas, 0, panel.datas.items[1], false)
    previousViews = #viewed
    panel.viewBtn.onclick(panel, panel.viewBtn)
    check(
        not panel.viewBtn.enable and panel[selectedField] == nil and #viewed == previousViews,
        "Native drawing and callback respect revoked management capability"
    )
    permissions[capability] = true
    selectObject(panel, latestReplacement)
    remove(records, latestReplacement)
    panel.viewBtn.onclick(panel, panel.viewBtn)
    check(
        #viewed == previousViews and #panel.datas.items == 0 and panel[selectedField] == nil,
        "Removed live object cannot be opened from cached selection"
    )

    panel.uacListClear.onclick(panel)
    local first, second = records[1], records[2]
    first.name, second.name = "duplicate", isHouse and "duplicate" or "Duplicate"
    panel:populateList()
    search(panel, "duplicate")
    selectObject(panel, second)
    panel:populateList()
    check(
        panel[selectedField] == second and #panel.datas.items == 2,
        "Duplicate labels retain object identity instead of row index"
    )
    if not isHouse then
        panel:setVisible(false)
        local before = nativeReads
        Events.SyncFaction.trigger("other")
        check(nativeReads == before, "Closed faction list skips incoming refreshes")
    end
    panel.no.onclick(panel, panel.no)
    check(not panel.visible, "Native Close callback remains usable")
end

screenHeight = 480
for _, class in ipairs({ ISSafehousesList, ISFactionsList }) do
    local panel = class:new(50, 50, 600, 600, player)
    panel:initialise()
    check(
        panel.y >= 8 and panel:getBottom() <= screenHeight - 8,
        "Native constructor fits a short screen"
    )
    check(
        panel.uacListSearch.width > 0 and panel.datas:getBottom() <= panel.no.y - 10,
        "Search and native footer fit short screen with large fonts"
    )
end
print(
    "PASS: "
        .. checks
        .. " master-list search checks against native dialogs (600 safehouses, 400 factions)"
)
