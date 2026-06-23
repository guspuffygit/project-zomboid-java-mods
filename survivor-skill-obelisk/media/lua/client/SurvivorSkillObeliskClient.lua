--
-- SurvivorSkillObeliskClient.lua
-- Right-click on a placed obelisk -> "Recover Skills" context menu entry ->
-- ISCollapsableWindow with the player's past deaths fetched from the server.
--

require("TimedActions/RecoverSkillsAction")

local MODULE = "SurvivorSkillObelisk"
local LIST_COMMAND = "listDeaths"
local DEATHS_REPLY = "deathsList"
local RECOVERED_REPLY = "recoveredData"
-- SyncPlayerFieldsPacket bit flags: 1 = recipes, 4 = already-read books.
local SYNC_RECIPES_AND_BOOKS = 1 + 4
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
    local player = getSpecificPlayer(0)
    if player == nil then
        return
    end
    ISTimedActionQueue.add(RecoverSkillsAction:new(player, self.selectedDeathId))
    self:close()
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
    local screenW = getCore():getScreenWidth()
    local screenH = getCore():getScreenHeight()
    local bottomReserved = 220
    local x = math.floor(screenW / 2 - width / 2)
    local y = math.floor((screenH - bottomReserved) / 2 - height / 2)
    if y < 40 then
        y = 40
    end
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

local function onDeathsList(args)
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

local function iterateLuaArray(t, fn)
    if t == nil then
        return
    end
    local i = 1
    while true do
        local v = t[i]
        if v == nil then
            return
        end
        fn(v, i)
        i = i + 1
    end
end

local function applySkills(player, skills)
    iterateLuaArray(skills, function(entry)
        if entry.perk == nil then
            return
        end
        local perk = PerkFactory.getPerkFromName(entry.perk)
        if perk == nil then
            return
        end
        local targetXp = entry.xp or 0
        player:setPerkLevelDebug(perk, targetXp)
        player:getXp():setXPToLevel(perk, targetXp)
    end)
end

local function applyRecipes(player, recipes)
    iterateLuaArray(recipes, function(name)
        player:learnRecipe(name)
    end)
end

local function applyLiterature(player, literature)
    iterateLuaArray(literature, function(title)
        player:addReadLiterature(title)
    end)
end

local function applyPrintMedia(player, printMedia)
    iterateLuaArray(printMedia, function(id)
        player:addReadPrintMedia(id)
    end)
end

local function applyWatchedMedia(player, watchedMedia)
    local radio = getZomboidRadio()
    if radio == nil then
        return
    end
    local recordedMedia = radio:getRecordedMedia()
    if recordedMedia == nil then
        return
    end
    iterateLuaArray(watchedMedia, function(entry)
        if entry.mediaId == nil then
            return
        end
        local media = recordedMedia:getMediaData(entry.mediaId)
        if media == nil then
            return
        end
        if not entry.fullyWatched then
            -- We only snapshot per-media line counts, not the per-line GUIDs. Skip the
            -- partial-watch case rather than guess which lines were seen.
            return
        end
        for i = 0, media:getLineCount() - 1 do
            local line = media:getLine(i)
            if line then
                player:addKnownMediaLine(line:getTextGuid())
            end
        end
    end)
end

local function applyLearnedSongs(player, songs)
    local modData = player:getModData()
    if modData == nil then
        return
    end
    iterateLuaArray(songs, function(entry)
        if entry.instrument == nil or entry.name == nil then
            return
        end
        local key = entry.instrument .. "LearnedTracks"
        local list = modData[key]
        if list == nil then
            list = {}
            modData[key] = list
        end
        for i = 1, #list do
            if list[i] and list[i].name == entry.name then
                return
            end
        end
        table.insert(list, { name = entry.name, sound = entry.sound })
    end)
end

local function applyAmbitions(player, ambitions)
    local modData = player:getModData()
    if modData == nil then
        return
    end
    if modData.Ambitions == nil then
        modData.Ambitions = {}
    end
    iterateLuaArray(ambitions, function(entry)
        if entry.name == nil then
            return
        end
        local existing = modData.Ambitions[entry.name] or {}
        existing.name = entry.name
        if entry.cat ~= nil then
            existing.cat = entry.cat
        end
        existing.completed = entry.completed or existing.completed or false
        existing.isActive = entry.isActive or existing.isActive or false
        existing.isPassive = entry.isPassive or existing.isPassive or false
        for g = 1, 6 do
            local goalKey = "goal" .. g
            local progressKey = goalKey .. "progress"
            if entry[goalKey] ~= nil then
                existing[goalKey] = entry[goalKey]
            end
            if entry[progressKey] ~= nil then
                existing[progressKey] = entry[progressKey]
            end
        end
        modData.Ambitions[entry.name] = existing
    end)
end

local function onRecoveredData(args)
    local player = getSpecificPlayer(0)
    if player == nil or args == nil then
        return
    end
    applySkills(player, args.skills)
    applyRecipes(player, args.recipes)
    applyLiterature(player, args.literature)
    applyPrintMedia(player, args.printMedia)
    applyWatchedMedia(player, args.watchedMedia)
    applyLearnedSongs(player, args.learnedSongs)
    applyAmbitions(player, args.ambitions)
    sendSyncPlayerFields(player, SYNC_RECIPES_AND_BOOKS)
    HaloTextHelper.addGoodText(player, "Skills recovered")
end

local function onServerCommand(module, command, args)
    if module ~= MODULE then
        return
    end
    if command == DEATHS_REPLY then
        onDeathsList(args)
    elseif command == RECOVERED_REPLY then
        onRecoveredData(args)
    end
end

Events.OnServerCommand.Add(onServerCommand)
