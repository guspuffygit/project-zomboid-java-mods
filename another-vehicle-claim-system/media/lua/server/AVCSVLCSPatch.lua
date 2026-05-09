--[[
VLCS_HDRcade ships a server schedule that calls `getCell():getVehicles():get(i)`,
but `IsoCell.getVehicles()` returns a `HashSet<BaseVehicle>` which has no indexed
access. The "Object tried to call nil" exception fires every EveryHours tick in
`SVLCSSystem:doPassiveAgeReset` and aborts `checkSchedule` before it can call
`delegateBatch`, so spawn-scan requests never reach clients and cars never
respawn. This patch replaces the two offenders with iterator-based versions.

Applied on the first server tick (rather than OnGameStart) so SVLCSSystem's own
SGlobalObjectSystem-derived methods are guaranteed to be wired up.
]]

if isClient() and not isServer() then
    return
end

local function applyPatch()
    if not SVLCSSystem then
        return false
    end

    if SVLCSSystem.doPassiveAgeReset and not AVCS.oSvlcsDoPassiveAgeReset then
        AVCS.oSvlcsDoPassiveAgeReset = SVLCSSystem.doPassiveAgeReset
        function SVLCSSystem:doPassiveAgeReset()
            local players = getOnlinePlayers()
            if not players or players:size() == 0 then
                return
            end
            local cell = getCell()
            if not cell then
                return
            end
            local vehicles = cell:getVehicles()
            if not vehicles then
                return
            end

            local now = getGameTime():getWorldAgeHours() / 24
            local radiusSq = 50 * 50

            local it = vehicles:iterator()
            while it:hasNext() do
                local veh = it:next()
                local vSq = veh and veh:getSquare()
                if vSq then
                    local md = veh:getModData()
                    local vx = vSq:getX()
                    local vy = vSq:getY()
                    for j = 0, players:size() - 1 do
                        local p = players:get(j)
                        local dx = p:getX() - vx
                        local dy = p:getY() - vy
                        if (dx * dx + dy * dy) < radiusSq then
                            if not md.VLCS_LastSeen or math.abs(md.VLCS_LastSeen - now) > 0.01 then
                                md.VLCS_LastSeen = now
                                veh:transmitModData()
                            end
                            break
                        end
                    end
                end
            end
        end
    end

    if SVLCSSystem.runJanitor and not AVCS.oSvlcsRunJanitor then
        AVCS.oSvlcsRunJanitor = SVLCSSystem.runJanitor
        function SVLCSSystem:runJanitor()
            local cell = getCell()
            if not cell then
                return
            end
            local vehicles = cell:getVehicles()
            if not vehicles then
                return
            end

            local removed = 0
            local now = getGameTime():getWorldAgeHours() / 24
            local limit = (SandboxVars.VLCS and SandboxVars.VLCS.JanitorAbandonmentDays) or 365

            local toRemove = {}
            local it = vehicles:iterator()
            while it:hasNext() do
                local v = it:next()
                if v then
                    local md = v:getModData()
                    if md.VLCS_LastSeen then
                        if (now - md.VLCS_LastSeen) > limit then
                            table.insert(toRemove, v)
                        end
                    else
                        md.VLCS_LastSeen = now
                        v:transmitModData()
                    end
                end
            end

            for _, v in ipairs(toRemove) do
                v:permanentlyRemove()
                removed = removed + 1
                if SandboxVars.VLCS and SandboxVars.VLCS.MaintainPopulation then
                    self:addTicket(1)
                end
            end

            self:debug("Janitor: Cleaned " .. removed .. " vehicles.")
        end
    end

    print("[AVCS] VLCS HashSet iteration patch applied.")
    return true
end

local function onFirstTick()
    Events.OnTick.Remove(onFirstTick)
    applyPatch()
end

Events.OnTick.Add(onFirstTick)
