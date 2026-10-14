require("AdminCore/WindowSizing")
require("ISUI/AdminPanel/ISSafehousesList")
require("ISUI/AdminPanel/ISFactionsList")
require("ISUI/ISTextEntryBox")
require("ISUI/ISLabel")

local C = AdminCore
if C.listSearchInstalled then
    return
end
C.listSearchInstalled = true

local function permitted(panel, capability)
    return panel.player:getRole():hasCapability(capability)
end

local function selectionKey(panel)
    local row = panel.datas.items[panel.datas.selected]
    return row and row.uacListKey or false
end

local function updateSelection(panel)
    local row = panel.datas.items[panel.datas.selected]
    local spec = panel.uacListSpec
    local object = row and permitted(panel, spec.capability) and row.item or nil
    panel[spec.selectedField] = object
    panel.viewBtn:setEnable(object ~= nil)
    if panel.teleportBtn then
        panel.teleportBtn:setEnable(
            object ~= nil and permitted(panel, Capability.TeleportToCoordinates)
        )
    end
end

function C.filterAdminList(panel, selectedKey)
    local list = panel.datas
    local query = panel.uacListSearch and panel.uacListSearch:getInternalText() or ""
    query = query:lower():match("^%s*(.-)%s*$")
    if selectedKey == nil then
        selectedKey = selectionKey(panel)
    end
    list:clear()
    list:setScrollHeight(0)
    list.selected = 0
    for _, row in ipairs(panel.uacListRows or {}) do
        if query == "" or row.uacSearchText:find(query, 1, true) then
            local added = list:addItem(row.text, row.item, row.tooltip)
            for key, value in pairs(row) do
                if key ~= "index" and key ~= "itemindex" then
                    added[key] = value
                end
            end
            if row.uacListKey == selectedKey then
                list.selected = #list.items
            end
        end
    end
    list.smoothScrollTargetY = nil
    list.smoothScrollY = nil
    list:setYScroll(0)
    if list.selected > 0 then
        list:ensureVisible(list.selected)
    end
    updateSelection(panel)
    if panel.uacListCount then
        local total = #(panel.uacListRows or {})
        panel.uacListCount:setName(
            #list.items == 0 and ("No matching " .. panel.uacListSpec.plural)
                or (#list.items .. " / " .. total .. " " .. panel.uacListSpec.plural .. " | A-Z")
        )
    end
end

local function install(class, spec)
    local originalPopulate = class.populateList
    function class:populateList()
        self.uacListSpec = spec
        local selectedKey = selectionKey(self)
        originalPopulate(self)
        self.uacListRows = self.datas.items
        for index, row in ipairs(self.uacListRows) do
            local name = tostring(spec.name(row.item) or "")
            local owner = tostring(row.item:getOwner() or "")
            local tag = spec.tag and tostring(spec.tag(row.item) or "") or ""
            row.uacListKey = spec.key(row.item)
            row.uacSortName = name:lower()
            row.uacSortOwner = owner:lower()
            row.uacSourceOrder = index
            row.uacSearchText = (name .. " " .. owner .. " " .. tag):lower()
        end
        -- Sort copied display rows, never the game's shared Java collections.
        table.sort(self.uacListRows, function(a, b)
            if a.uacSortName ~= b.uacSortName then
                return a.uacSortName < b.uacSortName
            end
            if a.uacSortOwner ~= b.uacSortOwner then
                return a.uacSortOwner < b.uacSortOwner
            end
            if a.uacListKey ~= b.uacListKey then
                return a.uacListKey < b.uacListKey
            end
            return a.uacSourceOrder < b.uacSourceOrder
        end)
        C.filterAdminList(self, selectedKey)
    end

    local originalInit = class.initialise
    function class:initialise()
        C.fit(self, self.width, self.height)
        originalInit(self)
        local list = self.datas
        local top = list.y
        local font = getTextManager():getFontHeight(UIFont.Small)
        local entryHeight = math.max(28, font + 6)
        local offset = entryHeight + font + 12
        list:setY(top + offset)
        list:setHeight(math.max(list.itemheight * 2, list.height - offset))
        local clearWidth = math.max(60, getTextManager():MeasureStringX(UIFont.Small, "Clear") + 16)
        self.uacListSearch =
            ISTextEntryBox:new("", list.x, top, list.width - clearWidth - 8, entryHeight)
        self.uacListSearch:initialise()
        self.uacListSearch:setPlaceholderText(spec.placeholder)
        self.uacListSearch.tooltip =
            "Filter by name or owner. Clear restores the alphabetical list."
        self.uacListSearch.onTextChange = function()
            C.filterAdminList(self)
        end
        self:addChild(self.uacListSearch)
        self.uacListClear = ISButton:new(
            list:getRight() - clearWidth,
            top,
            clearWidth,
            entryHeight,
            "Clear",
            self,
            function(panel)
                panel.uacListSearch:setText("")
                C.filterAdminList(panel)
            end
        )
        self.uacListClear:initialise()
        self:addChild(self.uacListClear)
        self.uacListCount = ISLabel:new(
            list.x,
            top + entryHeight + 4,
            font,
            "",
            0.8,
            0.8,
            0.8,
            1,
            UIFont.Small,
            true
        )
        self.uacListCount:initialise()
        self:addChild(self.uacListCount)
        C.filterAdminList(self)
    end

    local originalDraw = class.drawDatas
    function class:drawDatas(y, item, alt)
        local result = originalDraw(self, y, item, alt)
        if self.selected == item.index then
            -- Native drawing enables selected-row actions; retain current role checks.
            updateSelection(self.parent)
        end
        return result
    end

    local originalPrerender = class.prerender
    function class:prerender()
        originalPrerender(self)
        updateSelection(self)
    end

    local originalClick = class.onClick
    function class:onClick(button)
        if button.internal == "VIEW" or button.internal == "TELEPORT" then
            if not selectionKey(self) or not permitted(self, spec.capability) then
                updateSelection(self)
                return
            end
            -- Resolve the currently received object again before native View/Teleport.
            self:populateList()
            if not self[spec.selectedField] then
                return
            end
            if
                button.internal == "TELEPORT"
                and not permitted(self, Capability.TeleportToCoordinates)
            then
                return
            end
        end
        return originalClick(self, button)
    end
end

install(ISSafehousesList, {
    capability = Capability.CanSetupSafehouses,
    selectedField = "selectedSafehouse",
    plural = "safehouses",
    placeholder = "Search safehouse name or owner...",
    name = function(house)
        return house:getTitle()
    end,
    key = function(house)
        -- Safehouse packets identify claims by bounds; client-local getId() can change.
        return string.format("%d,%d,%d,%d", house:getX(), house:getY(), house:getW(), house:getH())
    end,
})

install(ISFactionsList, {
    capability = Capability.FactionCheat,
    selectedField = "selectedFaction",
    plural = "factions",
    placeholder = "Search faction name, tag or owner...",
    name = function(faction)
        return faction:getName()
    end,
    tag = function(faction)
        return faction:getTag()
    end,
    key = function(faction)
        return faction:getName()
    end,
})

-- Native safehouse changes already call our wrapped populateList(). Faction lists need a listener.
Events.SyncFaction.Add(function()
    local panel = ISFactionsList.instance
    if panel and panel.uacListRows and panel:getIsVisible() then
        panel:populateList()
    end
end)
