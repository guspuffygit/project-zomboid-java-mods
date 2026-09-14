require("AdminCore/WindowSizing")
require("AdminCore/DataAndObserve")
require("AdminCore/OfflinePlayers")
require("ISUI/AdminPanel/ISUsersList")
require("ISUI/PlayerStats/ISPlayerStatsManageInvUI")
require("ISUI/UserPanel/ISSafehouseUI")
require("ISUI/UserPanel/ISFactionUI")

local T = AdminCore
T.categories = {
    Teleport = "Teleport",
    TeleportToHim = "Teleport",
    ManageInventory = "Inventory",
    Kick = "Moderation",
    Ban = "Moderation",
    UnBan = "Moderation",
    BanIP = "Moderation",
    UnBanIP = "Moderation",
    BanSteamID = "Moderation",
    UnBanSteamID = "Moderation",
    AddWarningPoint = "Moderation",
    SeeUserLog = "Logs",
    SeeSuspicionActivity = "Logs",
    Delete = "Moderation",
    ResetTOTPSecret = "Moderation",
    ResetPassword = "Moderation",
    SetPassword = "Moderation",
}

-- Move existing options rather than rebuilding their authorization or callbacks.
function T.groupMenu(context)
    local options, groups = context.options, {}
    context.options, context.numOptions = {}, 1
    for _, option in ipairs(options) do
        local category = T.categories[option.param2]
        local target = context
        if category then
            if not groups[category] then
                groups[category] = T.submenu(context, category)
            end
            target = groups[category]
        end
        option.id = target.numOptions
        target.options[target.numOptions] = option
        target.numOptions = target.numOptions + 1
    end
    for _, sub in pairs(groups) do
        sub:calcHeight()
        sub:setWidth(sub:calcWidth())
    end
    context:calcHeight()
    context:setWidth(context:calcWidth())
    return groups
end

function T.safehouse(username)
    local list = SafeHouse.getSafehouseList()
    for i = 0, list:size() - 1 do
        local house = list:get(i)
        if house:getOwner() == username or house:getPlayers():contains(username) then
            return house
        end
    end
end

function T.faction(username)
    return Faction.getPlayerFaction(username)
end

local function coords(house)
    return math.floor(house:getX()) .. ", " .. math.floor(house:getY())
end

function T.teleportCoordinates(x, y, z)
    if not T.allowed(Capability.TeleportToCoordinates) then
        return
    end
    SendCommandToServer(
        "/teleportto " .. math.floor(x) .. "," .. math.floor(y) .. "," .. math.floor(z)
    )
end

function T.teleportHouse(username)
    local house = T.safehouse(username)
    if not house then
        return T.message("This player no longer belongs to a safehouse.")
    end
    local player = getPlayer()
    T.returnPosition = { x = player:getX(), y = player:getY(), z = player:getZ() }
    -- Outside the corner avoids spawning inside walls or on an unknown upper floor.
    T.teleportCoordinates(house:getX() - 1, house:getY() - 1, 0)
end

function T.removeHouseMember(username, expectedID)
    local house = T.safehouse(username)
    if not house or not T.allowed(Capability.CanSetupSafehouses) then
        return
    end
    if expectedID and house:getId() ~= expectedID then
        return T.message("Safehouse membership changed. Reopen the menu and review it.")
    end
    if house:getOwner() == username then
        return T.replaceOwner("safehouse", house, username)
    end
    sendSafehouseChangeMember(house, username)
end

function T.removeFactionMember(username, expectedName)
    local faction = T.faction(username)
    if not faction or not T.allowed(Capability.FactionCheat) then
        return
    end
    if expectedName and faction:getName() ~= expectedName then
        return T.message("Faction membership changed. Reopen the menu and review it.")
    end
    if faction:getOwner() == username then
        return T.replaceOwner("faction", faction:getName(), username)
    end
    sendFactionRemoveMember(faction, username)
end

