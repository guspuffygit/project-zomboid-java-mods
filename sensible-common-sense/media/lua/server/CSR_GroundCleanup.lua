if not isServer() then
    return
end

CSR_GroundCleanup = {}

local TAG_TIME = "CSR_GC_T"
local TAG_PROTECTED = "CSR_GC_P"
local CHUNK_SIZE = 10

local function sandbox()
    return SandboxVars and SandboxVars.CommonSenseReborn or {}
end

local function getConfig()
    local sv = sandbox()
    local minutes = tonumber(sv.GroundCleanupMinutes) or 1440
    return {
        enabled = sv.EnableGroundCleanup == true,
        cleanupHours = minutes / 60,
        cleanupMinutes = minutes,
        scanRadius = tonumber(sv.GroundCleanupScanRadius) or 40,
        maxZ = tonumber(sv.GroundCleanupMaxZ) or 3,
        maxPerScan = tonumber(sv.GroundCleanupMaxPerScan) or 250,
        logEnabled = sv.LogGroundCleanup ~= false,
    }
end

local function isEligibleWorldItem(worldObj)
    if not worldObj or not instanceof(worldObj, "IsoWorldInventoryObject") then
        return false
    end

    if worldObj.isIgnoreRemoveSandbox and worldObj:isIgnoreRemoveSandbox() then
        return false
    end

    -- v1.8.0: third-party mod compat guard.
    -- Some mods place stateful objects on the ground via ISPlace3DItemCursor and
    -- store their state on the WORLD OBJECT's modData rather than on the
    -- underlying inventory item (e.g. Zeer evaporative cooler stores waterUnits,
    -- coolingPercent, isCovered on worldObj:getModData()). If we delete the
    -- world object the engine silently nukes that state. CSR itself never
    -- writes to IsoWorldInventoryObject:getModData() -- we tag inventory items
    -- only -- so any non-empty world-object modData is a high-confidence signal
    -- that another mod owns this object. Skip cleanup.
    -- DO NOT start writing to worldObj:getModData() in CSR features without
    -- updating this guard, or you will re-break Zeer / similar mods.
    if worldObj.getModData then
        local woMd = worldObj:getModData()
        if woMd then
            for _ in pairs(woMd) do
                return false
            end
        end
    end

    local item = worldObj.getItem and worldObj:getItem() or nil
    if not item or not item.getModData then
        return false
    end

    -- v1.8.5: never wipe dropped generators. A Generator inventory item
    -- placed on the floor (carried but not yet installed) stores fuel,
    -- condition, activation state etc. on the inventory item -- losing it
    -- to the cleanup scan is destructive in a way players cannot recover
    -- from. Installed IsoGenerator instances are already excluded by the
    -- IsoWorldInventoryObject check above; this guard covers the dropped-
    -- but-not-placed window.
    if item.getType then
        local ok, t = pcall(function() return item:getType() end)
        if ok and t == "Generator" then return false end
    end

    local modData = item:getModData()
    if modData and modData[TAG_PROTECTED] then
        return false
    end

    return true
end

local function removeWorldItem(square, worldObj, item)
    if not square or not worldObj then
        return false
    end

    if square.transmitRemoveItemFromSquare then
        square:transmitRemoveItemFromSquare(worldObj)
    end
    if square.removeWorldObject then
        square:removeWorldObject(worldObj)
    end
    if item and item.setWorldItem then
        item:setWorldItem(nil)
    end

    return true
end

local function processSquare(square, nowHours, maxAgeHours, remainingBudget)
    if remainingBudget <= 0 or not square then
        return 0
    end

    local objects = square:getObjects()
    if not objects or objects:size() == 0 then
        return 0
    end

    local removed = 0
    for i = objects:size() - 1, 0, -1 do
        if removed >= remainingBudget then
            break
        end

        local worldObj = objects:get(i)
        if isEligibleWorldItem(worldObj) then
            local item = worldObj:getItem()
            local modData = item:getModData()
            local stampedAt = tonumber(modData[TAG_TIME])

            if not stampedAt then
                modData[TAG_TIME] = nowHours
            elseif (nowHours - stampedAt) >= maxAgeHours then
                if removeWorldItem(square, worldObj, item) then
                    removed = removed + 1
                end
            end
        end
    end

    return removed
end

