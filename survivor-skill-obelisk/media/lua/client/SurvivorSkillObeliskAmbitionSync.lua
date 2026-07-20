--
-- SurvivorSkillObeliskAmbitionSync.lua
-- Mirrors the goal-progress fields of the Lifestyles mod's Ambitions table from
-- the client to the server-side player modData.
--
-- Lifestyles' per-ambition handlers update goalNprogress in client-only Lua
-- every game minute (e.g. LSTerminator recomputes kill progress), but its own
-- client->server mirror (LS:SavePlayerData) only fires on discrete events
-- (complete, unlock, assign, reset) plus a configurable timer. In-progress goal
-- counts earned since the last mirror don't exist on the server, so the obelisk
-- death snapshot records stale progress. This script watches the flags and
-- progress slots and pushes them to SyncAmbitionsHandler within a game minute
-- of any change. The server merges per-field, so Lifestyles' sidecar state
-- (ogKills baselines etc.) is never disturbed.
--

local MODULE = "SurvivorSkillObelisk"
local SYNC_COMMAND = "syncAmbitions"

-- Must match SyncAmbitionsHandler.ALLOWED_FIELDS minus the static name/cat/goalN
-- definition fields: only these change during play, so only these feed the
-- change signature.
local SIGNATURE_FIELDS = {
    "completed",
    "isActive",
    "isPassive",
    "goal1progress",
    "goal2progress",
    "goal3progress",
    "goal4progress",
    "goal5progress",
    "goal6progress",
}

-- State lives on a global so a hot-reload of this file keeps the signature and
-- doesn't stack a second set of event handlers.
SurvivorSkillObeliskAmbitionSync = SurvivorSkillObeliskAmbitionSync or {}
local AmbitionSync = SurvivorSkillObeliskAmbitionSync

-- Ambition names are sorted so the signature is stable across pairs() ordering.
local function computeSignature(ambitions)
    local names = {}
    for name in pairs(ambitions) do
        table.insert(names, tostring(name))
    end
    table.sort(names)
    local parts = {}
    for i = 1, #names do
        local entry = ambitions[names[i]]
        local values = { names[i] }
        if type(entry) == "table" then
            for f = 1, #SIGNATURE_FIELDS do
                table.insert(values, tostring(entry[SIGNATURE_FIELDS[f]]))
            end
        end
        parts[i] = table.concat(values, ":")
    end
    return table.concat(parts, ",")
end

function AmbitionSync.sync()
    if not isClient() then
        return
    end
    local player = getPlayer()
    if player == nil or player:isDead() then
        return
    end
    local modData = player:getModData()
    if modData == nil or modData.Ambitions == nil then
        return
    end
    local signature = computeSignature(modData.Ambitions)
    if signature == AmbitionSync.lastSignature then
        return
    end
    sendClientCommand(player, MODULE, SYNC_COMMAND, { ambitions = modData.Ambitions })
    AmbitionSync.lastSignature = signature
end

if not AmbitionSync.registered then
    AmbitionSync.registered = true
    Events.EveryOneMinute.Add(function()
        AmbitionSync.sync()
    end)
    -- Push afresh after every world join: the server may have restarted (or its
    -- mirror rolled back) while this client session kept its last signature.
    Events.OnGameStart.Add(function()
        AmbitionSync.lastSignature = nil
    end)
    -- Lifestyles builds the default Ambitions entries only once per Lua session
    -- (AmbtMng gates customAmbtLoop on LSCheckCustomAmbts), so a character
    -- respawned without relogging keeps the empty table its OnCreatePlayer
    -- handler assigns: the painting/kill hooks find no entry, no progress ever
    -- accrues, and the death snapshot has no ambitions to record. Re-arm the
    -- check so the next EveryOneMinute tick rebuilds the entries.
    Events.OnCreatePlayer.Add(function()
        if LSAmbtMng ~= nil then
            LSAmbtMng.LSCheckCustomAmbts = false
        end
    end)
end
