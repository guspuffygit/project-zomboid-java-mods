require("AdminCore/WindowSizing")
require("AdminCore/DataAndObserve")
require("ISUI/UserPanel/ISSafehouseAddPlayerUI")
require("ISUI/UserPanel/ISFactionAddPlayerUI")
local T = AdminCore

function T.safehouseKey(house)
    -- The native synchronization packet identifies claims by their full bounds.
    -- getId() includes a timestamp generated separately on each client/server.
    return string.format("%d,%d,%d,%d", house:getX(), house:getY(), house:getW(), house:getH())
end

function T.sortedAccounts(excluded, offlineOnly)
    local records = {}
    local users = getUsers()
    for i = 0, users:size() - 1 do
        local u = users:get(i)
        if u:getUsername() ~= excluded and (not offlineOnly or not u:isOnline()) then
            records[#records + 1] = {
                username = u:getUsername(),
                online = u:isOnline(),
                last = u:getLastConnection() or "",
            }
        end
    end
    table.sort(records, function(a, b)
        if a.online ~= b.online then
            return a.online
        end
        if a.last ~= b.last then
            return a.last > b.last
        end
        return a.username:lower() < b.username:lower()
    end)
    return records
end

AdminCoreAccountPicker = ISPanel:derive("AdminCoreAccountPicker")
function AdminCoreAccountPicker:populate()
    local selected = self.list.items[self.list.selected]
    local username = selected and selected.item.username
    self.list:clear()
    local filter = self.search:getInternalText():lower()
    for _, row in ipairs(T.sortedAccounts(self.excluded, self.offlineOnly)) do
        if row.username:lower():find(filter, 1, true) then
            self.list:addItem(row.username, row)
            if row.username == username then
                self.list.selected = #self.list.items
            end
        end
    end
end
function AdminCoreAccountPicker:createChildren()
    self.search = ISTextEntryBox:new("", 12, 48, self.width - 24, 30)
    self.search:initialise()
    self.search.onTextChange = function()
        self:populate()
    end
    self:addChild(self.search)
    self.list = ISScrollingListBox:new(12, 88, self.width - 24, self.height - 145)
    self.list:initialise()
    self.list.itemheight = 60
    self.list.font = UIFont.Small
    self.list.doDrawItem = function(list, y, item)
        if list.selected == item.index then
            list:drawRect(0, y, list.width, 60, 0.3, 0.4, 0.5, 0.6)
        end
        local row = item.item
        list:drawText(row.username, 8, y + 2, 1, 1, 1, 1, UIFont.Small)
        local stats = T.stats[row.username]
        local seen = row.online and "Online"
            or (row.last ~= "" and "Last connection: " .. row.last or "Last connection unknown")
        if not row.online and stats and stats.lastSeen and stats.lastSeen > 0 then
            seen = string.format(
                "Seen %.1f hours ago",
                math.max(0, (getTimestamp() - stats.lastSeen) / 3600)
            )
        end
        list:drawText(seen, 8, y + 30, 0.7, 0.8, 0.8, 1, UIFont.Small)
        return y + 60
    end
    self:addChild(self.list)
    local cancel = ISButton:new(12, self.height - 42, 120, 30, "Cancel", self, function(p)
        p:close()
    end)
    cancel:initialise()
    self:addChild(cancel)
    local refresh = ISButton:new(142, self.height - 42, 120, 30, "Refresh", self, function(p)
        requestUsers()
        T.requestStats()
        p:populate()
    end)
    refresh:initialise()
    self:addChild(refresh)
    self.select = ISButton:new(
        self.width - 172,
        self.height - 42,
        160,
        30,
        self.actionLabel,
        self,
        function(p)
            local row = p.list.items[p.list.selected]
            if row then
                p.callback(row.item.username)
                p:close()
            end
        end
    )
    self.select:initialise()
    self:addChild(self.select)
    self:populate()
end
function AdminCoreAccountPicker:prerender()
    ISPanel.prerender(self)
    self:drawText(self.heading, 12, 12, 1, 1, 1, 1, UIFont.Medium)
    self.select:setEnable(self.list.items[self.list.selected] ~= nil)
end
function AdminCoreAccountPicker:close()
    self:removeFromUIManager()
    if T.directoryPanel == self then
        T.directoryPanel = nil
    end
end
function T.pickAccount(title, excluded, label, callback, offlineOnly)
    if T.directoryPanel then
        T.directoryPanel:close()
    end
    requestUsers()
    T.requestStats()
    local w, h =
        math.min(700, getCore():getScreenWidth() - 24),
        math.min(580, getCore():getScreenHeight() - 24)
    local p = ISPanel.new(AdminCoreAccountPicker, 20, 40, w, h)
    p.heading = title
    p.excluded = excluded
    p.callback = callback
    p.actionLabel = label
    p.moveWithMouse = true
    p.offlineOnly = offlineOnly
    p:initialise()
    p:addToUIManager()
    T.directoryPanel = p
end
Events.OnNetworkUsersReceived.Add(function()
    if T.directoryPanel then
        T.directoryPanel:populate()
        T.requestStats()
    end
end)

function T.replaceOwner(kind, id, username)
    if kind == "safehouse" then
        id = T.safehouseKey(id)
    end
    T.pickAccount("Choose replacement owner", username, "Transfer + remove", function(replacement)
        T.confirm(
            "Transfer "
                .. kind
                .. " ownership to "
                .. replacement
                .. " and remove "
                .. username
                .. "?",
            function()
                sendClientCommand(
                    "UniversalAdminCore",
                    "transferOwner",
                    { kind = kind, id = id, username = username, replacement = replacement }
                )
            end
        )
    end)
end

local function extendPicker(class, kind, cap)
    local init = class.initialise
    class.initialise = function(self)
        init(self)
        if not T.allowed(cap) then
            return
        end
        local b = ISButton:new(
            12,
            self.height + 5,
            250,
            30,
            "Offline accounts...",
            self,
            function(panel)
                local object = kind == "safehouse" and panel.safehouse or panel.faction
                local id = kind == "safehouse" and T.safehouseKey(object) or object:getName()
                local oldOwner = object:getOwner()
                if panel.changeOwnership then
                    -- This picker is a transfer-only vanilla action; use existing native ownership packet.
                    T.pickAccount(
                        "Choose offline owner",
                        oldOwner,
                        "Change owner",
                        function(username)
                            T.confirm("Transfer ownership to " .. username .. "?", function()
                                sendClientCommand("UniversalAdminCore", "transferOnly", {
                                    kind = kind,
                                    id = id,
                                    username = oldOwner,
                                    replacement = username,
                                })
                            end)
                        end,
                        true
                    )
                else
                    T.pickAccount(
                        "Add offline account (recent first)",
                        oldOwner,
                        "Add member",
                        function(username)
                            sendClientCommand(
                                "UniversalAdminCore",
                                "addMember",
                                { kind = kind, id = id, username = username }
                            )
                        end,
                        true
                    )
                end
                panel:setVisible(false)
                panel:removeFromUIManager()
                class.instance = nil
            end
        )
        b:initialise()
        self:addChild(b)
        self:setHeight(self.height + 45)
        T.fit(self, self.width, self.height)
    end
end
extendPicker(ISSafehouseAddPlayerUI, "safehouse", Capability.CanSetupSafehouses)
extendPicker(ISFactionAddPlayerUI, "faction", Capability.FactionCheat)
