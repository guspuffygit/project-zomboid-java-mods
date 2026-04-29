require "CSR_Config"
require "CSR_FeatureFlags"
require "CSR_Theme"

CSR_PlayerMapTracker = {
    tickCounter = 0,
    playerData = {},
    requestSeq = 0,
    lastAppliedSeq = 0,
    lastMarkerTick = 0,
    vanillaMiniMap = { saved = {} },
    vanillaWorldMap = { saved = {} },
    patchAttempts = 0,
    lastWorldMapErr = nil,
    lastMiniMapErr = nil,
}

local function hasMarkers()
    return type(CSR_PlayerMapTracker.playerData) == "table" and #CSR_PlayerMapTracker.playerData > 0
end

local function uiList()
    return UIManager.getUI and UIManager.getUI() or nil
end

local function getMapPanels()
    local panels = {}
    local list = uiList()
    if not list then
        return panels
    end

    for i = 0, list:size() - 1 do
        local ui = list:get(i)
        if ui and instanceof(ui, "UIWorldMap") then
            table.insert(panels, ui)
        end
    end

    return panels
end

local function getWorldMapApi(panel)
    if panel and panel.getAPIv1 then
        return panel:getAPIv1()
    end
    if panel and panel.mapAPI then
        return panel.mapAPI
    end
    return nil
end

local function getMiniMapOuter(playerNum)
    if type(getPlayerMiniMap) ~= "function" then
        return nil
    end

    local miniMap = getPlayerMiniMap(playerNum or 0)
    if not miniMap then
        return nil
    end

    return miniMap
end

local function getMiniMapApi(playerNum)
    local miniMap = getMiniMapOuter(playerNum)
    if not miniMap then
        return nil
    end

    if miniMap.inner and miniMap.inner.mapAPI then
        return miniMap.inner.mapAPI
    end

    if miniMap.mapAPI then
        return miniMap.mapAPI
    end

    return nil
end

local function isMiniMapVisible(playerNum)
    local miniMap = getMiniMapOuter(playerNum)
    if not miniMap then
        return false
    end

    if miniMap.isVisible then
        return miniMap:isVisible()
    end

    return true
end

local function shouldRequestMarkers()
    if #getMapPanels() > 0 then
        return true
    end

    return isMiniMapVisible(0)
end

local function getPlayerNum()
    local player = getPlayer()
    if player and player.getPlayerNum then
        return player:getPlayerNum()
    end
    return 0
end

local function saveVanillaFlags(bucket, playerNum, mapAPI)
    local saved = bucket.saved[playerNum]
    if saved and saved.hasSaved then
        return
    end

    saved = { hasSaved = true }

    if mapAPI.getBoolean then
        saved.Players = mapAPI:getBoolean("Players") ~= false
        saved.RemotePlayers = mapAPI:getBoolean("RemotePlayers") ~= false
        saved.PlayerNames = mapAPI:getBoolean("PlayerNames") ~= false
    else
        saved.Players = true
        saved.RemotePlayers = true
        saved.PlayerNames = true
    end

    bucket.saved[playerNum] = saved
end

local function applyVanillaOverride(bucket, playerNum, mapAPI, active)
    if not mapAPI or not mapAPI.setBoolean then
        return
    end

    saveVanillaFlags(bucket, playerNum, mapAPI)

    local saved = bucket.saved[playerNum]
    if not saved then
        return
    end

    if active then
        -- Hide all vanilla dots — CSR draws all players (including self) in uniform style
        mapAPI:setBoolean("Players", false)
        mapAPI:setBoolean("RemotePlayers", false)
        mapAPI:setBoolean("PlayerNames", false)
    else
        mapAPI:setBoolean("Players", saved.Players)
        mapAPI:setBoolean("RemotePlayers", saved.RemotePlayers)
        mapAPI:setBoolean("PlayerNames", saved.PlayerNames)
    end
end

