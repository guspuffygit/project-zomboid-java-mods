--[[
Talis New Music's EveryOneMinute item power tick (server/runtime/
NMServerItemPowerTick.lua) answers two questions by brute force every minute:

  1. "Which player is holding world device X?"  For EVERY registry entry it
     walks EVERY online player's entire nested inventory
     (syncWorldSnapshotToAnyInventoryOwner -> findItemByUuid), one
     pcall(NMDeviceRegistry.get) per item visited.
  2. "Which players carry a battery device?"  It flattens EVERY online
     player's inventory (collectItemsRecursive) and profiles every item.

Cost is registry x players x items — ~1.07M item visits per tick at 77
devices / 168 players (scan #7, 2026-09-01), all Kahlua->Java bridge calls.

The server already knows the answers. Every device state change is an intent
it executes itself with the player and item in hand
(NMServerItemIntentTargeting.resolveTarget), and registry entries already
carry the owner (entry.ownerId/ownerOnlineId/ownerUsername) with an O(1)
lookup the mod uses elsewhere (NMServerSourceRefreshTick.resolvePlayerFromOwner
over NMServerPlayerLookupSnapshot.build()).

This patch keeps an index uuid -> { player, item } of battery devices held by
online players, fed by:
  * resolveTarget (every item intent) — records the holder, or drops the
    entry when the intent targets a world item;
  * request_inventory_state_sync (the client's connect-time sync) and the
    first minute a player is seen online — one O(items) seed per session.
Each minute every index entry is validated in O(1) (outermost container's
parent must still be that player) and evicted otherwise.

NMServerItemPowerTick.onEveryOneMinute is replaced with a version that:
  * drains world registry entries exactly as before (per-entry logic is a
    behavioral copy; the attached-owner-online check uses the id map);
  * mirrors world snapshots only into indexed holders, falling back to a
    search of the ONE resolved owner's inventory for attached/stowed entries
    the index missed;
  * runs the inventory drain / world-mirror / stamp branches over the index
    instead of over every item on every player.

Side fix: NMServerVehicleSqlIndexCache.refresh rebuilds the sqlId->vehicle map
from a full getVehicles() walk every 1.5 s whenever ANY registry entry exists.
Its only consumers (NMServerSourceRefreshTick.resolveVehicleIdentity and our
vehicle sweep patch) act on vehicle entries, so the rebuild is skipped while
no entry is a vehicle.

NMServerMainRuntime.onEveryOneMinute, NMServerItemIntentAdapter.buildAdapter,
NMServerMainRuntime.onClientCommand and NMServerSourceRefreshTick all look the
patched functions up on their global tables at call time, so swapping the
members is sufficient. Applied on the first server tick so every Talis module
is guaranteed loaded.

Re-check this file whenever Talis New Music updates: the drain / mirror /
stamp branches below must stay behaviorally identical to theirs.

Live stats for eval inspection: ATFPatchesTalisNMItemPower.stats
]]

if isClient() and not isServer() then
    return
end

ATFPatchesTalisNMItemPower = ATFPatchesTalisNMItemPower or {}
ATFPatchesTalisNMItemPower.stats = {
    minuteTicks = 0,
    playersSeeded = 0,
    indexedByIntent = 0,
    indexedBySeed = 0,
    droppedByIntent = 0,
    evicted = 0,
    rehomed = 0,
    worldEntriesDrained = 0,
    worldMirrored = 0,
    ownerSearches = 0,
    ownerUnresolved = 0,
    personalDrained = 0,
    sqlIndexRefreshSkipped = 0,
}
-- uuid -> { player = IsoPlayer, item = InventoryItem }
ATFPatchesTalisNMItemPower.index = ATFPatchesTalisNMItemPower.index or {}
-- IsoPlayer -> true; keyed by object so a reconnect (new IsoPlayer) reseeds
ATFPatchesTalisNMItemPower.seeded = ATFPatchesTalisNMItemPower.seeded or {}

local function nowRealMs()
    if getTimestampMs then
        local ms = tonumber(getTimestampMs())
        if ms then
            return ms
        end
    end
    if getTimestamp then
        local ts = tonumber(getTimestamp())
        if ts then
            return ts * 1000
        end
    end
    return 0
end

local function markAuthoritativeMutation(state)
    if not state then
        return
    end
    NMDeviceState.bumpRevision(state)
    state.sourceGeneration = (tonumber(state.sourceGeneration) or 0) + 1
end

local function isBatteryProfile(profile)
    if not profile then
        return false
    end
    if profile.vehicleUsesCarBattery == true then
        return false
    end
    return profile.requiresBattery == true
end

local function resolveItemSourceMode(item, state)
    local mode = tostring(state and state.authoritativeMode or "")
    if mode ~= "" and mode ~= "off" then
        return mode
    end
    local worldItem = item and item.getWorldItem and item:getWorldItem() or nil
    if worldItem then
        return "placed"
    end
    return "inventory"
end

local function isWorldAuthoritativeMode(mode)
    local m = tostring(mode or "")
    return m == "attached" or m == "stowed" or m == "placed"
end

local function playerOnlineId(player)
    if not (player and player.getOnlineID) then
        return ""
    end
    return tostring(player:getOnlineID() or "")
end

local function playerName(player)
    if not (player and player.getUsername) then
        return "unknown"
    end
    return tostring(player:getUsername() or "unknown")
end

local function sendStateToPlayer(player, item, state, sourceMode)
    if not (player and item and state and sendServerCommand and NMCore and NMCore.NetModule) then
        return
    end
    sendServerCommand(player, NMCore.NetModule, "state", {
        itemId = tostring(item:getID() or ""),
        uuid = tostring(state.deviceUUID or ""),
        itemFullType = tostring(item:getFullType() or ""),
        sourceMode = tostring(sourceMode or resolveItemSourceMode(item, state)),
        state = NMDeviceState.export(state),
        serverSessionToken = NMServerBootReset
                and NMServerBootReset.getSessionToken
                and NMServerBootReset.getSessionToken()
            or nil,
    })
end

-- Behavioral copy of NMServerItemPowerTick's applyItemDrain (same shared
-- lastDrainMs table, same reducer path, same force-off on empty).
local function applyItemDrain(kind, key, state, nowMsValue, drainSeconds, logExtra)
    local prevMs = tonumber(NMServerItemPowerTick.lastDrainMs[key])
    if not state.isOn then
        NMServerItemPowerTick.lastDrainMs[key] = nowMsValue
        return false, false
    end
    local oldCharge = NMCore.clamp(tonumber(state.batteryCharge) or 0.0, 0.0, 1.0)
    if not prevMs then
        NMServerItemPowerTick.lastDrainMs[key] = nowMsValue
        return false, false
    end

    local deltaSeconds = math.max(0, (nowMsValue - prevMs) / 1000.0)
    if deltaSeconds <= 0 then
        return false, false
    end

    local mutated, stopped, nextCharge = false, false, oldCharge
    if NMServerCanonicalReducer and NMServerCanonicalReducer.applyBatteryDelta then
        mutated, stopped, nextCharge = NMServerCanonicalReducer.applyBatteryDelta({
            eventType = NMServerCanonicalReducer.Event
                    and NMServerCanonicalReducer.Event.TICK_BATTERY
                or "TICK_BATTERY",
            kind = kind,
            key = key,
            state = state,
            deltaSeconds = deltaSeconds,
            drainSeconds = drainSeconds,
            oldCharge = oldCharge,
            markMutation = markAuthoritativeMutation,
        })
    else
        nextCharge =
            NMServerBatteryAuthority.computeNextCharge(oldCharge, deltaSeconds, drainSeconds)
        state.batteryCharge = nextCharge
        mutated = (nextCharge ~= oldCharge)
        if mutated then
            markAuthoritativeMutation(state)
        end
        if nextCharge <= 0 then
            state.batteryCharge = 0.0
            stopped = NMServerBatteryAuthority.forceStateOff(state, "battery_empty")
            if stopped and not mutated then
                markAuthoritativeMutation(state)
            end
            if stopped then
                local token = string.format(
                    "%s:%s",
                    tostring(tonumber(state.playbackEpoch) or -1),
                    tostring(tonumber(state.trackIndex) or -1)
                )
                NMServerBatteryAuthority.logEmptyStop(kind, key, "battery_empty", token)
            end
            mutated = true
        end
    end
    NMServerItemPowerTick.lastDrainMs[key] = nowMsValue
    NMServerBatteryAuthority.logBatteryTick(
        kind,
        key,
        nowMsValue,
        prevMs,
        oldCharge,
        nextCharge,
        drainSeconds,
        logExtra
    )
    return mutated, stopped
