-- Vendor fixture first; optional native, Livestock and original Lifestyle
-- source paths exercise the exact installed providers without copying them.
local root = (arg[1] or "guspuffy-atf-patches/build/vendor-fixtures") .. "/"
local patched = root .. "mod-LifestyleHobbies/common/media/lua/client/ISUI/hooks/InvPane.lua"
local checks = 0
local function check(ok, why)
    assert(ok, why)
    checks = checks + 1
end
local function noop() end
local function list(values)
    return {
        size = function()
            return #values
        end,
        get = function(_, i)
            return values[i + 1]
        end,
    }
end
table.wipe = function(t)
    for k in pairs(t) do
        t[k] = nil
    end
end
require = noop
ISInventoryPaneDraggedItems = {}
ISMouseDrag = { dragging = {} }
ISPanel = {
    derive = function()
        return {}
    end,
}
ISInventoryItem = { renderItemIcon = noop }
AnimalDefinitions = { animals = { chicken = { eggType = "Base.Egg", timeToHatch = 100 } } }
SandboxVars = { AnimalEggHatch = 4 }
LivestockPanelPlusConfig = { eggMarkers = true }
getTexture = function(path)
    return path
end
getText = function(text)
    return string.gsub(text, "^IGUI_ItemCat_", "")
end
getCore = function()
    return {
        getGoodHighlitedColor = function()
            return {
                getR = function()
                    return 1
                end,
                getG = function()
                    return 1
                end,
                getB = function()
                    return 1
                end,
            }
        end,
        getOptionFontSizeReal = function()
            return 1
        end,
    }
end
getPlayerHotbar = function()
    return {
        isInHotbar = function()
            return false
        end,
    }
end
getMouseX = function()
    return 65
end
getMouseY = function()
    return 95
end
local player = setmetatable({}, {
    __index = function()
        return function()
            return false
        end
    end,
})
getSpecificPlayer = function()
    return player
end
instanceof = function(item, kind)
    return kind == "InventoryItem" or item.kind == kind
end

local visited = 0
local function item(name, data, egg)
    local result = {
        name = name,
        data = data,
        kind = egg and "Food" or "Moveable",
        unwanted = false,
        getName = function(self)
            return self.name
        end,
        hasModData = function(self)
            visited = visited + 1
            return rawget(self, "data") ~= nil
        end,
        getModData = function(self)
            return { movableData = rawget(self, "data") }
        end,
        getTex = function()
            return "item"
        end,
        getJobDelta = function()
            return 0
        end,
        getFullType = function()
            return egg and "Base.Egg" or "Base.Moveable"
        end,
        getDisplayCategory = function()
            return "Furniture"
        end,
        getAge = function()
            return 3
        end,
        isUnwanted = function(self)
            return self.unwanted
        end,
        isFertilized = function()
            return egg == "fertilized"
        end,
        getFertilizedTime = function()
            return 50
        end,
        getTimeToHatch = function()
            return 100
        end,
        getFluidContainer = function()
            return nil
        end,
        getWorldItem = function()
            return nil
        end,
        getHeat = function()
            return 1
        end,
        getItemHeat = function()
            return 1
        end,
        getInvHeat = function()
            return 0
        end,
        getMeltingTime = function()
            return 0
        end,
    }
    return setmetatable(result, {
        __index = function()
            return function()
                return false
            end
        end,
    })
end
local function stack(value, count)
    local values = { value }
    -- Native refresh adds a duplicate first item as the stack header.
    for i = 2, (count or 1) + 1 do
        values[i] = value
    end
    return { items = values, name = value.name, count = (count or 1) + 1 }
end