local function colorForPlayer(data)
    local name = data and data.username or tostring(data and data.id or "player")
    local hash = 0
    for i = 1, #name do
        hash = (hash * 31 + string.byte(name, i)) % 2147483647
    end

    local seed = hash % 5
    if seed == 0 then return CSR_Theme.getColor("accentBlue") end
    if seed == 1 then return CSR_Theme.getColor("accentGreen") end
    if seed == 2 then return CSR_Theme.getColor("accentAmber") end
    if seed == 3 then return CSR_Theme.getColor("accentRed") end
    return CSR_Theme.getColor("accentViolet")
end

local function drawLabel(mapObject, x, y, text)
    if not CSR_Config.PLAYER_MAP_DRAW_NAMES or not text or text == "" then
        return
    end

    local tm = getTextManager and getTextManager() or nil
    if not tm or not mapObject.drawText or not mapObject.drawRect then
        return
    end

    local font = UIFont.Small
    local width = tm:MeasureStringX(font, text)
    local height = tm:getFontHeight(font)
    local tx = math.floor(x - (width / 2))
    local ty = math.floor(y + CSR_Config.PLAYER_MAP_MARKER_SIZE)

    local bg = CSR_Theme.withAlpha(CSR_Theme.getColor("panelBg"), 0.72)
    local textColor = CSR_Theme.getColor("text")
    mapObject:drawRect(tx - 6, ty - 1, width + 12, height + 2, bg.a, bg.r, bg.g, bg.b)
    mapObject:drawText(text, tx, ty, textColor.r, textColor.g, textColor.b, 1.0, font)
end

local function drawMarker(mapObject, uiX, uiY, accent)
    local size = CSR_Config.PLAYER_MAP_MARKER_SIZE

    if mapObject.drawCircle then
        local bg = CSR_Theme.getColor("panelBg")
        mapObject:drawCircle(uiX, uiY, size, 1.0, bg.r, bg.g, bg.b)
        mapObject:drawCircle(uiX, uiY, math.max(1, size - 1), 1.0, accent.r, accent.g, accent.b)
        return
    end

    if mapObject.drawRect then
        local bg = CSR_Theme.getColor("panelBg")
        mapObject:drawRect(uiX - size / 2, uiY - size / 2, size, size, 1.0, bg.r, bg.g, bg.b)
        mapObject:drawRect(uiX - (size - 2) / 2, uiY - (size - 2) / 2, size - 2, size - 2, 1.0, accent.r, accent.g, accent.b)
    end
end

local function drawSingleMarker(mapObject, mapAPI, panelWidth, panelHeight, marker)
    if not marker or type(marker.x) ~= "number" or type(marker.y) ~= "number" then
        return
    end
    local uiX = mapAPI:worldToUIX(marker.x, marker.y)
    local uiY = mapAPI:worldToUIY(marker.x, marker.y)
    if uiX == nil or uiY == nil then return end
    if panelWidth and panelHeight then
        if uiX < -16 or uiX > panelWidth + 16 or uiY < -16 or uiY > panelHeight + 16 then
            return
        end
    end
    local accent = colorForPlayer(marker)
    drawMarker(mapObject, uiX, uiY, accent)
    drawLabel(mapObject, uiX, uiY, marker.username or tostring(marker.id or "Player"))
end

local function drawMarkersOnMap(mapObject, mapAPI)
    if not mapObject or not mapAPI then
        return
    end

    if type(mapAPI.worldToUIX) ~= "function" or type(mapAPI.worldToUIY) ~= "function" then
        return
    end

    local panelWidth = mapObject.getWidth and mapObject:getWidth() or nil
    local panelHeight = mapObject.getHeight and mapObject:getHeight() or nil

    -- Draw local player in the same CSR style
    local localPlayer = getPlayer()
    if localPlayer and not localPlayer:isDead() then
        drawSingleMarker(mapObject, mapAPI, panelWidth, panelHeight, {
            x = math.floor(localPlayer:getX()),
            y = math.floor(localPlayer:getY()),
            username = localPlayer:getDisplayName(),
            id = localPlayer.getOnlineID and localPlayer:getOnlineID() or 0,
        })
    end

    -- Draw remote players
    for _, marker in ipairs(CSR_PlayerMapTracker.playerData) do
        drawSingleMarker(mapObject, mapAPI, panelWidth, panelHeight, marker)
    end
