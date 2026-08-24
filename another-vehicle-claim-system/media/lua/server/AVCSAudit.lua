--[[
AVCS only ever logged rejections, so a claim that quietly disappeared left no
trace at all and had to be reconstructed by diffing global_mod_data.bin out of
world-save backups. Every mutation of AVCSByVehicleSQLID now writes one line.
]]

if isClient() and not isServer() then
    return
end

AVCS = AVCS or {}

-- Pseudo-actors for mutations no player requested; bracketed so they can never
-- collide with a username
AVCS.AUDIT_ACTOR_TIMEOUT = "<claim-timeout>"
AVCS.AUDIT_ACTOR_JANITOR = "<vlcs-janitor>"

--[[
Kahlua's tostring() drops to Double.toString() at >= 1e14, which would render a
15-digit SQLID as 1.787563862123E15 and make the line ungreppable. %d goes
through longValue() and stays exact up to 2^53.
]]
local function fmt(value)
    if value == nil then
        return "?"
    end
    if type(value) == "number" and value == math.floor(value) then
        return string.format("%d", value)
    end
    return tostring(value)
end

--[[
Same bracket layout as the pre-existing "Warning: ..." lines so existing greps
keep working. SQLID is appended because it is the only vehicle key that survives
a restart -- the "id" field in vehicle.txt is a runtime id and gets reused.

[26-08-24 08:08:13.402] [1787563862] Unclaimed [Cussmustard] [Base.87chevySuburban] [12682,6520] [SQLID=1786992116423] [owner=Arak] [via=safehouse]
]]
---@param action string
---@param actor string username, or one of the AVCS.AUDIT_ACTOR_* pseudo-actors
---@param vehicleID number|nil AVCS SQL ID
---@param record table|nil AVCSByVehicleSQLID entry; read it before deleting it
---@param extra string|nil trailing "[k=v]" fields
function AVCS.audit(action, actor, vehicleID, record, extra)
    record = record or {}

    local line = "["
        .. getTimestamp()
        .. "] "
        .. action
        .. " ["
        .. fmt(actor)
        .. "] ["
        .. fmt(record.CarModel)
        .. "] ["
        .. fmt(record.LastLocationX)
        .. ","
        .. fmt(record.LastLocationY)
        .. "] [SQLID="
        .. fmt(vehicleID)
        .. "] [owner="
        .. fmt(record.OwnerPlayerID)
        .. "]"

    if extra then
        line = line .. " " .. extra
    end

    writeLog("AVCS", line)
end