end

local function claimMutationPath(seenMap, key, path)
    local uuid = tostring(key or "")
    if uuid == "" then
        return false
    end
    local existing = seenMap[uuid]
    if existing then
        if
            existing ~= path
            and NMCore
            and NMCore.logChannel
            and NMCore.isSubsystemDebugEnabled
            and NMCore.isSubsystemDebugEnabled("runtime")
        then
            local nowMsValue = nowRealMs()
            local shouldLog = true
            if NMCore.shouldLogEvery then
                shouldLog = NMCore.shouldLogEvery(
                    "runtimeProbe.batteryPathSkip." .. tostring(uuid),
                    nowMsValue,
                    20000
                )
            end
            if shouldLog then
                NMCore.logChannel(
                    "runtime",
                    "server_battery_path_skip_duplicate",
                    string.format(
                        "uuid=%s existing=%s skipped=%s",
                        tostring(uuid),
                        tostring(existing),
                        tostring(path)
                    )
                )
            end
        end
        return false
    end
    seenMap[uuid] = tostring(path or "unknown")
    return true
end

-- Same resolution order as NMServerSourceRefreshTick.resolvePlayerFromOwner.
local function resolveOwnerPlayer(entry, state, byId, byName)
    local owner = tostring(
        state and state.sourceOwner
            or entry and entry.ownerId
            or entry and entry.ownerOnlineId
            or entry and entry.ownerUsername
            or ""
    )
    if owner == "" then
        return nil
    end
    local byIdHit = byId and byId[owner] or nil
    if byIdHit then
        return byIdHit
    end
    return byName and byName[string.lower(owner)] or nil
