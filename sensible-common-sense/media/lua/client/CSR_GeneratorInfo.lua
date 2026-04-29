require "CSR_FeatureFlags"

--[[
    CSR_GeneratorInfo.lua  (client)
    Enhanced generator info: fuel time remaining in the info window,
    fuel gauge bar with purple gradient, and power range overlay
    with subtle purple tile highlighting.
    Gated by EnableGeneratorInfo sandbox option.
]]

if not ISGeneratorInfoWindow then return end

local CSR_GI = {}

-- Purple theme
local PR, PG, PB = 0.51, 0.0, 0.78  -- rgb(130, 0, 200)

-- 8-direction neighbors for edge detection
local NEIGHBORS = {
    {-1,-1},{0,-1},{1,-1},
    {-1, 0},       {1, 0},
    {-1, 1},{0, 1},{1, 1},
}

-- Stencil cache (computed once per tile-range value)
local _stencil = { R = nil, edgeOffsets = nil }

-- Range overlay state
local _range = {
    enabled = false,
    gen = nil,
    edges = nil,
    lastOnState = nil,
}

-- Carry preview cache
local _carry = { edges = nil, px = nil, py = nil, R = nil }

-- ═══════════════════════════════════════════════════════════
-- Fuel Helpers
-- ═══════════════════════════════════════════════════════════

local function getGen(win)
    return win and (win.generator or win.isoObject or win.object) or nil
end

local function getFuelPct(gen)
    if not gen or not gen.getFuelPercentage then return 0 end
    local ok, pct = pcall(gen.getFuelPercentage, gen)
    if not ok or type(pct) ~= "number" then return 0 end
    return math.max(0, math.min(100, pct))
end

local function getLiters(gen)
    return (getFuelPct(gen) / 100.0) * 10.0
end

local function getConsumptionLPH(gen)
    if not gen or not gen.getTotalPowerUsingString then return nil end
    local s = gen:getTotalPowerUsingString() or ""
    if type(s) ~= "string" then return nil end
    local num = s:match("([%d%.,]+)%s*[Ll]/%s*[Hh]")
    if not num then return nil end
    num = num:gsub(",", ".")
    local lph = tonumber(num)
    return (lph and lph > 0) and lph or nil
end

local function getHoursLeft(gen, fuelPct)
    local lph = getConsumptionLPH(gen)
    if not lph then return nil end
    return ((fuelPct / 100.0) * 10.0) / lph
end

local function fmtTime(gen, fuelPct)
    if not gen:isActivated() then return "" end
    local h = getHoursLeft(gen, fuelPct)
    if not h then return "" end
    local d = math.floor(h / 24)
    local hr = math.floor(h) % 24
    if d > 0 then
        return hr > 0 and string.format(" (%dd %dh)", d, hr) or string.format(" (%dd)", d)
    elseif hr >= 1 then
        return string.format(" (%dh)", hr)
    else
        return string.format(" (%dm)", math.max(1, math.floor(h * 60)))
    end
end

local function getTileRange()
    local sv = rawget(_G, "SandboxVars")
    if sv and type(sv.GeneratorTileRange) == "number" then
        return math.max(1, math.floor(sv.GeneratorTileRange))
    end
    return 20
end

-- ═══════════════════════════════════════════════════════════
-- Override getRichText (adds fuel time remaining to info text)
-- ═══════════════════════════════════════════════════════════

