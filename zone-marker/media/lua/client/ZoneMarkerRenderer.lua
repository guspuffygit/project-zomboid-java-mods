require "ISUI/Maps/ISWorldMap"
require "ZoneMarkerClient"

--
-- Dynamic filter options
--
-- One duck-typed ConfigOption per category, created on demand.
-- State is keyed by category name so it persists across option panel recreations.
--

---@type table<string, boolean>
local filterState = {}

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
    function opt:getName() return categoryName end
    function opt:getType() return "boolean" end
    function opt:getValue() return filterState[categoryName] end
    function opt:setValue(v) filterState[categoryName] = v end
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
            if opt:getType() == "boolean" then boolCount = boolCount + 1 end
        end
        if boolCount ~= (self._lastBoolCount or -1) then
            local children = {}
            for k, v in pairs(self:getChildren()) do table.insert(children, v) end
            for _, child in ipairs(children) do self:removeChild(child) end
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

---@type number
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)

---@param javaObject UIWorldMap
---@param api UIWorldMapV3
---@param worldX number
---@param worldY number
---@param name string
local function renderZoneLabel(javaObject, api, worldX, worldY, name)
    local sx = PZMath.floor(api:worldToUIX(worldX, worldY))
    local sy = PZMath.floor(api:worldToUIY(worldX, worldY))
    local textW = getTextManager():MeasureStringX(UIFont.Small, name) + 16
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
local function renderZone(mapUI, zone, r, g, b, a)
    local api = mapUI.mapAPI
    local javaObject = mapUI.javaObject

    local x1 = api:worldToUIX(zone.xStart, zone.yStart)
    local y1 = api:worldToUIY(zone.xStart, zone.yStart)
    local x2 = api:worldToUIX(zone.xEnd, zone.yEnd)
    local y2 = api:worldToUIY(zone.xEnd, zone.yEnd)

    javaObject:DrawTextureScaledColor(nil, PZMath.floor(x1), PZMath.floor(y1), x2 - x1, y2 - y1, r, g, b, a)

    local midX = (zone.xStart + zone.xEnd) / 2
    local midY = (zone.yStart + zone.yEnd) / 2
    renderZoneLabel(javaObject, api, midX, midY, zone.region)
end

--
-- Patch ISWorldMap:render() to draw our overlays
--

local originalRender = ISWorldMap.render

function ISWorldMap:render()
    originalRender(self)

    for _, cat in ipairs(ZoneMarkerCache.categories) do
        if filterState[cat.name] ~= false then
            local zones = ZoneMarkerCache.zones[cat.name]
            if zones then
                for _, zone in ipairs(zones) do
                    renderZone(self, zone, cat.r, cat.g, cat.b, cat.a)
                end
            end
        end
    end
end