end

-- Original walks every online player comparing ids; the snapshot maps give
-- the same answer without the walk.
local function isOwnerOnlineForAttached(entry, state, byId, byName)
    local mode = tostring(state and state.authoritativeMode or entry and entry.sourceMode or "")
    if mode ~= "attached" then
        return true
    end
    return resolveOwnerPlayer(entry, state, byId, byName) ~= nil
end

-- ---------------------------------------------------------------------------
-- Holder index
-- ---------------------------------------------------------------------------

local function itemHeldBy(item, player)
    if not (item and player and item.getOutermostContainer) then
        return false
    end
    local outer = item:getOutermostContainer()
    local parent = outer and outer.getParent and outer:getParent() or nil
    if not parent then
        return false
    end
    if parent == player then
        return true
    end
    if not parent.getOnlineID then
        return false
    end
    local id = playerOnlineId(parent)
    return id ~= "" and id == playerOnlineId(player)
end

local function indexHeldItem(player, item, statKey)
    local profile = item and NMDeviceProfiles.getForItem(item) or nil
    if not isBatteryProfile(profile) then
        return false
    end
    local state = NMDeviceState.peek(item)
    local uuid = tostring(state and state.deviceUUID or "")
    if uuid == "" then
        return false
    end
    ATFPatchesTalisNMItemPower.index[uuid] = { player = player, item = item }
    local stats = ATFPatchesTalisNMItemPower.stats
    stats[statKey] = (stats[statKey] or 0) + 1
    return true
end

local function seedPlayer(player)
    local inv = player and player.getInventory and player:getInventory() or nil
    if not inv then
        return
    end
    local items = {}
    NMInventoryHelpers.collectItemsRecursive(inv, items)
    for i = 1, #items do
        indexHeldItem(player, items[i], "indexedBySeed")
    end
    ATFPatchesTalisNMItemPower.stats.playersSeeded = ATFPatchesTalisNMItemPower.stats.playersSeeded
        + 1
end

