-- Local-only diagnostics. No entity iteration, server requests, GC forcing or game mutations.
AdminDiagnostics = AdminDiagnostics or {}
local D = AdminDiagnostics
if D.recorderInstalled then
    return
end
D.recorderInstalled = true
D.version = "0.1.0"
D.config = {
    sampleMs = 2000,
    historySize = 30,
    afterMs = 20000,
    warmupMs = 10000,
    cooldownMs = 60000,
    globalCooldownMs = 10000,
    maxPartBytes = 2 * 1024 * 1024,
    parts = 4,
    maxReasons = 128,
    lowRenderHz = 15,
    stallMs = 1000,
    heapSpikeMiB = 256,
    checkpointMs = 60000,
}
local eventNames = {
    "OnTick",
    "OnPostRender",
    "OnPostUIDraw",
    "OnCreateUI",
    "OnResetLua",
    "OnDisconnect",
    "OnConnectionStateChanged",
}
local function now()
    return getTimestampMs()
end
local function safe(fn)
    local ok, value = pcall(fn)
    if ok then
        return value
    end
end
function D.allowed()
    return safe(function()
        local p = getPlayer()
        return isClient() and p and p:getRole() and p:getRole():hasAdminPower()
    end) == true
end
local function clean(s, limit)
    return tostring(s or ""):gsub("[%c]", " "):sub(1, limit or 120)
end
local function quote(s)
    return '"'
        .. tostring(s)
            :gsub("\\", "\\\\")
            :gsub('"', '\\"')
            :gsub("\n", "\\n")
            :gsub("\r", "\\r")
            :gsub("\t", "\\t")
        .. '"'
