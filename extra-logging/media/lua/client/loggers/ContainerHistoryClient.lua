--
-- ContainerHistoryClient.lua
-- Adds a "History" button on world-container inventory panels. Clicking sends a
-- queryContainerHistory client command to the server (handled by the extra-logging
-- mod's QueryContainerHistoryHandler) and displays the resulting transfer rows.
--

local MODULE = "ExtraLogging"
local QUERY_COMMAND = "queryContainerHistory"
local REPLY_COMMAND = "containerHistory"
local DEFAULT_LIMIT = 200

local ContainerHistory = {}
local openWindows = {} -- ref -> ContainerHistoryWindow

---------------------------------------------------------------------------
-- Container ref builder
--
-- Mirrors io.pzstorm.storm.transfer.StormTransferHandler.resolveContainer
-- so the strings sent here match those stored by the server-side handler.
---------------------------------------------------------------------------

local function buildContainerRef(container, character)
    if container == nil then
        return nil
    end
    if character and container == character:getInventory() then
        return "player"
    end

    local containingItem = container:getContainingItem()
    if containingItem and character and container:isInCharacterInventory(character) then
        return "bag:" .. tostring(containingItem:getID())
    end

    local part = container:getVehiclePart()
    if part then
        local vehicle = part:getVehicle()
        if vehicle then
            return "vehicle:" .. tostring(vehicle:getId()) .. ":" .. tostring(part:getIndex())
        end
    end

    local parent = container:getParent()
    if parent and parent:getSquare() then
        local sq = parent:getSquare()
        local objects = sq:getObjects()
        local objectIndex = -1
        for i = 0, objects:size() - 1 do
            if objects:get(i) == parent then
                objectIndex = i
                break
            end
        end
        if objectIndex >= 0 then
            local containerIndex = parent:getContainerIndex(container)
            return "object:"
                .. tostring(sq:getX())
                .. ":"
                .. tostring(sq:getY())
                .. ":"
                .. tostring(sq:getZ())
                .. ":"
                .. tostring(objectIndex)
                .. ":"
                .. tostring(containerIndex)
        end
    end

    if containingItem and containingItem:getWorldItem() then
        local worldItem = containingItem:getWorldItem()
        local sq = worldItem:getSquare()
        if sq then
            local objects = sq:getObjects()
            local objectIndex = -1
            for i = 0, objects:size() - 1 do
                if objects:get(i) == worldItem then
                    objectIndex = i
                    break
                end
            end
            if objectIndex >= 0 then
                return "worlditem:"
                    .. tostring(sq:getX())
                    .. ":"
                    .. tostring(sq:getY())
                    .. ":"
                    .. tostring(sq:getZ())
                    .. ":"
                    .. tostring(objectIndex)
            end
        end
    end

    return nil
end

local function isWorldContainerRef(ref)
    if ref == nil then
        return false
    end
    return ref:sub(1, 7) == "object:" or ref:sub(1, 10) == "worlditem:"
end

local function isPlayerAdmin()
    if not isClient() then
        return true
    end
    local player = getPlayer()
    if player == nil then
        return false
    end
    local role = player:getRole()
    if role == nil then
        return false
    end
    return role:getName() == "admin"
end

---------------------------------------------------------------------------
-- History window
---------------------------------------------------------------------------

local ContainerHistoryWindow = ISCollapsableWindow:derive("ContainerHistoryWindow")

function ContainerHistoryWindow:new(x, y, width, height, containerRef)
    local o = ISCollapsableWindow:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o.title = "Container History"
    o.containerRef = containerRef
    o.rows = {}
    o.loading = true
    o.resizable = true
    o.minimumWidth = 400
    o.minimumHeight = 200
    return o
end

function ContainerHistoryWindow:createChildren()
    ISCollapsableWindow.createChildren(self)

    local titleBarH = self:titleBarHeight()
    local padding = 6
    local btnW, btnH = 80, 22

    self.refreshBtn = ISButton:new(
        padding,
        titleBarH + padding,
        btnW,
        btnH,
        "Refresh",
        self,
        ContainerHistoryWindow.onRefresh
    )
    self.refreshBtn:initialise()
    self.refreshBtn:instantiate()
    self:addChild(self.refreshBtn)

    self.statusLabel = ISLabel:new(
        padding + btnW + 12,
        titleBarH + padding + 2,
        18,
        "",
        1,
        1,
        1,
        1,
        UIFont.Small,
        true
    )
    self.statusLabel:initialise()
    self.statusLabel:instantiate()
    self:addChild(self.statusLabel)

    local listY = titleBarH + padding + btnH + padding
    self.listBox = ISScrollingListBox:new(
        padding,
        listY,
        self.width - padding * 2,
        self.height - listY - padding
    )
    self.listBox:initialise()
    self.listBox:instantiate()
    self.listBox.itemheight = 20
    self.listBox.font = UIFont.Small
    self.listBox.drawBorder = true
    self.listBox.doDrawItem = ContainerHistoryWindow.drawListItem
    self:addChild(self.listBox)
end

function ContainerHistoryWindow:onResize()
    ISCollapsableWindow.onResize(self)
    local titleBarH = self:titleBarHeight()
    local padding = 6
    local btnH = 22
    local listY = titleBarH + padding + btnH + padding
    if self.listBox then
        self.listBox:setWidth(self.width - padding * 2)
        self.listBox:setHeight(self.height - listY - padding)
    end
end

local function formatTime(tsMillis)
    local secs = math.floor(tsMillis / 1000)
    return os.date("%Y-%m-%d %H:%M:%S", secs)
end

local function describeOtherSide(row, ourRef)
    local other
    if row.srcRef == ourRef then
        other = row.destRef
    else
        other = row.srcRef
    end

    if other == "player" then
        return "player inv"
    end
    if type(other) == "string" then
        if other:sub(1, 4) == "bag:" then
            return "bag " .. other:sub(5)
        end
        if other:sub(1, 7) == "object:" then
            return "world container"
        end
        if other:sub(1, 10) == "worlditem:" then
            return "placed container"
        end
        if other:sub(1, 8) == "vehicle:" then
            return "vehicle"
        end
        if other:sub(1, 5) == "loot:" then
            return "loot generation"
        end
    end
    return tostring(other)
end

function ContainerHistoryWindow:drawListItem(y, item, alt)
    if alt then
        self:drawRect(0, y, self:getWidth(), self.itemheight, 0.15, 0.5, 0.5, 0.5)
    end
    self:drawRectBorder(0, y, self:getWidth(), self.itemheight, 0.3, 0.4, 0.4, 0.4)

    local row = item.item
    local ourRef = self.parent.containerRef
    local direction
    local color
    if row.destRef == ourRef then
        direction = "+ put"
        color = { r = 0.6, g = 1.0, b = 0.6 }
    elseif row.srcRef == ourRef then
        direction = "- took"
        color = { r = 1.0, g = 0.7, b = 0.7 }
    else
        direction = "?"
        color = { r = 1.0, g = 1.0, b = 1.0 }
    end

    local text = string.format(
        "%s  %s  %s  %s  (%s)",
        formatTime(row.ts),
        row.player,
        direction,
        row.itemName or row.itemType,
        describeOtherSide(row, ourRef)
    )
    self:drawText(text, 6, y + 4, color.r, color.g, color.b, 1, UIFont.Small)

    return y + self.itemheight
end

function ContainerHistoryWindow:populate(rows)
    self.loading = false
    self.rows = rows or {}
    self.listBox:clear()
    for i = 1, #self.rows do
        self.listBox:addItem("", self.rows[i])
    end
    self:updateStatus()
end

function ContainerHistoryWindow:updateStatus()
    if not self.statusLabel then
        return
    end
    if self.loading then
        self.statusLabel:setName("Loading...")
    else
        self.statusLabel:setName(string.format("%d entries (most recent first)", #self.rows))
    end
end

function ContainerHistoryWindow:onRefresh()
    self.loading = true
    self:updateStatus()
    ContainerHistory.requestHistory(self.containerRef)
end

function ContainerHistoryWindow:close()
    openWindows[self.containerRef] = nil
    self:setVisible(false)
    self:removeFromUIManager()
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

function ContainerHistory.requestHistory(containerRef)
    if not isPlayerAdmin() then
        return
    end
    local character = getSpecificPlayer(0)
    if character == nil then
        return
    end
    sendClientCommand(character, MODULE, QUERY_COMMAND, {
        ref = containerRef,
        limit = DEFAULT_LIMIT,
    })
end

function ContainerHistory.openWindowForRef(ref)
    if not isPlayerAdmin() then
        return
    end
    if not isWorldContainerRef(ref) then
        return
    end

    local existing = openWindows[ref]
    if existing then
        existing:setVisible(true)
        existing:addToUIManager()
        existing:onRefresh()
        return
    end

    local w = ContainerHistoryWindow:new(
        getCore():getScreenWidth() / 2 - 350,
        getCore():getScreenHeight() / 2 - 200,
        700,
        400,
        ref
    )
    w:initialise()
    w:addToUIManager()
    openWindows[ref] = w
    ContainerHistory.requestHistory(ref)
end

---------------------------------------------------------------------------
-- Loot window control handler
--
-- Registers a "History" button alongside the vanilla "Transfer to Floor" /
-- "Delete All" buttons in ISLootWindowContainerControls. arrange() lays
-- left-side handlers out in registration order, so adding ours after RemoveAll
-- puts the History button to the right of both.
---------------------------------------------------------------------------

require("ISUI/LootWindow/ISLootWindowObjectControlHandler")

ContainerHistoryControlHandler =
    ISLootWindowObjectControlHandler:derive("ContainerHistoryControlHandler")
local Handler = ContainerHistoryControlHandler

function Handler:shouldBeVisible()
    if not isPlayerAdmin() then
        return false
    end
    if self.container == nil then
        return false
    end
    local ref = buildContainerRef(self.container, self.playerObj)
    if not isWorldContainerRef(ref) then
        return false
    end
    self.containerRef = ref
    return true
end

function Handler:getControl()
    self.control = self:getButtonControl("History")
    self.control.tooltip = "Show take/put history for this container"
    return self.control
end

function Handler:perform()
    if self.containerRef then
        ContainerHistory.openWindowForRef(self.containerRef)
    end
end

ISLootWindowContainerControls.AddHandler(ContainerHistoryControlHandler)

---------------------------------------------------------------------------
-- Server reply listener
---------------------------------------------------------------------------

local function onServerCommand(module, command, args)
    if module ~= MODULE then
        return
    end
    if command ~= REPLY_COMMAND then
        return
    end
    if args == nil or args.ref == nil then
        return
    end

    local w = openWindows[args.ref]
    if w == nil then
        return
    end

    local rows = {}
    if args.rows then
        for i = 1, args.count or 0 do
            local r = args.rows[i]
            if r then
                table.insert(rows, r)
            end
        end
    end
    w:populate(rows)
end

Events.OnServerCommand.Add(onServerCommand)