local function seedNewPlayers(byId)
    local seeded = ATFPatchesTalisNMItemPower.seeded
    local stale = {}
    for player in pairs(seeded) do
        if byId[playerOnlineId(player)] ~= player then
            stale[#stale + 1] = player
        end
    end
    for i = 1, #stale do
        seeded[stale[i]] = nil
    end
    for _, player in pairs(byId) do
        if not seeded[player] then
            seeded[player] = true
            seedPlayer(player)
        end
    end
end

-- The online IsoPlayer whose inventory (at any nesting depth) holds item.
local function onlineHolderOf(item, byId)
    if not (item and item.getOutermostContainer) then
        return nil
    end
    local outer = item:getOutermostContainer()
    local parent = outer and outer.getParent and outer:getParent() or nil
    if not (parent and parent.getOnlineID) then
        return nil
    end
    local online = byId[playerOnlineId(parent)]
    if online == parent then
        return online
    end
    return nil
end

-- Vanilla hand-offs (trade, loot from a corpse) move an item between players
-- with no NM intent, so an entry whose item now sits with another online
-- player is re-homed rather than evicted.
local function validateIndex(byId)
    local index = ATFPatchesTalisNMItemPower.index
    local stats = ATFPatchesTalisNMItemPower.stats
    local dead = {}
    for uuid, rec in pairs(index) do
        local holder = onlineHolderOf(rec and rec.item or nil, byId)
        if not holder then
            dead[#dead + 1] = uuid
        elseif holder ~= rec.player then
            rec.player = holder
            stats.rehomed = stats.rehomed + 1
        end
    end
    for i = 1, #dead do
        index[dead[i]] = nil
    end
    stats.evicted = stats.evicted + #dead
end

-- ---------------------------------------------------------------------------
-- Minute tick
-- ---------------------------------------------------------------------------

-- Behavioral copy of the original processWorldRegistry.
local function processWorldRegistry(nowMsValue, drainSeconds, seenUuids, byId, byName)
    local world = NMServerRegistryState and NMServerRegistryState.worldRegistry or nil
    if type(world) ~= "table" then
        return
    end
    local stats = ATFPatchesTalisNMItemPower.stats
    for uuid, entry in pairs(world) do
        local state = entry and entry.stateSnapshot or nil
        local profileType = entry and (entry.profileType or entry.itemFullType) or nil
        local profile = profileType
                and NMDeviceProfiles
                and NMDeviceProfiles.getForFullType
                and NMDeviceProfiles.getForFullType(profileType)
            or nil
        if state and isBatteryProfile(profile) then
            local key = tostring(uuid or state.deviceUUID or "")
            if claimMutationPath(seenUuids, key, "world") then
                local listenerEval = NMServerListenerEligibility
                        and NMServerListenerEligibility.evaluate
                        and NMServerListenerEligibility.evaluate(entry, state, profile)
                    or nil
                local noListenerFreeze = listenerEval
                    and listenerEval.shouldFreezeForNoListener == true
                if noListenerFreeze then
                    NMServerItemPowerTick.lastDrainMs[key] = nowMsValue
                    if
                        NMCore
                        and NMCore.logChannel
                        and NMCore.isSubsystemDebugEnabled
                        and NMCore.isSubsystemDebugEnabled("runtime")
                        and NMCore.shouldLogEvery
                    then
                        local logKey = "runtimeProbe.batterySkipNoListener." .. tostring(key)
                        if NMCore.shouldLogEvery(logKey, nowMsValue, 5000) then
                            NMCore.logChannel(
                                "runtime",
                                "battery_tick_skipped_no_listener",
                                string.format(
                                    "uuid=%s mode=%s",
                                    tostring(key),
                                    tostring(state.authoritativeMode or "unknown")
                                )
                            )
                        end
                    end
                elseif entry._batteryDrainSkipUntilResume == true then
                    NMServerItemPowerTick.lastDrainMs[key] = nowMsValue
                    if
                        NMCore
                        and NMCore.logChannel
                        and NMCore.isSubsystemDebugEnabled
                        and NMCore.isSubsystemDebugEnabled("runtime")
                        and NMCore.shouldLogEvery
                    then
                        local logKey = "runtimeProbe.batterySkipOffline." .. tostring(key)
                        if NMCore.shouldLogEvery(logKey, nowMsValue, 5000) then
                            NMCore.logChannel(
                                "runtime",
                                "battery_tick_skipped_offline_pause",
                                string.format(
                                    "uuid=%s mode=%s",
                                    tostring(key),
                                    tostring(state.authoritativeMode or "unknown")
                                )
                            )
                        end
                    end
                elseif not isOwnerOnlineForAttached(entry, state, byId, byName) then
                    NMServerItemPowerTick.lastDrainMs[key] = nowMsValue
                else
                    local updated = applyItemDrain(
                        "item_world",
                        key,
                        state,
                        nowMsValue,
                        drainSeconds,
                        "mode=" .. tostring(state.authoritativeMode or "nil")
                    )
                    if updated then
                        entry.stateSnapshot = NMDeviceState.export(state)
                        world[uuid] = entry
                        stats.worldEntriesDrained = stats.worldEntriesDrained + 1
                    end
                end
            end
        end
    end
end

local function canLiveInInventory(entry, snapshot)
    local mode = tostring(entry and entry.sourceMode or "")
    if mode == "" then
        mode = tostring(snapshot and snapshot.authoritativeMode or "")
    end
    return mode == "attached" or mode == "stowed"
end

-- Replaces syncWorldSnapshotToAnyInventoryOwner: indexed holder first, then
-- a search of the one resolved owner's inventory for entries the index
-- missed. Entries that cannot be in an inventory (placed / vehicle) are
-- skipped; the original scanned every player for them and never matched.
local function mirrorWorldEntriesToHolders(byId, byName)
    local world = NMServerRegistryState and NMServerRegistryState.worldRegistry or nil
    if type(world) ~= "table" then
        return
    end
    local index = ATFPatchesTalisNMItemPower.index
    local stats = ATFPatchesTalisNMItemPower.stats
    for uuid, entry in pairs(world) do
        local snapshot = entry and entry.stateSnapshot or nil
        if type(snapshot) == "table" then
            local key = tostring(uuid)
            local rec = index[key]
            local item = rec and rec.item or nil
            if not item and canLiveInInventory(entry, snapshot) then
                local owner = resolveOwnerPlayer(entry, snapshot, byId, byName)
                local inv = owner and owner.getInventory and owner:getInventory() or nil
                if inv then
                    stats.ownerSearches = stats.ownerSearches + 1
                    item = NMInventoryHelpers.findItemByUuid(inv, key)
                    if item then
                        index[key] = { player = owner, item = item }
                    end
                else
                    stats.ownerUnresolved = stats.ownerUnresolved + 1
                end
            end
            if item then
                local state = NMDeviceState.peek(item)
                if state then
                    NMDeviceState.import(state, snapshot)
                    stats.worldMirrored = stats.worldMirrored + 1
                end
            end
        end
    end
end

-- Behavioral copy of the original processPlayerInventory's per-item body,
-- driven by the index instead of a per-player inventory flatten.
local function processIndexedInventory(nowMsValue, drainSeconds, seenUuids)
    local stats = ATFPatchesTalisNMItemPower.stats
    for key, rec in pairs(ATFPatchesTalisNMItemPower.index) do
        local player, item = rec.player, rec.item
        local state = NMDeviceState.peek(item)
        if state and tostring(state.deviceUUID or "") == key then
            local worldEntry = NMServerRegistryState
                    and NMServerRegistryState.worldRegistry
                    and NMServerRegistryState.worldRegistry[key]
                or nil
            local worldSnapshot = worldEntry and worldEntry.stateSnapshot or nil
            local mode = tostring(state.authoritativeMode or "")
            if isWorldAuthoritativeMode(mode) and type(worldSnapshot) ~= "table" then
                NMServerItemPowerTick.lastDrainMs[key] = nowMsValue
            elseif type(worldSnapshot) == "table" then
                NMDeviceState.import(state, worldSnapshot)
                sendStateToPlayer(player, item, state, resolveItemSourceMode(item, state))
                claimMutationPath(seenUuids, key, "world_mirror")
            else
                if claimMutationPath(seenUuids, key, "personal") then
                    local updated = applyItemDrain(
                        "item_personal",
                        key,
                        state,
                        nowMsValue,
                        drainSeconds,
                        "mode=" .. tostring(resolveItemSourceMode(item, state))
                    )
                    if updated then
                        sendStateToPlayer(player, item, state, resolveItemSourceMode(item, state))
                        stats.personalDrained = stats.personalDrained + 1
                    end
                end
            end
        end
    end
end

local function onEveryOneMinute()
    if not (NMCore and NMCore.isMPServerAuthority and NMCore.isMPServerAuthority()) then
        return
    end
    local stats = ATFPatchesTalisNMItemPower.stats
    stats.minuteTicks = stats.minuteTicks + 1

    local nowMsValue = nowRealMs()
    local drainSeconds = tonumber(
        NMRuntimeConfig.getBatteryDrainSecondsPortableFromSandbox
                and NMRuntimeConfig.getBatteryDrainSecondsPortableFromSandbox()
            or 86400
    ) or 86400
    drainSeconds = math.max(1, drainSeconds)
    local seenUuids = {}

    local byId, byName = NMServerPlayerLookupSnapshot.build()
    seedNewPlayers(byId)
    validateIndex(byId)

    processWorldRegistry(nowMsValue, drainSeconds, seenUuids, byId, byName)
    mirrorWorldEntriesToHolders(byId, byName)
    processIndexedInventory(nowMsValue, drainSeconds, seenUuids)
end

-- ---------------------------------------------------------------------------
-- Hooks
-- ---------------------------------------------------------------------------

local function wrapResolveTarget()
    local original = NMServerItemIntentTargeting.resolveTarget
    NMServerItemIntentTargeting.resolveTarget = function(player, args)
        local ctx, err = original(player, args)
        if ctx and ctx.item and ctx.state and isBatteryProfile(ctx.profile) then
            local uuid = tostring(ctx.state.deviceUUID or "")
            if uuid ~= "" then
                local stats = ATFPatchesTalisNMItemPower.stats
                if itemHeldBy(ctx.item, player) then
                    ATFPatchesTalisNMItemPower.index[uuid] = { player = player, item = ctx.item }
                    stats.indexedByIntent = stats.indexedByIntent + 1
                elseif ATFPatchesTalisNMItemPower.index[uuid] then
                    ATFPatchesTalisNMItemPower.index[uuid] = nil
                    stats.droppedByIntent = stats.droppedByIntent + 1
                end
            end
        end
        return ctx, err
    end
end

local function wrapOnClientCommand()
    local original = NMServerIntentRouter.onClientCommand
    NMServerIntentRouter.onClientCommand = function(module, command, player, args)
        local result = original(module, command, player, args)
        -- Seed after the original so states it ensures are visible.
        if module == NMCore.NetModule and command == "request_inventory_state_sync" and player then
            ATFPatchesTalisNMItemPower.seeded[player] = true
            seedPlayer(player)
        end
        return result
    end
end

local function registryHasVehicleEntry()
    local world = NMServerRegistryState and NMServerRegistryState.worldRegistry or nil
    if type(world) ~= "table" then
        return false
    end
    for _, entry in pairs(world) do
        if
            entry
            and (
                tostring(entry.vehicleSqlId or "") ~= ""
                or tostring(entry.sourceMode or "") == "vehicle"
            )
        then
            return true
        end
    end
    return false
end

local function wrapVehicleSqlIndexRefresh()
    if not (NMServerVehicleSqlIndexCache and NMServerVehicleSqlIndexCache.refresh) then
        return
    end
    local original = NMServerVehicleSqlIndexCache.refresh
    NMServerVehicleSqlIndexCache.refresh = function()
        if registryHasVehicleEntry() then
            return original()
        end
        ATFPatchesTalisNMItemPower.stats.sqlIndexRefreshSkipped = ATFPatchesTalisNMItemPower.stats.sqlIndexRefreshSkipped
            + 1
        return false
    end
end

local function applyPatch()
    if
        not (
            NMServerItemPowerTick
            and NMServerItemPowerTick.onEveryOneMinute
            and NMServerItemPowerTick.lastDrainMs
            and NMServerItemIntentTargeting
            and NMServerItemIntentTargeting.resolveTarget
            and NMServerIntentRouter
            and NMServerIntentRouter.onClientCommand
            and NMServerPlayerLookupSnapshot
            and NMServerPlayerLookupSnapshot.build
            and NMServerRegistryState
            and NMServerBatteryAuthority
            and NMDeviceProfiles
            and NMDeviceState
            and NMInventoryHelpers
            and NMInventoryHelpers.collectItemsRecursive
            and NMInventoryHelpers.findItemByUuid
            and NMRuntimeConfig
            and NMCore
        )
    then
        print(
            "[ATFPatches] Talis New Music not loaded (or shape changed); item power index skipped."
        )
        return false
    end

    ATFPatchesTalisNMItemPower.original = ATFPatchesTalisNMItemPower.original
        or NMServerItemPowerTick.onEveryOneMinute
    NMServerItemPowerTick.onEveryOneMinute = onEveryOneMinute
    wrapResolveTarget()
    wrapOnClientCommand()
    wrapVehicleSqlIndexRefresh()

    print("[ATFPatches] Talis New Music item power tick now index-driven.")
    return true
end

local function onFirstTick()
    Events.OnTick.Remove(onFirstTick)
    applyPatch()
end

Events.OnTick.Add(onFirstTick)