function CSR_GroundCleanup.scan()
    local cfg = getConfig()
    if not cfg.enabled then
        return
    end

    local cell = getCell()
    local players = getOnlinePlayers and getOnlinePlayers() or nil
    if not cell or not players or players:size() == 0 then
        return
    end

    local nowHours = getGameTime():getWorldAgeHours()
    local chunkRadius = math.ceil(cfg.scanRadius / CHUNK_SIZE)
    local seenChunks = {}
    local totalRemoved = 0

    for p = 0, players:size() - 1 do
        if totalRemoved >= cfg.maxPerScan then
            break
        end

        local player = players:get(p)
        if player then
            local pcx = math.floor(player:getX() / CHUNK_SIZE)
            local pcy = math.floor(player:getY() / CHUNK_SIZE)

            for cx = pcx - chunkRadius, pcx + chunkRadius do
                if totalRemoved >= cfg.maxPerScan then
                    break
                end

                for cy = pcy - chunkRadius, pcy + chunkRadius do
                    if totalRemoved >= cfg.maxPerScan then
                        break
                    end

                    local key = cx * 131072 + cy
                    if not seenChunks[key] then
                        seenChunks[key] = true

                        local baseX = cx * CHUNK_SIZE
                        local baseY = cy * CHUNK_SIZE
                        for z = 0, cfg.maxZ do
                            if totalRemoved >= cfg.maxPerScan then
                                break
                            end

                            for lx = 0, CHUNK_SIZE - 1 do
                                if totalRemoved >= cfg.maxPerScan then
                                    break
                                end

                                for ly = 0, CHUNK_SIZE - 1 do
                                    if totalRemoved >= cfg.maxPerScan then
                                        break
                                    end

                                    local square = cell:getGridSquare(baseX + lx, baseY + ly, z)
                                    if square then
                                        totalRemoved = totalRemoved + processSquare(
                                            square,
                                            nowHours,
                                            cfg.cleanupHours,
                                            cfg.maxPerScan - totalRemoved
                                        )
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    if totalRemoved > 0 and cfg.logEnabled then
        print("[CSR] Ground cleanup removed " .. tostring(totalRemoved)
            .. " loose world items older than " .. tostring(cfg.cleanupMinutes) .. " minutes")
    end
end

local function onPlayerDropItem(player, item)
    if not item or not item.getModData then
        return
    end

    local modData = item:getModData()
    if not modData[TAG_TIME] then
        modData[TAG_TIME] = getGameTime():getWorldAgeHours()
    end
end

-- ─── Forced Item Wipe Scheduler ──────────────────────────────────────────────
-- Separate from the age-based cleanup: removes ALL eligible ground items near
-- players on a fixed real-time interval. Each client receives a countdown via
-- the ItemWipeStatus server command so the Utility HUD can show a timer.

local _wipeState = {
    nextWipeRealSec = nil,   -- os.time() value when next wipe fires (real-world seconds)
    intervalMinutes = 0,
    warned          = false, -- one-shot flag: warning already sent for current cycle
}

-- Remove all eligible items on a square without age check (forced wipe variant).
local function processSquareForcedWipe(square, remainingBudget)
    if remainingBudget <= 0 or not square then return 0 end
    local objects = square:getObjects()
    if not objects or objects:size() == 0 then return 0 end
    local removed = 0
    for i = objects:size() - 1, 0, -1 do
        if removed >= remainingBudget then break end
        local worldObj = objects:get(i)
        if isEligibleWorldItem(worldObj) then
            local item = worldObj:getItem()
            if removeWorldItem(square, worldObj, item) then
                removed = removed + 1
            end
        end
    end
    return removed
end

local function broadcastWipeStatus(remainingSeconds, wiping)
    local players = getOnlinePlayers and getOnlinePlayers() or nil
    if not players then return end
    for i = 0, players:size() - 1 do
        local p = players:get(i)
        if p then
            sendServerCommand(p, "CommonSenseReborn", "ItemWipeStatus", {
                remainingSeconds = remainingSeconds,
                wiping           = wiping == true,
            })
        end
    end
end

local function broadcastWipeWarning(remainingSeconds)
    local players = getOnlinePlayers and getOnlinePlayers() or nil
    if not players then return end
    for i = 0, players:size() - 1 do
        local p = players:get(i)
        if p then
            sendServerCommand(p, "CommonSenseReborn", "ItemWipeWarning", {
                remainingSeconds = remainingSeconds,
            })
        end
    end
