local function _toNumberOrNil(v)
    if type(v) == "number" then return v end
    local n = tonumber(v)
    if n == nil or n ~= n then return nil end
    return n
end

local function _clampMin(n, minVal)
    if n == nil then return nil end
    if n < minVal then return minVal end
    return n
end

local function _fallbackWorkTimeFromPart(part)
    if not part or not part.getTable then return nil end
    local tbl = part:getTable("uninstall")
    if not tbl then return nil end
    return _toNumberOrNil(tbl.time or tbl.workTime)
end

local function _sanitizeWorkTime(part, workTime)
    local n = _toNumberOrNil(workTime)
    n = _clampMin(n, 1)
    if n then return n end

    -- fallback "giusto": dallo script della parte
    n = _fallbackWorkTimeFromPart(part)
    n = _clampMin(n, 1)
    if n then return n end

    -- ultimo fallback: non enorme
    return 120
end

local ok = pcall(require, "TimedActions/ISUninstallVehiclePart")
if ok and ISUninstallVehiclePart and ISUninstallVehiclePart.new then
    local oldNew = ISUninstallVehiclePart.new
    function ISUninstallVehiclePart:new(character, part, workTime, ...)
        workTime = _sanitizeWorkTime(part, workTime)
        return oldNew(self, character, part, workTime, ...)
    end
end