end
function D.encode(record)
    local fields = {}
    for key, value in pairs(record) do
        local kind = type(value)
        if kind == "string" then
            value = quote(clean(value, 1200))
        elseif kind == "boolean" then
            value = tostring(value)
        elseif kind == "number" and value == value and math.abs(value) < math.huge then
            value = tostring(value)
        else
            value = quote("unavailable")
        end
        fields[#fields + 1] = quote(key) .. ":" .. value
    end
    table.sort(fields)
    return "[ADMIN-DIAG] " .. "{" .. table.concat(fields, ",") .. "}\n"
end
function D.write(record)
    if D.writeFailed then
        return
    end
    record.session = D.session
    local line = D.encode(record)
    if D.partBytes + #line > D.config.maxPartBytes then
        D.part = D.part % D.config.parts + 1
        D.partBytes = 0
    end
    local writer
    local ok = pcall(function()
        writer = assert(getFileWriter("admin-diag-" .. D.part .. ".log", true, D.partBytes > 0))
        writer:write(line)
        writer:close()
        writer = nil
    end)
    if not ok then
        if writer then
            pcall(function()
                writer:close()
            end)
        end
        D.writeFailed = true
        -- Disable first: a broken disk or formatter must never create a per-frame error loop.
        D.detach()
        print("[ADMIN-DIAG] Recorder disabled: could not write its local log.")
        return
    end
    D.partBytes = D.partBytes + #line
end
local function count(fn)
    return safe(function()
        local list = fn()
        return list and list:size()
    end)
end
function D.snapshot(time)
    local s = { epochMs = time, elapsedMs = time - D.lastSample }
    s.tickHz = D.ticks * 1000 / math.max(1, s.elapsedMs)
    s.renderHz = D.frames * 1000 / math.max(1, s.elapsedMs)
    s.uiDrawHz = D.uiFrames * 1000 / math.max(1, s.elapsedMs)
    s.maxTickGapMs = D.maxTickGap
    s.knownPlayers = count(function()
        return getOnlinePlayers()
    end)
    local cell = safe(getCell)
    s.cellPresent = cell ~= nil
    if cell then
        s.loadedVehicles = count(function()
            return cell:getVehicles()
        end)
        s.loadedZombies = count(function()
            return cell:getZombieList()
        end)
        s.loadedAnimals = count(function()
            return cell:getAnimals()
        end)
        s.loadedRemotePlayers = count(function()
            return cell:getRemoteSurvivorList()
        end)
    end
    local p = safe(getPlayer)
    s.playerPresent = p ~= nil
    if p then
        s.x, s.y, s.z = p:getX(), p:getY(), p:getZ()
        s.role = clean(p:getAccessLevel(), 40)
        s.squarePresent = p:getCurrentSquare() ~= nil
        s.dead = p:isDead()
        s.inVehicle = p:getVehicle() ~= nil
        s.invisible = p:isInvisible()
        s.god = p:isGodMod()
        s.noclip = p:isNoClip()
        s.selfAlpha = safe(function()
            return p:getAlpha(p:getPlayerNum())
        end)
    end
    s.luaErrors = safe(getLuaDebuggerErrorCount)
    s.observeTarget = AdminCore and AdminCore.observing and clean(AdminCore.observing, 64) or ""
    local panels = {}
    local ui = safe(function()
        return UIManager.getUI()
    end)
    if ui then
        s.uiElements, s.uiVisible = ui:size(), 0
        for i = 0, math.min(ui:size(), 128) - 1 do
            local element = ui:get(i)
            if safe(function()
                return element:isVisible()
            end) then
                s.uiVisible = s.uiVisible + 1
                local t = safe(function()
                    return element:getTable()
                end)
                if t and #panels < 24 then
                    panels[#panels + 1] = clean(t.Type or "LuaUI", 48)
                end
            end
        end
        s.uiTruncated = ui:size() > 128
    end
    s.panels = table.concat(panels, ",")
    s.jvmProbe = AdminDiagnosticsProbe ~= nil and not D.probeFailed
    if s.jvmProbe then
        local metrics = safe(function()
            return AdminDiagnosticsProbe.snapshot()
        end)
        if type(metrics) == "table" then
            for _, key in ipairs({
                "heapUsedMiB",
                "heapCommittedMiB",
                "heapMaxMiB",
                "gcCount",
                "gcMillis",
                "sharedChunks",
                "uiGlobalVisible",
                "pingMs",
                "fullyConnected",
            }) do
                s[key] = metrics[key]
            end
        else
            D.probeFailed = true
            s.jvmProbe = false
        end
    end
    return s
end
local function sampleRecord(sample, kind, reason, incident)
    local record = {}
    for key, value in pairs(sample) do
        record[key] = value
    end
    record.kind, record.reason, record.incident = kind, reason, incident
    return record
end
function D.incident(reason, sample, manual)
    if not D.enabled then
        return false
    end
    local time = sample.epochMs
    local cooldown = manual and 5000 or D.config.cooldownMs
    if
        time - (D.reasonTimes[reason] or -math.huge) < cooldown
        or (not manual and time - D.lastIncident < D.config.globalCooldownMs)
    then
        D.suppressed = D.suppressed + 1
        return false
    end
    if D.reasonTimes[reason] == nil then
        if D.reasonCount >= D.config.maxReasons then
            D.reasonTimes, D.reasonCount = {}, 0
        end
        D.reasonCount = D.reasonCount + 1
    end
    D.reasonTimes[reason], D.lastIncident = time, time
    D.incidentNumber = D.incidentNumber + 1
    D.write({
        kind = "incident",
        epochMs = time,
        reason = reason,
        incident = D.incidentNumber,
        suppressed = D.suppressed,
    })
    D.suppressed = 0
    for _, old in ipairs(D.history) do
        D.write(sampleRecord(old, "before", reason, D.incidentNumber))
    end
    D.write(sampleRecord(sample, "trigger", reason, D.incidentNumber))
    D.afterUntil = time + D.config.afterMs
    return true
end
function D.detect(s, previous)
    if not previous or s.epochMs - D.started < D.config.warmupMs then
        return nil
    end
    local reasons = {}
    local function add(reason)
        reasons[#reasons + 1] = reason
    end
    local dx, dy = 0, 0
    if s.x and previous.x then
        dx, dy = s.x - previous.x, s.y - previous.y
    end
    local moved = dx * dx + dy * dy
    if moved >= 6400 or (s.z and previous.z and math.abs(s.z - previous.z) > 2) then
        add("position_jump")
        D.movementGraceUntil = s.epochMs + 15000
    end
    if s.maxTickGapMs >= D.config.stallMs then
        add("client_tick_stall")
    end
    D.lowFrames = s.renderHz < D.config.lowRenderHz and D.lowFrames + 1 or 0
    if D.lowFrames == 3 then
        add("sustained_low_render_rate")
    end
    D.noUiFrames = s.uiDrawHz == 0 and D.noUiFrames + 1 or 0
    if D.noUiFrames == 3 then
        add("ui_draw_callbacks_stopped")
    end
    if
        s.heapUsedMiB
        and previous.heapUsedMiB
        and s.heapUsedMiB - previous.heapUsedMiB >= D.config.heapSpikeMiB
    then
        add("heap_spike")
    end
    if s.heapMaxMiB and s.heapMaxMiB > 0 and s.heapUsedMiB >= s.heapMaxMiB * 0.9 then
        add("heap_pressure")
    end
    if s.gcMillis and previous.gcMillis and s.gcMillis - previous.gcMillis >= 500 then
        add("gc_collection_time_increased")
    end
    if s.pingMs and s.pingMs > 500 and (not previous.pingMs or previous.pingMs <= 500) then
        add("high_ping")
    end
    if s.luaErrors and previous.luaErrors and s.luaErrors > previous.luaErrors then
        add("lua_error_count_increased")
    end
    if s.uiGlobalVisible == false and previous.uiGlobalVisible == true then
        add("global_ui_hidden")
    end
    if
        s.uiVisible
        and previous.uiVisible
        and previous.uiVisible >= 4
        and s.uiVisible <= previous.uiVisible / 4
        and not s.uiTruncated
        and not previous.uiTruncated
    then
        add("visible_ui_count_dropped")
    end
    D.missingSquare = (not s.playerPresent or not s.squarePresent) and D.missingSquare + 1 or 0
    if D.missingSquare == 2 then
        add("local_player_or_square_missing")
    end
    if s.selfAlpha and previous.selfAlpha and previous.selfAlpha > 0.5 and s.selfAlpha <= 0.05 then
        add("local_player_alpha_dropped")
    end
    if moved < 256 and s.z == previous.z and s.epochMs > D.movementGraceUntil and not s.dead then
        for _, metric in ipairs({
            "loadedVehicles",
            "loadedZombies",
            "loadedAnimals",
            "loadedRemotePlayers",
            "sharedChunks",
        }) do
            local minimum = metric == "loadedZombies" and 20 or 3
            if
                s[metric]
                and previous[metric]
                and previous[metric] >= minimum
                and s[metric] <= previous[metric] / 4
            then
                add(metric .. "_dropped")
            end
        end
    end
    if #reasons > 0 then
        return table.concat(reasons, ",")
    end
end
function D.sample()
    local time = now()
    local s = D.snapshot(time)
    local reason = D.detect(s, D.previous)
    if reason then
        D.incident(reason, s)
    end
    if time <= D.afterUntil then
        D.write(sampleRecord(s, "after", "incident_followup", D.incidentNumber))
    elseif time - D.lastCheckpoint >= D.config.checkpointMs then
        D.write(sampleRecord(s, "checkpoint", "last_known_state", D.incidentNumber))
        D.lastCheckpoint = time
    end
    D.history[#D.history + 1] = s
    if #D.history > D.config.historySize then
        table.remove(D.history, 1)
    end
    D.previous, D.lastSample = s, time
    D.ticks, D.frames, D.uiFrames, D.maxTickGap = 0, 0, 0, 0
end
function D.detach()
    D.enabled = false
    for _, name in ipairs(eventNames) do
        if Events[name] and D.handlers[name] then
            Events[name].Remove(D.handlers[name])
        end
    end
end
local function guarded(fn)
    return function(...)
        if not D.enabled then
            return
        end
        local ok = pcall(fn, ...)
        if not ok then
            D.detach()
            -- No recursion through a potentially failing sample or writer.
            print("[ADMIN-DIAG] Recorder disabled after an internal sampling error.")
        end
    end
end
function D.stop(reason)
    if not D.enabled then
        return
    end
    for _, sample in ipairs(D.history) do
        D.write(
            sampleRecord(sample, "session_tail", clean(reason or "manual_stop"), D.incidentNumber)
        )
    end
    D.write({ kind = "stopped", epochMs = now(), reason = clean(reason or "manual_stop") })
    D.detach()
end
function D.mark(reason)
    if not D.enabled or not D.allowed() then
        return
    end
    local ok, sample = pcall(D.snapshot, now())
    if not ok then
        D.stop("manual_sample_unavailable")
        return
    end
    D.incident(clean(reason or "manual_visible_failure"), sample, true)
end
D.handlers = {
    OnTick = guarded(function()
        local time = now()
        D.ticks = D.ticks + 1
        D.maxTickGap = math.max(D.maxTickGap, time - D.lastTick)
        D.lastTick = time
        if time - D.lastSample >= D.config.sampleMs then
            -- A missing player is evidence; only a present player losing staff permission stops recording.
            if getPlayer() and not D.allowed() then
                D.stop("staff_permission_lost")
                return
            end
            D.sample()
        end
    end),
    OnPostRender = function()
        D.frames = D.frames + 1
    end,
    OnPostUIDraw = function()
        D.uiFrames = D.uiFrames + 1
    end,
    OnCreateUI = guarded(function()
        D.incident("ui_reinitialized", D.snapshot(now()))
    end),
    OnResetLua = guarded(function()
        D.stop("lua_reset")
    end),
    OnDisconnect = guarded(function()
        D.incident("disconnected", D.snapshot(now()), true)
        D.stop("disconnected")
    end),
    OnConnectionStateChanged = guarded(function(state)
        D.incident("connection_state_" .. clean(state, 40), D.snapshot(now()))
    end),
}
function D.start()
    if D.enabled or not D.allowed() then
        return false
    end
    local time = now()
    D.started, D.lastSample, D.lastTick, D.lastCheckpoint = time, time, time, time
    D.session = tostring(time)
    D.part, D.partBytes, D.writeFailed = math.floor(time / 1000) % D.config.parts + 1, 0, false
    D.history, D.reasonTimes, D.previous = {}, {}, nil
    D.reasonCount = 0
    D.ticks, D.frames, D.uiFrames, D.maxTickGap = 0, 0, 0, 0
    D.lowFrames, D.noUiFrames, D.missingSquare = 0, 0, 0
    D.lastIncident, D.afterUntil, D.movementGraceUntil = -math.huge, 0, 0
    D.incidentNumber, D.suppressed, D.probeFailed = 0, 0, false
    D.enabled = true
    local metadata = {
        kind = "session_start",
        epochMs = time,
        version = D.version,
        clientUsername = safe(function()
            return clean(getPlayer():getUsername(), 80)
        end),
        gameVersion = safe(function()
            return getCore():getVersion()
        end),
        width = safe(function()
            return getCore():getScreenWidth()
        end),
        height = safe(function()
            return getCore():getScreenHeight()
        end),
        note = "Loaded counts are not rendering visibility; renderHz measures Lua render callbacks; heap is not process RAM.",
    }
    for key, value in pairs(D.config) do
        metadata[key] = value
    end
    D.write(metadata)
    if not D.enabled then
        return false
    end
    for _, name in ipairs(eventNames) do
        if Events[name] then
            Events[name].Add(D.handlers[name])
        end
    end
    return true
end