end

local function forcedWipeScan()
    local cfg = getConfig()
    local cell = getCell()
    local players = getOnlinePlayers and getOnlinePlayers() or nil
    if not cell or not players or players:size() == 0 then return end

    local chunkRadius = math.ceil(cfg.scanRadius / CHUNK_SIZE)
    local seenChunks  = {}
    local totalRemoved = 0
    local wipeLimit    = (cfg.maxPerScan or 250) * 4

    for p = 0, players:size() - 1 do
        if totalRemoved >= wipeLimit then break end
        local player = players:get(p)
        if player then
            local pcx = math.floor(player:getX() / CHUNK_SIZE)
            local pcy = math.floor(player:getY() / CHUNK_SIZE)
            for cx = pcx - chunkRadius, pcx + chunkRadius do
                if totalRemoved >= wipeLimit then break end
                for cy = pcy - chunkRadius, pcy + chunkRadius do
                    if totalRemoved >= wipeLimit then break end
                    local key = cx * 131072 + cy
                    if not seenChunks[key] then
                        seenChunks[key] = true
                        local baseX = cx * CHUNK_SIZE
                        local baseY = cy * CHUNK_SIZE
                        for z = 0, cfg.maxZ do
                            if totalRemoved >= wipeLimit then break end
                            for lx = 0, CHUNK_SIZE - 1 do
                                if totalRemoved >= wipeLimit then break end
                                for ly = 0, CHUNK_SIZE - 1 do
                                    if totalRemoved >= wipeLimit then break end
                                    local sq = cell:getGridSquare(baseX + lx, baseY + ly, z)
                                    totalRemoved = totalRemoved
                                        + processSquareForcedWipe(sq, wipeLimit - totalRemoved)
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    if cfg.logEnabled then
        print("[CSR] Forced item wipe removed " .. tostring(totalRemoved) .. " ground items")
    end
end

local function checkItemWipeSchedule()
    local sv = sandbox()
    if sv.EnableItemWipeScheduler ~= true then return end
    local interval = tonumber(sv.ItemWipeIntervalMinutes) or 360
    if interval <= 0 then return end
    local warnMinutes = tonumber(sv.ItemWipeWarnMinutes) or 60

    local nowSec        = os.time()
    local intervalSec   = interval * 60
    local warnSec       = warnMinutes * 60

    -- First-time initialization
    if not _wipeState.nextWipeRealSec then
        _wipeState.nextWipeRealSec = nowSec + intervalSec
        _wipeState.intervalMinutes = interval
        _wipeState.warned          = false
        broadcastWipeStatus(intervalSec, false)
        return
    end

    -- Sandbox interval changed mid-session: re-anchor cycle to "interval-from-now"
    -- so the HUD countdown reflects the new value immediately.
    if _wipeState.intervalMinutes ~= interval then
        _wipeState.nextWipeRealSec = nowSec + intervalSec
        _wipeState.intervalMinutes = interval
        _wipeState.warned          = false
        broadcastWipeStatus(intervalSec, false)
        return
    end

    local remainingSec = _wipeState.nextWipeRealSec - nowSec
    if remainingSec <= 0 then
        broadcastWipeStatus(0, true)
        forcedWipeScan()
        _wipeState.nextWipeRealSec = nowSec + intervalSec
        _wipeState.warned          = false
        broadcastWipeStatus(intervalSec, false)
    else
        broadcastWipeStatus(remainingSec, false)
        -- One-shot warning broadcast when crossing the warn threshold
        if warnSec > 0 and not _wipeState.warned and remainingSec <= warnSec then
            _wipeState.warned = true
            broadcastWipeWarning(remainingSec)
        end
    end
end

-- ─────────────────────────────────────────────────────────────────────────────

if not _G.__CSR_GroundCleanup_evRegistered then
    _G.__CSR_GroundCleanup_evRegistered = true
    Events.EveryOneMinute.Add(CSR_GroundCleanup.scan)
    Events.EveryOneMinute.Add(checkItemWipeSchedule)
    if Events.OnPlayerDropItem then
        Events.OnPlayerDropItem.Add(onPlayerDropItem)
    end
end

return CSR_GroundCleanup