local function info(menu, text)
    local option = menu:addOption(text, nil, nil)
    option.notAvailable = true
end

function T.membershipMenu(context, username)
    if not (T.allowed(Capability.CanSetupSafehouses) or T.allowed(Capability.FactionCheat)) then
        return
    end
    local menu = T.submenu(context, "Safehouse")
    local house, faction = T.safehouse(username), T.faction(username)
    info(menu, house and ("Safehouse: " .. tostring(house:getTitle())) or "Safehouse: none")
    if house then
        info(menu, "Owner: " .. house:getOwner() .. " | Location: " .. coords(house))
        if T.allowed(Capability.TeleportToCoordinates) then
            menu:addOption("Teleport to safehouse edge", username, T.teleportHouse)
        end
        if T.allowed(Capability.CanSetupSafehouses) then
            menu:addOption("Open safehouse management", nil, function()
                local current = T.safehouse(username)
                if not current then
                    return
                end
                local panel = ISSafehouseUI:new(50, 50, 500, 450, current, getPlayer())
                panel:initialise()
                panel:addToUIManager()
                T.fit(panel, panel.width, panel.height)
            end)
            local remove = menu:addOption("Remove player from safehouse...", nil, function()
                local id = house:getId()
                T.confirm("Remove " .. username .. " from this safehouse?", function()
                    T.removeHouseMember(username, id)
                end)
            end)
            if house:getOwner() == username then
                remove.name = "Transfer ownership + remove owner..."
            end
            menu:addOption("Delete safehouse claim...", nil, function()
                local id = house:getId()
                T.confirm(
                    "Release the safehouse claim at "
                        .. coords(house)
                        .. " for ALL members? Buildings and items remain.",
                    function()
                        local current = T.safehouse(username)
                        if
                            current
                            and current:getId() == id
                            and T.allowed(Capability.CanSetupSafehouses)
                        then
                            sendSafehouseRelease(current)
                        end
                    end
                )
            end)
        end
    end
    menu = T.submenu(context, "Faction")
    info(
        menu,
        faction and ("Faction: " .. faction:getName() .. " | Owner: " .. faction:getOwner())
            or "Faction: none"
    )
    if faction and T.allowed(Capability.FactionCheat) then
        menu:addOption("Open faction management", nil, function()
            local current = T.faction(username)
            if not current then
                return
            end
            local panel = ISFactionUI:new(50, 50, 500, 450, current, getPlayer())
            panel:initialise()
            panel:addToUIManager()
            T.fit(panel, panel.width, panel.height)
        end)
        local remove = menu:addOption("Remove player from faction...", nil, function()
            local name = faction:getName()
            T.confirm("Remove " .. username .. " from their faction?", function()
                T.removeFactionMember(username, name)
            end)
        end)
        if faction:getOwner() == username then
            remove.name = "Transfer ownership + remove owner..."
        end
    end
end

function T.playerReport(user)
    local username = user:getUsername()
    local house, faction = T.safehouse(username), T.faction(username)
    local lines = {
        "Player: " .. username,
        "Role: " .. user:getRole():getName(),
        "Online: " .. tostring(user:isOnline()) .. " | Ping: " .. tostring(user:getPing()),
        "Warnings: "
            .. user:getWarningPoints()
            .. " | Suspicion: "
            .. user:getSuspicionPoints()
            .. " | Kicks: "
            .. user:getKicks(),
        "Faction: " .. (faction and faction:getName() or "none"),
        "Safehouse: "
            .. (
                house
                    and (tostring(house:getTitle()) .. " | Owner: " .. house:getOwner() .. " | " .. coords(
                        house
                    ))
                or "none"
            ),
        "Snapshot of the admin client's received data. Suspicion points are leads, not proof of cheating.",
    }
    return table.concat(lines, "\n")
end

