--
-- SurvivorSkillObeliskClient.lua
-- Right-click on a placed obelisk -> "Recover Skills" context menu entry ->
-- ISCollapsableWindow with the player's past deaths fetched from the server.
--

local MODULE = "SurvivorSkillObelisk"
local LIST_COMMAND = "listDeaths"
local DEATHS_REPLY = "deathsList"
local SPRITE_PREFIX = "survivor_skill_obelisk_"
local DEFAULT_LIMIT = 200

local SurvivorSkillObelisk = {}
local openWindow = nil

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function isObeliskObject(obj)
    if obj == nil then
        return false
    end
    local sprite = obj:getSprite()
    if sprite == nil then
        return false
    end
    local name = sprite:getName()
    if name == nil then
        return false
    end
    return string.sub(name, 1, #SPRITE_PREFIX) == SPRITE_PREFIX
end

local function findObeliskInWorldObjects(worldobjects)
    if worldobjects == nil then
        return nil
    end
    for i = 1, #worldobjects do
        local obj = worldobjects[i]
        if isObeliskObject(obj) then
            return obj
        end
    end
    return nil
end

local function formatTime(tsMillis)
    if tsMillis == nil then
        return ""
    end
    return os.date("%Y-%m-%d %H:%M", math.floor(tsMillis / 1000))
end

local function formatName(row)
    local fore = row.forename or ""
    local sur = row.surname or ""
    local full = (fore .. " " .. sur):gsub("^%s+", ""):gsub("%s+$", "")
    if full == "" then
        return row.username or "?"
    end
    return full
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------

local RecoverSkillsWindow = ISCollapsableWindow:derive("RecoverSkillsWindow")

function RecoverSkillsWindow:new(x, y, width, height)
    local o = ISCollapsableWindow:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o.title = "Recover Skills"
    o.rows = {}
    o.loading = true
    o.selectedDeathId = nil
    o.resizable = true
    o.minimumWidth = 480
    o.minimumHeight = 280
    return o
end

function RecoverSkillsWindow:createChildren()
    ISCollapsableWindow.createChildren(self)

    local titleBarH = self:titleBarHeight()
    local padding = 6
    local btnH = 24

    self.statusLabel = ISLabel:new(
        padding,
        titleBarH + padding + 2,
        18,
        "Loading...",
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

    local listY = titleBarH + padding + 22
    local listH = self.height - listY - padding - btnH - padding
    self.listBox = ISScrollingListBox:new(padding, listY, self.width - padding * 2, listH)
    self.listBox:initialise()
    self.listBox:instantiate()
    self.listBox.itemheight = 22
    self.listBox.font = UIFont.Small
    self.listBox.drawBorder = true
    self.listBox.doDrawItem = RecoverSkillsWindow.drawListItem
    self.listBox.onMouseDown = RecoverSkillsWindow.onRowClicked
    self.listBox.target = self
    self:addChild(self.listBox)

    self.recoverBtn = ISButton:new(
        self.width - padding - 140,
        self.height - padding - btnH,
        140,
        btnH,
        "Recover Skills",
        self,
        RecoverSkillsWindow.onRecover
    )
    self.recoverBtn:initialise()
    self.recoverBtn:instantiate()
    self.recoverBtn:setEnable(false)
    self.recoverBtn.anchorTop = false
    self.recoverBtn.anchorBottom = true
    self.recoverBtn.anchorRight = true
    self.recoverBtn.anchorLeft = false
    self:addChild(self.recoverBtn)
end

function RecoverSkillsWindow:onResize()
    ISCollapsableWindow.onResize(self)
    local titleBarH = self:titleBarHeight()
    local padding = 6
    local btnH = 24
    local listY = titleBarH + padding + 22
    if self.listBox then
        self.listBox:setWidth(self.width - padding * 2)
        self.listBox:setHeight(self.height - listY - padding - btnH - padding)
    end
    if self.recoverBtn then
        self.recoverBtn:setX(self.width - padding - self.recoverBtn:getWidth())
        self.recoverBtn:setY(self.height - padding - btnH)
    end
end

function RecoverSkillsWindow:drawListItem(y, item, alt)
    if alt then
        self:drawRect(0, y, self:getWidth(), self.itemheight, 0.15, 0.5, 0.5, 0.5)
    end
    self:drawRectBorder(0, y, self:getWidth(), self.itemheight, 0.3, 0.4, 0.4, 0.4)

    local row = item.item
    if self.selected == row._index then
        self:drawRect(0, y, self:getWidth(), self.itemheight, 0.3, 0.7, 0.35, 0.15)
    end

    local hours = row.hoursSurvived or 0
    local text = string.format(
        "%s   %s   %.1f h   %d zk",
        formatTime(row.ts),
        formatName(row),
        hours,
        row.zombieKills or 0
    )
    self:drawText(text, 6, y + 4, 1, 1, 1, 1, UIFont.Small)

    return y + self.itemheight
end

function RecoverSkillsWindow.onRowClicked(self, x, y)
    ISScrollingListBox.onMouseDown(self, x, y)
    local parent = self.target
    if parent == nil then
        return
    end
    local row = self.items and self.items[self.selected] and self.items[self.selected].item
    if row == nil then
        parent.selectedDeathId = nil
        parent.recoverBtn:setEnable(false)
        return
    end
    parent.selectedDeathId = row.id
    parent.recoverBtn:setEnable(true)
end

function RecoverSkillsWindow:populate(rows)
    self.loading = false
    self.rows = rows or {}
    self.listBox:clear()
    self.selectedDeathId = nil
    if self.recoverBtn then
        self.recoverBtn:setEnable(false)
    end
    for i = 1, #self.rows do
        local row = self.rows[i]
        row._index = i
        self.listBox:addItem("", row)
    end
    self:updateStatus()
end

function RecoverSkillsWindow:updateStatus()
    if self.statusLabel == nil then
        return
    end
    if self.loading then
        self.statusLabel:setName("Loading...")
    elseif #self.rows == 0 then
        self.statusLabel:setName("No past lives recorded for this character.")
    else
        self.statusLabel:setName(string.format("%d past lives (most recent first)", #self.rows))
    end
end

function RecoverSkillsWindow:onRecover()
    if self.selectedDeathId == nil then
        return
    end
    -- TODO: send a "recoverSkills" client command with self.selectedDeathId.
    print(
        string.format(
            "[SurvivorSkillObelisk] Recover Skills clicked for death id=%s",
            tostring(self.selectedDeathId)
        )
    )
end

function RecoverSkillsWindow:close()
    openWindow = nil
    self:setVisible(false)
    self:removeFromUIManager()
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

function SurvivorSkillObelisk.requestDeaths()
    local player = getSpecificPlayer(0)
    if player == nil then
        return
    end
    sendClientCommand(player, MODULE, LIST_COMMAND, { limit = DEFAULT_LIMIT })
end

function SurvivorSkillObelisk.openRecoverWindow()
    if openWindow ~= nil then
        openWindow:setVisible(true)
        openWindow:addToUIManager()
        openWindow.loading = true
        openWindow:updateStatus()
        SurvivorSkillObelisk.requestDeaths()
        return
    end
    local width = 560
    local height = 360
    local x = math.floor(getCore():getScreenWidth() / 2 - width / 2)
    local y = math.floor(getCore():getScreenHeight() / 2 - height / 2)
    local w = RecoverSkillsWindow:new(x, y, width, height)
    w:initialise()
    w:addToUIManager()
    openWindow = w
    SurvivorSkillObelisk.requestDeaths()
end

---------------------------------------------------------------------------
-- Context menu hook
---------------------------------------------------------------------------

local function onFillWorldObjectContextMenu(player, context, worldobjects, test)
    if test and ISWorldObjectContextMenu.Test then
        return true
    end
    if findObeliskInWorldObjects(worldobjects) == nil then
        return
    end
    context:addOption("Recover Skills", worldobjects, SurvivorSkillObelisk.openRecoverWindow)
end

Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)

---------------------------------------------------------------------------
-- Server reply
---------------------------------------------------------------------------

local function onServerCommand(module, command, args)
    if module ~= MODULE then
        return
    end
    if command ~= DEATHS_REPLY then
        return
    end
    if openWindow == nil then
        return
    end
    local rows = {}
    if args and args.rows then
        local count = args.count or 0
        for i = 1, count do
            local r = args.rows[i]
            if r then
                table.insert(rows, r)
            end
        end
    end
    openWindow:populate(rows)
end

Events.OnServerCommand.Add(onServerCommand)
