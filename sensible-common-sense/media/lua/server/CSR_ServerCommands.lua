require "CSR_Utils"
require "CSR_Config"

local CSR_DualWieldUtils = nil
local function getDWUtils()
    if not CSR_DualWieldUtils then
        CSR_DualWieldUtils = require "CSR_DualWieldUtils"
    end
    return CSR_DualWieldUtils
end

CSR_ServerCommands = {}

local function splitIds(str)
    local result = {}
    if not str or str == "" then return result end
    for v in string.gmatch(str, "[^,]+") do
        result[#result + 1] = tonumber(v)
    end
    return result
end

local function splitStrings(str)
    local result = {}
    if not str or str == "" then return result end
    for v in string.gmatch(str, "[^,]+") do
        result[#result + 1] = v
    end
    return result
end
local recentRequests = {}
local markerRequests = {}
local markerStateCache = {}
local zombieDensityRequests = {}
local zombieDensityStateCache = {}
-- Shared zombie-position list: rebuilt at most once every ZOMBIE_SCAN_SHARE_MS ms,
-- shared across all players to avoid rescanning all objects per-request.
local _zombieScanCache = { time = 0, positions = nil }
local ZOMBIE_SCAN_SHARE_MS = 5000

local failStreaks = {}

local PRY_FRUSTRATION = {
    "Pry failed",
    "Come on...",
    "It won't budge!",
    "This is really jammed...",
    "Son of a...",
    "I'm gonna break this thing!",
    "Why won't this OPEN?!",
}

local LOCKPICK_FRUSTRATION = {
    "Lockpick failed",
    "Almost had it...",
    "Slipped again...",
    "This lock is tricky...",
    "Are you kidding me?!",
    "I can't feel the pins!",
    "This is impossible!",
}

local BOLT_CUT_FRUSTRATION = {
    "Bolt cut failed",
    "These are tough...",
    "Almost through!",
    "Come on, snap already!",
    "This metal is thick...",
    "One more try!",
    "I need more leverage!",
}

local function getFrustrationMessage(player, table)
    local id = player and player.getOnlineID and player:getOnlineID() or 0
    failStreaks[id] = (failStreaks[id] or 0) + 1
    local idx = math.min(failStreaks[id], #table)
    return table[idx]
end

local function resetFrustration(player)
    local id = player and player.getOnlineID and player:getOnlineID() or 0
    failStreaks[id] = 0
end

local function sandbox()
    return SandboxVars and SandboxVars.CommonSenseReborn or {}
end

local spriteName -- forward declaration (defined at line ~400)

local function sendResult(player, text)
    sendServerCommand(player, "CommonSenseReborn", "ActionResult", {
        text = text,
        playerOnlineID = player and player.getOnlineID and player:getOnlineID() or nil,
        playerIndex = player and player.getPlayerNum and player:getPlayerNum() or 0,
    })
end

local function sendOpenAnim(player, obj)
    if not player or not obj or not obj.getSquare then
        return
    end

    local sq = obj:getSquare()
    if not sq then
        return
    end

    local onlineID = player.getOnlineID and player:getOnlineID() or -1
    local playerNum = player.getPlayerNum and player:getPlayerNum() or 0

    sendServerCommand(player, "CommonSenseReborn", "DoClientOpenAnim", {
        x = sq:getX(),
        y = sq:getY(),
        z = sq:getZ(),
        objectIndex = obj.getObjectIndex and obj:getObjectIndex() or -1,
        sprite = spriteName(obj) or "",
        playerOnlineID = onlineID,
        playerIndex = playerNum,
    })
end

local function getPlayerRequestKey(player)
    return tostring(player and player.getOnlineID and player:getOnlineID() or "local")
end

local function getNowMs()
    return getTimestampMs and getTimestampMs() or os.time() * 1000
end

local function isFreshRequest(args)
    -- Timestamp freshness check removed: client and dedicated server clocks
    -- are almost never in sync, causing all requests to expire.
    -- Security is enforced by isNearPlayer() distance checks and
    -- requestId deduplication (pruneOldRequests) instead.
    return true
end

local function pruneOldRequests(bucket, nowMs)
    local cutoff = nowMs - CSR_Config.REQUEST_DEDUPE_WINDOW_MS
    for key, entry in pairs(bucket) do
        if not entry or (entry.time or 0) < cutoff then
            bucket[key] = nil
        end
    end
end

local function syncInventoryItem(item)
    if not item then
        return
    end

    if item.transmitModData then
        item:transmitModData()
    end

    -- sendReplaceItemInContainer forces a full item re-sync to the client,
    -- including condition, uses, delta, etc. (vanilla pattern from item.changeRecording)
    local container = item.getContainer and item:getContainer() or nil
    if container and sendReplaceItemInContainer then
        sendReplaceItemInContainer(container, item, item)
    elseif sendItemStats then
        sendItemStats(item)
    end
end

local function syncPlayerInventory(player)
    if not player then return end
    local inv = player:getInventory()
    if inv then
        inv:setDrawDirty(true)
        if inv.setDirtySlots then inv:setDirtySlots(true) end
    end
end

local function isDuplicateRequest(player, command, args)
    local requestId = args and args.requestId or nil
    if not requestId or requestId == "" then
        return false
    end

    local nowMs = getNowMs()
    pruneOldRequests(recentRequests, nowMs)

    local key = table.concat({ getPlayerRequestKey(player), tostring(command), tostring(requestId) }, ":")
    if recentRequests[key] then
        print("[CSR] Duplicate request blocked: " .. tostring(command))
        return true
    end

    recentRequests[key] = { time = nowMs }
    return false
end

local function pruneMarkerCaches(nowMs)
    local requestCutoff = nowMs - math.max(CSR_Config.REQUEST_DEDUPE_WINDOW_MS, CSR_Config.PLAYER_MAP_CACHE_TTL_MS)
    for key, entry in pairs(markerRequests) do
        if not entry or (entry.time or 0) < requestCutoff then
            markerRequests[key] = nil
        end
    end

    local stateCutoff = nowMs - CSR_Config.PLAYER_MAP_CACHE_TTL_MS
    for key, entry in pairs(markerStateCache) do
        if not entry or (entry.time or 0) < stateCutoff then
            markerStateCache[key] = nil
        end
    end

    local densityRequestCutoff = nowMs - math.max(CSR_Config.REQUEST_DEDUPE_WINDOW_MS, CSR_Config.ZOMBIE_DENSITY_CACHE_TTL_MS)
    for key, entry in pairs(zombieDensityRequests) do
        if not entry or (entry.time or 0) < densityRequestCutoff then
            zombieDensityRequests[key] = nil
        end
    end

    local densityStateCutoff = nowMs - CSR_Config.ZOMBIE_DENSITY_CACHE_TTL_MS
    for key, entry in pairs(zombieDensityStateCache) do
        if not entry or (entry.time or 0) < densityStateCutoff then
            zombieDensityStateCache[key] = nil
        end
    end
end


local function getInventoryItems(container)
    if not container or not container.getItems then
        return nil
    end

    return container:getItems()
end

local function findInventoryItemById(player, itemId)
    if not player or not itemId then
        return nil
    end

    local mainInv = player:getInventory()
    if not mainInv then
        return nil
    end

    -- Recursive walk: items can be nested arbitrarily deep (bag-in-bag-in-bag).
    -- The previous one-level search returned nil for any item more than one
    -- container deep, silently breaking every "All" command on stowed items.
    local visited = {}
    local function search(inv)
        if not inv or visited[inv] then return nil end
        visited[inv] = true
        local items = getInventoryItems(inv)
        if not items then return nil end
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            if item and item.getID and item:getID() == itemId then
                return item
            end
        end
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            if item and instanceof(item, "InventoryContainer") then
                local subInv = item.getInventory and item:getInventory() or nil
                if subInv then
                    local found = search(subInv)
                    if found then return found end
                end
            end
        end
        return nil
    end

    return search(mainInv)
end

local function findOnlinePlayerByID(onlineID)
    if onlineID == nil then
        return nil
    end

    if getPlayerByOnlineID then
        return getPlayerByOnlineID(onlineID)
    end

    local players = getOnlinePlayers and getOnlinePlayers() or nil
    if not players then
        return nil
    end

    for i = 0, players:size() - 1 do
        local candidate = players:get(i)
        if candidate and candidate:getOnlineID() == onlineID then
            return candidate
        end
    end

    return nil
end

local function removeInventoryItem(player, item)
    local container = item and item.getContainer and item:getContainer() or (player and player:getInventory())
    if not container or not item then
        return
    end

    if container.DoRemoveItem then
        container:DoRemoveItem(item)
    else
        container:Remove(item)
    end
    if sendRemoveItemFromContainer then
        sendRemoveItemFromContainer(container, item)
    end
end

local function addItem(container, itemOrType)
    local item = container:AddItem(itemOrType)
    if item and sendAddItemToContainer then
        sendAddItemToContainer(container, item)
    end
    return item
end

local function damageTool(tool, amount)
    if tool and tool.getCondition and tool.setCondition then
        tool:setCondition(math.max(0, tool:getCondition() - amount))
    end
end

local function consumeItemUse(player, item)
    if not item then
        return
    end

    if item.Use then
        item:Use()
    else
        removeInventoryItem(player, item)
    end
end

local function copyCondition(source, dest)
    if source and dest and source.getCondition and dest.setCondition then
        dest:setCondition(source:getCondition())
    end
end

local function getSquare(x, y, z)
    local cell = getCell()
    if not cell then
        return nil
    end
    return cell:getGridSquare(x, y, z)
end

local function iterateSquareObjects(square, fn)
    if not square then
        return
    end

    local objects = square:getObjects()
    if objects then
        for i = 0, objects:size() - 1 do
            fn(objects:get(i))
        end
    end

    local specialObjects = square:getSpecialObjects()
    if specialObjects then
        for i = 0, specialObjects:size() - 1 do
            fn(specialObjects:get(i))
        end
    end
end

spriteName = function(obj)
    local sprite = obj and obj.getSprite and obj:getSprite() or nil
    if sprite and sprite.getName then
        return sprite:getName()
    end
    return nil
end

local function resolveWorldObject(args, player)
    if not args or args.x == nil or args.y == nil or args.z == nil then
        return nil
    end

    local square = getSquare(args.x, args.y, args.z)
    if not square then
        return nil
    end

    local selected = nil
    local fallback = nil
    iterateSquareObjects(square, function(obj)
        if not fallback and CSR_Utils.isPryTarget(obj) and not CSR_Utils.isBarricadedForPlayer(obj, player) then
            fallback = obj
        end

        if not selected and args.sprite and args.sprite ~= "" and spriteName(obj) == args.sprite and CSR_Utils.isPryTarget(obj) and not CSR_Utils.isBarricadedForPlayer(obj, player) then
            selected = obj
        end
    end)

    if args.objectIndex ~= nil and args.objectIndex >= 0 then
        local objects = square:getObjects()
        if objects and args.objectIndex < objects:size() then
            local obj = objects:get(args.objectIndex)
            if obj and CSR_Utils.isPryTarget(obj) and not CSR_Utils.isBarricadedForPlayer(obj, player) then
                return obj
            end
        end
    end

    if selected then
        return selected
    end

    return fallback
end

local function resolveBoltCutObject(args, player)
    if not args or args.x == nil or args.y == nil or args.z == nil then
        return nil
    end

    local square = getSquare(args.x, args.y, args.z)
    if not square then
        return nil
    end

    local selected = nil
    local fallback = nil
    iterateSquareObjects(square, function(obj)
        if not fallback and CSR_Utils.isBoltCutterTarget(obj) and not CSR_Utils.isBarricadedForPlayer(obj, player) then
            fallback = obj
        end

        if not selected and args.sprite and args.sprite ~= "" and spriteName(obj) == args.sprite and CSR_Utils.isBoltCutterTarget(obj) and not CSR_Utils.isBarricadedForPlayer(obj, player) then
            selected = obj
        end
    end)

    if args.objectIndex ~= nil and args.objectIndex >= 0 then
        local objects = square:getObjects()
        if objects and args.objectIndex < objects:size() then
            local obj = objects:get(args.objectIndex)
            if obj and CSR_Utils.isBoltCutterTarget(obj) and not CSR_Utils.isBarricadedForPlayer(obj, player) then
                return obj
            end
        end
    end

    if selected then
        return selected
    end

    return fallback
end

local function resolveCorpse(args)
    if not args or args.x == nil or args.y == nil or args.z == nil then
        return nil
    end

    local square = getSquare(args.x, args.y, args.z)
    if not square or not square.getStaticMovingObjects then
        return nil
    end

    local corpses = square:getStaticMovingObjects()
    if not corpses then
        return nil
    end

    local fallback = nil
    for i = 0, corpses:size() - 1 do
        local obj = corpses:get(i)
        if obj and instanceof(obj, "IsoDeadBody") then
            if not fallback then
                fallback = obj
            end
            if args.corpseIndex ~= nil and obj.getStaticMovingObjectIndex and obj:getStaticMovingObjectIndex() == args.corpseIndex then
                return obj
            end
        end
    end

    return fallback
end

local function resolveBarricadeWindow(args, player)
    if not args or args.x == nil or args.y == nil or args.z == nil then
        return nil
    end

    local square = getSquare(args.x, args.y, args.z)
    if not square then
        return nil
    end

    if args.objectIndex ~= nil and args.objectIndex >= 0 then
        local objects = square:getObjects()
        if objects and args.objectIndex < objects:size() then
            local obj = objects:get(args.objectIndex)
            if obj and instanceof(obj, "IsoWindow")
                and not CSR_Utils.isBarricadedForPlayer(obj, player)
                and (not obj.isBarricadeAllowed or obj:isBarricadeAllowed()) then
                return obj
            end
        end
    end

    local selected = nil
    iterateSquareObjects(square, function(obj)
        if selected then
            return
        end

        if obj and instanceof(obj, "IsoWindow")
            and not CSR_Utils.isBarricadedForPlayer(obj, player)
            and (not obj.isBarricadeAllowed or obj:isBarricadeAllowed()) then
            if args.sprite and args.sprite ~= "" then
                if spriteName(obj) == args.sprite then
                    selected = obj
                end
            else
                selected = obj
            end
        end
    end)

    return selected
end

local function isNearPlayer(player, args)
    return math.abs(player:getX() - args.x) <= CSR_Config.MAX_WORLD_INTERACT_DISTANCE
        and math.abs(player:getY() - args.y) <= CSR_Config.MAX_WORLD_INTERACT_DISTANCE
        and math.abs(player:getZ() - args.z) <= 1
end

local function getVehicleByArgs(args)
    if not args or not args.vehicleId then
        return nil
    end
    return getVehicleById and getVehicleById(args.vehicleId) or nil
end

local function addInjury(player, amount)
    local hand = ZombRand(2) == 0 and BodyPartType.Hand_L or BodyPartType.Hand_R
    player:getBodyDamage():AddDamage(hand, amount)
end

local function shouldSendPlayerMarkersTo(requester)
    local mode = sandbox().PlayerMapVisibilityMode or 1
    if sandbox().EnablePlayerMapTracking == false or mode == 3 then
        return false
    end

    if mode == 2 then
        local level = requester.getAccessLevel and requester:getAccessLevel() or ""
        return level == "admin" or level == "moderator" or level == "gm" or level == "overseer"
    end

    return true
end

local function getVisiblePlayersFor(requester)
    local results = {}
    if not shouldSendPlayerMarkersTo(requester) then
        return results
    end

    -- Use getOnlinePlayers() on the server; IsoPlayer.getPlayers() is client-only
    local players = getOnlinePlayers and getOnlinePlayers() or nil
    if not players then
        return results
    end

    local function isFiniteWorldCoord(value)
        return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
    end

    for i = 0, players:size() - 1 do
        local other = players:get(i)
        if other and requester ~= other and not other:isDead()
            and isFiniteWorldCoord(other:getX()) and isFiniteWorldCoord(other:getY()) and isFiniteWorldCoord(other:getZ()) then
            table.insert(results, {
                id = other:getOnlineID(),
                username = other:getDisplayName(),
                x = math.floor(other:getX()),
                y = math.floor(other:getY()),
                z = math.floor(other:getZ()),
            })
        end
    end

    return results
end

local function markerKey(player)
    return getPlayerRequestKey(player)
end

local function buildMarkerSignature(players)
    if not players or #players == 0 then
        return "empty"
    end

    local parts = {}
    for i = 1, #players do
        local data = players[i]
        parts[#parts + 1] = table.concat({
            tostring(data.id or ""),
            tostring(data.x or ""),
            tostring(data.y or ""),
            tostring(data.z or ""),
            tostring(data.username or ""),
        }, "|")
    end

    return table.concat(parts, ";")
end

local function buildZombieCellSignature(cells)
    if not cells or #cells == 0 then
        return "empty"
    end

    local parts = {}
    for i = 1, #cells do
        local data = cells[i]
        parts[#parts + 1] = table.concat({
            tostring(data.x or ""),
            tostring(data.y or ""),
            tostring(data.amount or ""),
            tostring(data.density or ""),
        }, "|")
    end

    return table.concat(parts, ";")
end

local function sendMarkerResponse(player, players, requestSeq)
    sendServerCommand(player, "CommonSenseReborn", "PlayerMarkers", {
        players = players or {},
        requestSeq = requestSeq or 0,
    })
end

local function sendZombieDensityResponse(player, cells, requestSeq)
    sendServerCommand(player, "CommonSenseReborn", "ZombieDensityCells", {
        cells = cells or {},
        requestSeq = requestSeq or 0,
    })
end

function CSR_ServerCommands.handlePlayerMarkerRequest(player, args)
    if not player then
        return
    end

    local playerKey = markerKey(player)
    local nowMs = getNowMs()
    pruneMarkerCaches(nowMs)

    local lastRequest = markerRequests[playerKey]
    if lastRequest and (nowMs - lastRequest.time) < (CSR_Config.PLAYER_MAP_SERVER_MIN_TICKS * 16) then
        local cached = markerStateCache[playerKey]
        if cached then
            sendMarkerResponse(player, cached.players, args and args.requestSeq or 0)
        end
        return
    end

    local players = getVisiblePlayersFor(player)
    local signature = buildMarkerSignature(players)
    local cached = markerStateCache[playerKey]

    markerRequests[playerKey] = { time = nowMs }
    if cached and cached.signature == signature then
        cached.time = nowMs
        sendMarkerResponse(player, cached.players, args and args.requestSeq or 0)
        return
    end

    markerStateCache[playerKey] = {
        time = nowMs,
        signature = signature,
        players = players,
    }
    sendMarkerResponse(player, players, args and args.requestSeq or 0)
end

function CSR_ServerCommands.handleZombieDensityRequest(player, args)
    if not player or sandbox().EnableZombieDensityOverlay == false then
        return
    end

    local playerKey = markerKey(player)
    local nowMs = getNowMs()
    pruneMarkerCaches(nowMs)

    local lastRequest = zombieDensityRequests[playerKey]
    if lastRequest and (nowMs - lastRequest.time) < (CSR_Config.ZOMBIE_DENSITY_SERVER_MIN_TICKS * 16) then
        local cached = zombieDensityStateCache[playerKey]
        if cached then
            sendZombieDensityResponse(player, cached.cells, args and args.requestSeq or 0)
        end
        return
    end

    local cellSize = CSR_Config.ZOMBIE_DENSITY_CELL_SIZE
    -- Server admin can shrink the grid via the ZombieDensityCellRadius sandbox option
    -- to cut both scan area and per-frame client render cost.
    local radius = sandbox().ZombieDensityCellRadius or CSR_Config.ZOMBIE_DENSITY_CELL_RADIUS
    if type(radius) ~= "number" or radius < 1 then radius = CSR_Config.ZOMBIE_DENSITY_CELL_RADIUS end
    if radius > 3 then radius = 3 end
    local baseX = math.floor(player:getX() / cellSize) * cellSize
    local baseY = math.floor(player:getY() / cellSize) * cellSize
    local cellMap = {}

    for dx = -radius, radius do
        for dy = -radius, radius do
            local x = baseX + (dx * cellSize)
            local y = baseY + (dy * cellSize)
            local key = tostring(x) .. "," .. tostring(y)
            cellMap[key] = {
                x = x,
                y = y,
                amount = 0,
                density = 0,
            }
        end
    end

    local cell = player.getCell and player:getCell() or getCell()
    -- Use shared zombie-position cache so the world is sampled at most once every
    -- ZOMBIE_SCAN_SHARE_MS (5 s) across ALL players. The cache is keyed on time only;
    -- in MP the dedicated server's cell holds every loaded zombie, so one scan covers
    -- every connected player.
    local zombiePositions
    if nowMs - _zombieScanCache.time < ZOMBIE_SCAN_SHARE_MS and _zombieScanCache.positions then
        zombiePositions = _zombieScanCache.positions
    else
        -- B42.17 exposes IsoCell:getZombieList() which returns ONLY zombies (~10-200 entries).
        -- The previous code preferred getObjectListForLua() which returns every loaded object
        -- (walls, floors, items, ~50k+) and then filtered with instanceof(IsoZombie) -> 99% of
        -- the work was discarded. Prefer the typed list; fall back to the object list only on
        -- ancient builds that lack it.
        local zombieList = cell and ((cell.getZombieList and cell:getZombieList())
                                     or (cell.getObjectListForLua and cell:getObjectListForLua())) or nil
        local positions = {}
        if zombieList then
            local sz = zombieList:size()
            for i = 0, sz - 1 do
                local zombie = zombieList:get(i)
                -- getZombieList() is already typed; only re-check instanceof on the legacy fallback path.
                if zombie and not zombie:isDead()
                        and (zombieList ~= cell.getObjectListForLua or instanceof(zombie, "IsoZombie")) then
                    positions[#positions + 1] = { x = zombie:getX(), y = zombie:getY() }
                end
            end
        end
        _zombieScanCache = { time = nowMs, positions = positions }
        zombiePositions = positions
    end

    for _, zpos in ipairs(zombiePositions) do
        local zx = math.floor(zpos.x / cellSize) * cellSize
        local zy = math.floor(zpos.y / cellSize) * cellSize
        local key = tostring(zx) .. "," .. tostring(zy)
        local cellData = cellMap[key]
        if cellData then
            cellData.amount = cellData.amount + 1
        end
    end

    local cells = {}
    for _, cellData in pairs(cellMap) do
        if cellData.amount > 60 then
            cellData.density = 3
        elseif cellData.amount > 30 then
            cellData.density = 2
        elseif cellData.amount > 0 then
            cellData.density = 1
        end
        cells[#cells + 1] = cellData
    end

    table.sort(cells, function(a, b)
        if a.y == b.y then
            return a.x < b.x
        end
        return a.y < b.y
    end)

    local signature = buildZombieCellSignature(cells)
    local cached = zombieDensityStateCache[playerKey]
    zombieDensityRequests[playerKey] = { time = nowMs }
    if cached and cached.signature == signature then
        cached.time = nowMs
        sendZombieDensityResponse(player, cached.cells, args and args.requestSeq or 0)
        return
    end

    zombieDensityStateCache[playerKey] = {
        time = nowMs,
        signature = signature,
        cells = cells,
    }
    sendZombieDensityResponse(player, cells, args and args.requestSeq or 0)
end

function CSR_ServerCommands.handlePry(player, args)
    if not player or not args then
        return
    end

    if not isFreshRequest(args) then
        sendResult(player, "Pry request expired")
        return
    end

    if not isNearPlayer(player, args) then
        sendResult(player, "Too far away")
        return
    end

    if sandbox().EnablePrySystem ~= true then
        sendResult(player, "Pry is disabled")
        return
    end

    local crowbar = findInventoryItemById(player, args.crowbarId) or player:getInventory():FindAndReturn("Crowbar")
    local target = resolveWorldObject(args, player)
    local canPry = target and CSR_Utils.canPryWorldTarget(target, player) or false
    if not crowbar or not target or not canPry then
        sendResult(player, "Nothing to pry")
        return
    end

    local success = ZombRandFloat(0, 1) < CSR_Utils.calculatePrySuccess(player, crowbar)
    local noiseMult = sandbox().PryNoiseMultiplier or 1.0

    if success and CSR_Utils.unlockTarget(target, player, false) then
        addSound(player, args.x, args.y, args.z, CSR_Config.BASE_NOISE_RADIUS * noiseMult, 1)
        resetFrustration(player)
        sendResult(player, "Got it open!")
        return
    end

    local wear = math.max(1, math.floor(CSR_Config.TOOL_DAMAGE_ON_FAIL * (sandbox().ToolWearMultiplier or 1.0)))
    damageTool(crowbar, wear)
    addSound(player, args.x, args.y, args.z, CSR_Config.BASE_NOISE_RADIUS * noiseMult * 0.5, 1)

    if ZombRandFloat(0, 1) < (sandbox().InjuryChance or 0.1) then
        addInjury(player, CSR_Config.INJURY_DAMAGE)
        sendResult(player, "Ouch!")
    else
        sendResult(player, getFrustrationMessage(player, PRY_FRUSTRATION))
    end
end

function CSR_ServerCommands.handleBoltCut(player, args)
    if not player or not args then
        return
    end

    if not isFreshRequest(args) then
        sendResult(player, "Bolt cut request expired")
        return
    end

    if not isNearPlayer(player, args) then
        sendResult(player, "Too far away")
        return
    end

    if sandbox().EnableBoltCutter == false or sandbox().EnablePrySystem ~= true then
        sendResult(player, "Bolt cutters disabled")
        return
    end

    local tool = findInventoryItemById(player, args.toolId) or player:getInventory():FindAndReturn("BoltCutters")
    local target = resolveBoltCutObject(args, player)
    local canCut = target and CSR_Utils.canBoltCutWorldTarget(target, player) or false
    if not tool or not target or not canCut then
        sendResult(player, "Nothing to cut")
        return
    end

    local success = ZombRandFloat(0, 1) < CSR_Utils.calculateBoltCutSuccess(player, tool)
    local noiseMult = sandbox().PryNoiseMultiplier or 1.0

    if success and CSR_Utils.unlockTarget(target, player, false) then
        addSound(player, args.x, args.y, args.z, CSR_Config.BOLT_CUT_NOISE_RADIUS * noiseMult, 1)
        resetFrustration(player)
        sendResult(player, "Cut through!")
        return
    end

    local wear = math.max(1, math.floor(CSR_Config.TOOL_DAMAGE_ON_FAIL * (sandbox().ToolWearMultiplier or 1.0)))
    damageTool(tool, wear)
    addSound(player, args.x, args.y, args.z, CSR_Config.BOLT_CUT_NOISE_RADIUS * noiseMult * 0.5, 1)

    if ZombRandFloat(0, 1) < (sandbox().InjuryChance or 0.1) then
        addInjury(player, CSR_Config.INJURY_DAMAGE)
        sendResult(player, "Ouch!")
    else
        sendResult(player, getFrustrationMessage(player, BOLT_CUT_FRUSTRATION))
    end
end

function CSR_ServerCommands.handleLockpick(player, args)
    if not player or not args or sandbox().EnableScrewdriverLockpick == false then
        return
    end

    if not isFreshRequest(args) then
        sendResult(player, "Lockpick request expired")
        return
    end

    if not isNearPlayer(player, args) then
        sendResult(player, "Too far away")
        return
    end

    local screwdriver = findInventoryItemById(player, args.screwdriverId)
    if not screwdriver then
        local inv = player:getInventory()
        screwdriver = inv:FindAndReturn("Screwdriver") or inv:FindAndReturn("Screwdriver_Old") or inv:FindAndReturn("Screwdriver_Improvised")
    end
    local isPaperclip = args.isPaperclip == true
    if isPaperclip and not screwdriver then
        screwdriver = player:getInventory():FindAndReturn("Paperclip")
    end
    local target = resolveWorldObject(args, player)
    local canLockpick = target and CSR_Utils.canLockpickWorldTarget(target, player) or false
    if not screwdriver or not target or not canLockpick then
        sendResult(player, "Nothing to lockpick")
        return
    end

    local success = ZombRandFloat(0, 1) < CSR_Utils.calculateLockpickSuccess(player, screwdriver, target)
    local noiseMult = sandbox().LockpickNoiseMultiplier or 0.4
    if success and CSR_Utils.unlockTarget(target, player, false) then
        if isPaperclip then
            removeInventoryItem(player, screwdriver)
        end
        addSound(player, args.x, args.y, args.z, math.max(1, CSR_Config.BASE_NOISE_RADIUS * noiseMult), 1)
        resetFrustration(player)
        sendResult(player, "Unlocked it")
        return
    end

    if not isPaperclip then
        damageTool(screwdriver, 1)
    end
    addSound(player, args.x, args.y, args.z, math.max(1, CSR_Config.BASE_NOISE_RADIUS * noiseMult * 0.5), 1)
    sendResult(player, getFrustrationMessage(player, LOCKPICK_FRUSTRATION))
end

function CSR_ServerCommands.handlePryVehicleDoor(player, args)
    if not player or not args or sandbox().EnableVehicleDoorPry == false then
        return
    end

    if not isFreshRequest(args) then
        sendResult(player, "Pry request expired")
        return
    end

    local crowbar = findInventoryItemById(player, args.crowbarId) or player:getInventory():FindAndReturn("Crowbar")
    local vehicle = getVehicleByArgs(args)
    local part = vehicle and args.partId and vehicle:getPartById(args.partId) or nil
    if not crowbar or not vehicle or not part or not CSR_Utils.canPryVehiclePart(part) then
        sendResult(player, "Nothing to pry")
        return
    end

    if player.DistToSquared and vehicle.getX and vehicle.getY then
        local maxDistance = CSR_Config.MAX_VEHICLE_INTERACT_DISTANCE
        if player:DistToSquared(vehicle:getX(), vehicle:getY()) > (maxDistance * maxDistance) then
            sendResult(player, "Too far away")
            return
        end
    end

    local success = ZombRandFloat(0, 1) < CSR_Utils.calculatePrySuccess(player, crowbar)
    if success then
        CSR_Utils.unlockVehicleDoorPart(vehicle, part, player, true, true)
        resetFrustration(player)
        sendResult(player, "Got it open!")
        return
    end

    damageTool(crowbar, math.max(1, math.floor(CSR_Config.TOOL_DAMAGE_ON_FAIL * (sandbox().ToolWearMultiplier or 1.0))))
    if sandbox().VehicleWindowShatterChance and ZombRand(100) < sandbox().VehicleWindowShatterChance then
        local windowPart = part.getChildWindow and part:getChildWindow() or vehicle:getClosestWindow(player)
        if windowPart and windowPart.getWindow and windowPart:getWindow() and not windowPart:getWindow():isDestroyed() then
            windowPart:getWindow():damage(windowPart:getWindow():getHealth())
            vehicle:transmitPartWindow(windowPart)
        end
    end

    if ZombRandFloat(0, 1) < (sandbox().InjuryChance or 0.1) then
        addInjury(player, CSR_Config.INJURY_DAMAGE)
        sendResult(player, "Ouch!")
    else
        sendResult(player, getFrustrationMessage(player, PRY_FRUSTRATION))
    end
end

function CSR_ServerCommands.handleLockpickVehicleDoor(player, args)
    if not player or not args or sandbox().EnableScrewdriverLockpick == false then
        return
    end

    if not isFreshRequest(args) then
        sendResult(player, "Lockpick request expired")
        return
    end

    local screwdriver = findInventoryItemById(player, args.screwdriverId)
    if not screwdriver then
        local inv = player:getInventory()
        screwdriver = inv:FindAndReturn("Screwdriver") or inv:FindAndReturn("Screwdriver_Old") or inv:FindAndReturn("Screwdriver_Improvised")
    end
    local vehicle = getVehicleByArgs(args)
    local part = vehicle and args.partId and vehicle:getPartById(args.partId) or nil
    if not screwdriver or not vehicle or not part or not CSR_Utils.canLockpickVehiclePart(part) then
        sendResult(player, "Nothing to lockpick")
        return
    end

    if player.DistToSquared and vehicle.getX and vehicle.getY then
        local maxDistance = CSR_Config.MAX_VEHICLE_INTERACT_DISTANCE
        if player:DistToSquared(vehicle:getX(), vehicle:getY()) > (maxDistance * maxDistance) then
            sendResult(player, "Too far away")
            return
        end
    end

    local success = ZombRandFloat(0, 1) < CSR_Utils.calculateLockpickSuccess(player, screwdriver, part)
    if success then
        CSR_Utils.unlockVehicleDoorPart(vehicle, part, player, false, false)
        resetFrustration(player)
        sendResult(player, "Unlocked it")
        return
    end

    damageTool(screwdriver, 1)
    sendResult(player, getFrustrationMessage(player, LOCKPICK_FRUSTRATION))
end

function CSR_ServerCommands.handleOpenCan(player, args)
    local item = findInventoryItemById(player, args and args.itemId)
    local tool = findInventoryItemById(player, args and args.toolId)
    if not item or not tool or not CSR_Utils.isSupportedCan(item) or not CSR_Utils.isCanOpeningTool(tool) then
        return
    end

    local newType = CSR_Utils.getOpenCanResult(item)
    if not newType then
        return
    end

    local inv = player:getInventory()
    local openedItem = addItem(inv, newType)
    if openedItem then
        copyCondition(item, openedItem)
    end
    removeInventoryItem(player, item)
    damageTool(tool, 1)
    syncInventoryItem(tool)

    local canInjuryChance = sandbox().CanInjuryChance or 0.05
    if CSR_Utils.isKnifeItem(tool) and ZombRandFloat(0, 1) < canInjuryChance then
        addInjury(player, 5)
        sendResult(player, "Ouch! Cut myself opening the can")
    end
end

function CSR_ServerCommands.handleIgniteCorpse(player, args)
    if not player or not args or sandbox().EnableCorpseIgnite == false then
        return
    end

    if not isFreshRequest(args) then
        sendResult(player, "Ignite request expired")
        return
    end

    if not isNearPlayer(player, args) then
        sendResult(player, "Too far away")
        return
    end

    local corpse = resolveCorpse(args)
    local ignition = findInventoryItemById(player, args.ignitionId) or CSR_Utils.findPreferredIgnitionSource(player)
    if not corpse or not ignition or not CSR_Utils.hasIgnitionSource(player) then
        sendResult(player, "Need a lighter or matches")
        return
    end

    if player.burnCorpse then
        player:burnCorpse(corpse)
        consumeItemUse(player, ignition)
        syncInventoryItem(ignition)
        sendResult(player, "Corpse ignited")
    end
end

function CSR_ServerCommands.handleBarricadeWindow(player, args)
    if not player or not args then
        return
    end

    if not isFreshRequest(args) then
        sendResult(player, "Barricade request expired")
        return
    end

    if not isNearPlayer(player, args) then
        sendResult(player, "Too far away")
        return
    end

    local window = resolveBarricadeWindow(args, player)
    local plank = findInventoryItemById(player, args.plankId) or CSR_Utils.findPreferredPlank(player)
    if not window or not plank then
        sendResult(player, "Need a plank and a clear window")
        return
    end

    local barricade = IsoBarricade and IsoBarricade.AddBarricadeToObject and IsoBarricade.AddBarricadeToObject(window, player) or nil
    if not barricade then
        sendResult(player, "Cannot barricade that window")
        return
    end

    removeInventoryItem(player, plank)
    barricade:addPlank(player, plank)
    if barricade.getNumPlanks and barricade:getNumPlanks() == 1 and barricade.transmitCompleteItemToClients then
        barricade:transmitCompleteItemToClients()
    elseif barricade.sendObjectChange then
        barricade:sendObjectChange(IsoObjectChange.STATE)
    end

    sendResult(player, "Window barricaded")
end

function CSR_ServerCommands.handleMakeBandage(player, args)
    if not player or not args then
        return
    end

    if not isFreshRequest(args) then
        sendResult(player, "Bandage request expired")
        return
    end

    local item = findInventoryItemById(player, args.itemId)
    local thread = findInventoryItemById(player, args.threadId)
    local needle = findInventoryItemById(player, args.needleId)
    if not item or not thread or not needle or not CSR_Utils.canMakeBandage(item, player) then
        sendResult(player, "Need cloth, thread, and a needle")
        return
    end

    removeInventoryItem(player, item)
    consumeItemUse(player, thread)
    damageTool(needle, 1)
    local bandage = addItem(player:getInventory(), "Base.Bandage")
    syncInventoryItem(thread)
    syncInventoryItem(needle)
    syncInventoryItem(bandage)
    sendResult(player, "Bandage made")
end

function CSR_ServerCommands.handleOpenJar(player, args)
    local item = findInventoryItemById(player, args and args.itemId)
    if not item or not CSR_Utils.isSupportedJarFood(item) then
        return
    end

    local newType = CSR_Utils.getOpenJarResult(item)
    if not newType then
        return
    end

    local inv = player:getInventory()
    local openedItem = addItem(inv, newType)
    if openedItem then
        copyCondition(item, openedItem)
    end
    removeInventoryItem(player, item)

    local lidType = CSR_Utils.getJarLidType()
    if lidType then
        addItem(inv, lidType)
    end

    sendResult(player, "Jar opened")
end

function CSR_ServerCommands.handleOpenAllJars(player, args)
    local itemIds = splitIds(args and args.itemIdStr)
    local expectedTypes = splitStrings(args and args.expectedTypeStr)
    if #itemIds == 0 then
        print("[CSR] OpenAllJars: no itemIds in args")
        return
    end

    local opened = 0
    local lidType = CSR_Utils.getJarLidType()
    local inv = player:getInventory()
    for idx, itemId in ipairs(itemIds) do
        local item = findInventoryItemById(player, itemId)
        local expectedType = expectedTypes[idx]
        local newType = CSR_Utils.getOpenJarResult(item)
        if item and expectedType and item:getFullType() == expectedType and newType then
            local openedItem = addItem(inv, newType)
            if openedItem then
                copyCondition(item, openedItem)
            end
            removeInventoryItem(player, item)
            if lidType then
                addItem(inv, lidType)
            end
            opened = opened + 1
        end
    end

    if opened > 0 then
        sendResult(player, "Opened " .. opened .. " jars")
    end
end

function CSR_ServerCommands.handleSawAllLogs(player, args)
    local tool = findInventoryItemById(player, args and args.toolId)
    local itemIds = splitIds(args and args.itemIdStr)
    if not tool or #itemIds == 0 then
        print("[CSR] SawAllLogs: invalid args, tool=" .. tostring(tool) .. " ids=" .. tostring(#itemIds))
        return
    end

    local sawed = 0
    local inv = player:getInventory()
    local dropToGround = sandbox().EnableSawAllDropToGround == true
    local square = dropToGround and player:getCurrentSquare() or nil
    for _, itemId in ipairs(itemIds) do
        local item = findInventoryItemById(player, itemId)
        if item and item:getFullType() == "Base.Log" then
            removeInventoryItem(player, item)
            for _ = 1, 3 do
                if dropToGround and square then
                    local plank = instanceItem("Base.Plank")
                    square:AddWorldInventoryItem(plank, 0.0, 0.0, 0.0)
                else
                    addItem(inv, "Base.Plank")
                end
            end
            sawed = sawed + 1
        end
    end

    if sawed > 0 then
        local wear = math.max(1, math.floor(sawed / 3))
        damageTool(tool, wear)
        syncInventoryItem(tool)
        addXp(player, Perks.Woodwork, sawed * 5)
        sendResult(player, "Sawed " .. sawed .. " logs into planks (+" .. (sawed * 5) .. " XP)")
    end
end

local WATCH_TYPES_SERVER = {
    -- B42 standalone clocks
    ["AlarmClock2"] = true,
    ["Pocketwatch"] = true,
    -- B42 wristwatches (digital)
    ["WristWatch_Right_DigitalBlack"] = true,
    ["WristWatch_Left_DigitalBlack"] = true,
    ["WristWatch_Right_DigitalRed"] = true,
    ["WristWatch_Left_DigitalRed"] = true,
    ["WristWatch_Right_DigitalDress"] = true,
    ["WristWatch_Left_DigitalDress"] = true,
    -- B42 wristwatches (analog)
    ["WristWatch_Right_ClassicBlack"] = true,
    ["WristWatch_Left_ClassicBlack"] = true,
    ["WristWatch_Right_ClassicBrown"] = true,
    ["WristWatch_Left_ClassicBrown"] = true,
    ["WristWatch_Right_ClassicMilitary"] = true,
    ["WristWatch_Left_ClassicMilitary"] = true,
    ["WristWatch_Right_ClassicGold"] = true,
    ["WristWatch_Left_ClassicGold"] = true,
    ["WristWatch_Right_Expensive"] = true,
    ["WristWatch_Left_Expensive"] = true,
}

function CSR_ServerCommands.handleDismantleAllWatches(player, args)
    local tool = findInventoryItemById(player, args and args.toolId)
    local itemIds = splitIds(args and args.itemIdStr)
    if not tool or #itemIds == 0 then
        print("[CSR] DismantleAllWatches: invalid args, tool=" .. tostring(tool) .. " ids=" .. tostring(#itemIds))
        return
    end

    local dismantled = 0
    local inv = player:getInventory()
    for _, itemId in ipairs(itemIds) do
        local item = findInventoryItemById(player, itemId)
        if item and WATCH_TYPES_SERVER[item:getType()] then
            removeInventoryItem(player, item)
            addItem(inv, "Base.ElectronicsScrap")
            dismantled = dismantled + 1
        end
    end

    if dismantled > 0 then
        local wear = math.max(1, math.floor(dismantled / 4))
        damageTool(tool, wear)
        syncInventoryItem(tool)
        -- XP awarded server-side (Journals pattern: server-authoritative addXp).
        local xpGained = dismantled * 3
        if addXp and Perks and Perks.Electricity then
            addXp(player, Perks.Electricity, xpGained)
        end
        sendResult(player, "Dismantled " .. dismantled .. " watches (+" .. xpGained .. " XP)")
    end
end

function CSR_ServerCommands.handleOpenAllCans(player, args)
    local tool = findInventoryItemById(player, args and args.toolId)
    local itemIds = splitIds(args and args.itemIdStr)
    local expectedTypes = splitStrings(args and args.expectedTypeStr)
    if not tool or #itemIds == 0 or not CSR_Utils.isCanOpeningTool(tool) then
        print("[CSR] OpenAllCans: invalid args, tool=" .. tostring(tool) .. " ids=" .. tostring(#itemIds))
        return
    end

    local opened = 0
    local canInjuryChance = sandbox().CanInjuryChance or 0.05
    local inv = player:getInventory()
    for idx, itemId in ipairs(itemIds) do
        local item = findInventoryItemById(player, itemId)
        local expectedType = expectedTypes[idx]
        local newType = CSR_Utils.getOpenCanResult(item)
        if item and expectedType and item:getFullType() == expectedType and newType then
            local openedItem = addItem(inv, newType)
            if openedItem then
                copyCondition(item, openedItem)
            end
            removeInventoryItem(player, item)
            opened = opened + 1

            if CSR_Utils.isKnifeItem(tool) and ZombRandFloat(0, 1) < canInjuryChance then
                addInjury(player, 5)
            end
        end
    end

    if opened > 0 then
        damageTool(tool, math.max(1, math.floor(opened / 5)))
        syncInventoryItem(tool)
        sendResult(player, "Opened " .. opened .. " cans")
    end
end

function CSR_ServerCommands.handleOpenAmmoBox(player, args)
    local boxId = args and args.boxId
    local box = findInventoryItemById(player, boxId)
    if not box then
        print("[CSR] OpenAmmoBox: item not found for boxId=" .. tostring(boxId))
        return
    end
    if not CSR_Utils.isAmmoBox(box) then
        print("[CSR] OpenAmmoBox: item is not an ammo box: " .. tostring(box:getFullType()))
        return
    end
    local info = CSR_Utils.getAmmoBoxInfo(box)
    if not info then
        print("[CSR] OpenAmmoBox: no ammo box info for " .. tostring(box:getFullType()))
        return
    end

    local inv = player:getInventory()
    removeInventoryItem(player, box)
    for _ = 1, info.count do
        addItem(inv, info.round)
    end

    sendResult(player, "Opened box: " .. info.count .. " rounds")
end

function CSR_ServerCommands.handleOpenAllAmmoBoxes(player, args)
    local boxIdStr = args and args.boxIdStr or nil
    if not boxIdStr or boxIdStr == "" then
        print("[CSR] OpenAllAmmoBoxes: no boxIdStr in args")
        return
    end
    local boxTypeStr = args and args.boxTypeStr or ""

    local boxIds = {}
    for id in string.gmatch(boxIdStr, "[^,]+") do
        boxIds[#boxIds + 1] = tonumber(id)
    end
    local boxTypeList = {}
    for t in string.gmatch(boxTypeStr, "[^,]+") do
        boxTypeList[#boxTypeList + 1] = t
    end

    print("[CSR] OpenAllAmmoBoxes: processing " .. #boxIds .. " boxes")
    local totalRounds = 0
    local boxCount = 0
    local inv = player:getInventory()
    for idx, boxId in ipairs(boxIds) do
        local box = findInventoryItemById(player, boxId)
        if box and CSR_Utils.isAmmoBox(box) then
            local info = CSR_Utils.getAmmoBoxInfo(box)
            if info then
                removeInventoryItem(player, box)
                for _ = 1, info.count do
                    addItem(inv, info.round)
                end
                totalRounds = totalRounds + info.count
                boxCount = boxCount + 1
            end
        else
            print("[CSR] OpenAllAmmoBoxes: box not found or not ammo box, id=" .. tostring(boxId))
        end
    end
    if totalRounds > 0 then
        sendResult(player, "Opened " .. boxCount .. " boxes: " .. totalRounds .. " rounds")
    else
        print("[CSR] OpenAllAmmoBoxes: no rounds opened from " .. #boxIds .. " boxes")
    end
end

function CSR_ServerCommands.handlePackAmmoBox(player, args)
    if not player or not args then return end
    local roundType = args.roundType
    local boxType = args.boxType
    local perBox = args.perBox
    if not roundType or not boxType or not perBox then return end

    local rounds = CSR_Utils.collectAmmoRounds(player, roundType, perBox)
    if #rounds < perBox then
        sendResult(player, "Not enough rounds to pack")
        return
    end

    for _, round in ipairs(rounds) do
        removeInventoryItem(player, round)
    end
    addItem(player:getInventory(), boxType)
    sendResult(player, "Packed " .. perBox .. " rounds into a box")
end

function CSR_ServerCommands.handlePackAllAmmoBoxes(player, args)
    if not player or not args then
        print("[CSR] PackAllAmmoBoxes: nil player or args")
        return
    end
    local roundType = args.roundType
    local boxType = args.boxType
    local perBox = args.perBox
    if not roundType or not boxType or not perBox then
        print("[CSR] PackAllAmmoBoxes: missing roundType/boxType/perBox: " .. tostring(roundType) .. "/" .. tostring(boxType) .. "/" .. tostring(perBox))
        return
    end

    local totalAvailable = CSR_Utils.countAmmoRoundsOfType(player, roundType)
    local boxesToMake = math.floor(totalAvailable / perBox)
    if boxesToMake < 1 then
        print("[CSR] PackAllAmmoBoxes: not enough rounds, available=" .. tostring(totalAvailable) .. " perBox=" .. tostring(perBox))
        sendResult(player, "Not enough rounds to pack")
        return
    end

    local totalToRemove = boxesToMake * perBox
    local rounds = CSR_Utils.collectAmmoRounds(player, roundType, totalToRemove)
    if #rounds < totalToRemove then
        print("[CSR] PackAllAmmoBoxes: collected " .. #rounds .. " but needed " .. totalToRemove)
        return
    end

    local inv = player:getInventory()
    for _, round in ipairs(rounds) do
        removeInventoryItem(player, round)
    end
    for _ = 1, boxesToMake do
        addItem(inv, boxType)
    end
    sendResult(player, "Packed " .. boxesToMake .. " boxes (" .. totalToRemove .. " rounds)")
end

function CSR_ServerCommands.handleQuickRepair(player, args)
    local itemId = args and args.itemId
    local toolId = args and args.toolId
    local item = findInventoryItemById(player, itemId)
    local tool = findInventoryItemById(player, toolId)
    if not item then
        print("[CSR] QuickRepair: item not found for itemId=" .. tostring(itemId))
        return
    end
    if not tool then
        print("[CSR] QuickRepair: tool not found for toolId=" .. tostring(toolId))
        return
    end
    if not CSR_Utils.isRepairableItem(item) then
        local cond = item.getCondition and item:getCondition() or "?"
        local condMax = item.getConditionMax and item:getConditionMax() or "?"
        print("[CSR] QuickRepair: item not repairable: " .. tostring(item:getFullType()) .. " cond=" .. tostring(cond) .. "/" .. tostring(condMax))
        return
    end
    if tool:getCondition() <= 0 then
        print("[CSR] QuickRepair: tool has no condition")
        return
    end
    if CSR_Utils.isClothingItem(item) then return end

    local repairAmount = math.min(10, item:getConditionMax() - item:getCondition())
    local wear = math.max(1, math.floor(2 * (sandbox().ToolWearMultiplier or 1.0)))
    item:setCondition(item:getCondition() + repairAmount)
    damageTool(tool, wear)
    syncInventoryItem(item)
    syncInventoryItem(tool)
    syncPlayerInventory(player)
    sendResult(player, "Repaired: +" .. repairAmount .. " condition")
end

function CSR_ServerCommands.handleMaterialRepair(player, args, amount)
    local item = findInventoryItemById(player, args and args.itemId)
    local material = findInventoryItemById(player, args and args.materialId)
    if not item or not material or not CSR_Utils.isRepairableItem(item) then
        return
    end

    local repairAmount = math.min(amount, item:getConditionMax() - item:getCondition())
    item:setCondition(item:getCondition() + repairAmount)
    consumeItemUse(player, material)
    syncInventoryItem(item)
    syncInventoryItem(material)
    syncPlayerInventory(player)
    sendResult(player, "Repaired with material")
end

function CSR_ServerCommands.handlePatchClothing(player, args)
    local item = findInventoryItemById(player, args and args.itemId)
    local thread = findInventoryItemById(player, args and args.threadId)
    local needle = findInventoryItemById(player, args and args.needleId)
    local fabric = findInventoryItemById(player, args and args.fabricId)
    if not item or not thread or not needle or not fabric then return end
    if not CSR_Utils.isClothingItem(item) or not CSR_Utils.isRepairableItem(item) then return end

    local repairAmount = math.min(15, item:getConditionMax() - item:getCondition())
    item:setCondition(item:getCondition() + repairAmount)
    consumeItemUse(player, thread)
    damageTool(needle, 1)
    removeInventoryItem(player, fabric)
    syncInventoryItem(item)
    syncInventoryItem(thread)
    syncInventoryItem(needle)
    syncPlayerInventory(player)
    if player.getXp then
        addXp(player, Perks.Tailoring, 3)
    end
    sendResult(player, "Clothing patched")
end

function CSR_ServerCommands.handleRepairAllClothing(player, args)
    if not player then return end
    local inv = player:getInventory()
    if not inv then return end

    local list = CSR_Utils.getDamagedWornClothing(player)
    if #list == 0 then return end

    local processed = 0
    for _, item in ipairs(list) do
        local thread = CSR_Utils.findPreferredThread(player)
        local needle = CSR_Utils.findPreferredNeedle(player)
        local fabric = CSR_Utils.findPreferredFabricMaterial(player)
        if not (thread and needle and fabric) then break end

        item:setCondition(item:getConditionMax())

        if item.getCoveredParts and item.getPatchType and item.removePatch then
            local parts = item:getCoveredParts()
            if parts and parts.size then
                for i = 0, parts:size() - 1 do
                    local part = parts:get(i)
                    if part and item:getPatchType(part) ~= nil then
                        item:removePatch(part)
                    end
                end
            end
        end

        consumeItemUse(player, thread)
        damageTool(needle, 1)
        removeInventoryItem(player, fabric)
        syncInventoryItem(item)
        syncInventoryItem(thread)
        syncInventoryItem(needle)
        processed = processed + 1
    end

    if processed > 0 then
        syncPlayerInventory(player)
        if player.getXp then
            addXp(player, Perks.Tailoring, 3 * processed)
        end
        sendResult(player, "Repaired " .. processed .. " garment(s)")
    end
end

function CSR_ServerCommands.handleTearCloth(player, args)
    local item = findInventoryItemById(player, args and args.itemId)
    local expectedType = args and args.expectedType or nil
    local tearInfo = CSR_Utils.getTearClothInfo(item)
    if not item or not expectedType or item:getFullType() ~= expectedType or not tearInfo then
        return
    end

    local tool = findInventoryItemById(player, args and args.toolId)
    if tearInfo.requiresTool and (not tool or not CSR_Utils.isClothCuttingTool(tool) or tool:getCondition() <= 0) then
        return
    end

    local inv = player:getInventory()
    removeInventoryItem(player, item)
    for _ = 1, tearInfo.quantity do
        addItem(inv, tearInfo.outputType)
    end
    if tool then
        damageTool(tool, 1)
        syncInventoryItem(tool)
    end
    sendResult(player, "Tore clothing into usable material")
end

function CSR_ServerCommands.handleTearAllCloth(player, args)
    local itemIds = splitIds(args and args.itemIdStr)
    local expectedTypes = splitStrings(args and args.expectedTypeStr)
    local outputTypes = splitStrings(args and args.outputTypeStr)
    local quantities = splitStrings(args and args.quantityStr)
    if #itemIds == 0 then
        print("[CSR] TearAllCloth: no itemIds in args")
        return
    end

    local tool = findInventoryItemById(player, args and args.toolId)
    local torn = 0
    for idx, itemId in ipairs(itemIds) do
        local item = findInventoryItemById(player, itemId)
        local expectedType = expectedTypes[idx]
        local expectedOutput = outputTypes[idx]
        local expectedQuantity = tonumber(quantities[idx] or 0) or 0
        local tearInfo = CSR_Utils.getTearClothInfo(item)
        if item and expectedType and item:getFullType() == expectedType and tearInfo and tearInfo.outputType == expectedOutput and tearInfo.quantity == expectedQuantity then
            if tearInfo.requiresTool and (not tool or not CSR_Utils.isClothCuttingTool(tool) or tool:getCondition() <= 0) then
                break
            end
            removeInventoryItem(player, item)
            for _ = 1, tearInfo.quantity do
                addItem(player:getInventory(), tearInfo.outputType)
            end
            torn = torn + 1
        end
    end

    if torn > 0 then
        if tool then
            damageTool(tool, math.max(1, math.floor(torn / 3)))
            syncInventoryItem(tool)
        end
        sendResult(player, "Tore " .. torn .. " clothing items into material")
    end
end

function CSR_ServerCommands.handleReplaceBattery(player, args)
    local item = findInventoryItemById(player, args and args.itemId)
    local battery = findInventoryItemById(player, args and args.batteryId)
    if not item or not battery or not CSR_Utils.canRechargeFlashlight(item) or battery:getType() ~= "Battery" then
        return
    end

    item:setDelta(1.0)
    removeInventoryItem(player, battery)
    syncInventoryItem(item)
    syncPlayerInventory(player)
    sendResult(player, "Battery replaced")
end

function CSR_ServerCommands.handleRefillLighter(player, args)
    local lighter = findInventoryItemById(player, args and args.itemId)
    local fluid = findInventoryItemById(player, args and args.fluidId)
    if not lighter or not fluid or not CSR_Utils.canRefillLighter(lighter) or fluid:getType() ~= "LighterFluid" or not fluid.getDelta then
        return
    end

    local current = lighter:getDelta()
    local available = fluid:getDelta()
    local needed = 1.0 - current
    local transfer = math.min(needed, available)

    lighter:setDelta(math.min(1.0, current + transfer))
    fluid:setDelta(math.max(0.0, available - transfer))
    if fluid:getDelta() <= 0 then
        removeInventoryItem(player, fluid)
    end

    syncInventoryItem(lighter)
    syncInventoryItem(fluid)
    sendResult(player, "Lighter refilled")
end

function CSR_ServerCommands.handleClipboardAddPaper(player, args)
    if not isFreshRequest(args) then
        return
    end

    local item = findInventoryItemById(player, args and args.itemId)
    local paper = player and player:getInventory() and player:getInventory():FindAndReturn("SheetPaper2") or nil
    if not item or not paper or not CSR_Utils.isClipboard(item) then
        return
    end

    local data = CSR_Utils.getClipboardData(item)
    if not data or data.paperAmount >= 5 then
        return
    end

    data.paperAmount = data.paperAmount + 1
    removeInventoryItem(player, paper)
    syncInventoryItem(item)
    sendResult(player, "Added paper to clipboard")
end

function CSR_ServerCommands.handleClipboardRemovePaper(player, args)
    if not isFreshRequest(args) then
        return
    end

    local item = findInventoryItemById(player, args and args.itemId)
    if not item or not CSR_Utils.isClipboard(item) then
        return
    end

    local data = CSR_Utils.getClipboardData(item)
    if not data or data.paperAmount <= 0 then
        return
    end

    data.paperAmount = data.paperAmount - 1
    local maxEntries = data.paperAmount * 6
    for i = #data.entries, maxEntries + 1, -1 do
        data.entries[i] = nil
    end
    addItem(player:getInventory(), "Base.SheetPaper2")
    syncInventoryItem(item)
    sendResult(player, "Removed paper from clipboard")
end

function CSR_ServerCommands.handleClipboardSave(player, args)
    if not isFreshRequest(args) then
        return
    end

    local item = findInventoryItemById(player, args and args.itemId)
    if not item or not CSR_Utils.isClipboard(item) then
        return
    end

    local data = CSR_Utils.getClipboardData(item)
    if not data then
        return
    end

    local title = tostring(args and args.title or data.title or "Clipboard")
    title = title:gsub("[%c]", ""):sub(1, 48)
    if title == "" then
        title = "Clipboard"
    end

    local paperAmount = data.paperAmount or 0
    local maxEntries = paperAmount * 6
    local entryTextsStr = args and args.entryTextsStr or ""
    local entryCheckedStr = args and args.entryCheckedStr or ""

    local entryTexts = {}
    if entryTextsStr ~= "" then
        for text in string.gmatch(entryTextsStr .. "\n", "(.-)\n") do
            entryTexts[#entryTexts + 1] = text
        end
    end

    local checkedSet = {}
    for idx in string.gmatch(entryCheckedStr, "[^,]+") do
        checkedSet[tonumber(idx)] = true
    end

    local entries = {}
    for i = 1, math.min(maxEntries, #entryTexts) do
        local text = tostring(entryTexts[i] or ""):gsub("[%c]", " "):sub(1, 64)
        entries[i] = {
            text = text,
            checked = checkedSet[i] == true,
        }
    end

    data.title = title
    data.entries = entries
    if item.setCustomName then
        item:setCustomName(true)
    end
    item:setName("Clipboard: " .. title)
    syncInventoryItem(item)
    sendResult(player, "Clipboard updated")
end


-- ─── Dual Wield Server Logic ──────────────────────────────────────────
--
-- ARCHITECTURE NOTE -- READ BEFORE REFACTORING (especially LLM advisors):
--
-- The dual-wield secondary-weapon restoration uses a HYBRID design on
-- purpose. Two cooperating mechanisms run in parallel:
--
--   1. Events.OnTick -> checkUnarmedWeaponMode (below)
--        Anchors the current secondary every tick + restores within a
--        2-tick freshness window. This is the SAFETY NET.
--   2. Events.OnPlayerAttackFinished -> onServerAttackFinished (below)
--        Restores secondary after Java's Hit() pipeline nulls it during a
--        primary attack. This is the FAST PATH.
--
-- Do NOT "convert OnTick to event-driven" -- that suggestion has been
-- floated repeatedly and has been rejected each time. The OnTick path is
-- load-bearing and catches three classes of clears that no event covers:
--
--   (a) Third-party sync-mod clears (iSync, anti-cheat) that null the
--       secondary slot OUTSIDE any attack pipeline. No OnPlayerAttackFinished
--       fires. Only the per-tick freshness check restores it.
--   (b) 2H weapon mirror transitions. Vanilla mirrors a 2H weapon into BOTH
--       primary and secondary slots while wielded; on unequip the engine
--       clears primary first and secondary one tick later. The isMirrored2H
--       guard below is a per-tick state machine that drops the anchor during
--       2H states so we never restore a 1H over the 2H state, nor restore
--       the 2H over the unequip. This cannot be expressed as a single event.
--   (c) Distinguishing intentional player unequip from engine clear. The
--       2-tick freshness window is what tells them apart. Attack-finished
--       events carry no temporal context that can replace this.
--
-- History: v1.7.5-v1.7.7 changelog entries document the field bugs that
-- forced this design (off-hand weapon permanently disappearing, 2H weapons
-- stuck in off-hand, sync-mod ghost clears). Per-player cost is O(1) -- a
-- couple of getters and a hashmap write -- so there is no perf reason to
-- collapse it. If you must touch this, read those changelog entries first
-- and add new edge cases ALONGSIDE the existing logic, not in place of it.
--
-- ─────────────────────────────────────────────────────────────────────
local playerUnarmedModes = {}
local playerLastLeftHandInfos = {}

-- Secondary-weapon anchor: tracks each dual-wielding player's last-known valid
-- secondary so it can be restored when Java's primary-attack pipeline clears it.
-- The anchor is considered "fresh" only when it was updated in the same server
-- tick as the attack-finished event fires; this prevents fighting intentional
-- player unequips (which happen on a different tick than any attack).
local playerSecondaryAnchors = {}  -- [pid] = { weapon = item, tick = N }
local dwServerTick = 0             -- monotonic counter updated in onDualWieldServerTick

-- v1.8.1 Part A helper: clear any attachedSlot the engine set on an item so
-- setSecondaryHandItem() doesn't re-equip a weapon that the hotbar still
-- considers "stowed" (which is what makes the off-hand weapon appear stuck
-- and unequipable from inventory).
local function dwClearAttachedSlot(player, item)
    if not item then return end
    if item.getAttachedSlot and item:getAttachedSlot() ~= -1 then
        if item.setAttachedSlot     then item:setAttachedSlot(-1) end
        if item.setAttachedSlotType then item:setAttachedSlotType(nil) end
        if item.setAttachedToModel  then item:setAttachedToModel(nil) end
        if player and player.removeAttachedItem then
            player:removeAttachedItem(item)
        end
    end
end

-- v1.8.1 Part B: anchor freshness window extended from 2 -> 8 ticks. Catches
-- the slow-swing / packet-lag case where OnPlayerAttackFinished fires later
-- than the previous 2-tick window, leaving the secondary cleared. 8 ticks is
-- still far below any human-perceptible unequip intent.
local DW_ANCHOR_FRESHNESS_TICKS = 8

local function getIsoCharacterFromID(referencePlayer, id)
    local utils = getDWUtils()
    local p = utils.getPlayerFromID(id)
    if p then return p end
    return utils.getZombieFromID(referencePlayer, id)
end

local function checkUnarmedWeaponMode(player)
    if player:isDead() or player:isZombie() then return end

    local utils = getDWUtils()
    local pid = utils.getPlayerID(player)

    -- Track secondary-weapon anchor every tick, regardless of primary-hand state.
    -- This must happen before any early-return so even armed players are tracked.
    --
    -- v1.7.7: NEVER anchor a 2H weapon held in the secondary slot. Vanilla
    -- mirrors a 2H weapon into BOTH primary and secondary slots while it is
    -- wielded. On unequip the engine clears primary first and secondary one
    -- tick later. Without this guard the previous code (a) saved the mirrored
    -- 2H ref into the anchor every tick, then (b) the moment the engine cleared
    -- secondary the next tick saw an empty slot with a fresh anchor and
    -- re-equipped the 2H weapon as a "dual-wield secondary" -- leaving the
    -- weapon visually stuck in the off-hand and un-stowable. The fix: only
    -- anchor a real dual-wield secondary (1H weapon, distinct from primary).
    local sec = player:getSecondaryHandItem()
    local prim = player:getPrimaryHandItem()
    local isMirrored2H = sec ~= nil and (
        sec == prim
        or (sec.isRequiresEquippedBothHands and sec:isRequiresEquippedBothHands())
        or (sec.isTwoHandWeapon and sec:isTwoHandWeapon())
    )
    if sec and not sec:isBroken() and sec.IsWeapon and sec:IsWeapon() and not isMirrored2H then
        playerSecondaryAnchors[pid] = { weapon = sec, tick = dwServerTick }
    elseif isMirrored2H then
        -- Drop any stale anchor while a 2H mirror is active so we never restore
        -- a 1H weapon over the 2H state, and never restore the 2H over the unequip.
        playerSecondaryAnchors[pid] = nil
    else
        -- Slot empty: if the anchor is still fresh (<= DW_ANCHOR_FRESHNESS_TICKS),
        -- restore.  Catches engine clears + third-party sync-mod clears that
        -- don't fire OnPlayerAttackFinished. The freshness window prevents
        -- fighting an intentional unequip (which would settle within 1 tick).
        local anchor = playerSecondaryAnchors[pid]
        if anchor and (dwServerTick - anchor.tick) <= DW_ANCHOR_FRESHNESS_TICKS then
            local w = anchor.weapon
            -- Extra defence: the cached weapon may have been a 2H mirror saved
            -- before this guard existed; refuse to re-equip 2H weapons here.
            local wIs2H = w ~= nil and (
                (w.isRequiresEquippedBothHands and w:isRequiresEquippedBothHands())
                or (w.isTwoHandWeapon and w:isTwoHandWeapon())
            )
            if w and not w:isBroken() and not wIs2H and player:getInventory():contains(w) then
                dwClearAttachedSlot(player, w)
                player:setSecondaryHandItem(w)
            else
                playerSecondaryAnchors[pid] = nil
            end
        end
    end

    if player:getPrimaryHandItem() ~= nil then return end
    local unarmedMode = utils.getUnarmedMode(player)
    if playerUnarmedModes[pid] == unarmedMode then return end
    local weapon = player:getAttackingWeapon()
    if weapon:getScriptItem() ~= unarmedMode.SCRIPTITEM then
        utils.changeWeaponStats(weapon, unarmedMode.ITEM, unarmedMode.SCRIPTITEM)
    end
    playerUnarmedModes[pid] = unarmedMode
end

local function onDualWieldServerTick(tick)
    local sb = SandboxVars and SandboxVars.CommonSenseReborn or nil
    if sb and sb.EnableDualWield == false then return end
    dwServerTick = dwServerTick + 1
    -- v1.8.5: ~3 Hz throttle. Vanilla ~30 Hz tick × every player × every
    -- frame walked the unarmed-mode check on the server thread; on a
    -- 16-player server that's 480 calls/sec for a state that changes
    -- only when items are equipped/unequipped. Every 10th tick is plenty.
    if (dwServerTick % 10) ~= 0 then return end
    getDWUtils().foreachPlayerDo(checkUnarmedWeaponMode)
end

function CSR_ServerCommands.handleDW_LeftAttack(player, args)
    local utils = getDWUtils()
    local pid = utils.getPlayerID(player)
    playerLastLeftHandInfos[pid] = utils.checkIfValidLeftHandAttack(player, true)
end

function CSR_ServerCommands.handleDW_LeftHit(player, data)
    local utils = getDWUtils()
    local pid = utils.getPlayerID(player)
    local leftHandAttackInfo = playerLastLeftHandInfos[pid]
    if not leftHandAttackInfo then return end
    playerLastLeftHandInfos[pid] = nil

    -- Re-resolve weapon from current hand to avoid stale item references
    local weapon = leftHandAttackInfo.weapon
    if leftHandAttackInfo.mode == CSR_DualWield.ArmedMode then
        local currentSec = player:getSecondaryHandItem()
        if currentSec and not currentSec:isBroken() then
            weapon = currentSec
        end
    end
    if weapon:isBroken() then return end

    -- Anchor: save secondary before combat processing so we can restore it.
    -- Java's Hit() can internally clear the player's equipped items as part of
    -- the combat pipeline (designed for primary hand only). We must restore after.
    local anchoredSecondary = player:getSecondaryHandItem()

    local maxHits = CSR_LeftHandAttackAction.getMaxHits(player, weapon, leftHandAttackInfo.mode)
    local attackerIsDoShove = player:isDoShove()
    player:setDoShove(false)
    -- Co-operative flag: third-party sync/anti-cheat mods (e.g. iSync) can read
    -- this to skip ghost-swing detection during our authoritative left-hand
    -- Hit() calls.  Always cleared in the protected pcall below.
    CSR_DualWield._inLeftHandHit = true
    local ok, err = pcall(function()
        for _, targetID in ipairs(data) do
            local enemy = getIsoCharacterFromID(player, targetID)
            if enemy then
                -- Use Hit() for full combat effects (knockback, stagger, blood, etc.)
                -- but immediately re-anchor the secondary hand afterward
                enemy:Hit(weapon, player, 1, false, 1)
                -- Re-anchor: Hit() may have cleared the secondary hand item
                if anchoredSecondary and not anchoredSecondary:isBroken() then
                    if player:getSecondaryHandItem() ~= anchoredSecondary then
                        dwClearAttachedSlot(player, anchoredSecondary)
                        player:setSecondaryHandItem(anchoredSecondary)
                    end
                end
                maxHits = maxHits - 1
                if maxHits <= 0 then break end
            end
        end
    end)
    CSR_DualWield._inLeftHandHit = false
    if not ok then print("[CSR][DW] handleDW_LeftHit error: " .. tostring(err)) end
    player:setDoShove(attackerIsDoShove)

    -- Final anchor check after all hits processed
    if anchoredSecondary and not anchoredSecondary:isBroken() then
        if player:getSecondaryHandItem() ~= anchoredSecondary then
            dwClearAttachedSlot(player, anchoredSecondary)
            player:setSecondaryHandItem(anchoredSecondary)
        end
    end

    -- Handle weapon breaking (only if it actually broke from Hit()'s internal damage)
    if weapon:isBroken() then
        if player:getSecondaryHandItem() == weapon then
            player:setSecondaryHandItem(nil)
        end
    end

    -- Sync weapon condition state to clients
    if leftHandAttackInfo.mode.MAYDAMAGEWEAPON then
        syncInventoryItem(weapon)
    end

    if leftHandAttackInfo.xpPerk and player.getXp then
        addXp(player, leftHandAttackInfo.xpPerk, CSR_DualWield.LEFT_ATTACK_XP)
        if not weapon:hasTag(ItemTag.NO_MAINTENANCE_XP) then
            local condLowerChance = weapon:getConditionLowerChance()
            local amount = CSR_DualWield.LEFT_ATTACK_MAINTENANCE_XP
            if condLowerChance > 10 then
                amount = amount * 10 / condLowerChance
            end
            addXp(player, Perks.Maintenance, amount)
        end
    end
end

function CSR_ServerCommands.handleDW_UnarmedRightHit(player, data)
    if not data or #data < 2 then return end
    local targetID = data[1]
    local damageSplit = data[2]
    if not targetID or not damageSplit then return end
    local target = getIsoCharacterFromID(player, targetID)
    if not target then return end
    local utils = getDWUtils()
    local valid, mode = utils.isNonDefaultUnarmedAttack(player, target, true)
    if not valid then return end
    local attackerIsDoShove = player:isDoShove()
    player:setDoShove(false)
    CSR_DualWield._inLeftHandHit = true
    pcall(target.Hit, target, mode.ITEM, player, damageSplit, false, 1.0)
    CSR_DualWield._inLeftHandHit = false
    player:setDoShove(attackerIsDoShove)
end

if not CSR_ServerCommands._dualWieldTickRegistered then
    CSR_ServerCommands._dualWieldTickRegistered = true
    Events.OnTick.Add(onDualWieldServerTick)
end

-- Restore secondary weapon if the vanilla primary-attack pipeline cleared it.
-- Java's Hit() may null the secondary hand slot during combat processing.
-- We re-equip it here, within the same update cycle, so the cleared state is
-- never broadcast to clients.
-- Anchor freshness check (tick delta ≤ 1) prevents fighting intentional
-- player unequips, which happen on a prior tick, not during an attack.
local function onServerAttackFinished(player)
    if not player or not instanceof(player, "IsoPlayer") then return end
    local sb = SandboxVars and SandboxVars.CommonSenseReborn or nil
    if sb and sb.EnableDualWield == false then return end
    if player:getSecondaryHandItem() ~= nil then return end  -- nothing to restore

    local utils = getDWUtils()
    local pid = utils.getPlayerID(player)
    local anchorData = playerSecondaryAnchors[pid]
    if not anchorData then return end

    -- Only act when the anchor was set in the current or recent ticks.
    -- A stale anchor means the player unequipped before this attack.
    if dwServerTick - anchorData.tick > DW_ANCHOR_FRESHNESS_TICKS then return end

    local weapon = anchorData.weapon
    if weapon:isBroken() then
        playerSecondaryAnchors[pid] = nil
        return
    end
    -- v1.7.7: refuse to restore 2H weapons -- they are mirrored from primary,
    -- not real dual-wield secondaries (see checkUnarmedWeaponMode comment).
    local wIs2H = (weapon.isRequiresEquippedBothHands and weapon:isRequiresEquippedBothHands())
        or (weapon.isTwoHandWeapon and weapon:isTwoHandWeapon())
    if wIs2H then
        playerSecondaryAnchors[pid] = nil
        return
    end
    if player:getInventory():contains(weapon) then
        dwClearAttachedSlot(player, weapon)
        player:setSecondaryHandItem(weapon)
    else
        playerSecondaryAnchors[pid] = nil
    end
end

if Events and Events.OnPlayerAttackFinished then
    Events.OnPlayerAttackFinished.Add(onServerAttackFinished)
end

-- ─── End Dual Wield Server Logic ─────────────────────────────────────

-- ─── Admin: Purge All Fireworks ──────────────────────────────────────

local function removeFireworksFromContainer(container)
    if not container or not container.getItems then return 0 end
    local items = container:getItems()
    if not items then return 0 end
    local count = 0
    for i = items:size() - 1, 0, -1 do
        local item = items:get(i)
        if item and item.getFullType and item:getFullType() == "CommonSenseReborn.Firework" then
            container:Remove(item)
            if sendRemoveItemFromContainer then
                sendRemoveItemFromContainer(container, item)
            end
            count = count + 1
        elseif item and instanceof(item, "InventoryContainer") then
            local subInv = item.getInventory and item:getInventory() or nil
            if subInv then
                count = count + removeFireworksFromContainer(subInv)
            end
        end
    end
    return count
end

-- =============================================
-- NOTICE BOARD SERVER HANDLERS
-- =============================================

local NOTICE_PREFIX_SRV        = "papernotices_01_"
local WHITEBOARD_PREFIX_SRV    = "location_business_office_generic_01_"
local WHITEBOARD_MIN_SRV       = 50
local WHITEBOARD_MAX_SRV       = 55
local NOTICE_MAX_LEN_SRV       = 80
local WHITEBOARD_MAX_LEN_SRV   = 80
local WHITEBOARD_LINES_SRV     = 6

local function isWhiteboardSpriteSrv(sName)
    if not sName then return false end
    if sName:sub(1, #WHITEBOARD_PREFIX_SRV) ~= WHITEBOARD_PREFIX_SRV then return false end
    local num = tonumber(sName:sub(#WHITEBOARD_PREFIX_SRV + 1))
    return num and num >= WHITEBOARD_MIN_SRV and num <= WHITEBOARD_MAX_SRV
end

local function findWorldIsoObject(x, y, z, spriteName)
    if not x or not y or not z then return nil end
    local sq = getCell and getCell():getGridSquare(x, y, z)
    if not sq then return nil end
    local objs = sq:getObjects()
    if not objs then return nil end
    for i = 0, objs:size() - 1 do
        local o = objs:get(i)
        if o and o.getSpriteName and o:getSpriteName() == spriteName then
            return o
        end
    end
    return nil
end

local function serverHasPenOrMarker(player)
    local inv = player:getInventory()
    return inv:containsTypeRecurse("Pen")
        or inv:containsTypeRecurse("RedPen")
        or inv:containsTypeRecurse("BluePen")
        or inv:containsTypeRecurse("Pencil")
        or inv:containsTypeRecurse("MarkerBlack")
        or inv:containsTypeRecurse("MarkerBlue")
        or inv:containsTypeRecurse("MarkerRed")
        or inv:containsTypeRecurse("MarkerGreen")
end

function CSR_ServerCommands.handleNoticeBoardWrite(player, args)
    if not CSR_FeatureFlags.isNoticeBoardEnabled() then return end

    local x = args and tonumber(args.x)
    local y = args and tonumber(args.y)
    local z = args and tonumber(args.z)
    local spriteName = args and tostring(args.spriteName or "")

    -- Validate sprite is a paper notice
    if spriteName:sub(1, #NOTICE_PREFIX_SRV) ~= NOTICE_PREFIX_SRV then
        return
    end

    if not serverHasPenOrMarker(player) then
        sendResult(player, "You need a pen or marker to write.")
        return
    end

    -- Distance check: server player vs tile coords
    if not isNearPlayer(player, {x=x, y=y, z=z}) then
        return
    end

    local obj = findWorldIsoObject(x, y, z, spriteName)
    if not obj then return end

    local text = tostring(args.text or ""):gsub("[%c]", " "):sub(1, NOTICE_MAX_LEN_SRV)
    local md = obj:getModData()
    md.csrNotice = {
        text      = text,
        author    = player:getUsername(),
        timestamp = getTimestamp and getTimestamp() or 0,
    }
    if obj.transmitModData then obj:transmitModData() end
    sendResult(player, "Notice posted.")
end

function CSR_ServerCommands.handleWhiteboardWrite(player, args)
    if not CSR_FeatureFlags.isNoticeBoardEnabled() then return end

    local x = args and tonumber(args.x)
    local y = args and tonumber(args.y)
    local z = args and tonumber(args.z)
    local spriteName = args and tostring(args.spriteName or "")

    if not isWhiteboardSpriteSrv(spriteName) then
        return
    end

    -- Whiteboard writing requires a marker specifically
    local inv = player:getInventory()
    local hasMarker = inv:containsTypeRecurse("MarkerBlack")
        or inv:containsTypeRecurse("MarkerBlue")
        or inv:containsTypeRecurse("MarkerRed")
        or inv:containsTypeRecurse("MarkerGreen")
    if not hasMarker then
        sendResult(player, "You need a marker to write on the whiteboard.")
        return
    end

    if not isNearPlayer(player, {x=x, y=y, z=z}) then
        return
    end

    local obj = findWorldIsoObject(x, y, z, spriteName)
    if not obj then return end

    local linesStr = tostring(args.linesStr or "")
    -- Sanitize each line but keep as a flat newline-delimited string.
    -- Nested Lua arrays in world-object modData don't survive the Java
    -- round-trip after transmitModData, so we never store arrays here.
    local rawLines = {}
    for line in (linesStr .. "\n"):gmatch("(.-)\n") do
        rawLines[#rawLines + 1] = tostring(line):gsub("[%c]", " "):sub(1, WHITEBOARD_MAX_LEN_SRV)
        if #rawLines >= WHITEBOARD_LINES_SRV then break end
    end

    local md = obj:getModData()
    -- Store each line under its own flat key (no delimiter) so values survive
    -- the Java modData serialization round-trip without issues.
    for i = 1, WHITEBOARD_LINES_SRV do
        md["csrWbLine" .. i] = rawLines[i] or ""
    end
    md.csrWbEditor = player:getUsername()
    if obj.transmitModData then obj:transmitModData() end
    sendResult(player, "Whiteboard saved.")
end


function CSR_ServerCommands.handlePurgeFireworks(player, args)
    local access = player and player.getAccessLevel and player:getAccessLevel() or ""
    if access ~= "admin" and access ~= "Admin" then
        print("[CSR] PurgeFireworks denied for non-admin: " .. tostring(access))
        return
    end

    local totalRemoved = 0

    -- 1) Purge from all online players' inventories
    local players = getOnlinePlayers and getOnlinePlayers() or nil
    if players then
        for i = 0, players:size() - 1 do
            local p = players:get(i)
            if p then
                local inv = p:getInventory()
                if inv then
                    local removed = removeFireworksFromContainer(inv)
                    if removed > 0 then
                        totalRemoved = totalRemoved + removed
                        syncPlayerInventory(p)
                        local pName = p.getUsername and p:getUsername() or "?"
                        print("[CSR] PurgeFireworks: removed " .. removed .. " from player " .. pName)
                    end
                end
            end
        end
    end

    -- 2) Purge from world containers in all loaded cells
    local cell = getCell and getCell() or nil
    if cell then
        -- B42.17: getObjectList() renamed to getObjectListForLua()
        local objects = (cell.getObjectListForLua and cell:getObjectListForLua()) or cell:getObjectList()
        if objects then
            for i = 0, objects:size() - 1 do
                local obj = objects:get(i)
                if obj then
                    local containerCount = obj.getContainerCount and obj:getContainerCount() or 0
                    for c = 0, containerCount - 1 do
                        local container = obj:getContainerByIndex(c)
                        if container then
                            totalRemoved = totalRemoved + removeFireworksFromContainer(container)
                        end
                    end
                end
            end
        end
    end

    print("[CSR] PurgeFireworks complete: " .. totalRemoved .. " fireworks removed")
    sendResult(player, "Purged " .. totalRemoved .. " Distraction Firework(s) from all players and loaded world containers")
end

-- ─── End Admin: Purge All Fireworks ──────────────────────────────────

local function onClientCommand(module, command, player, args)
    if module ~= "CommonSenseReborn" then
        return
    end

    local playerName = player and player.getUsername and player:getUsername() or "unknown"
    print("[CSR] Server received command: " .. tostring(command) .. " from " .. playerName)


    if isDuplicateRequest(player, command, args) then
        return
    end


    local ok, err = pcall(function()
    if command == "RequestPlayerMarkers" then
        CSR_ServerCommands.handlePlayerMarkerRequest(player, args)
    elseif command == "RequestZombieDensity" then
        CSR_ServerCommands.handleZombieDensityRequest(player, args)
    elseif command == "LockpickTarget" then
        CSR_ServerCommands.handleLockpick(player, args)
    elseif command == "LockpickVehicleDoor" then
        CSR_ServerCommands.handleLockpickVehicleDoor(player, args)
    elseif command == "PryTarget" then
        CSR_ServerCommands.handlePry(player, args)
    elseif command == "BoltCutTarget" then
        CSR_ServerCommands.handleBoltCut(player, args)
    elseif command == "PryVehicleDoor" then
        CSR_ServerCommands.handlePryVehicleDoor(player, args)
    elseif command == "IgniteCorpse" then
        CSR_ServerCommands.handleIgniteCorpse(player, args)
    elseif command == "BarricadeWindow" then
        CSR_ServerCommands.handleBarricadeWindow(player, args)
    elseif command == "OpenCan" then
        CSR_ServerCommands.handleOpenCan(player, args)
    elseif command == "OpenJar" then
        CSR_ServerCommands.handleOpenJar(player, args)
    elseif command == "OpenAllCans" then
        CSR_ServerCommands.handleOpenAllCans(player, args)
    elseif command == "OpenAllJars" then
        CSR_ServerCommands.handleOpenAllJars(player, args)
    elseif command == "OpenAmmoBox" then
        CSR_ServerCommands.handleOpenAmmoBox(player, args)
    elseif command == "OpenAllAmmoBoxes" then
        CSR_ServerCommands.handleOpenAllAmmoBoxes(player, args)
    elseif command == "PackAmmoBox" then
        CSR_ServerCommands.handlePackAmmoBox(player, args)
    elseif command == "PackAllAmmoBoxes" then
        CSR_ServerCommands.handlePackAllAmmoBoxes(player, args)
    elseif command == "SawAllLogs" then
        CSR_ServerCommands.handleSawAllLogs(player, args)
    elseif command == "DismantleAllWatches" then
        CSR_ServerCommands.handleDismantleAllWatches(player, args)
    elseif command == "QuickRepair" then
        CSR_ServerCommands.handleQuickRepair(player, args)
    elseif command == "DuctTapeRepair" then
        CSR_ServerCommands.handleMaterialRepair(player, args, 25)
    elseif command == "GlueRepair" then
        local gItem = findInventoryItemById(player, args and args.itemId)
        if not CSR_Utils.isClothingItem(gItem) then
            CSR_ServerCommands.handleMaterialRepair(player, args, 20)
        end
    elseif command == "TapeRepair" then
        CSR_ServerCommands.handleMaterialRepair(player, args, 15)
    elseif command == "PatchClothing" then
        CSR_ServerCommands.handlePatchClothing(player, args)
    elseif command == "RepairAllClothing" then
        CSR_ServerCommands.handleRepairAllClothing(player, args)
    elseif command == "TearCloth" then
        CSR_ServerCommands.handleTearCloth(player, args)
    elseif command == "TearAllCloth" then
        CSR_ServerCommands.handleTearAllCloth(player, args)
    elseif command == "ReplaceBattery" then
        CSR_ServerCommands.handleReplaceBattery(player, args)
    elseif command == "RefillLighter" then
        CSR_ServerCommands.handleRefillLighter(player, args)
    elseif command == "MakeBandage" then
        CSR_ServerCommands.handleMakeBandage(player, args)
    elseif command == "ClipboardAddPaper" then
        CSR_ServerCommands.handleClipboardAddPaper(player, args)
    elseif command == "ClipboardRemovePaper" then
        CSR_ServerCommands.handleClipboardRemovePaper(player, args)
    elseif command == "ClipboardSave" then
        CSR_ServerCommands.handleClipboardSave(player, args)
    elseif command == "DW_LeftAttack" then
        CSR_ServerCommands.handleDW_LeftAttack(player, args)
    elseif command == "DW_LeftHit" then
        CSR_ServerCommands.handleDW_LeftHit(player, args)
    elseif command == "DW_UnarmedRightHit" then
        CSR_ServerCommands.handleDW_UnarmedRightHit(player, args)
    elseif command == "PurgeFireworks" then
        CSR_ServerCommands.handlePurgeFireworks(player, args)
    elseif command == "NoticeBoardWrite" then
        CSR_ServerCommands.handleNoticeBoardWrite(player, args)
    elseif command == "WhiteboardWrite" then
        CSR_ServerCommands.handleWhiteboardWrite(player, args)
    end
    end) -- end pcall
    if not ok then
        print("[CSR] ERROR in handler for " .. tostring(command) .. ": " .. tostring(err))
    end
end

Events.OnClientCommand.Add(onClientCommand)

-- ============================================================================
-- Zombie density: server-driven push.
-- One zombie scan per ZOMBIE_DENSITY_SERVER_PUSH_TICKS, then per-player grid
-- bucketing + broadcast. Replaces the old client-pull model so a busy MP server
-- with many players keeps a fixed scan budget instead of N requests/window.
-- ============================================================================
local _zdensityPushCounter = 0

local function pushZombieDensityToAllPlayers()
    if isClient() then return end
    if sandbox().EnableZombieDensityOverlay == false then return end
    local players = getOnlinePlayers and getOnlinePlayers() or nil
    if not players or players:size() == 0 then return end

    -- Trigger one shared scan via the existing handler path on the first player;
    -- subsequent per-player calls within the same ZOMBIE_SCAN_SHARE_MS window
    -- reuse _zombieScanCache for free.
    for i = 0, players:size() - 1 do
        local p = players:get(i)
        if p and p.getModData then
            local md = p:getModData()
            -- Player can opt out via client flag; reset SERVER_MIN_TICKS guard each push.
            if md and md.CSRZombieDensityOptIn ~= false then
                local key = markerKey(p)
                if zombieDensityRequests[key] then
                    zombieDensityRequests[key] = nil
                end
                CSR_ServerCommands.handleZombieDensityRequest(p, { requestSeq = 0 })
            end
        end
    end
end

local function onZombieDensityServerTick()
    _zdensityPushCounter = _zdensityPushCounter + 1
    local interval = CSR_Config.ZOMBIE_DENSITY_SERVER_PUSH_TICKS or 25
    if _zdensityPushCounter < interval then return end
    _zdensityPushCounter = 0
    local ok, err = pcall(pushZombieDensityToAllPlayers)
    if not ok then
        print("[CSR] zombie density push error: " .. tostring(err))
    end
end

if Events and Events.OnTick and not CSR_ServerCommands._zdensityTickRegistered then
    CSR_ServerCommands._zdensityTickRegistered = true
    Events.OnTick.Add(onZombieDensityServerTick)
end

return CSR_ServerCommands