local oldContext = ISUsersList.doContextMenu
function ISUsersList:doContextMenu(item, x, y)
    if not item then
        return
    end
    oldContext(self, item, x, y)
    local context = getPlayerContextMenu(self.player:getPlayerNum())
    local groups = T.groupMenu(context)
    T.membershipMenu(context, item:getUsername())
    if T.allowed(Capability.ReadUserLog) then
        local investigation = groups.Logs or T.submenu(context, "Logs")
        investigation:addOption("Player / membership report", nil, function()
            T.message(T.playerReport(item))
        end)
        investigation:addOption("Save investigation snapshot", nil, function()
            local file = "admin-investigation-" .. tostring(getTimestamp()) .. ".txt"
            local writer = getFileWriter(file, true, false)
            if not writer then
                return T.message("Could not open the report file.")
            end
            writer:write(T.playerReport(item))
            writer:close()
            T.message("Saved " .. file .. " in this client's Zomboid profile.")
        end)
        investigation:addOption("Screenshot my game view", nil, function()
            takeScreenshot()
        end)
        if
            AdminCoreObserveCamera
            and item:isOnline()
            and item:getUsername() ~= getPlayer():getUsername()
            and T.allowed(Capability.TeleportToPlayer)
        then
            investigation:addOption("Observe / follow player (experimental)...", nil, function()
                T.confirm(
                    "Follow "
                        .. item:getUsername()
                        .. "? Your invisible admin will move near them to load their area. Stop returns you to the starting position. Enable god mode and noclip first.",
                    function()
                        if T.cancelZoneSelection then
                            T.cancelZoneSelection()
                        end
                        sendClientCommand(
                            "UniversalAdminCore",
                            "observeStart",
                            { username = item:getUsername() }
                        )
                    end
                )
            end)
        end
    end
    if T.allowed(Capability.TeleportToCoordinates) and T.returnPosition then
        local playerMenu = groups.Teleport or T.submenu(context, "Teleport")
        playerMenu:addOption("Return to previous inspection location", nil, function()
            local pos = T.returnPosition
            if pos then
                T.teleportCoordinates(pos.x, pos.y, pos.z)
                T.returnPosition = nil
            end
        end)
    end
    context:calcHeight()
    context:setWidth(context:calcWidth())
end

-- Empty-space right clicks in the vanilla user list dereference a missing row.
function ISUsersList:onRightMouse(x, y)
    local panel = ISUsersList.instance
    if not panel then
        return
    end
    panel.datas:onMouseDown(x, y)
    local selected = panel.datas.items[panel.datas.selected]
    if selected then
        panel:doContextMenu(selected.item, x, y)
    end
end

local function usersLayout(panel)
    local w, h = panel.width, panel.height
    local headers = {
        panel.sortByNameButton,
        panel.uacFactionHeader,
        panel.sortByRoleButton,
        panel.sortByLastConnectionButton,
        panel.uacPlaytimeHeader,
        panel.sortByWarningsButton,
    }
    local fractions = { 0, 0.20, 0.35, 0.48, 0.70, 0.82, 1 }
    local positions = {}
    for i, value in ipairs(fractions) do
        positions[i] = 11 + math.floor((w - 22) * value)
    end
    panel.uacColumns = positions
    panel.roleColumnX = positions[3]
    panel.lastConnectionColumnX = positions[4]
    panel.warningsColumnX = positions[6]
    for i, header in ipairs(headers) do
        header:setX(positions[i])
        header:setWidth(positions[i + 1] - positions[i])
    end
    panel.datas:setWidth(w - 22)
    local bottom = h - panel.add.height - 12
    panel.datas:setHeight(bottom - panel.datas.y - 45)
    panel.add:setY(bottom)
    panel.bannedIPs:setY(bottom)
    panel.refresh:setY(bottom)
    panel.close:setX(w - panel.close.width - 25)
    panel.close:setY(bottom)
    panel.searchEntry:setX(80)
    panel.searchEntry:setY(bottom - 32)
    panel.searchEntry:setWidth(math.min(260, w - 110))
    -- Vanilla creates the filter label and online checkbox as unnamed children.
    for _, child in pairs(panel:getChildren()) do
        if child.Type == "ISLabel" then
            child:setX(12)
            child:setY(bottom - 32)
        end
        if child.Type == "ISTickBox" then
            child:setX(360)
            child:setY(bottom - 32)
        end
    end