function ISGeneratorInfoWindow.getRichText(object, displayStats)
    local sq = object:getSquare()
    if not displayStats then
        local t = " <INDENT:10> "
        if sq and not sq:isOutside() and sq:getBuilding() then
            t = t .. " <RED> " .. getText("IGUI_Generator_IsToxic")
        end
        return t
    end

    local fuelRaw = getFuelPct(object)
    local fuelShow = math.ceil(fuelRaw)
    local timeStr = CSR_FeatureFlags.isGeneratorInfoEnabled() and fmtTime(object, fuelRaw) or ""
    local cond = object:getCondition()

    local t = getText("IGUI_Generator_FuelAmount", fuelShow) .. timeStr .. " <LINE> " ..
              getText("IGUI_Generator_Condition", cond) .. " <LINE> "

    if object:isActivated() then
        t = t .. " <LINE> " .. getText("IGUI_PowerConsumption") .. ": <LINE> <INDENT:10> "
        local items = object:getItemsPowered()
        for i = 0, items:size() - 1 do
            t = t .. "   " .. items:get(i) .. " <LINE> "
        end
        t = t .. getText("IGUI_Generator_TypeGas") .. " (" .. object:getBasePowerConsumptionString() .. ") <LINE> "
        t = t .. getText("IGUI_Total") .. ": " .. object:getTotalPowerUsingString() .. " <LINE> "
    end

    if CSR_FeatureFlags.isGeneratorInfoEnabled() then
        t = t .. string.format(" <LINE> Power range: %d tiles", getTileRange())
    end

    if sq and not sq:isOutside() and sq:getBuilding() then
        t = t .. " <LINE> <RED> " .. getText("IGUI_Generator_IsToxic")
    end

    return t
end

-- ═══════════════════════════════════════════════════════════
-- Fuel Gauge Bar (purple gradient, drawn inside info window)
-- ═══════════════════════════════════════════════════════════

local function lerp(a, b, t) return a + (b - a) * t end

local function barColor(p)
    local RD = { r = 1.0, g = 0.25, b = 0.20 }
    if p <= 10 then return RD.r, RD.g, RD.b, 1 end
    if p >= 90 then return PR, PG, PB, 1 end
    local t = (p - 10) / 80
    return lerp(RD.r, PR, t), lerp(RD.g, PG, t), lerp(RD.b, PB, t), 1
end

local function drawFuelBar(win, fuelPct, liters, hours)
    local titleH = win:titleBarHeight() or 20
    local font = getTextManager():getFontFromEnum(UIFont.Small)
    local lineH = font and font:getLineHeight() or 18

    local barY = titleH + 69 + 18 + 4 + math.floor(lineH * 0.4)
    local barX, barW, barH = 8, 62, 10

    -- Track background
    win:drawRect(barX - 1, barY - 1, barW + 2, barH + 2, 0.35, 0, 0, 0)
    win:drawRect(barX, barY, barW, barH, 0.8, 0.12, 0.12, 0.12)

    -- Fill
    local fillW = math.floor(barW * fuelPct / 100)
    local r, g, b, a = barColor(fuelPct)
    if fuelPct <= 5 then
        local phase = ((UIManager.getMillisSinceStart and UIManager.getMillisSinceStart() or 0) % 1200) / 1200
        a = 0.85 + 0.15 * math.sin(phase * math.pi * 2)
    end
    if fillW > 0 then
        win:drawRect(barX, barY, fillW, barH, a, r, g, b)
    end

    -- Purple border
    win:drawRectBorder(barX - 1, barY - 1, barW + 2, barH + 2, 0.4, PR, PG, PB)

    -- Hover tooltip
    local mx, my = win:getMouseX(), win:getMouseY()
    if mx >= barX - 1 and mx <= barX + barW + 1 and my >= barY - 1 and my <= barY + barH + 1 then
        local tip = string.format("Fuel %d%%", math.ceil(fuelPct))
        if liters then tip = tip .. string.format(" | %.1fL", liters) end
        if hours then tip = tip .. string.format(" | ~%.1fh", hours) end

        local tw = getTextManager():MeasureStringX(UIFont.Small, tip) + 10
        local th = (font and font:getLineHeight() or 14) + 6
        local tx = math.min(mx + 20, win.width - tw - 6)
        local ty = math.max(titleH + 4, my + 20)

        win:drawRect(tx - 1, ty - 1, tw + 2, th + 2, 0.60, 0, 0, 0)
        win:drawRect(tx, ty, tw, th, 0.95, 0, 0, 0)
        win:drawRectBorder(tx, ty, tw, th, 0.8, PR, PG, PB)
        win:drawText(tip, tx + 5, ty + 3, 1, 1, 1, 1, UIFont.Small)
    end
end

