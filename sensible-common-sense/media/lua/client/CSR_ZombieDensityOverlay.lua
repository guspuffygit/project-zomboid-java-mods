
require "CSR_Config"
require "CSR_FeatureFlags"
require "CSR_Theme"

local DENSITY_TOGGLE_DEFAULT_KEY = Keyboard and Keyboard.KEY_MULTIPLY or 55
local densityOptions = nil
local densityKeyBind = nil
if PZAPI and PZAPI.ModOptions and PZAPI.ModOptions.create then
    densityOptions = PZAPI.ModOptions:create("CommonSenseRebornDensity", "Common Sense Reborn - Zombie Density")
    if densityOptions and densityOptions.addKeyBind then
        densityKeyBind = densityOptions:addKeyBind("densityToggle", "Toggle Zombie Density Overlay", DENSITY_TOGGLE_DEFAULT_KEY)
    end
end

local function getDensityBoundKey()
    if densityKeyBind and densityKeyBind.getValue then
        return densityKeyBind:getValue()
    end
    return DENSITY_TOGGLE_DEFAULT_KEY
end

CSR_ZombieDensityOverlay = {
    tickCounter = 0,
    requestSeq = 0,
    lastAppliedSeq = 0,
    lastDataTick = 0,
    cells = {},
    worldMapVisible = true,
    miniMapVisible = false, -- Deprecated: minimap heatmap removed in v1.6.7. Replaced by Nearby Density HUD.
    patchAttempts = 0,
    lastWorldMapErr = nil,
    lastMiniMapErr = nil,
    -- Per-cell text-measurement cache: avoids re-measuring the same number every frame.
    -- Keyed on "x,y"; entry = { amount, font, w, h }.
    _labelCache = {},
}

local DENSITY_COLORS = {
    [0] = { accent = "accentGreen", a = 0.18 },
    [1] = { accent = "accentAmber", a = 0.22 },
    [2] = { accent = "accentRed", a = 0.24 },
    [3] = { accent = "accentViolet", a = 0.28 },
}

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

    return getPlayerMiniMap(playerNum or 0)
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

local function shouldRequest()
    -- World map only; the minimap heatmap was removed in favour of the Nearby Density HUD.
    return CSR_FeatureFlags.isZombieDensityOverlayEnabled()
        and CSR_ZombieDensityOverlay.worldMapVisible
        and #getMapPanels() > 0
end

local function drawLabel(mapObject, uiX, uiY, text, cacheKey)
    local tm = getTextManager and getTextManager() or nil
    if not tm or not mapObject.drawText or not mapObject.drawRect then
        return
    end

    local font = UIFont.Small
    -- Cache MeasureStringX/getFontHeight per cell amount; the same numeric label is re-rendered
    -- every frame and Java text measurement is one of the heavier per-frame calls.
    local cache = CSR_ZombieDensityOverlay._labelCache
    local entry
    if cacheKey then
        entry = cache[cacheKey]
        if entry and entry.text == text then
            -- hit
        else
            entry = { text = text, w = tm:MeasureStringX(font, text), h = tm:getFontHeight(font) }
            cache[cacheKey] = entry
        end
    else
        entry = { w = tm:MeasureStringX(font, text), h = tm:getFontHeight(font) }
    end
    local width = entry.w
    local height = entry.h
    local tx = math.floor(uiX - (width / 2))
    local ty = math.floor(uiY - (height / 2))

    local bg = CSR_Theme.withAlpha(CSR_Theme.getColor("panelBg"), 0.68)
    local textColor = CSR_Theme.getColor("text")
    mapObject:drawRect(tx - 4, ty - 1, width + 8, height + 2, bg.a, bg.r, bg.g, bg.b)
    mapObject:drawText(text, tx, ty, textColor.r, textColor.g, textColor.b, 0.95, font)
end