end

local oldUsersInit = ISUsersList.initialise
function ISUsersList:initialise()
    T.fit(
        self,
        math.min(self.width, getCore():getScreenWidth() - 24),
        math.min(self.height, getCore():getScreenHeight() - 24)
    )
    oldUsersInit(self)
    self.uacFactionHeader = self:createColumnHeader("Faction", "uacFaction", 0, 100)
    self.uacPlaytimeHeader = self:createColumnHeader("Time played*", "uacHours", 0, 100)
    self.uacPlaytimeHeader.tooltip =
        "Real hours on this server tracked since this addon was installed, across deaths. Earlier history is unavailable."
    self:addChild(self.uacFactionHeader)
    self:addChild(self.uacPlaytimeHeader)
    T.resizable(self, "Users", 950, 400, usersLayout)
    T.requestStats()
end

local oldUserComparator = ISUsersList.comparator
function ISUsersList.comparator(a, b)
    local panel = ISUsersList.instance
    if not panel or not panel.sortType:find("^uac") then
        return oldUserComparator(a, b)
    end
    local function value(row)
        local name = row.item:getUsername()
        if panel.sortType == "uacFaction" then
            local f = T.faction(name)
            return f and f:getName():lower() or ""
        end
        local data = T.stats[name]
        if panel.sortType == "uacHours" then
            return data and data.tracked and data.seconds or -1
        end
        return -1
    end
    local av, bv = value(a), value(b)
    if av == bv then
        return a.item:getUsername():lower() < b.item:getUsername():lower()
    end
    return panel.sortDown and av > bv or not panel.sortDown and av < bv
end

local factionDisplayCache, factionDisplayUntil, factionDisplayCount = {}, 0, 0
local function clearFactionDisplayCache()
    factionDisplayCache, factionDisplayUntil, factionDisplayCount = {}, 0, 0
end
if Events and Events.SyncFaction then
    Events.SyncFaction.Add(clearFactionDisplayCache)
end