-- ═══════════════════════════════════════════════════════════
-- Power Range Stencil + Drawing
-- ═══════════════════════════════════════════════════════════

local function buildStencil(R)
    if _stencil.R == R and _stencil.edgeOffsets then return end
    local reach = R + 2
    local Rsq = R * R
    local powered = {}
    for y = -reach, reach do
        powered[y] = {}
        for x = -reach, reach do
            powered[y][x] = (x * x + y * y) <= Rsq
        end
    end
    local edges = {}
    for y = -reach, reach do
        for x = -reach, reach do
            if not powered[y][x] then
                for i = 1, #NEIGHBORS do
                    local nx, ny = x + NEIGHBORS[i][1], y + NEIGHBORS[i][2]
                    if nx >= -reach and nx <= reach and ny >= -reach and ny <= reach
                       and powered[ny] and powered[ny][nx] then
                        edges[#edges + 1] = { x, y }
                        break
                    end
                end
            end
        end
    end
    _stencil.R = R
    _stencil.edgeOffsets = edges
end

local function buildEdgesForGen(gen)
    local sq = gen:getSquare()
    if not sq then return nil end
    local gx, gy = sq:getX(), sq:getY()
    buildStencil(getTileRange())
    if not _stencil.edgeOffsets then return nil end
    local edges = {}
    for i = 1, #_stencil.edgeOffsets do
        edges[i] = { gx + _stencil.edgeOffsets[i][1], gy + _stencil.edgeOffsets[i][2] }
    end
    return edges
end

local function drawEdges(edges, z, alpha)
    if not edges then return end
    for i = 1, #edges do
        local e = edges[i]
        addAreaHighlight(e[1], e[2], e[1] + 1, e[2] + 1, z, PR, PG, PB, alpha)
    end
end

local function updatePowerRange()
    if not _range.enabled or not _range.gen then return end
    local gen = _range.gen
    local isOn = gen:isActivated()
    if _range.lastOnState ~= isOn or not _range.edges then
        _range.edges = buildEdgesForGen(gen)
        _range.lastOnState = isOn
    end
    if not _range.edges then return end
    local p = getPlayer()
    if not p then return end
    drawEdges(_range.edges, p:getZ(), isOn and 0.60 or 0.40)
end

-- ═══════════════════════════════════════════════════════════
-- Window Overrides
-- ═══════════════════════════════════════════════════════════

CSR_GI._origRender = ISGeneratorInfoWindow.render
CSR_GI._origPrerender = ISGeneratorInfoWindow.prerender
CSR_GI._origCreateChildren = ISGeneratorInfoWindow.createChildren
CSR_GI._origSetObject = ISGeneratorInfoWindow.setObject
CSR_GI._origSetVisible = ISGeneratorInfoWindow.setVisible
CSR_GI._origRemove = ISGeneratorInfoWindow.removeFromUIManager

function ISGeneratorInfoWindow:render()
    if CSR_GI._origRender then CSR_GI._origRender(self) end
    if not CSR_FeatureFlags.isGeneratorInfoEnabled() then return end
    local gen = getGen(self)
    if not gen then return end
    local fuel = getFuelPct(gen)
    drawFuelBar(self, fuel, getLiters(gen), getHoursLeft(gen, fuel))
end

function ISGeneratorInfoWindow:prerender()
    if CSR_FeatureFlags.isGeneratorInfoEnabled() then
        if self.csrRangeBtn then
            local tbH = 20
            if self.titleBarHeight then
                tbH = type(self.titleBarHeight) == "function" and self:titleBarHeight()
                   or type(self.titleBarHeight) == "number" and self.titleBarHeight or tbH
            end
            self.csrRangeBtn:setY(math.max(1, math.floor((tbH - self.csrRangeBtn:getHeight()) / 2)))
            self.csrRangeBtn:setX(self:getWidth() - 56 - self.csrRangeBtn:getWidth())
            self.csrRangeBtn:setVisible(true)
            -- Perf: skip string.format + setTitle unless tile range actually changed.
            local curTR = getTileRange()
            if self._csrLastTR ~= curTR then
                self._csrLastTR = curTR
                self.csrRangeBtn.title = string.format("Range (%dt)", curTR)
            end
            if _range.enabled then
                self.csrRangeBtn.borderColor     = { r = 0.3, g = 0.9, b = 0.3, a = 1.0 }
                self.csrRangeBtn.backgroundColor = { r = 0.05, g = 0.25, b = 0.05, a = 0.85 }
            else
                self.csrRangeBtn.borderColor     = { r = PR, g = PG, b = PB, a = 0.6 }
                self.csrRangeBtn.backgroundColor = { r = 0.0,  g = 0.0,  b = 0.0,  a = 0.6  }
            end
        end
        -- v1.7.7: passive multi-gen overlay toggle button, sits left of Range.
        if self.csrAllGensBtn then
            local tbH = 20
            if self.titleBarHeight then
                tbH = type(self.titleBarHeight) == "function" and self:titleBarHeight()
                   or type(self.titleBarHeight) == "number" and self.titleBarHeight or tbH
            end
            self.csrAllGensBtn:setY(math.max(1, math.floor((tbH - self.csrAllGensBtn:getHeight()) / 2)))
            local rangeRight = self.csrRangeBtn and self.csrRangeBtn:getX() or (self:getWidth() - 56)
            self.csrAllGensBtn:setX(rangeRight - self.csrAllGensBtn:getWidth() - 4)
            self.csrAllGensBtn:setVisible(true)
            local enabled = (CSR_GI.isPassiveOverlayEnabled and CSR_GI.isPassiveOverlayEnabled()) or false
            local newTitle = enabled and "Overlay: ON" or "Overlay: OFF"
            if self._csrLastOverlayTitle ~= newTitle then
                self._csrLastOverlayTitle = newTitle
                self.csrAllGensBtn.title = newTitle
            end
            if enabled then
                self.csrAllGensBtn.borderColor     = { r = 0.3, g = 0.9, b = 0.3, a = 1.0 }
                self.csrAllGensBtn.backgroundColor = { r = 0.05, g = 0.25, b = 0.05, a = 0.85 }
            else
                self.csrAllGensBtn.borderColor     = { r = PR, g = PG, b = PB, a = 0.6 }
                self.csrAllGensBtn.backgroundColor = { r = 0.0,  g = 0.0,  b = 0.0,  a = 0.6  }
            end
        end
        -- NOTE: updatePowerRange() is now called from Events.OnTick so
        -- addAreaHighlight() runs in game-tick context and renders correctly.
    else
        if self.csrRangeBtn   then self.csrRangeBtn:setVisible(false) end
        if self.csrAllGensBtn then self.csrAllGensBtn:setVisible(false) end
    end
    if CSR_GI._origPrerender then CSR_GI._origPrerender(self) end
end

function ISGeneratorInfoWindow:createChildren()
    if CSR_GI._origCreateChildren then CSR_GI._origCreateChildren(self) end
    if not CSR_FeatureFlags.isGeneratorInfoEnabled() then return end

    if not self.csrRangeBtn then
        local R = getTileRange()
        local label = string.format("Range (%dt)", R)
        local txtW = getTextManager():MeasureStringX(UIFont.Small, "Range (100t)")
        local btnW = math.max(70, txtW + 10)
        self.csrRangeBtn = ISButton:new(0, 0, btnW, 18, label, self, function()
            _range.enabled = not _range.enabled
            if _range.enabled then _range.edges = nil end
            local p = getPlayer()
            if p and p.getModData then p:getModData().CSR_ShowGenRange = _range.enabled end
        end)
        self.csrRangeBtn:initialise()
        self.csrRangeBtn:instantiate()
        self.csrRangeBtn.borderColor     = { r = PR, g = PG, b = PB, a = 0.6 }
        self.csrRangeBtn.backgroundColor = { r = 0.0, g = 0.0, b = 0.0, a = 0.6 }
        self.csrRangeBtn.tooltip = string.format("Toggle power range overlay — %d tile radius", R)
        self:addChild(self.csrRangeBtn)
    end

    -- v1.7.7: "All Gens" button -- toggles the passive multi-generator overlay
    -- that draws a dim purple ring around every activated generator on the
    -- player's Z. Sits to the left of the Range button. Same persisted state
    -- as the right-click context-menu "Show / Hide Power Range Overlay" entry.
    if not self.csrAllGensBtn then
        -- v1.7.10: relabel "All Gens" -> "Overlay: ON/OFF" so the toggle state is
        -- visible at a glance. Width is sized for the longest of the two labels.
        local txtOn  = getTextManager():MeasureStringX(UIFont.Small, "Overlay: OFF")
        local btnW = math.max(78, txtOn + 10)
        self.csrAllGensBtn = ISButton:new(0, 0, btnW, 18, "Overlay: OFF", self, function()
            if CSR_GI.togglePassiveOverlay then CSR_GI.togglePassiveOverlay() end
        end)
        self.csrAllGensBtn:initialise()
        self.csrAllGensBtn:instantiate()
        self.csrAllGensBtn.borderColor     = { r = PR, g = PG, b = PB, a = 0.6 }
        self.csrAllGensBtn.backgroundColor = { r = 0.0, g = 0.0, b = 0.0, a = 0.6 }
        self.csrAllGensBtn.tooltip = "Toggle the passive overlay around every activated generator on this floor"
        self:addChild(self.csrAllGensBtn)
    end
end

function ISGeneratorInfoWindow:setObject(object)
    if CSR_FeatureFlags.isGeneratorInfoEnabled() then
        _range.gen = object
        _range.edges = nil
        _range.lastOnState = nil
    end
    if CSR_GI._origSetObject then return CSR_GI._origSetObject(self, object) end
end

function ISGeneratorInfoWindow:setVisible(visible, ...)
    if visible and CSR_FeatureFlags.isGeneratorInfoEnabled() then
        _range.gen = getGen(self)
        _range.edges = nil
        _range.lastOnState = nil
        local p = getPlayer()
        if p and p.getModData then
            local md = p:getModData()
            _range.enabled = md.CSR_ShowGenRange ~= false
        else
            _range.enabled = true
        end
    elseif not visible then
        _range.enabled = false
        _range.gen = nil
        _range.edges = nil
    end
    if CSR_GI._origSetVisible then return CSR_GI._origSetVisible(self, visible, ...) end
end

function ISGeneratorInfoWindow:removeFromUIManager()
    _range.enabled = false
    _range.gen = nil
    _range.edges = nil
    if CSR_GI._origRemove then return CSR_GI._origRemove(self) end
end

-- ═══════════════════════════════════════════════════════════
-- Carrying Generator Preview
-- ═══════════════════════════════════════════════════════════

local function isHoldingGenerator(player)
    local prim = player:getPrimaryHandItem()
    local sec = player:getSecondaryHandItem()
    if not (prim and sec) then return false end
    if not (prim.hasTag and sec.hasTag) then return false end
    if ItemTag and ItemTag.GENERATOR then
        return prim:hasTag(ItemTag.GENERATOR) and sec:hasTag(ItemTag.GENERATOR)
    end
    return prim:hasTag("Generator") and sec:hasTag("Generator")
end

-- Idempotent event registration: prevent duplicate callbacks on world reload
if not _G.__CSR_GeneratorInfo_evRegistered then
    _G.__CSR_GeneratorInfo_evRegistered = true

-- v1.8.7: gate hot-path event registrations on the feature flag (Phoenix II).
-- Local helpers (isPassiveOverlayEnabled, setPassiveOverlayEnabled, ...) and
-- their CSR_GI exports are still defined unconditionally so other modules can
-- query them safely; only the per-tick / per-load callbacks are skipped when
-- the feature is off.
local _csrGiFlag = (CSR_FeatureFlags and CSR_FeatureFlags.isGeneratorInfoEnabled
    and CSR_FeatureFlags.isGeneratorInfoEnabled()) or false

if _csrGiFlag then
Events.OnTick.Add(function()
    if not CSR_FeatureFlags.isGeneratorInfoEnabled() then return end
    if _range.enabled then return end  -- placed-generator path will draw instead
    local player = getPlayer()
    if not player or not isHoldingGenerator(player) then return end

    local sq = player:getSquare()
    if not sq then return end
    local px, py, pz = sq:getX(), sq:getY(), sq:getZ()
    local R = getTileRange()

    buildStencil(R)
    if not _stencil.edgeOffsets then return end

    if _carry.px ~= px or _carry.py ~= py or _carry.R ~= R then
        local edges = {}
        for i = 1, #_stencil.edgeOffsets do
            edges[i] = { px + _stencil.edgeOffsets[i][1], py + _stencil.edgeOffsets[i][2] }
        end
        _carry.edges = edges
        _carry.px, _carry.py, _carry.R = px, py, R
    end

    if _carry.edges then
        drawEdges(_carry.edges, pz, 0.45)
    end
end)

-- Draw the power-range circle from a game-tick event so addAreaHighlight()
-- fires in the correct render context (before the world-render pass, not inside
-- a UI prerender which runs after the world was already composited).
Events.OnTick.Add(function()
    if not CSR_FeatureFlags.isGeneratorInfoEnabled() then return end
    updatePowerRange()
end)

-- ═══════════════════════════════════════════════════════════
-- Passive multi-generator on-ground overlay
-- (ported from Better Generator Info 42.17 — registry + union edges)
-- Renders dim purple edges for EVERY activated IsoGenerator on the
-- player's Z whenever the info window is closed and no carry preview
-- is showing. Lets players see all active generator coverage at a
-- glance without opening UI. Always-on (no user toggle yet).
-- ═══════════════════════════════════════════════════════════

local _liveGens   = {}    -- [IsoGenerator] = true
local _genCacheZ  = nil   -- last computed z
local _genEdgesZ  = nil   -- cached edges array for that z
local _genDirty   = true

local function _isGen(o) return o and instanceof and instanceof(o, "IsoGenerator") end

local function _markDirty() _genDirty = true end

Events.LoadGridsquare.Add(function(sq)
    if not sq or not sq.getObjects then return end
    local objs = sq:getObjects()
    if not objs or not objs.size then return end
    for i = 0, objs:size() - 1 do
        local o = objs:get(i)
        if _isGen(o) and not _liveGens[o] then
            _liveGens[o] = true
            _markDirty()
        end
    end
end)

Events.OnObjectAboutToBeRemoved.Add(function(o)
    if _isGen(o) and _liveGens[o] then
        _liveGens[o] = nil
        _markDirty()
    end
end)

local function rebuildPassiveEdges(playerZ)
    -- Collect all (gx,gy) of activated gens on the same Z, then union
    -- their stencils into one edge set.
    local R = getTileRange()
    buildStencil(R)
    if not _stencil.edgeOffsets then return nil end

    -- Build an inside-set: every powered tile from every active gen.
    local powered = {}
    local reach   = R + 2
    local Rsq     = R * R
    local hasAny  = false

    for gen, _ in pairs(_liveGens) do
        local valid = gen and gen.getSquare and gen.isActivated
        if valid then
            local on = gen:isActivated()
            if on == true then
                local sq = gen:getSquare()
                if sq and sq:getZ() == playerZ then
                    hasAny = true
                    local gx, gy = sq:getX(), sq:getY()
                    for dy = -R, R do
                        local ry = powered[gy + dy]
                        if not ry then ry = {}; powered[gy + dy] = ry end
                        for dx = -R, R do
                            if dx * dx + dy * dy <= Rsq then
                                ry[gx + dx] = true
                            end
                        end
                    end
                end
            end
        end
    end

    if not hasAny then return nil end

    -- Edge tiles: NOT powered but adjacent to a powered tile.
    local edges = {}
    -- Iterate only over the bounding boxes (powered keys) to keep cost down.
    for gen, _ in pairs(_liveGens) do
        local valid = gen and gen.getSquare and gen.isActivated
        if valid and gen:isActivated() == true then
            local sq = gen:getSquare()
            if sq and sq:getZ() == playerZ then
                local gx, gy = sq:getX(), sq:getY()
                for dy = -reach, reach do
                    for dx = -reach, reach do
                        local x, y = gx + dx, gy + dy
                        if not (powered[y] and powered[y][x]) then
                            -- 8-neighbor adjacency to powered
                            local touched = false
                            for i = 1, #NEIGHBORS do
                                local nx = x + NEIGHBORS[i][1]
                                local ny = y + NEIGHBORS[i][2]
                                if powered[ny] and powered[ny][nx] then
                                    touched = true
                                    break
                                end
                            end
                            if touched then
                                edges[#edges + 1] = { x, y }
                            end
                        end
                    end
                end
            end
        end
    end
    return edges
end

-- v1.7.7: persistent on/off toggle for the passive multi-gen overlay.
-- Default OFF -- player explicitly opts in via the "All Gens" title-bar
-- button or the right-click context-menu entry on any IsoGenerator.
-- State saved per-player via modData and survives reloads.
local function isPassiveOverlayEnabled()
    local p = getPlayer()
    if not p or not p.getModData then return false end
    local md = p:getModData()
    return md.CSR_PassiveGenOverlay == true
end

local function setPassiveOverlayEnabled(state)
    local p = getPlayer()
    if not p or not p.getModData then return end
    p:getModData().CSR_PassiveGenOverlay = state and true or false
    _markDirty()
end

local function togglePassiveOverlay()
    setPassiveOverlayEnabled(not isPassiveOverlayEnabled())
end

-- Expose for other CSR systems / debug.
CSR_GI.isPassiveOverlayEnabled = isPassiveOverlayEnabled
CSR_GI.setPassiveOverlayEnabled = setPassiveOverlayEnabled
CSR_GI.togglePassiveOverlay = togglePassiveOverlay

Events.OnFillWorldObjectContextMenu.Add(function(playerNum, context, worldobjects, test)
    if test then return end
    if not CSR_FeatureFlags.isGeneratorInfoEnabled() then return end
    -- Only show when right-clicking on a tile that contains a generator.
    local hasGen = false
    for i = 1, #worldobjects do
        if _isGen(worldobjects[i]) then hasGen = true; break end
    end
    if not hasGen then return end
    local label = isPassiveOverlayEnabled()
        and "Hide Power Range Overlay"
        or  "Show Power Range Overlay"
    context:addOption(label, nil, togglePassiveOverlay)
end)

Events.OnTick.Add(function()
    if not CSR_FeatureFlags.isGeneratorInfoEnabled() then return end
    if not isPassiveOverlayEnabled() then return end
    -- Defer to single-gen overlay or carry preview when active.
    if _range.enabled then return end
    -- Carry preview: skip passive when player holds a generator.
    local p = getPlayer()
    if not p then return end
    local prim = p:getPrimaryHandItem()
    local sec  = p:getSecondaryHandItem()
    if prim and sec and prim.hasTag and sec.hasTag then
        local tag = (ItemTag and ItemTag.GENERATOR) or "Generator"
        if prim:hasTag(tag) and sec:hasTag(tag) then return end
    end

    local pz = p:getZ()
    if _genDirty or _genCacheZ ~= pz then
        _genEdgesZ = rebuildPassiveEdges(pz)
        _genCacheZ = pz
        _genDirty  = false
    end
    if _genEdgesZ then
        drawEdges(_genEdgesZ, pz, 0.35)
    end
end)

-- Periodically refresh activation state changes (gen turned on/off).
local _stateTick = 0
Events.OnTick.Add(function()
    _stateTick = _stateTick + 1
    if _stateTick < 30 then return end  -- ~once per second at 30 ticks/sec
    _stateTick = 0
    -- Detect activation flips by re-marking dirty unconditionally; the
    -- rebuild is cheap because _liveGens is a small set.
    _markDirty()
end)

end -- _csrGiFlag (v1.8.7 hot-path gate)

end -- __CSR_GeneratorInfo_evRegistered guard

print("[CSR] Generator Info enhancement loaded")