end

function CSR_PlayerMapTracker.applyWorldMapOverride()
    local active = CSR_FeatureFlags.isPlayerMapTrackingEnabled() and hasMarkers()
    local playerNum = getPlayerNum()

    for _, panel in ipairs(getMapPanels()) do
        applyVanillaOverride(CSR_PlayerMapTracker.vanillaWorldMap, playerNum, getWorldMapApi(panel), active)
    end

    applyVanillaOverride(CSR_PlayerMapTracker.vanillaMiniMap, playerNum, getMiniMapApi(playerNum), active)
end

function CSR_PlayerMapTracker.requestPlayerMarkers(force)
    if not CSR_FeatureFlags.isPlayerMapTrackingEnabled() or not shouldRequestMarkers() then
        if not CSR_FeatureFlags.isPlayerMapTrackingEnabled() then
            CSR_PlayerMapTracker.playerData = {}
            CSR_PlayerMapTracker.applyWorldMapOverride()
        end
        return
    end

    if force then
        CSR_PlayerMapTracker.tickCounter = 0
    end

    if CSR_PlayerMapTracker.tickCounter > 0 then
        CSR_PlayerMapTracker.tickCounter = CSR_PlayerMapTracker.tickCounter - 1
        return
    end

    local player = getPlayer()
    if player and isClient() then
        CSR_PlayerMapTracker.requestSeq = CSR_PlayerMapTracker.requestSeq + 1
        sendClientCommand(player, "CommonSenseReborn", "RequestPlayerMarkers", {
            requestSeq = CSR_PlayerMapTracker.requestSeq
        })
    end
    CSR_PlayerMapTracker.tickCounter = CSR_Config.PLAYER_MAP_REQUEST_TICKS
end

function CSR_PlayerMapTracker.setPlayerData(players, requestSeq)
    if requestSeq and requestSeq < (CSR_PlayerMapTracker.lastAppliedSeq or 0) then
        return
    end

    CSR_PlayerMapTracker.playerData = players or {}
    CSR_PlayerMapTracker.lastAppliedSeq = requestSeq or CSR_PlayerMapTracker.lastAppliedSeq or 0
    CSR_PlayerMapTracker.lastMarkerTick = getTimestampMs and getTimestampMs() or os.time() * 1000
    CSR_PlayerMapTracker.applyWorldMapOverride()
end

local function renderWorldMapMarkers(panel)
    local mapAPI = panel.mapAPI or getWorldMapApi(panel.javaObject and panel.javaObject or panel)

    if CSR_FeatureFlags.isPlayerMapTrackingEnabled() then
        CSR_PlayerMapTracker.applyWorldMapOverride()
        drawMarkersOnMap(panel, mapAPI)
    end
end

local function renderMiniMapMarkers(panel)
    local mapAPI = panel.inner and panel.inner.mapAPI or panel.mapAPI

    if CSR_FeatureFlags.isPlayerMapTrackingEnabled() then
        CSR_PlayerMapTracker.applyWorldMapOverride()
        drawMarkersOnMap(panel, mapAPI)
    end
end

local function patchWorldMap()
    if not ISWorldMap or ISWorldMap.__csr_player_render then
        return ISWorldMap ~= nil
    end

    local originalRender = ISWorldMap.render
    if not originalRender then
        return false
    end

    ISWorldMap.__csr_player_render = true
    function ISWorldMap:render(...)
        originalRender(self, ...)
        renderWorldMapMarkers(self)
    end
    return true