-- A small renderer models the native row/name contract for source-only CI.
-- When supplied, the installed ISInventoryPane.lua replaces this model.
local function modelRender(self, dragged)
    if not dragged then
        table.wipe(self.items)
        if self.inventory:isDrawDirty() then
            self:refreshContainer()
        end
    end
    if not self.itemslist then
        self:refreshContainer()
    end
    local row = 0
    for _, entry in ipairs(self.itemslist) do
        for count, value in ipairs(entry.items) do
            if not dragged then
                self.items[#self.items + 1] = count == 1 and entry or value
            end
            local selected = self.dragging ~= nil and self.selected[row + 1] and self.dragStarted
            local xoff, yoff = 0, 0
            if selected then
                xoff = self:getMouseX() - self.draggingX
                yoff = self:getMouseY() - self.draggingY
            end
            local top = row * self.itemHgt + self:getYScroll()
            local visible = selected or (top + self.itemHgt >= 0 and top <= self.height)
            if
                visible
                and ((dragged and selected) or (not dragged and not selected))
                and count == 1
            then
                local suffix = entry.count > 2 and (" (" .. (entry.count - 1) .. ")") or ""
                local r, g, b, a = 0.7, 0.7, 0.7, 1
                if value.unwanted then
                    r, g, b, a = 0.5, 0.5, 0.5, 0.65
                end
                local y = row * self.itemHgt
                    + self.headerHgt
                    + (self.itemHgt - self.fontHgt) / 2
                    + yoff
                self:drawText(
                    value.name .. suffix,
                    self.column2 + 8 + xoff,
                    y,
                    r,
                    g,
                    b,
                    a,
                    self.font
                )
                self:drawText("Furniture", self.column3 + 8 + xoff, y, 0.6, 0.6, 0.8, 1, self.font)
            end
            row = row + 1
            if count == 1 and self.collapsed[entry.name] then
                break
            end
            if count == 51 then
                break
            end
        end
    end
end

local baseCalls = 0
local function resetRenderer()
    ISInventoryPane = { renderdetails = modelRender, MAX_ITEMS_IN_STACK_TO_RENDER = 50 }
    if arg[2] then
        dofile(arg[2])
    end
    local native = ISInventoryPane.renderdetails
    ISInventoryPane.renderdetails = function(self, dragged)
        baseCalls = baseCalls + 1
        native(self, dragged)
        return "native-result", 17
    end
    baseCalls = 0
end
local function installEggs()
    if arg[3] then
        dofile(arg[3])
    else
        local previous = ISInventoryPane.renderdetails
        ISInventoryPane.renderdetails = function(self, dragged)
            previous(self, dragged)
            self.eggPasses = self.eggPasses + 1
        end
    end
end
local function makePane(entries)
    local pane = {
        itemslist = entries,
        items = {},
        selected = {},
        collapsed = {},
        drawn = {},
        eggs = {},
        eggPasses = 0,
        player = 0,
        itemHgt = 24,
        fontHgt = 12,
        headerHgt = 18,
        font = "small",
        column2 = 40,
        column3 = 200,
        column4 = 300,
        height = 120,
        width = 300,
        scroll = 0,
        refreshes = 0,
        dirty = false,
        getMouseX = getMouseX,
        getMouseY = getMouseY,
        getYScroll = function(self)
            return self.scroll
        end,
        getHeight = function(self)
            return self.height
        end,
        getWidth = function(self)
            return self.width
        end,
        refreshContainer = function(self)
            self.refreshes = self.refreshes + 1
            self.dirty = false
            self.itemslist = self.nextEntries or entries
        end,
        isLiteratureRead = function()
            return false
        end,
        drawText = function(self, text, x, y, r, g, b, a)
            self.drawn[#self.drawn + 1] = { text = text, x = x, y = y, r = r, g = g, b = b, a = a }
        end,
        drawTextureScaled = function(self, texture, x, y)
            if
                type(texture) == "string"
                and string.find(texture, "LivestockPanelPlus/Egg", 1, true)
            then
                self.eggs[#self.eggs + 1] = { texture = texture, x = x, y = y }
            end
        end,
    }
    for _, entry in ipairs(entries) do
        pane.collapsed[entry.name] = true
    end
    local nativeRefresh = pane.refreshContainer
    pane.refreshContainer = function(self)
        nativeRefresh(self)
        for _, entry in ipairs(self.itemslist) do
            if self.collapsed[entry.name] == nil then
                self.collapsed[entry.name] = true
            end
        end
    end
    pane.inventory = {
        isDrawDirty = function()
            return pane.dirty
        end,
        isLockedToCharacter = function()
            return false
        end,
        getItems = function()
            return list({})
        end,
    }
    pane.draggedItems = {
        update = noop,
        cannotDropAnyItem = function()
            return false
        end,
        cannotDropItem = function()
            return false
        end,
    }
    return setmetatable(pane, {
        __index = function(_, key)
            if ISInventoryPane[key] then
                return ISInventoryPane[key]
            end
            if
                string.match(key, "^(draw)")
                or string.match(key, "^(set)")
                or string.match(key, "^(clear)")
                or string.match(key, "^(repaint)")
                or string.match(key, "^(resume)")
                or string.match(key, "^(suspend)")
                or string.match(key, "^(update)")
            then
                return noop
            end
        end,
    })
end
local function hasLabel(pane, text, color)
    for _, drawn in ipairs(pane.drawn) do
        if
            drawn.text == text
            and (
                not color
                or (
                    drawn.r == color[1]
                    and drawn.g == color[2]
                    and drawn.b == color[3]
                    and drawn.a == color[4]
                )
            )
        then
            return true
        end
    end
    return false
end
local function render(pane, dragged)
    pane.drawn = {}
    pane.eggs = {}
    return pane:renderdetails(dragged == true)
end

if arg[4] then
    resetRenderer()
    installEggs()
    dofile(arg[4])
    local oldPane = makePane({
        stack(item("Chair", { customName = "Old custom" })),
        stack(item("Egg", nil, "fertilized")),
    })
    render(oldPane)
    check(baseCalls == 0, "Original custom branch bypasses the captured native renderer")
    check(
        #oldPane.eggs == 0 and oldPane.eggPasses == 0,
        "Original branch suppresses the prior egg wrapper"
    )
    resetRenderer()
    dofile(arg[4])
    local entries = {}
    for i = 1, 5000 do
        entries[i] = stack(item("Plain" .. i))
    end
    visited = 0
    render(makePane(entries))
    check(visited >= 5000, "Original negative custom-data detection scans all 5000 items")
end

for _, order in ipairs({ "eggs-first", "lifestyle-first" }) do
    resetRenderer()
    if order == "eggs-first" then
        installEggs()
        dofile(patched)
    else
        dofile(patched)
        installEggs()
    end
    local chair = item("Chair", { customName = "Audit Chair", inventionData = {} })
    local pane = makePane({
        stack(chair, 3),
        stack(item("Egg", nil, "fertilized")),
        stack(item("Egg stale", nil, "unfertilized")),
    })
    pane.collapsed.Chair = true
    local priorDraw = pane.drawText
    render(pane)
    check(baseCalls == 1, order .. ": previous renderer called exactly once")
    check(pane.drawText == priorDraw, order .. ": pane draw method restored")
    check(
        hasLabel(pane, "Audit Chair (3)", { 0.8, 0.8, 0.25, 1 }),
        order .. ": custom name/count and invention color"
    )
    check(hasLabel(pane, "Furniture", { 0.6, 0.6, 0.8, 1 }), order .. ": categories remain native")
    check(
        arg[3] and #pane.eggs == 2 or not arg[3] and pane.eggPasses == 1,
        order .. ": both egg markers preserved"
    )

    chair.data.customName = "Renamed"
    chair.data.inventionData = nil
    render(pane)
    check(
        hasLabel(pane, "Renamed (3)", { 0.7, 0.7, 0.7, 1 }),
        order .. ": rename/invention removal is immediate"
    )
    chair.data.inventionData = {}
    chair.unwanted = true
    render(pane)
    check(
        hasLabel(pane, "Renamed (3)", { 0.5, 0.5, 0.5, 0.65 }),
        order .. ": unwanted color takes priority"
    )
    chair.unwanted = false
    chair.data.customName = nil
    render(pane)
    check(
        hasLabel(pane, "Chair (3)", { 0.8, 0.8, 0.25, 1 }),
        order .. ": invention without custom name is current"
    )
    pane.selected[2] = true
    pane.dragging = 1
    pane.dragStarted = true
    pane.draggingX = 20
    pane.draggingY = 30
    render(pane, true)
    if arg[3] then
        check(#pane.eggs == 1, order .. ": dragged egg marker remains visible")
        check(
            pane.eggs[1].x == 74.375 and pane.eggs[1].y == 124.5,
            order .. ": egg marker drag offsets unchanged"
        )
    end
    pane.selected = {}
    pane.dragging = nil
    pane.dragStarted = false
    pane.dirty = true
    pane.nextEntries = { stack(item("Replacement", { customName = "Transferred" })) }
    render(pane)
    check(
        pane.refreshes == 1 and hasLabel(pane, "Transferred"),
        order .. ": native dirty refresh/transfer is reflected"
    )
    pane.itemslist = nil
    render(pane)
    check(
        pane.refreshes == 2 and hasLabel(pane, "Transferred"),
        order .. ": missing list uses native refresh"
    )
    pane.selected[1] = true
    pane.dragging = 1
    pane.dragStarted = true
    pane.draggingX = 20
    pane.draggingY = 30
    render(pane, true)
    check(hasLabel(pane, "Transferred"), order .. ": dragged name follows native offsets")
    local drawn = pane.drawn[1]
    check(drawn.x == 93 and drawn.y == 89, order .. ": drag coordinates unchanged")
end

resetRenderer()
dofile(patched)
local resultPane = makePane({ stack(item("Return", { customName = "Return custom" })) })
local first, second = render(resultPane)
check(first == "native-result" and second == 17, "Delegated return values survive")
local scrollEntries = {}
for i = 1, 100 do
    scrollEntries[i] = stack(item("Row" .. i, { customName = "Custom" .. i }))
end
local scrollPane = makePane(scrollEntries)
scrollPane.scroll = -50 * scrollPane.itemHgt
render(scrollPane)
check(
    hasLabel(scrollPane, "Custom51") and not hasLabel(scrollPane, "Custom1"),
    "Scrolled native row coordinates resolve the correct item"
)

for _, count in ipairs({ 100, 1000, 5000 }) do
    local entries = {}
    for i = 1, count do
        entries[i] = stack(item("Plain" .. i))
    end
    for _, frames in ipairs({ 30, 60 }) do
        local left, right = makePane(entries), makePane(entries)
        visited = 0
        for frame = 1, frames do
            render(left)
            render(right)
        end
        check(
            visited <= 7 * frames * 2,
            count .. " items: two panes check only visible name rows across " .. frames .. " frames"
        )
        print(
            "DATA: "
                .. count
                .. " items/pane, "
                .. frames
                .. " frames, custom-data checks="
                .. visited
        )
    end
end
local offscreen = makePane(scrollEntries)
offscreen.height = -100
visited = 0
render(offscreen)
check(visited == 0, "A pane with no drawn item names performs no custom-data checks")

-- Restoring nil matters: an inherited drawText must not become a permanent
-- per-instance method after closing or reopening a pane.
resetRenderer()
ISInventoryPane.drawText = function()
    error("DRAW_FAILURE")
end
local inherited = makePane({ stack(item("Fail", { customName = "Failed" })) })
inherited.drawText = nil
dofile(patched)
local ok, why = pcall(function()
    render(inherited)
end)
check(
    not ok and string.find(tostring(why), "DRAW_FAILURE", 1, true),
    "Original renderer error propagates"
)
check(
    rawget(inherited, "drawText") == nil and inherited.drawText == ISInventoryPane.drawText,
    "Inherited drawText is restored on error"
)
print("PASS: " .. checks .. " Lifestyle inventory composition/performance checks")
