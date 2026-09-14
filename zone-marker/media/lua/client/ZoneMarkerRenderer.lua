require("ISUI/Maps/ISWorldMap")
require("ZoneMarkerClient")

--
-- Dynamic filter options
--
-- One duck-typed ConfigOption per category, created on demand.
-- State is keyed by category name so it persists across option panel recreations.
--

---@type table<string, boolean>
local filterState = {}
local filterRevision = 0

---@class ZoneMarkerFilterOption
---@field getName fun(self: ZoneMarkerFilterOption): string
---@field getType fun(self: ZoneMarkerFilterOption): string
---@field getValue fun(self: ZoneMarkerFilterOption): boolean
---@field setValue fun(self: ZoneMarkerFilterOption, v: boolean)

---@param categoryName string
---@return ZoneMarkerFilterOption
local function getOrCreateOption(categoryName)
    if filterState[categoryName] == nil then
        filterState[categoryName] = true -- default: visible
    end
    ---@type ZoneMarkerFilterOption
    local opt = {}
    function opt:getName()
        return categoryName
    end
    function opt:getType()
        return "boolean"
    end
    function opt:getValue()
        return filterState[categoryName]
    end
    function opt:setValue(v)
        filterState[categoryName] = v
        filterRevision = filterRevision + 1
    end
    return opt
end

--
-- Register filter options via global hook table
-- Works on both vanilla clients (monkey-patch fallback) and Storm clients (Storm calls hooks too)
--

WorldMapOptions_visibleOptionsHooks = WorldMapOptions_visibleOptionsHooks or {}

table.insert(WorldMapOptions_visibleOptionsHooks, function(result)
    for _, cat in ipairs(ZoneMarkerCache.categories) do
        table.insert(result, getOrCreateOption(cat.name))
    end
end)

-- Monkey-patch getVisibleOptions/synchUI to iterate the shared hooks table.
-- Multiple mods add hooks to the same table; only the first mod to load does the patch.
if not WorldMapOptions._visibleOptionsHooksPatched then
    local originalGetVisibleOptions = WorldMapOptions.getVisibleOptions
    function WorldMapOptions:getVisibleOptions()
        local result = originalGetVisibleOptions(self)
        for _, hook in ipairs(WorldMapOptions_visibleOptionsHooks) do
            hook(result)
        end
        return result
    end

    local originalSynchUI = WorldMapOptions.synchUI
    function WorldMapOptions:synchUI()
        local visibleOptions = self:getVisibleOptions()
        local boolCount = 0
        for _, opt in ipairs(visibleOptions) do
            if opt:getType() == "boolean" then
                boolCount = boolCount + 1
            end
        end
        if boolCount ~= (self._lastBoolCount or -1) then
            local children = {}
            for k, v in pairs(self:getChildren()) do
                table.insert(children, v)
            end
            for _, child in ipairs(children) do
                self:removeChild(child)
            end
            self:createChildren()
            self._lastBoolCount = boolCount
        end
        originalSynchUI(self)
    end

    WorldMapOptions._visibleOptionsHooksPatched = true
end

--
-- Zone rendering
--

-- A category rename can keep the option count unchanged. Invalidate the shared
-- options UI regardless of whether AVCS or Zone Marker installed its wrapper first.
local originalOptionsSync = WorldMapOptions.synchUI
function WorldMapOptions:synchUI()
    if self._zoneMarkerVersion ~= ZoneMarkerCache.version then
        self._lastBoolCount = nil
    end
    originalOptionsSync(self)
    self._zoneMarkerVersion = ZoneMarkerCache.version
end

---@type number
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)

---@param javaObject UIWorldMap
---@param api UIWorldMapV3
---@param worldX number
---@param worldY number
---@param name string
local function renderZoneLabel(javaObject, api, worldX, worldY, name, textW)
    local sx = PZMath.floor(api:worldToUIX(worldX, worldY))
    local sy = PZMath.floor(api:worldToUIY(worldX, worldY))
    local lineH = FONT_HGT_SMALL
    local boxH = math.ceil(lineH * 1.25)
    -- background
    javaObject:DrawTextureScaledColor(nil, sx - textW / 2, sy + 4, textW, boxH, 0.5, 0.5, 0.5, 0.5)
    -- text
    javaObject:DrawTextCentre(name, sx, sy + 4 + (boxH - lineH) / 2, 0, 0, 0, 1)
end

---@param mapUI ISWorldMap
---@param zone ZoneMarkerZone
---@param r number
---@param g number
---@param b number
---@param a number
local function renderZone(mapUI, zone, r, g, b, a, textW)
    local api = mapUI.mapAPI
    local javaObject = mapUI.javaObject

    local x1 = api:worldToUIX(zone.xStart, zone.yStart)
    local y1 = api:worldToUIY(zone.xStart, zone.yStart)
    local x2 = api:worldToUIX(zone.xEnd, zone.yEnd)
    local y2 = api:worldToUIY(zone.xEnd, zone.yEnd)

    javaObject:DrawTextureScaledColor(
        nil,
        PZMath.floor(x1),
        PZMath.floor(y1),
        x2 - x1,
        y2 - y1,
        r,
        g,
        b,
        a
    )

    local midX = (zone.xStart + zone.xEnd) / 2
    local midY = (zone.yStart + zone.yEnd) / 2
    renderZoneLabel(javaObject, api, midX, midY, zone.region, textW)
end

--
-- Patch ISWorldMap:render() to draw our overlays
--

local originalRender = ISWorldMap.render
local entries, cachedVersion, cachedFilter, margin = {}, nil, nil, 0

local function refreshEntries()
    if cachedVersion == ZoneMarkerCache.version and cachedFilter == filterRevision then
        return
    end
    entries, margin = {}, 0
    cachedVersion, cachedFilter = ZoneMarkerCache.version, filterRevision
    for _, cat in ipairs(ZoneMarkerCache.categories) do
        if filterState[cat.name] ~= false then
            for _, zone in ipairs(ZoneMarkerCache.zones[cat.name] or {}) do
                local width = getTextManager():MeasureStringX(UIFont.Small, zone.region) + 16
                entries[#entries + 1] = { zone = zone, cat = cat, width = width }
                margin = math.max(margin, width / 2, FONT_HGT_SMALL * 2)
            end
        end
    end
end

function ISWorldMap:render()
    originalRender(self)

    refreshEntries()
    -- Four corners keep the broad-phase bounds conservative on rotated maps.
    local api, w, h = self.mapAPI, self:getWidth(), self:getHeight()
    local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
    for _, x in ipairs({ -margin, w + margin }) do
        for _, y in ipairs({ -margin, h + margin }) do
            local wx, wy = api:uiToWorldX(x, y), api:uiToWorldY(x, y)
            minX, minY = math.min(minX, wx), math.min(minY, wy)
            maxX, maxY = math.max(maxX, wx), math.max(maxY, wy)
        end
    end
    for _, entry in ipairs(entries) do
        local zone, cat = entry.zone, entry.cat
        if
            zone.xEnd >= minX
            and zone.xStart <= maxX
            and zone.yEnd >= minY
            and zone.yStart <= maxY
        then
            renderZone(self, zone, cat.r, cat.g, cat.b, cat.a, entry.width)
        end
    end
end
