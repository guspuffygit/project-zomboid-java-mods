---@class ZoneMarkerZone
---@field xStart number
---@field xEnd number
---@field yStart number
---@field yEnd number
---@field region string

---@class ZoneMarkerCategory
---@field name string
---@field r number Red (0-1)
---@field g number Green (0-1)
---@field b number Blue (0-1)
---@field a number Alpha (0-1)

---@class ZoneMarkerData
---@field categories ZoneMarkerCategory[]
---@field zones table<string, ZoneMarkerZone[]> Keyed by category name

---@class ZoneMarkerSharedModule
---@field MODULE string
ZoneMarkerShared = {}

ZoneMarkerShared.MODULE = "ZoneMarker"

---@param zone? ZoneMarkerZone
---@return boolean
function ZoneMarkerShared.isValidZone(zone)
    if not zone then return false end
    if type(zone.xStart) ~= "number" then return false end
    if type(zone.xEnd) ~= "number" then return false end
    if type(zone.yStart) ~= "number" then return false end
    if type(zone.yEnd) ~= "number" then return false end
    if type(zone.region) ~= "string" or zone.region == "" then return false end
    return true
end

---@param r? number
---@param g? number
---@param b? number
---@param a? number
---@return boolean
function ZoneMarkerShared.isValidColor(r, g, b, a)
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return false end
    if a ~= nil and type(a) ~= "number" then return false end
    return true
end
