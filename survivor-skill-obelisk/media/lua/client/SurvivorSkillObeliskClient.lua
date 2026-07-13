--
-- SurvivorSkillObeliskClient.lua
-- Right-click on a placed obelisk -> "Recover Skills" context menu entry ->
-- ISCollapsableWindow with the player's past deaths fetched from the server.
--

require("ISUI/ISCollapsableWindowJoypad")
require("TimedActions/RecoverSkillsAction")

local MODULE = "SurvivorSkillObelisk"
local LIST_COMMAND = "listDeaths"
local SET_TYPE_COMMAND = "setObeliskType"
local GET_TYPE_COMMAND = "getObeliskType"
local DEATHS_REPLY = "deathsList"
local RECOVERED_REPLY = "recoveredData"
local TYPE_REPLY = "obeliskType"
-- SyncPlayerFieldsPacket bit flags: 1 = recipes, 4 = already-read books.
local SYNC_RECIPES_AND_BOOKS = 1 + 4
local SPRITE_PREFIX = "atf_obelisks_"
local DEFAULT_LIMIT = 20
local NONE_TYPE = "None"

local SurvivorSkillObelisk = {}
local openWindow = nil
local openConfigureWindow = nil

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function isObeliskSpriteName(name)
    if name == nil then
        return false
    end
    if string.sub(name, 1, #SPRITE_PREFIX) ~= SPRITE_PREFIX then
        return false
    end
    -- The `_on` companion tilesheets are packed with the base sprites but
    -- never appear as world objects; belt-and-braces filter in case a future
    -- refactor changes that.
    if string.find(name, "_on_", 1, true) then
        return false
    end
    return true
end

local function isObeliskObject(obj)
    if obj == nil then
        return false
    end
    local sprite = obj:getSprite()
    if sprite == nil then
        return false
    end
    return isObeliskSpriteName(sprite:getName())
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

local function isPlayerAdmin()
    if getDebug() then
        return true
    end
    if isClient() and getAccessLevel() == "admin" then
        return true
    end
    return false
end

local function perkDisplayName(typeId)
    if typeId == nil or typeId == "" or typeId == NONE_TYPE then
        return NONE_TYPE
    end
    local perk = PerkFactory.Perks.FromString(typeId)
    if perk == nil then
        return typeId
    end
    return perk:getName()
end

local function collectSkillPerks()
    local perks = {}
    local list = PerkFactory.PerkList
    if list == nil then
        return perks
    end
    for i = 0, list:size() - 1 do
        local perk = list:get(i)
        if perk ~= nil then
            table.insert(perks, { id = perk:getId(), name = perk:getName() })
        end
    end
    table.sort(perks, function(a, b)
        return a.name < b.name
    end)
    return perks
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

-- List subclass so a controller player can press A on a highlighted past life
-- to recover it, and B to close the whole window in one press.
local RecoverDeathList = ISScrollingListBox:derive("RecoverDeathList")

function RecoverDeathList:onJoypadDown(button, joypadData)
    if button == Joypad.BButton and self.recoverWindow then
        self.recoverWindow:close()
        return
    end
    -- Base impl indexes items[selected] unconditionally on A; that crashes on an
    -- empty list (still loading, or no past lives). Swallow the press instead.
    if button == Joypad.AButton and (#self.items == 0 or not self.items[self.selected]) then
        return
    end
    ISScrollingListBox.onJoypadDown(self, button, joypadData)
end

local RecoverSkillsWindow = ISCollapsableWindowJoypad:derive("RecoverSkillsWindow")

function RecoverSkillsWindow:new(x, y, width, height, playerNum)
    local o = ISCollapsableWindowJoypad.new(self, x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o.baseTitle = "Recover Skills"
    o.title = o.baseTitle
    o.rows = {}
    o.loading = true
    o.selectedDeathId = nil
    o.obeliskX = nil
    o.obeliskY = nil
    o.obeliskZ = nil
    o.resizable = false
    o.minimumWidth = width
    o.minimumHeight = height
    o.playerNum = playerNum or 0
    return o
end

function RecoverSkillsWindow:setObelisk(x, y, z)
    self.obeliskX = x
    self.obeliskY = y
    self.obeliskZ = z
    self.title = self.baseTitle
end

function RecoverSkillsWindow:setObeliskType(typeId)
    if typeId == nil or typeId == "" or typeId == NONE_TYPE then
        self.title = self.baseTitle
    else
        self.title = self.baseTitle .. " - " .. perkDisplayName(typeId)
    end
end

function RecoverSkillsWindow:createChildren()
    ISCollapsableWindowJoypad.createChildren(self)

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
    self.listBox = RecoverDeathList:new(padding, listY, self.width - padding * 2, listH)
    self.listBox:initialise()
    self.listBox:instantiate()
    self.listBox.itemheight = 22
    self.listBox.font = UIFont.Small
    self.listBox.drawBorder = true
    self.listBox.doDrawItem = RecoverSkillsWindow.drawListItem
    self.listBox.onMouseDown = RecoverSkillsWindow.onRowClicked
    self.listBox.target = self
    self.listBox.recoverWindow = self
    self.listBox.overrideAButtonFunction = RecoverSkillsWindow.onListJoypadA
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

function RecoverSkillsWindow.onListJoypadA(window, item)
    if window == nil or item == nil or item.id == nil then
        return
    end
    window.selectedDeathId = item.id
    window:onRecover()
end

function RecoverSkillsWindow:onGainJoypadFocus(joypadData)
    ISCollapsableWindowJoypad.onGainJoypadFocus(self, joypadData)
    self.drawJoypadFocus = false
    if self.listBox then
        self.listBox:setJoypadFocused(true, joypadData)
        setJoypadFocus(self.playerNum, self.listBox)
    end
end

function RecoverSkillsWindow:onLoseJoypadFocus(joypadData)
    ISCollapsableWindowJoypad.onLoseJoypadFocus(self, joypadData)
    if self.listBox then
        self.listBox:setJoypadFocused(false, joypadData)
    end
end

function RecoverSkillsWindow:onJoypadDown(button, joypadData)
    if button == Joypad.BButton then
        self:close()
        return
    end
    ISCollapsableWindowJoypad.onJoypadDown(self, button, joypadData)
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

local function buildSkillTooltip(row)
    local skills = row.skills
    if skills == nil or skills[1] == nil then
        return nil
    end
    local lines = {}
    local i = 1
    while skills[i] ~= nil do
        local s = skills[i]
        local xp = s.xp or 0
        if xp > 0 then
            table.insert(lines, string.format("%s: %d xp", s.perk or "?", math.floor(xp + 0.5)))
        end
        i = i + 1
    end
    if #lines == 0 then
        return "(no XP earned)"
    end
    return table.concat(lines, "\n")
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
        self.listBox:addItem("", row, buildSkillTooltip(row))
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
    local player = getSpecificPlayer(self.playerNum or 0)
    if player == nil then
        return
    end
    ISTimedActionQueue.add(
        RecoverSkillsAction:new(
            player,
            self.selectedDeathId,
            self.obeliskX,
            self.obeliskY,
            self.obeliskZ
        )
    )
    self:close()
end

function RecoverSkillsWindow:close()
    openWindow = nil
    self:setVisible(false)
    self:removeFromUIManager()
    if JoypadState.players and JoypadState.players[(self.playerNum or 0) + 1] then
        setJoypadFocus(self.playerNum or 0, nil)
    end
end

---------------------------------------------------------------------------
-- Configure Obelisk (admin)
---------------------------------------------------------------------------

local ConfigureObeliskWindow = ISCollapsableWindow:derive("ConfigureObeliskWindow")

function ConfigureObeliskWindow:new(x, y, width, height, obeliskX, obeliskY, obeliskZ)
    local o = ISCollapsableWindow:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o.title = "Configure Obelisk"
    o.obeliskX = obeliskX
    o.obeliskY = obeliskY
    o.obeliskZ = obeliskZ
    o.resizable = false
    o.minimumWidth = width
    o.minimumHeight = height
    return o
end

function ConfigureObeliskWindow:createChildren()
    ISCollapsableWindow.createChildren(self)

    local titleBarH = self:titleBarHeight()
    local padding = 10
    local rowH = 24
    local labelY = titleBarH + padding

    self.skillLabel =
        ISLabel:new(padding, labelY + 4, 18, "Skill type:", 1, 1, 1, 1, UIFont.Small, true)
    self.skillLabel:initialise()
    self.skillLabel:instantiate()
    self:addChild(self.skillLabel)

    local comboX = padding + 90
    local comboW = self.width - comboX - padding
    self.skillCombo = ISComboBox:new(comboX, labelY, comboW, rowH)
    self.skillCombo:initialise()
    self.skillCombo:instantiate()
    self.skillCombo:addOptionWithData(NONE_TYPE, NONE_TYPE)
    for _, perk in ipairs(collectSkillPerks()) do
        self.skillCombo:addOptionWithData(perk.name, perk.id)
    end
    self.skillCombo.selected = 1
    self:addChild(self.skillCombo)

    self:requestCurrentType()

    local btnW = 100
    local btnH = 24
    local btnY = self.height - padding - btnH

    self.saveBtn = ISButton:new(
        self.width - padding - btnW,
        btnY,
        btnW,
        btnH,
        "Save",
        self,
        ConfigureObeliskWindow.onSave
    )
    self.saveBtn:initialise()
    self.saveBtn:instantiate()
    self.saveBtn.anchorTop = false
    self.saveBtn.anchorBottom = true
    self.saveBtn.anchorRight = true
    self.saveBtn.anchorLeft = false
    self:addChild(self.saveBtn)

    self.cancelBtn = ISButton:new(
        self.width - padding * 2 - btnW * 2,
        btnY,
        btnW,
        btnH,
        "Cancel",
        self,
        ConfigureObeliskWindow.onCancel
    )
    self.cancelBtn:initialise()
    self.cancelBtn:instantiate()
    self.cancelBtn.anchorTop = false
    self.cancelBtn.anchorBottom = true
    self.cancelBtn.anchorRight = true
    self.cancelBtn.anchorLeft = false
    self:addChild(self.cancelBtn)
end

function ConfigureObeliskWindow:requestCurrentType()
    local player = getSpecificPlayer(0)
    if player == nil then
        return
    end
    sendClientCommand(player, MODULE, GET_TYPE_COMMAND, {
        x = self.obeliskX,
        y = self.obeliskY,
        z = self.obeliskZ,
    })
end

function ConfigureObeliskWindow:applyType(typeId)
    if self.skillCombo == nil then
        return
    end
    if typeId == nil or typeId == "" then
        typeId = NONE_TYPE
    end
    local options = self.skillCombo.options
    if options == nil then
        return
    end
    for i = 1, #options do
        if options[i].data == typeId then
            self.skillCombo.selected = i
            return
        end
    end
    -- Unknown type (e.g. perk from a since-removed mod) — leave combo at default.
end

function ConfigureObeliskWindow:onSave()
    local player = getSpecificPlayer(0)
    if player == nil then
        return
    end
    local selected = self.skillCombo:getOptionData(self.skillCombo.selected)
    if selected == nil then
        selected = NONE_TYPE
    end
    sendClientCommand(player, MODULE, SET_TYPE_COMMAND, {
        type = selected,
        x = self.obeliskX,
        y = self.obeliskY,
        z = self.obeliskZ,
    })
    self:close()
end

function ConfigureObeliskWindow:onCancel()
    self:close()
end

function ConfigureObeliskWindow:close()
    openConfigureWindow = nil
    self:setVisible(false)
    self:removeFromUIManager()
end

function SurvivorSkillObelisk.openConfigureWindow(worldobjects)
    local obj = findObeliskInWorldObjects(worldobjects)
    if obj == nil then
        return
    end
    local square = obj:getSquare()
    if square == nil then
        return
    end
    if openConfigureWindow ~= nil then
        openConfigureWindow:close()
    end
    local width = 360
    local height = 130
    local screenW = getCore():getScreenWidth()
    local screenH = getCore():getScreenHeight()
    local x = math.floor(screenW / 2 - width / 2)
    local y = math.floor(screenH / 2 - height / 2)
    local w =
        ConfigureObeliskWindow:new(x, y, width, height, square:getX(), square:getY(), square:getZ())
    w:initialise()
    w:addToUIManager()
    openConfigureWindow = w
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

function SurvivorSkillObelisk.requestDeaths()
    local player = getSpecificPlayer(0)
    if player == nil or openWindow == nil then
        return
    end
    sendClientCommand(player, MODULE, LIST_COMMAND, {
        limit = DEFAULT_LIMIT,
        x = openWindow.obeliskX,
        y = openWindow.obeliskY,
        z = openWindow.obeliskZ,
    })
end

function SurvivorSkillObelisk.openRecoverWindow(worldobjects, playerNum)
    playerNum = playerNum or 0
    local obj = findObeliskInWorldObjects(worldobjects)
    local square = obj and obj:getSquare() or nil
    local ox = square and square:getX() or nil
    local oy = square and square:getY() or nil
    local oz = square and square:getZ() or nil
    local usingJoypad = JoypadState.players and JoypadState.players[playerNum + 1] ~= nil

    if openWindow ~= nil then
        openWindow.playerNum = playerNum
        openWindow:setObelisk(ox, oy, oz)
        openWindow:setVisible(true)
        openWindow:addToUIManager()
        openWindow.loading = true
        openWindow:updateStatus()
        SurvivorSkillObelisk.requestDeaths()
        if usingJoypad then
            setJoypadFocus(playerNum, openWindow)
        end
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
    local w = RecoverSkillsWindow:new(x, y, width, height, playerNum)
    w:setObelisk(ox, oy, oz)
    w:initialise()
    w:addToUIManager()
    openWindow = w
    SurvivorSkillObelisk.requestDeaths()
    if usingJoypad then
        setJoypadFocus(playerNum, w)
    end
end

---------------------------------------------------------------------------
-- Context menu hook
---------------------------------------------------------------------------

local function onFillWorldObjectContextMenu(player, context, worldobjects, test)
    if findObeliskInWorldObjects(worldobjects) == nil then
        return
    end
    -- On controller, PZ calls this once with test=true just to see if any handler
    -- has anything to add. setTest() signals that we do; the menu will then be
    -- opened for real and this function called again with test=false.
    if test == true then
        return ISWorldObjectContextMenu.setTest()
    end
    context:addOption(
        "Recover Skills",
        worldobjects,
        SurvivorSkillObelisk.openRecoverWindow,
        player
    )
    if isPlayerAdmin() then
        context:addOption(
            "Configure Obelisk",
            worldobjects,
            SurvivorSkillObelisk.openConfigureWindow
        )
    end
end

Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)

---------------------------------------------------------------------------
-- Server reply
---------------------------------------------------------------------------

local function onDeathsList(args)
    if openWindow == nil then
        return
    end
    openWindow:setObeliskType(args and args.type or NONE_TYPE)
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

-- Sandbox-synced to the client by PZ; nil before world load, so guard.
-- Skills are already scaled server-side in RecoverSkillsHandler — ambitions are
-- scaled client-side because the goal/progress decode lives here.
local function getRecoveryPercent()
    local sv = SandboxVars and SandboxVars.SkillObelisk
    local percent = sv and sv.SkillRecoveryPercent
    if type(percent) ~= "number" then
        return 1.0
    end
    if percent < 0 then
        return 0
    end
    if percent > 100 then
        return 1.0
    end
    return percent / 100.0
end

local function applyAmbitions(player, ambitions)
    local modData = player:getModData()
    if modData == nil then
        return
    end
    if modData.Ambitions == nil then
        modData.Ambitions = {}
    end
    local percent = getRecoveryPercent()
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
                -- Lifestyles goal slots are heterogeneous (number target, string
                -- flag, boolean). Only scale numbers; flags pass through verbatim.
                local value = entry[progressKey]
                if type(value) == "number" then
                    existing[progressKey] = value * percent
                else
                    existing[progressKey] = value
                end
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

    applyRecipes(player, args.recipes)
    applyLiterature(player, args.literature)
    applyPrintMedia(player, args.printMedia)
    applyWatchedMedia(player, args.watchedMedia)
    applyLearnedSongs(player, args.learnedSongs)
    applyAmbitions(player, args.ambitions)
    sendSyncPlayerFields(player, SYNC_RECIPES_AND_BOOKS)
    HaloTextHelper.addGoodText(player, "Skills recovered")
end

local function onObeliskType(args)
    if openConfigureWindow == nil or args == nil then
        return
    end
    if
        args.x ~= openConfigureWindow.obeliskX
        or args.y ~= openConfigureWindow.obeliskY
        or args.z ~= openConfigureWindow.obeliskZ
    then
        return
    end
    openConfigureWindow:applyType(args.type)
end

local function onServerCommand(module, command, args)
    if module ~= MODULE then
        return
    end
    if command == DEATHS_REPLY then
        onDeathsList(args)
    elseif command == RECOVERED_REPLY then
        onRecoveredData(args)
    elseif command == TYPE_REPLY then
        onObeliskType(args)
    end
end

Events.OnServerCommand.Add(onServerCommand)