function ISUsersList:drawDatas(y, item, alt)
    -- The native list calls doDrawItem for every account, including hidden rows.
    local clipY = math.max(0, y + self:getYScroll())
    local clipEnd = math.min(self.height, y + self:getYScroll() + self.itemheight)
    if clipEnd <= clipY then
        return y + self.itemheight
    end
    local p = self.parent
    if not p.uacColumns then
        return y + self.itemheight
    end
    local user = item.item
    if self.selected == item.index then
        self:drawRect(0, y, self.width, self.itemheight, 0.3, 0.7, 0.35, 0.15)
    end
    self:drawRectBorder(0, y, self.width, self.itemheight, 0.7, 0.4, 0.4, 0.4)
    local name = user:getUsername()
    local now = getTimestampMs()
    if now >= factionDisplayUntil or factionDisplayCount >= 256 then
        factionDisplayCache, factionDisplayUntil, factionDisplayCount = {}, now + 2000, 0
    end
    local factionName = factionDisplayCache[name]
    if not factionName then
        local f = T.faction(name)
        factionName = f and f:getName() or "None"
        factionDisplayCache[name] = factionName
        factionDisplayCount = factionDisplayCount + 1
    end
    local data = T.stats[name]
    local connection = user:getLastConnection() or ""
    local online, role = user:isOnline(), user:getRole():getName()
    local warning, suspicion, kicks =
        user:getWarningPoints(), user:getSuspicionPoints(), user:getKicks()
    local seconds = data and data.tracked and data.seconds or false
    local epoch = math.floor(now / 2000)
    if self.uacDrawEpoch ~= epoch or (self.uacDrawCount or 0) >= 256 then
        self.uacDrawCache, self.uacDrawCount, self.uacDrawEpoch = {}, 0, epoch
    end
    local cached = self.uacDrawCache[name]
    if
        not cached
        or cached.online ~= online
        or cached.role ~= role
        or cached.connection ~= connection
        or cached.faction ~= factionName
        or cached.seconds ~= seconds
        or cached.warning ~= warning
        or cached.suspicion ~= suspicion
        or cached.kicks ~= kicks
    then
        local date, time = connection:match("^(%S+)%s+(.+)$")
        local values = {
            { name, online and "Online" or "Offline" },
            { factionName },
            { role },
            { date or connection, time or "" },
            { seconds and string.format("%.2f h", seconds / 3600) or "N/A" },
            { "Warn: " .. warning, "Suspect: " .. suspicion, "Kicks: " .. kicks },
        }
        if not cached then
            self.uacDrawCount = self.uacDrawCount + 1
        end
        cached = {
            online = online,
            role = role,
            connection = connection,
            faction = factionName,
            seconds = seconds,
            warning = warning,
            suspicion = suspicion,
            kicks = kicks,
            values = values,
        }
        self.uacDrawCache[name] = cached
    end
    local values = cached.values
    local line = getTextManager():getFontHeight(UIFont.Small) + 3
    for i, lines in ipairs(values) do
        local x = p.uacColumns[i] - self.x
        local width = p.uacColumns[i + 1] - p.uacColumns[i]
        if clipEnd > clipY then
            self:setStencilRect(x, clipY, width, clipEnd - clipY)
            for n, text in ipairs(lines) do
                local r, g, b = 1, 1, 1
                if i == 1 and n == 2 then
                    if user:isOnline() then
                        r, g, b = 0.2, 1, 0.2
                    else
                        r, g, b = 1, 0.25, 0.25
                    end
                end
                self:drawText(text, x + 6, y + 3 + (n - 1) * line, r, g, b, 1, UIFont.Small)
            end
            self:clearStencilRect()
        end
    end
    return y + self.itemheight
end

local oldRefresh = ISUsersList.refresh
function ISUsersList:refresh()
    oldRefresh(self)
    T.requestStats()
end

local function inventoryLayout(panel)
    panel.datas:setWidth(panel.width - 20)
    local y = panel.height - panel.no.height - 22
    panel.datas:setY(70)
    panel.datas:setHeight(y - 85)
    panel.no:setY(y)
    local right = panel.width - 24
    for _, button in ipairs({
        panel.removeBtn,
        panel.getItemBtn,
        panel.addItemBtn,
        panel.refreshBtn,
    }) do
        if button:getIsVisible() then
            right = right - button.width
            button:setX(right)
            button:setY(y)
            right = right - 10
        end
    end
end

local oldInventoryInit = ISPlayerStatsManageInvUI.initialise
function ISPlayerStatsManageInvUI:initialise()
    T.fit(self, self.width, self.height)
    oldInventoryInit(self)
    self.addItemBtn:setVisible(self.playerID ~= -1 and T.allowed(Capability.AddItem))
    T.resizable(self, "Inventory", 740, 360, inventoryLayout)
end

-- Validate text before using the game's server-checked /additem command.
function ISPlayerStatsManageInvUI:onAddItem(button)
    if button.internal ~= "OK" or not T.allowed(Capability.AddItem) then
        return
    end
    local itemType = luautils.trim(button.parent.entry:getText())
    if not itemType:match("^[%w_%-]+%.[%w_%-]+$") or not getScriptManager():FindItem(itemType) then
        return T.message("Enter a valid full item ID, for example Base.Hammer.")
    end
    if self.playerUsername:find('["\r\n]') then
        return T.message("This username cannot be passed safely to the game's command parser.")
    end
    SendCommandToServer('/additem "' .. self.playerUsername .. '" "' .. itemType .. '"')
    self:requestDatas()
end

print("[Universal Admin Core] Grouped admin menus, membership tools and resizable panels loaded.")
