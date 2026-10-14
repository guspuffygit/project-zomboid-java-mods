require("ISUI/ISPanelJoypad")
require("OptionScreens/MapSpawnSelect")
require("OptionScreens/CoopMapSpawnSelect")
require("OptionScreens/CoopCharacterCreation")
require("OptionScreens/CharacterCreationMain")
require("ISUI/UserPanel/ISSafehouseUI")

-- Keep the native location/map screen and other mods' region providers intact.
-- A safehouse is an explicit, server-confirmed choice for one creation attempt.
AdminSafehouseRespawn = AdminSafehouseRespawn or {}
local R = AdminSafehouseRespawn
if R.installed then
    return
end
R.installed = true
R.windows = {}
R.accepted = {}
R.creationErrors = {}
R.requestAfter = 0
local serial = 0
local function supported()
    return isClient()
        and AdminCoreRespawnBridge ~= nil
        and AdminCoreRespawnBridge.requestChoices ~= nil
        and not getCore():isChallenge()
        and not Core.isLastStand()
end
local function slot()
    if MainScreen.instance.inGame and CoopCharacterCreation.instance then
        return CoopCharacterCreation.instance.playerIndex
    end
    return 0
end
local function nonce()
    serial = serial + 1
    return tostring(getTimestampMs()) .. ":" .. tostring(serial)
end
local function clean(value, fallback)
    local text = type(value) == "string" and value or fallback or ""
    return string.sub(text, 1, 160):gsub("[<>\r\n]", " ")
end
local function coordinate(value)
    return type(value) == "number" and value == value and math.abs(value) < 10000000
end
local function updateCheckbox()
    local panel = R.safehousePanel
    if not panel or not panel.respawn then
        return
    end
    local hide = R.serverEnabled == true or R.infoRequest ~= nil
    panel.respawn:setVisible(not hide)
    panel.respawn.enable = not hide and panel.uacRespawnOriginalEnable ~= false
end
local function selected(window)
    local list = window.listbox
    return list and list.items[list.selected] and list.items[list.selected].item
end
local function stopPages(state)
    state.loading = false
    state.awaitingChoices = false
    state.nextOffset = nil
    state.pageAfter = nil
end
local function cancel(state)
    if state then
        if AdminCoreRespawnBridge and AdminCoreRespawnBridge.cancel then
            pcall(AdminCoreRespawnBridge.cancel, state.playerIndex)
        end
        stopPages(state)
        state.requestId = nonce()
        state.choosing = nil
        state.chooseAfter = nil
        state.ticket = nil
        state.commit = nil
    end
end
local function forget(window)
    local state = window.uacRespawn
    cancel(state)
    if state and R.windows[state.playerIndex] == window then
        R.windows[state.playerIndex] = nil
    end
    window.uacRespawn = nil
end
local function description(row)
    return "Safehouse: "
        .. clean(row.name, "Safehouse")
        .. " <LINE> Owner: "
        .. clean(row.owner, "Unknown")
        .. " <LINE> Location: "
        .. tostring(math.floor(row.x))
        .. ", "
        .. tostring(math.floor(row.y))
        .. ", floor "
        .. tostring(math.floor(row.z))
        .. " <LINE> This choice applies only to this character. Membership is checked again when spawning."
end
local function addStatus(window, text)
    window.listbox:addItem(text, {
        name = text,
        desc = clean(text),
        dir = "",
        uacStatus = true,
        zoomX = 0,
        zoomY = 0,
        zoomS = 0,
    })
