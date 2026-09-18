require("AdminCore/OfflinePlayers")
require("ISUI/ISTextEntryBox")
require("ISUI/ISLabel")

local C = AdminCore
if C.inviteSearchInstalled then
    return
end
C.inviteSearchInstalled = true

local function username(row)
    return row and row.item and (row.item.username or row.item.name)
end

local function updateSelection(panel)
    local row = panel.playerList.items[panel.playerList.selected]
    local blocked = row and (row.tooltip or row.item.tooltip)
    panel.selectedPlayer = row and not blocked and username(row) or nil
    panel.addPlayer:setEnable(panel.selectedPlayer ~= nil)
    panel.addPlayer.tooltip = blocked
end

function C.filterInvitePlayers(panel, selectedName)
    local list = panel.playerList
    local query = panel.uacInviteSearch and panel.uacInviteSearch:getInternalText() or ""
    query = query:lower():match("^%s*(.-)%s*$")
    if selectedName == nil then
        selectedName = username(list.items[list.selected])
    end
    list:clear()
    list:setScrollHeight(0)
    list.selected = 0
    for _, row in ipairs(panel.uacInviteRows or {}) do
        if query == "" or row.uacSearchText:find(query, 1, true) then
            local added = list:addItem(row.text, row.item, row.tooltip)
            for key, value in pairs(row) do
                if key ~= "index" and key ~= "itemindex" then
                    added[key] = value
                end
            end
            if username(row) == selectedName then
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
    if panel.uacInviteCount then
        local total = #(panel.uacInviteRows or {})
        panel.uacInviteCount:setName(
            #list.items == 0 and "No matching players"
                or (#list.items .. " / " .. total .. " players")
        )
    end
end

local function install(class, isFaction)
    local originalPopulate = class.populateList
    function class:populateList()
        local selectedName = username(self.playerList.items[self.playerList.selected]) or false
        originalPopulate(self)
        self.uacInviteRows = self.playerList.items
        for _, row in ipairs(self.uacInviteRows) do
            -- Vanilla faction UI indexes tooltips by scoreboard position after excluding rows.
            -- Keep the restriction attached to its actual player when filtering.
            if isFaction then
                row.tooltip = row.item.tooltip
            end
            row.uacSearchText = (tostring(username(row) or "") .. " " .. tostring(row.text or "")):lower()
        end
        C.filterInvitePlayers(self, selectedName)
    end

    local originalInit = class.initialise
    function class:initialise()
        originalInit(self)
        -- Every client gets search, including ordinary owners without admin capabilities.
        local list = self.playerList
        local top = list.y
        local font = getTextManager():getFontHeight(UIFont.Small)
        local entryHeight = math.max(28, font + 6)
        local offset = entryHeight + font + 12
        for _, child in pairs(self:getChildren()) do
            if child.y >= top then
                child:setY(child.y + offset)
            end
        end
        self:setHeight(self.height + offset)
        local overflow = math.max(0, self.height - (getCore():getScreenHeight() - 16))
        local shrink = math.min(overflow, math.max(0, list.height - list.itemheight * 2))
        if shrink > 0 then
            local bottom = list:getBottom()
            list:setHeight(list.height - shrink)
            for _, child in pairs(self:getChildren()) do
                if child ~= list and child.y >= bottom then
                    child:setY(child.y - shrink)
                end
            end
            self:setHeight(self.height - shrink)
        end
        C.fit(self, self.width, self.height)
        local clearWidth = math.max(60, getTextManager():MeasureStringX(UIFont.Small, "Clear") + 16)
        self.uacInviteSearch =
            ISTextEntryBox:new("", list.x, top, list.width - clearWidth - 8, entryHeight)
        self.uacInviteSearch:initialise()
        self.uacInviteSearch:setPlaceholderText("Search username or display name...")
        self.uacInviteSearch.tooltip = "Filter the current player list. Clear restores all names."
        self.uacInviteSearch.onTextChange = function()
            C.filterInvitePlayers(self)
        end
        self:addChild(self.uacInviteSearch)
        self.uacInviteClear = ISButton:new(
            list:getRight() - clearWidth,
            top,
            clearWidth,
            entryHeight,
            "Clear",
            self,
            function(p)
                p.uacInviteSearch:setText("")
                C.filterInvitePlayers(p)
            end
        )
        self.uacInviteClear:initialise()
        self:addChild(self.uacInviteClear)
        self.uacInviteCount = ISLabel:new(
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
        self.uacInviteCount:initialise()
        self:addChild(self.uacInviteCount)
        self:populateList()
    end

    local originalClick = class.onClick
    function class:onClick(button)
        if button.internal == "ADDPLAYER" then
            if not self.playerList.items[self.playerList.selected] then
                return
            end
            -- Rebuild against the latest received scoreboard/membership before sending.
            self:populateList()
            if not self.selectedPlayer then
                return
            end
        end
        return originalClick(self, button)
    end
end

install(ISSafehouseAddPlayerUI, false)
install(ISFactionAddPlayerUI, true)