local function drawCells(mapObject, mapAPI, alphaMultiplier)
    if not mapObject or not mapAPI or #CSR_ZombieDensityOverlay.cells == 0 then
        return
    end

    if type(mapAPI.worldToUIX) ~= "function" or type(mapAPI.worldToUIY) ~= "function" or not mapObject.drawRect then
        return
    end

    local cellSize = CSR_Config.ZOMBIE_DENSITY_CELL_SIZE
    local alpha = alphaMultiplier or 1.0
    local panelWidth = mapObject.getWidth and mapObject:getWidth() or nil
    local panelHeight = mapObject.getHeight and mapObject:getHeight() or nil
    for i = 1, #CSR_ZombieDensityOverlay.cells do
        local cell = CSR_ZombieDensityOverlay.cells[i]
        -- Sample all four corners to handle rotated projections (minimap isometric view)
        local cx = cell.x
        local cy = cell.y
        -- Tight center-point cull: a cell whose center is more than one cell-width
        -- outside the visible panel cannot possibly intersect it (mapAPI projection
        -- is monotonic). Skipping the 4-corner projection here saves 8 worldToUI
        -- calls per off-screen cell -- the largest per-frame cost.
        local earlyReject = false
        if panelWidth and panelHeight then
            local centerX = mapAPI:worldToUIX(cx + cellSize * 0.5, cy + cellSize * 0.5)
            local centerY = mapAPI:worldToUIY(cx + cellSize * 0.5, cy + cellSize * 0.5)
            if centerX and centerY then
                local margin = cellSize
                if centerX < -margin or centerX > panelWidth + margin
                or centerY < -margin or centerY > panelHeight + margin then
                    earlyReject = true
                end
            end
        end
        if not earlyReject then
        local ux1 = mapAPI:worldToUIX(cx, cy)
        local uy1 = mapAPI:worldToUIY(cx, cy)
        local ux2 = mapAPI:worldToUIX(cx + cellSize, cy)
        local uy2 = mapAPI:worldToUIY(cx + cellSize, cy)
        local ux3 = mapAPI:worldToUIX(cx + cellSize, cy + cellSize)
        local uy3 = mapAPI:worldToUIY(cx + cellSize, cy + cellSize)
        local ux4 = mapAPI:worldToUIX(cx, cy + cellSize)
        local uy4 = mapAPI:worldToUIY(cx, cy + cellSize)

        if ux1 and uy1 and ux2 and uy2 and ux3 and uy3 and ux4 and uy4 then
            local left = math.min(ux1, ux2, ux3, ux4)
            local top = math.min(uy1, uy2, uy3, uy4)
            local right = math.max(ux1, ux2, ux3, ux4)
            local bottom = math.max(uy1, uy2, uy3, uy4)

            -- Clamp rects to panel bounds so overlay doesn't bleed outside minimap
            local skip = false
            if panelWidth and panelHeight then
                if left > panelWidth or top > panelHeight or right < 0 or bottom < 0 then
                    skip = true
                end
                if not skip then
                    left = math.max(0, left)
                    top = math.max(0, top)
                    right = math.min(panelWidth, right)
                    bottom = math.min(panelHeight, bottom)
                end
            end

            if not skip then
            local width = right - left
            local height = bottom - top
            if width > 0 and height > 0 then

            local color = DENSITY_COLORS[cell.density or 0] or DENSITY_COLORS[0]
            local accent = CSR_Theme.getColor(color.accent) or CSR_Theme.getColor("accentSlate")

            mapObject:drawRect(left, top, width, height, color.a * alpha, accent.r, accent.g, accent.b)
            if mapObject.drawRectBorder then
                local border = CSR_Theme.withAlpha(CSR_Theme.getColor("panelBorder"), 0.60 * alpha)
                mapObject:drawRectBorder(left, top, width, height, border.a, border.r, border.g, border.b)
            end

            if cell.amount and cell.amount > 0 then
                local labelX = left + (width / 2)
                local labelY = top + (height / 2)
                if not panelWidth or not panelHeight or (labelX > 0 and labelX < panelWidth and labelY > 0 and labelY < panelHeight) then
                    drawLabel(mapObject, labelX, labelY, tostring(cell.amount), tostring(cell.x) .. "," .. tostring(cell.y))
                end
            end

            end -- width > 0 and height > 0
            end -- not skip
        end
        end -- not earlyReject
    end
end

local function getPlayerModData()
    local player = getPlayer()
    return player and player.getModData and player:getModData() or nil
end

local function loadVisibilityState()
    local modData = getPlayerModData()
    if not modData then
        return
    end

    if modData.CSRZombieDensityWorldVisible ~= nil then
        CSR_ZombieDensityOverlay.worldMapVisible = modData.CSRZombieDensityWorldVisible == true
    end
    if modData.CSRZombieDensityMiniVisible ~= nil then
        CSR_ZombieDensityOverlay.miniMapVisible = modData.CSRZombieDensityMiniVisible == true
    end
end

local function saveVisibilityState()
    local modData = getPlayerModData()
    if not modData then
        return
    end

    modData.CSRZombieDensityWorldVisible = CSR_ZombieDensityOverlay.worldMapVisible == true
    modData.CSRZombieDensityMiniVisible = CSR_ZombieDensityOverlay.miniMapVisible == true
end

local function refreshButtonLabels(panel)
    if panel and panel.csrZombieDensityWorldButton and panel.csrZombieDensityWorldButton.setTitle then
        panel.csrZombieDensityWorldButton:setTitle(CSR_ZombieDensityOverlay.worldMapVisible and "Z Density: On" or "Z Density: Off")
        CSR_Theme.applyButtonStyle(panel.csrZombieDensityWorldButton, "accentRed", CSR_ZombieDensityOverlay.worldMapVisible)
    end
