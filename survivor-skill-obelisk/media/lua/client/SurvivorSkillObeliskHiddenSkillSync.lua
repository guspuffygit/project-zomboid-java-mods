--
-- SurvivorSkillObeliskHiddenSkillSync.lua
-- Mirrors the Lifestyles mod's hidden-skill table (LSHiddenSkills: Yoga,
-- Inventing) from the client to the server-side player modData.
--
-- Lifestyles earns hidden-skill XP in client-only Lua (HSMng.lua), but B42
-- player persistence is server-authoritative, and Lifestyles' own
-- client->server modData mirror (LS:SavePlayerData) only runs once per in-game
-- day. XP earned since the last mirror doesn't exist on the server, so the
-- obelisk death snapshot never sees it. This script watches LSHiddenSkills and
-- pushes it to SyncHiddenSkillsHandler within a game minute of any change.
--

local MODULE = "SurvivorSkillObelisk"
local SYNC_COMMAND = "syncHiddenSkills"

-- State lives on a global so a hot-reload of this file keeps the signature and
-- doesn't stack a second set of event handlers.
SurvivorSkillObeliskHiddenSkillSync = SurvivorSkillObeliskHiddenSkillSync or {}
local HiddenSkillSync = SurvivorSkillObeliskHiddenSkillSync

-- Skill names are sorted so the signature is stable across pairs() ordering;
-- level and xp both feed it so mid-level grinding re-syncs, not just level-ups.
local function computeSignature(skills)
    local names = {}
    for name in pairs(skills) do
        table.insert(names, tostring(name))
    end
    table.sort(names)
    local parts = {}
    for i = 1, #names do
        local entry = skills[names[i]]
        local level = (type(entry) == "table" and entry[1]) or -1
        local xp = (type(entry) == "table" and entry[2]) or -1
        parts[i] = string.format("%s=%s:%s", names[i], tostring(level), tostring(xp))
    end
    return table.concat(parts, ",")
end

function HiddenSkillSync.sync()
    if not isClient() then
        return
    end
    local player = getPlayer()
    if player == nil or player:isDead() then
        return
    end
    local modData = player:getModData()
    if modData == nil or modData.LSHiddenSkills == nil then
        return
    end
    local signature = computeSignature(modData.LSHiddenSkills)
    if signature == HiddenSkillSync.lastSignature then
        return
    end
    sendClientCommand(player, MODULE, SYNC_COMMAND, { skills = modData.LSHiddenSkills })
    HiddenSkillSync.lastSignature = signature
end

if not HiddenSkillSync.registered then
    HiddenSkillSync.registered = true
    Events.EveryOneMinute.Add(function()
        HiddenSkillSync.sync()
    end)
    -- Push afresh after every world join: the server may have restarted (or its
    -- mirror rolled back) while this client session kept its last signature.
    Events.OnGameStart.Add(function()
        HiddenSkillSync.lastSignature = nil
    end)
end