end

local function patchMiniMap()
    if not ISMiniMapOuter or ISMiniMapOuter.__csr_player_render then
        return ISMiniMapOuter ~= nil
    end

    local originalRender = ISMiniMapOuter.render
    if not originalRender then
        return false
    end

    ISMiniMapOuter.__csr_player_render = true
    function ISMiniMapOuter:render(...)
        originalRender(self, ...)
        renderMiniMapMarkers(self)
    end
    return true
end

local function tryPatch()
    local worldOk = patchWorldMap()
    local miniOk = patchMiniMap()
    if worldOk and miniOk then
        Events.OnTickEvenPaused.Remove(tryPatch)
        return
    end

    CSR_PlayerMapTracker.patchAttempts = CSR_PlayerMapTracker.patchAttempts + 1
    if CSR_PlayerMapTracker.patchAttempts >= 60 then
        Events.OnTickEvenPaused.Remove(tryPatch)
    end
end

local function onTick()
    -- v1.8.7 (Phoenix II perf gating): early-exit when feature is disabled.
    -- Avoids the per-tick applyWorldMapOverride() cost (Phoenix measured ~13%
    -- main-thread CPU here on a 240Hz client).
    if not (CSR_FeatureFlags and CSR_FeatureFlags.isPlayerMapTrackingEnabled
        and CSR_FeatureFlags.isPlayerMapTrackingEnabled()) then
        return
    end
    local nowMs = getTimestampMs and getTimestampMs() or os.time() * 1000
    if CSR_PlayerMapTracker.lastMarkerTick > 0 and nowMs > 0 then
        local ageMs = nowMs - CSR_PlayerMapTracker.lastMarkerTick
        if ageMs > (CSR_Config.PLAYER_MAP_STALE_TICKS * 16) then
            CSR_PlayerMapTracker.playerData = {}
            CSR_PlayerMapTracker.applyWorldMapOverride()
        end
    end

    CSR_PlayerMapTracker.requestPlayerMarkers(false)
    CSR_PlayerMapTracker.applyWorldMapOverride()
end

local function onGameStart()
    CSR_PlayerMapTracker.tickCounter = 0
    CSR_PlayerMapTracker.requestSeq = 0
    CSR_PlayerMapTracker.lastAppliedSeq = 0
    CSR_PlayerMapTracker.lastMarkerTick = 0
    CSR_PlayerMapTracker.patchAttempts = 0
    CSR_PlayerMapTracker.lastWorldMapErr = nil
    CSR_PlayerMapTracker.lastMiniMapErr = nil
    CSR_PlayerMapTracker.applyWorldMapOverride()

    if not (patchWorldMap() and patchMiniMap()) then
        Events.OnTickEvenPaused.Remove(tryPatch)
        Events.OnTickEvenPaused.Add(tryPatch)
    end
end

if Events then
    local _csrMapPatchInstalled = false
    local function csrEnsureMapPatched()
        if _csrMapPatchInstalled then return end
        _csrMapPatchInstalled = true
        if not (patchWorldMap() and patchMiniMap()) then
            Events.OnTickEvenPaused.Remove(tryPatch)
            Events.OnTickEvenPaused.Add(tryPatch)
        end
    end

    local _csrMapTrackerRegistered = false
    local function csrEnsureMapTrackerRegistered()
        csrEnsureMapPatched()
        if _csrMapTrackerRegistered then return end
        if not (CSR_FeatureFlags and CSR_FeatureFlags.isPlayerMapTrackingEnabled
            and CSR_FeatureFlags.isPlayerMapTrackingEnabled()) then return end
        _csrMapTrackerRegistered = true
        if Events.OnTick then Events.OnTick.Add(onTick) end
        onGameStart()
    end
    if Events.OnGameStart then Events.OnGameStart.Add(csrEnsureMapTrackerRegistered) end
end

return CSR_PlayerMapTracker