end

local function anchorButtons(panel)
    if not panel then
        return
    end

    local width = panel.getWidth and panel:getWidth() or getCore():getScreenWidth()
    local x = math.max(12, math.floor((width - 148) / 2))
    local y = 12

    if panel.csrZombieDensityWorldButton and panel.csrZombieDensityWorldButton.setX then
        panel.csrZombieDensityWorldButton:setX(x)
        panel.csrZombieDensityWorldButton:setY(y)
    end
end

function CSR_ZombieDensityOverlay.requestData(force)
    if not shouldRequest() then
        return
    end

    if force then
        CSR_ZombieDensityOverlay.tickCounter = 0
    end

    if CSR_ZombieDensityOverlay.tickCounter > 0 then
        CSR_ZombieDensityOverlay.tickCounter = CSR_ZombieDensityOverlay.tickCounter - 1
        return
    end

    local player = getPlayer()
    CSR_ZombieDensityOverlay.requestSeq = CSR_ZombieDensityOverlay.requestSeq + 1
    if player and isClient() then
        sendClientCommand(player, "CommonSenseReborn", "RequestZombieDensity", {
            requestSeq = CSR_ZombieDensityOverlay.requestSeq,
        })
    elseif player then
        -- Single-player fallback uses the local cell and mirrors the server logic enough to stay useful.
        local cellSize = CSR_Config.ZOMBIE_DENSITY_CELL_SIZE
        local radius = CSR_Config.ZOMBIE_DENSITY_CELL_RADIUS
        local baseX = math.floor(player:getX() / cellSize) * cellSize
        local baseY = math.floor(player:getY() / cellSize) * cellSize
        local cellsByKey = {}
        for dx = -radius, radius do
            for dy = -radius, radius do
                local x = baseX + (dx * cellSize)
                local y = baseY + (dy * cellSize)
                cellsByKey[tostring(x) .. "," .. tostring(y)] = { x = x, y = y, amount = 0, density = 0 }
            end
        end

        -- Walk only the tiles within the density radius instead of iterating the entire loaded cell.
        -- getObjectListForLua() returns every loaded object (walls, floors, furniture, zombies) which
        -- can be 50 000+ instanceof checks per call. Bounded grid scan at z=0 is much cheaper.
        local pcell = player:getCell()
        if pcell and pcell.getGridSquare then
            local x1 = baseX - radius * cellSize
            local x2 = baseX + (radius + 1) * cellSize - 1
            local y1 = baseY - radius * cellSize
            local y2 = baseY + (radius + 1) * cellSize - 1
            for tx = x1, x2 do
                for ty = y1, y2 do
                    local sq = pcell:getGridSquare(tx, ty, 0)
                    if sq then
                        local sqObjects = sq:getObjects()
                        for oi = 0, sqObjects:size() - 1 do
                            local zombie = sqObjects:get(oi)
                            if zombie and instanceof(zombie, "IsoZombie") and not zombie:isDead() then
                                local zx = math.floor(zombie:getX() / cellSize) * cellSize
                                local zy = math.floor(zombie:getY() / cellSize) * cellSize
                                local key = tostring(zx) .. "," .. tostring(zy)
                                local cellData = cellsByKey[key]
                                if cellData then
                                    cellData.amount = cellData.amount + 1
                                end
                            end
                        end
                    end
                end
            end        -- for tx
        end            -- if pcell
        local cells = {}
        for _, cellData in pairs(cellsByKey) do
            if cellData.amount > 60 then
                cellData.density = 3
            elseif cellData.amount > 30 then
                cellData.density = 2
            elseif cellData.amount > 0 then
                cellData.density = 1
            end
            cells[#cells + 1] = cellData
        end
        CSR_ZombieDensityOverlay.setCells(cells, CSR_ZombieDensityOverlay.requestSeq)
    end

    CSR_ZombieDensityOverlay.tickCounter = CSR_Config.ZOMBIE_DENSITY_REQUEST_TICKS
end

function CSR_ZombieDensityOverlay.setCells(cells, requestSeq)
    if requestSeq and requestSeq < (CSR_ZombieDensityOverlay.lastAppliedSeq or 0) then
        return
    end

    CSR_ZombieDensityOverlay.cells = cells or {}
    CSR_ZombieDensityOverlay.lastAppliedSeq = requestSeq or CSR_ZombieDensityOverlay.lastAppliedSeq or 0
    CSR_ZombieDensityOverlay.lastDataTick = getTimestampMs and getTimestampMs() or os.time() * 1000
end

local function renderWorldMapOverlay(panel)
    if not CSR_FeatureFlags.isZombieDensityOverlayEnabled() or not CSR_ZombieDensityOverlay.worldMapVisible then
        return
    end

    drawCells(panel, panel.mapAPI or getWorldMapApi(panel.javaObject and panel.javaObject or panel), 1.0)
end

local function patchWorldMap()
    if not ISWorldMap or ISWorldMap.__csr_zdensity_render then
        return ISWorldMap ~= nil
    end

    local originalRender = ISWorldMap.render
    local originalCreateChildren = ISWorldMap.createChildren
    if not originalRender or not originalCreateChildren then
        return false
    end

    ISWorldMap.__csr_zdensity_render = true
    function ISWorldMap:render(...)
        originalRender(self, ...)
        renderWorldMapOverlay(self)
        anchorButtons(self)
        refreshButtonLabels(self)
    end

    ISWorldMap.__csr_zdensity_children = true
    function ISWorldMap:createChildren(...)
        originalCreateChildren(self, ...)
        if self.csrZombieDensityWorldButton then
            anchorButtons(self)
            refreshButtonLabels(self)
            return
        end

        local buttonHeight = getTextManager():getFontHeight(UIFont.Small) + 4
        self.csrZombieDensityWorldButton = ISButton:new(
            0,
            0,
            148,
            buttonHeight,
            "",
            self,
            function()
                CSR_ZombieDensityOverlay.worldMapVisible = not CSR_ZombieDensityOverlay.worldMapVisible
                saveVisibilityState()
                refreshButtonLabels(self)
            end
        )
        self:addChild(self.csrZombieDensityWorldButton)
        anchorButtons(self)
        refreshButtonLabels(self)
    end

    return true
end

local function patchMiniMap()
    -- Removed in v1.6.7: minimap heatmap deleted in favour of CSR_NearbyDensityHUD.
    -- Stub kept so tryPatch()'s control flow still completes cleanly.
    return true
end

local function patchTTFMiniMap()
    -- Removed in v1.6.7: see patchMiniMap() above.
    return true
end

local function tryPatch()
    local worldOk = patchWorldMap()
    local miniOk = patchMiniMap()
    local ttfOk = patchTTFMiniMap()
    if worldOk and (miniOk or ttfOk) then
        Events.OnTickEvenPaused.Remove(tryPatch)
        return
    end

    CSR_ZombieDensityOverlay.patchAttempts = CSR_ZombieDensityOverlay.patchAttempts + 1
    if CSR_ZombieDensityOverlay.patchAttempts >= 60 then
        Events.OnTickEvenPaused.Remove(tryPatch)
    end
end

local function onTick()
    local nowMs = getTimestampMs and getTimestampMs() or os.time() * 1000
    if CSR_ZombieDensityOverlay.lastDataTick > 0 and nowMs > 0 then
        local ageMs = nowMs - CSR_ZombieDensityOverlay.lastDataTick
        if ageMs > (CSR_Config.ZOMBIE_DENSITY_STALE_TICKS * 16) then
            CSR_ZombieDensityOverlay.cells = {}
        end
    end

    CSR_ZombieDensityOverlay.requestData(false)
end

local function onGameStart()
    CSR_ZombieDensityOverlay.tickCounter = 0
    CSR_ZombieDensityOverlay.requestSeq = 0
    CSR_ZombieDensityOverlay.lastAppliedSeq = 0
    CSR_ZombieDensityOverlay.lastDataTick = 0
    CSR_ZombieDensityOverlay.cells = {}
    CSR_ZombieDensityOverlay.patchAttempts = 0
    CSR_ZombieDensityOverlay.lastWorldMapErr = nil
    CSR_ZombieDensityOverlay.lastMiniMapErr = nil
    CSR_ZombieDensityOverlay.worldMapVisible = true
    CSR_ZombieDensityOverlay.miniMapVisible = true
    loadVisibilityState()

    if not (patchWorldMap() and (patchMiniMap() or patchTTFMiniMap())) then
        Events.OnTickEvenPaused.Remove(tryPatch)
        Events.OnTickEvenPaused.Add(tryPatch)
    end
end

local function onKeyPressed(key)
    if key ~= getDensityBoundKey() then
        return
    end
    if not CSR_FeatureFlags.isZombieDensityOverlayEnabled() then
        return
    end
    CSR_ZombieDensityOverlay.worldMapVisible = not CSR_ZombieDensityOverlay.worldMapVisible
    saveVisibilityState()
end

if Events then
    if Events.OnTick then Events.OnTick.Add(onTick) end
    if Events.OnGameStart then Events.OnGameStart.Add(onGameStart) end
    if Events.OnKeyPressed then Events.OnKeyPressed.Add(onKeyPressed) end
end

return CSR_ZombieDensityOverlay