end
local function append(window)
    local state = window.uacRespawn
    if not state or not window.listbox then
        return
    end
    for _, row in ipairs(state.rows or {}) do
        local region = {
            name = "Safehouse: " .. clean(row.name, "Safehouse"),
            points = { unemployed = { { posX = row.x, posY = row.y, posZ = row.z } } },
        }
        window.listbox:addItem(region.name, {
            name = region.name,
            region = region,
            dir = "",
            desc = description(row),
            uacHouseId = row.id,
            zoomX = 0,
            zoomY = 0,
            zoomS = 0,
        })
    end
    if state.message then
        addStatus(window, state.message)
    end
    if state.loading then
        addStatus(
            window,
            #state.rows > 0
                    and ("Loading safehouse choices (" .. tostring(#state.rows) .. " found)...")
                or "Checking safehouse spawn options..."
        )
    elseif #window.listbox.items == 0 then
        addStatus(window, "No spawn locations available.")
    end
    -- Never auto-select a safehouse, including servers without a normal region.
    local item = selected(window)
    if not item or item.uacHouseId then
        local normal
        for i, entry in ipairs(window.listbox.items) do
            if not entry.item.uacHouseId then
                normal = i
                break
            end
        end
        if not normal then
            addStatus(window, "Select a safehouse to continue.")
            normal = #window.listbox.items
        end
        window.listbox.selected = normal
    end
    window:recalculateMapSize()
end
local function rebuildChoices(window)
    -- A page only changes list rows. Do not reload native/custom map data per page.
    local list = window.listbox
    if not list then
        return
    end
    local old = selected(window)
    local oldId, oldRegion = old and old.uacHouseId, old and old.region
    local normal = {}
    for _, entry in ipairs(list.items) do
        if not entry.item.uacHouseId and not entry.item.uacStatus then
            normal[#normal + 1] = entry
        end
    end
    list:clear()
    list:setScrollHeight(0)
    for _, entry in ipairs(normal) do
        list:addItem(entry.text, entry.item, entry.tooltip)
    end
    append(window)
    for i, entry in ipairs(list.items) do
        if
            (oldId and entry.item.uacHouseId == oldId)
            or (not oldId and oldRegion and entry.item.region == oldRegion)
        then
            list.selected = i
            break
        end
    end
end
local function refresh(window)
    if not window.listbox then
        return
    end
    local old = selected(window)
    local oldId, oldRegion = old and old.uacHouseId, old and old.region
    window:fillList()
    -- Preserve a choice made by the user, not a previous attempt's default.
    for i, entry in ipairs(window.listbox.items) do
        local item = entry.item
        if
            (oldId and item.uacHouseId == oldId)
            or (not oldId and oldRegion and item.region == oldRegion)
        then
            window.listbox.selected = i
            break
        end
    end
end
local function showChoices(window)
    local creation = MainScreen.instance.inGame and CoopCharacterCreation.instance
        or MainScreen.instance
    if creation then
        if creation.charCreationMain then
            creation.charCreationMain:setVisible(false)
        end
        if creation.charCreationProfession then
            creation.charCreationProfession:setVisible(false)
        end
    end
    window:setVisible(true, window.joyfocus)
end
local function begin(window, force)
    if not supported() then
        return nil
    end
    local playerIndex = slot()
    if type(playerIndex) ~= "number" or playerIndex < 0 or playerIndex > 3 then
        return nil
    end
    if window.uacRespawn and not force then
        return window.uacRespawn
    end
    if R.windows[playerIndex] and R.windows[playerIndex] ~= window then
        forget(R.windows[playerIndex])
    end
    cancel(window.uacRespawn)
    local state = {
        playerIndex = playerIndex,
        requestId = nonce(),
        rows = {},
        seen = {},
        loading = true,
        awaitingChoices = true,
        pageOffset = 0,
        coop = MainScreen.instance.inGame
            and CoopCharacterCreation.instance
            and CoopCharacterCreation.instance.mapSpawnSelect == window,
        expires = getTimestampMs() + 10000,
    }
    window.uacRespawn = state
    R.windows[playerIndex] = window
    R.requestAfter = getTimestampMs() + 200
    local ok, sent = pcall(AdminCoreRespawnBridge.requestChoices, playerIndex, state.requestId)
    if not ok or sent == false then
        stopPages(state)
        R.serverEnabled = false
        state.message = "Safehouse choices unavailable. Normal locations are still available."
    end
    return state
end

local originalSafehouseRegion = MapSpawnSelect.getSafehouseSpawnRegion
function MapSpawnSelect:getSafehouseSpawnRegion(...)
    if supported() and R.serverEnabled ~= false then
        return nil
    end
    return originalSafehouseRegion(self, ...)
end
local originalHasChoices = MapSpawnSelect.hasChoices
function MapSpawnSelect:hasChoices(...)
    if begin(self) then
        return true
    end
    return originalHasChoices(self, ...)
end
local originalCoopHasChoices = CoopMapSpawnSelect.hasChoices
function CoopMapSpawnSelect:hasChoices(...)
    if begin(self) then
        return true
    end
    return originalCoopHasChoices(self, ...)
end
local originalFill = MapSpawnSelect.fillList
function MapSpawnSelect:fillList(...)
    begin(self)
    originalFill(self, ...)
    append(self)
end

local originalMapNext = MapSpawnSelect.clickNext
local originalCoopNext = CoopMapSpawnSelect.clickNext
local function continueNative(window)
    local state = window.uacRespawn
    if
        (state and state.coop)
        or (
            not state
            and MainScreen.instance.inGame
            and CoopCharacterCreation.instance
            and CoopCharacterCreation.instance.mapSpawnSelect == window
        )
    then
        return originalCoopNext(window)
    end
    return originalMapNext(window)
end
local function sendChoice(window)
    local state = window.uacRespawn
    state.chooseAfter = nil
    state.expires = getTimestampMs() + 10000
    R.requestAfter = getTimestampMs() + 200
    local ok, sent =
        pcall(AdminCoreRespawnBridge.choose, state.playerIndex, state.choosing, state.requestId)
    if not ok or sent == false then
        cancel(state)
        state.message = "Safehouse selection failed. Select a location and try again."
        refresh(window)
        showChoices(window)
    end
end
local function choose(window, item, commit)
    local state = window.uacRespawn
    stopPages(state)
    state.choosing = item.uacHouseId
    state.requestId = nonce()
    state.chooseAfter = math.max(getTimestampMs(), R.requestAfter)
    state.expires = state.chooseAfter + 10000
    state.message = nil
    state.commit = commit
    if getTimestampMs() >= state.chooseAfter then
        sendChoice(window)
    end
end
local function nextChoice(window)
    local state = window.uacRespawn
    if not state then
        return continueNative(window)
    end
    -- A main-menu button may have captured the native callback before mods loaded.
    -- That callback hides first, then dispatches our current clickNext method.
    window:setVisible(true, window.joyfocus)
    local item = selected(window)
    if not item or item.uacStatus or state.choosing then
        return
    end
    if item.uacHouseId then
        choose(window, item)
        return
    end
    -- Native Random rolls over every list row. Exclude safehouses and status rows.
    if item.name == getText("UI_mapspawn_random") then
        local normal = {}
        for i, entry in ipairs(window.listbox.items) do
            if entry.item.region and not entry.item.uacHouseId then
                normal[#normal + 1] = i
            end
        end
        if #normal == 0 then
            return
        end
        window.listbox.selected = normal[ZombRand(#normal) + 1]
    end
    cancel(state)
    return continueNative(window)
end
function MapSpawnSelect:clickNext()
    return nextChoice(self)
end
function CoopMapSpawnSelect:clickNext()
    return nextChoice(self)
end
local originalOption = MapSpawnSelect.onOptionMouseDown
function MapSpawnSelect:onOptionMouseDown(button, x, y)
    -- Native hides the panel before clickNext, which is too early for an async choice.
    if self.uacRespawn and button.internal == "NEXT" then
        return self:clickNext()
    end
    return originalOption(self, button, x, y)
end
local originalMapBack = MapSpawnSelect.clickBack
function MapSpawnSelect:clickBack(...)
    forget(self)
    return originalMapBack(self, ...)
end
local originalCoopBack = CoopMapSpawnSelect.clickBack
function CoopMapSpawnSelect:clickBack(...)
    forget(self)
    return originalCoopBack(self, ...)
end
local originalPrerender = MapSpawnSelect.prerender
local function maintain()
    local now = getTimestampMs()
    local pendingChoice = false
    for _, window in pairs(R.windows) do
        if window.uacRespawn and window.uacRespawn.chooseAfter then
            pendingChoice = true
        end
    end
    if R.infoRequest and now >= R.infoRequest.expires then
        R.infoRequest = nil
        updateCheckbox()
    end
    for _, window in pairs(R.windows) do
        local state = window.uacRespawn
        if state and (state.awaitingChoices or state.choosing) and now >= state.expires then
            local committing = state.commit ~= nil
            if state.loading and R.serverEnabled == nil then
                R.serverEnabled = false
            end
            cancel(state)
            state.loading = false
            state.requestId = nonce() -- Late replies cannot advance the screen.
            state.message = "Safehouse request timed out. Normal locations are still available."
            refresh(window)
            if committing then
                showChoices(window)
            end
        elseif
            state
            and state.choosing
            and state.chooseAfter
            and now >= state.chooseAfter
            and now >= R.requestAfter
        then
            sendChoice(window)
        elseif
            not pendingChoice
            and state
            and state.loading
            and state.nextOffset
            and now >= state.pageAfter
            and now >= R.requestAfter
        then
            state.pageOffset = state.nextOffset
            state.nextOffset = nil
            state.requestId = nonce()
            state.awaitingChoices = true
            state.expires = now + 10000
            R.requestAfter = now + 200
            local ok, sent = pcall(
                AdminCoreRespawnBridge.requestMoreChoices,
                state.playerIndex,
                state.requestId,
                state.pageOffset
            )
            if not ok or sent == false then
                cancel(state)
                state.message =
                    "More safehouse choices could not be loaded. Loaded locations remain available."
                rebuildChoices(window)
            end
        end
    end
end
function MapSpawnSelect:prerender(...)
    maintain()
    originalPrerender(self, ...)
    local state, item = self.uacRespawn, selected(self)
    if state and (state.choosing or not item or item.uacStatus) then
        self.nextButton:setEnable(false)
    end
    if state and state.choosing then
        self.nextButton.tooltip = "Checking current safehouse membership..."
        self.uacRespawnTooltip = true
    elseif self.uacRespawnTooltip then
        self.nextButton.tooltip = nil
        self.uacRespawnTooltip = nil
    end
end

local function onCommand(module, command, args)
    if module ~= "UniversalAdminRespawn" or type(args) ~= "table" then
        return
    end
    if command == "rejected" and args.creation == true then
        -- The final native acceptance check can run after the choice request ended.
        -- Initial loading is aborted by the native bridge; Coop emits OnCoopJoinFailed.
        local active = R.windows[args.playerIndex]
        local activeState = active and active.uacRespawn
        if
            type(args.playerIndex) == "number"
            and args.playerIndex >= 0
            and args.playerIndex <= 3
            and (R.accepted[args.playerIndex] or (activeState and activeState.ticket))
        then
            R.creationErrors[args.playerIndex] =
                clean(args.message, "Safehouse is no longer available. Select another location.")
        end
        return
    end
    local info = R.infoRequest
    if info and args.requestId == info.requestId and args.playerIndex == info.playerIndex then
        if command == "choices" then
            R.serverEnabled = args.enabled == true
        end
        if command == "choices" or command == "rejected" then
            R.infoRequest = nil
            updateCheckbox()
        end
        return
    end
    local window = R.windows[args.playerIndex]
    local state = window and window.uacRespawn
    if not state or args.requestId ~= state.requestId then
        return
    end
    if command == "choices" and state.loading and state.awaitingChoices then
        if args.offset ~= nil and args.offset ~= state.pageOffset then
            return
        end
        state.awaitingChoices = false
        state.nextOffset = nil
        R.serverEnabled = args.enabled == true
        updateCheckbox()
        if args.enabled == true and type(args.rows) == "table" then
            for _, row in ipairs(args.rows) do
                if
                    type(row) == "table"
                    and type(row.id) == "string"
                    and not state.seen[row.id]
                    and #row.id <= 256
                    and coordinate(row.x)
                    and coordinate(row.y)
                    and coordinate(row.z)
                then
                    state.seen[row.id] = true
                    state.rows[#state.rows + 1] = row
                end
            end
        end
        if args.enabled == true and args.nextOffset ~= nil then
            local offset = args.nextOffset
            if
                type(offset) == "number"
                and offset == math.floor(offset)
                and offset > state.pageOffset
                and offset <= 2147483647
                and AdminCoreRespawnBridge.requestMoreChoices
            then
                state.nextOffset = offset
                state.pageAfter = getTimestampMs() + 200
            else
                state.message =
                    "More safehouse choices could not be loaded. Loaded locations remain available."
            end
        end
        state.loading = state.nextOffset ~= nil
        if args.enabled ~= true then
            state.rows, state.seen = {}, {}
            refresh(window) -- An explicit disabled response restores the legacy provider.
        else
            rebuildChoices(window)
        end
    elseif command == "selected" and state.choosing then
        local item = selected(window)
        if not item or item.uacHouseId ~= state.choosing then
            cancel(state)
            return
        end
        if
            type(args.regionKey) ~= "string"
            or not args.regionKey:match("^UACRespawn:")
            or #args.regionKey > 256
            or not coordinate(args.x)
            or not coordinate(args.y)
            or not coordinate(args.z)
        then
            cancel(state)
            state.message = "Invalid safehouse response. Select a location and try again."
            refresh(window)
            showChoices(window)
            return
        end
        local commit = state.commit
        state.commit = nil
        state.choosing = nil
        state.ticket = args.regionKey
        item.region = {
            name = args.regionKey,
            key = args.regionKey,
            points = { unemployed = { { posX = args.x, posY = args.y, posZ = args.z } } },
        }
        if commit then
            window.selectedRegion = item.region
            setSpawnRegion(args.regionKey)
            commit()
        else
            continueNative(window)
        end
    elseif command == "rejected" then
        if state.loading and R.serverEnabled == nil then
            R.serverEnabled = false
        end
        cancel(state)
        state.loading = false
        state.message =
            clean(args.message, "Safehouse is no longer available. Select another location.")
        refresh(window)
        showChoices(window)
    end
end
R.onServerCommand = onCommand
Events.OnServerCommand.Add(onCommand)
Events.OnTick.Add(maintain)
local originalCancel = CoopCharacterCreation.cancel
function CoopCharacterCreation:cancel(...)
    if self.mapSpawnSelect then
        forget(self.mapSpawnSelect)
    end
    R.accepted[self.playerIndex] = nil
    return originalCancel(self, ...)
end
local originalAccept = CoopCharacterCreation.accept
function CoopCharacterCreation:accept(...)
    local state = self.mapSpawnSelect and self.mapSpawnSelect.uacRespawn
    if state and state.choosing then
        return
    end
    local item = self.mapSpawnSelect and selected(self.mapSpawnSelect)
    if state and state.ticket and item and item.uacHouseId then
        self.charCreationMain:setVisible(true, self.joypadData)
        return choose(self.mapSpawnSelect, item, function()
            R.accepted[self.playerIndex] = self
            originalAccept(self)
        end)
    end
    return originalAccept(self, ...)
end
local originalCharacterOption = CharacterCreationMain.onOptionMouseDown
function CharacterCreationMain:onOptionMouseDown(button, x, y)
    if button.internal == "NEXT" and not MainScreen.instance.inGame then
        local window = R.windows[0]
        local state, item = window and window.uacRespawn, window and selected(window)
        if state and state.choosing then
            return
        end
        if state and state.ticket and item and item.uacHouseId then
            return choose(window, item, function()
                originalCharacterOption(self, button, x, y)
            end)
        end
    end
    return originalCharacterOption(self, button, x, y)
end
local originalCharacterPrerender = CharacterCreationMain.prerender
function CharacterCreationMain:prerender(...)
    maintain()
    originalCharacterPrerender(self, ...)
    local window = R.windows[slot()]
    local state = window and window.uacRespawn
    if state and state.choosing then
        self.playButton:setEnable(false)
        self.playButton.tooltip = "Checking current safehouse membership..."
        self.uacRespawnPending = true
    elseif self.uacRespawnPending then
        self.uacRespawnPending = nil
        self.playButton.tooltip = nil
        self:disableBtn()
    end
end
Events.OnCoopJoinFailed.Add(function(playerIndex)
    local creation = R.accepted[playerIndex]
    if not creation or CoopCharacterCreation.instance then
        return
    end
    R.accepted[playerIndex] = nil
    CoopCharacterCreation.instance = creation
    CoopCharacterCreation.setVisibleAllUI(false)
    creation:addToUIManager()
    creation.charCreationMain:setVisible(false)
    creation.charCreationProfession:setVisible(false)
    local state = begin(creation.mapSpawnSelect, true)
    if state then
        state.message = R.creationErrors[playerIndex]
    end
    R.creationErrors[playerIndex] = nil
    creation.mapSpawnSelect:fillList()
    creation.mapSpawnSelect:setVisible(true, creation.joypadData)
end)
Events.OnCreatePlayer.Add(function(playerIndex)
    R.accepted[playerIndex] = nil
    R.creationErrors[playerIndex] = nil
    local window = R.windows[playerIndex]
    if window then
        window.uacRespawn = nil
    end
    R.windows[playerIndex] = nil
end)
Events.OnDisconnect.Add(function()
    for _, window in pairs(R.windows) do
        window.uacRespawn = nil
    end
    R.windows = {}
    R.accepted = {}
    R.creationErrors = {}
    R.requestAfter = 0
    R.serverEnabled = nil
    R.infoRequest = nil
    R.safehousePanel = nil
end)

-- Do not edit the saved vanilla preference: stop offering a persistent switch.
local originalSafehouseInit = ISSafehouseUI.initialise
function ISSafehouseUI:initialise(...)
    originalSafehouseInit(self, ...)
    if supported() and self.respawn then
        self.uacRespawnOriginalEnable = self.respawn.enable
        R.safehousePanel = self
        local request = {
            requestId = nonce(),
            playerIndex = self.player:getPlayerNum(),
            expires = getTimestampMs() + 10000,
        }
        R.infoRequest = request
        R.requestAfter = getTimestampMs() + 200
        local ok, sent =
            pcall(AdminCoreRespawnBridge.requestChoices, request.playerIndex, request.requestId)
        if not ok or sent == false then
            R.infoRequest = nil
        end
        updateCheckbox()
    end
end
local originalRespawnClick = ISSafehouseUI.onClickRespawn
function ISSafehouseUI:onClickRespawn(...)
    if supported() and (R.serverEnabled == true or R.infoRequest ~= nil) then
        return
    end
    return originalRespawnClick(self, ...)
end
local originalSafehouseClose = ISSafehouseUI.close
function ISSafehouseUI:close(...)
    if R.safehousePanel == self then
        R.safehousePanel = nil
    end
    return originalSafehouseClose(self, ...)
end

-- MainScreen can already exist when a joining server loads its client mods.
-- Update only the native callback we wrapped; retain unrelated mod callbacks.
local initialMain = MainScreen.instance and MainScreen.instance.charCreationMain
if
    initialMain
    and initialMain.playButton
    and initialMain.playButton.onclick == originalCharacterOption
then
    initialMain.playButton.onclick = CharacterCreationMain.onOptionMouseDown
end
