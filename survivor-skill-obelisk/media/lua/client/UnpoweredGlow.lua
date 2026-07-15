--
-- UnpoweredGlow.lua
-- Generic "make-this-sprite-glow-without-a-generator" client library.
--
-- Register a glow config with UnpoweredGlow.register{...}; on every grid load,
-- object-add, and object-remove this module walks the relevant square's objects
-- and attaches/detaches an IsoLightSource via IsoCell:addLamppost. addLamppost
-- builds an unpowered light (hydroPowered=false) that ItemContainer.isObjectPowered
-- never gates, which avoids the generator requirement that LightR/LightG/LightB
-- sprite properties would otherwise trigger through IsoObject.addLightSourceToWorld.
--
-- Each registered config keeps its own per-square dedup table, so the same square
-- can host glows from multiple configs without them clobbering each other.
--
-- LoadGridsquare fires for every square that streams in, so onLoadGridsquare is
-- a hot path: it must walk a square's objects exactly once and resolve each
-- sprite name against all configs together, never once per config. register()
-- maintains a three-tier match index to make that possible:
--   * exactIndex: sprite name -> configs (from `sprites` lists)
--   * prefixGroups: one entry per distinct spritePrefix, so N configs sharing a
--     prefix cost one string compare
--   * funcConfigs: custom `match` functions — the slow tier, called once per
--     sprite name. Prefer `sprites` or `spritePrefix` whenever the names are
--     known up front.
--
-- Survives `reload`: two paths, depending on which file you actually reloaded.
--   * Full reload (this file re-executes): prior-load state is stashed on the
--     global UnpoweredGlow table (Events listeners and IsoLightSource objects
--     both outlive a Lua reload). On re-execution we remove the old listeners,
--     drop the old lights from the cell, then re-light the same positions with
--     the new configs on the next OnTick.
--   * Partial reload (only the config file re-executes): the second
--     UnpoweredGlow.register call with the same `name` (defaulting to the
--     `spritePrefix`) replaces the old entry in place, drops its lights, and
--     re-lights at those positions with the new color/radius immediately.
-- Either way you can edit r/g/b/radius in a config file, `reload`, and see the
-- new color on every currently-loaded obelisk on the next tick.
--
-- Usage:
--     require "UnpoweredGlow"
--     UnpoweredGlow.register({
--         spritePrefix = "after_the_fall_economy_",
--         r = 1.0, g = 0.75, b = 0.35,
--         radius = 6,
--     })
--
-- Exact sprite names (fastest — hash lookup per streamed object):
--     UnpoweredGlow.register({
--         name = "weird_lanterns",
--         sprites = { "weird_lantern_07", "weird_lantern_08" },
--         r = 0.3, g = 0.9, b = 1.0, radius = 4,
--     })
--
-- Custom matcher (slowest — runs for every streamed sprite name; use only when
-- the names aren't enumerable):
--     UnpoweredGlow.register({
--         name = "weird_lanterns",
--         match = function(spriteName) return spriteName == "weird_lantern_07" end,
--         r = 0.3, g = 0.9, b = 1.0, radius = 4,
--     })
--

UnpoweredGlow = UnpoweredGlow or {}

local function uninstallHooks(state)
    if state == nil or state.hooks == nil then
        return
    end
    if state.hooks.onLoadGridsquare ~= nil then
        Events.LoadGridsquare.Remove(state.hooks.onLoadGridsquare)
    end
    if state.hooks.onObjectAdded ~= nil then
        Events.OnObjectAdded.Remove(state.hooks.onObjectAdded)
    end
    if state.hooks.onObjectAboutToBeRemoved ~= nil then
        Events.OnObjectAboutToBeRemoved.Remove(state.hooks.onObjectAboutToBeRemoved)
    end
end

-- Snapshot of prior-load state (nil on first load). Captured before we replace
-- _state so the cleanup pass on next-tick has somewhere to read the old lights
-- and listener fns from.
local previousState = UnpoweredGlow._state
uninstallHooks(previousState)

local configs = {}
local hooks = {}
UnpoweredGlow._state = { configs = configs, hooks = hooks }

-- Match index (see header). Rebuilt from `configs` on every register() so the
-- hot path never iterates configs directly.
local exactIndex = {}
local prefixGroups = {}
local funcConfigs = {}

local function rebuildMatchIndex()
    exactIndex = {}
    prefixGroups = {}
    funcConfigs = {}
    local groupsByPrefix = {}
    for i = 1, #configs do
        local cfg = configs[i]
        if cfg.sprites ~= nil then
            for j = 1, #cfg.sprites do
                local spriteName = cfg.sprites[j]
                local list = exactIndex[spriteName]
                if list == nil then
                    list = {}
                    exactIndex[spriteName] = list
                end
                list[#list + 1] = cfg
            end
        elseif cfg.spritePrefix ~= nil then
            local group = groupsByPrefix[cfg.spritePrefix]
            if group == nil then
                group = { prefix = cfg.spritePrefix, len = #cfg.spritePrefix, configs = {} }
                groupsByPrefix[cfg.spritePrefix] = group
                prefixGroups[#prefixGroups + 1] = group
            end
            group.configs[#group.configs + 1] = cfg
        else
            funcConfigs[#funcConfigs + 1] = cfg
        end
    end
end

local function keyOf(x, y, z)
    return x .. "," .. y .. "," .. z
end

local function parseKey(k)
    local sx, sy, sz = string.match(k, "^(%-?%d+),(%-?%d+),(%-?%d+)$")
    if sx == nil then
        return nil
    end
    return tonumber(sx), tonumber(sy), tonumber(sz)
end

local function spriteNameOf(obj)
    if obj == nil then
        return nil
    end
    local sprite = obj:getSprite()
    if sprite == nil then
        return nil
    end
    return sprite:getName()
end

-- Returns an array of every config matching `name`, or nil. Allocates only on
-- a hit; misses (the overwhelming majority of streamed sprites) cost one hash
-- lookup plus one prefix compare per distinct prefix.
local function matchConfigsFor(name)
    if name == nil then
        return nil
    end
    local matched = nil
    local exact = exactIndex[name]
    if exact ~= nil then
        matched = {}
        for i = 1, #exact do
            matched[#matched + 1] = exact[i]
        end
    end
    for i = 1, #prefixGroups do
        local group = prefixGroups[i]
        if string.sub(name, 1, group.len) == group.prefix then
            matched = matched or {}
            local groupConfigs = group.configs
            for j = 1, #groupConfigs do
                matched[#matched + 1] = groupConfigs[j]
            end
        end
    end
    for i = 1, #funcConfigs do
        local cfg = funcConfigs[i]
        if cfg.match(name) then
            matched = matched or {}
            matched[#matched + 1] = cfg
        end
    end
    return matched
end

-- Single-config predicate for the rare paths (reload cleanup, register-replace
-- relight). The hot streaming path goes through matchConfigsFor instead.
local function configMatchesName(cfg, name)
    if name == nil then
        return false
    end
    if cfg.sprites ~= nil then
        for i = 1, #cfg.sprites do
            if cfg.sprites[i] == name then
                return true
            end
        end
        return false
    end
    if cfg.spritePrefix ~= nil then
        return string.sub(name, 1, #cfg.spritePrefix) == cfg.spritePrefix
    end
    return cfg.match(name)
end

local function squareHasMatch(square, cfg)
    -- IsoGridSquare:getObjects() returns PZArrayList; indexed get(i) is the
    -- only safe traversal (iterator()/listIterator() throw).
    local objects = square:getObjects()
    if objects == nil then
        return false
    end
    for i = 0, objects:size() - 1 do
        if configMatchesName(cfg, spriteNameOf(objects:get(i))) then
            return true
        end
    end
    return false
end

local function lightSquare(cfg, x, y, z)
    local cell = getCell()
    if cell == nil then
        return
    end
    local k = keyOf(x, y, z)
    local tracked = cfg.lights[k]
    if tracked ~= nil then
        -- LightingJNI.checkLights drops any light whose position falls outside
        -- every player's chunk-map bounds — so when chunks stream out, the game
        -- removes our light from lamppostPositions but our tracked handle here
        -- survives. A plain nil-check would then skip re-adding on the next
        -- LoadGridsquare and leave the sprite dark forever. Verify the handle
        -- is still in the list; if not, treat as unlit and fall through.
        local list = cell:getLamppostPositions()
        for i = 0, list:size() - 1 do
            if list:get(i) == tracked then
                return
            end
        end
        cfg.lights[k] = nil
    end
    cfg.lights[k] = cell:addLamppost(x, y, z, cfg.r, cfg.g, cfg.b, cfg.radius)
end

local function unlightSquare(cfg, x, y, z)
    local cell = getCell()
    if cell == nil then
        return
    end
    local k = keyOf(x, y, z)
    local light = cfg.lights[k]
    if light == nil then
        return
    end
    cell:removeLamppost(light)
    cfg.lights[k] = nil
end

local function onLoadGridsquare(square)
    if square == nil or #configs == 0 then
        return
    end
    local objects = square:getObjects()
    if objects == nil then
        return
    end
    -- x/y/z resolved lazily: most streamed squares match nothing, and the
    -- three Java getters would otherwise run for every one of them.
    local x, y, z
    for i = 0, objects:size() - 1 do
        local matched = matchConfigsFor(spriteNameOf(objects:get(i)))
        if matched ~= nil then
            if x == nil then
                x, y, z = square:getX(), square:getY(), square:getZ()
            end
            for j = 1, #matched do
                lightSquare(matched[j], x, y, z)
            end
        end
    end
end

local function onObjectAdded(obj)
    local matched = matchConfigsFor(spriteNameOf(obj))
    if matched == nil then
        return
    end
    local square = obj:getSquare()
    if square == nil then
        return
    end
    local x, y, z = square:getX(), square:getY(), square:getZ()
    for i = 1, #matched do
        lightSquare(matched[i], x, y, z)
    end
end

local function onObjectAboutToBeRemoved(obj)
    local matched = matchConfigsFor(spriteNameOf(obj))
    if matched == nil then
        return
    end
    local square = obj:getSquare()
    if square == nil then
        return
    end
    local x, y, z = square:getX(), square:getY(), square:getZ()
    for i = 1, #matched do
        unlightSquare(matched[i], x, y, z)
    end
end

local function installHooks()
    if hooks.onLoadGridsquare ~= nil then
        return
    end
    hooks.onLoadGridsquare = onLoadGridsquare
    hooks.onObjectAdded = onObjectAdded
    hooks.onObjectAboutToBeRemoved = onObjectAboutToBeRemoved
    Events.LoadGridsquare.Add(onLoadGridsquare)
    Events.OnObjectAdded.Add(onObjectAdded)
    Events.OnObjectAboutToBeRemoved.Add(onObjectAboutToBeRemoved)
end

-- One-shot post-reload cleanup: drop the prior load's IsoLightSource objects and
-- re-light their positions with whatever's currently registered. Deferred to
-- OnTick so every register() call from any reloaded file has had a chance to run.
local function refreshAfterReload()
    Events.OnTick.Remove(refreshAfterReload)
    if previousState == nil then
        return
    end
    local cell = getCell()
    if cell == nil then
        previousState = nil
        return
    end
    local positions = {}
    local seen = {}
    if previousState.configs ~= nil then
        for i = 1, #previousState.configs do
            local oldCfg = previousState.configs[i]
            if oldCfg.lights ~= nil then
                for k, oldLight in pairs(oldCfg.lights) do
                    cell:removeLamppost(oldLight)
                    if not seen[k] then
                        seen[k] = true
                        local x, y, z = parseKey(k)
                        if x ~= nil then
                            positions[#positions + 1] = { x, y, z }
                        end
                    end
                end
            end
        end
    end
    previousState = nil
    for i = 1, #positions do
        local pos = positions[i]
        local square = cell:getGridSquare(pos[1], pos[2], pos[3])
        -- Chunk may have unloaded; if so LoadGridsquare will re-light on reload.
        if square ~= nil then
            for j = 1, #configs do
                local cfg = configs[j]
                if squareHasMatch(square, cfg) then
                    lightSquare(cfg, pos[1], pos[2], pos[3])
                end
            end
        end
    end
end

if previousState ~= nil then
    Events.OnTick.Add(refreshAfterReload)
end

local function validateMatcher(config)
    if config.sprites ~= nil then
        assert(
            type(config.sprites) == "table" and #config.sprites > 0,
            "UnpoweredGlow.register: 'sprites' must be a non-empty array of sprite names"
        )
        for i = 1, #config.sprites do
            assert(
                type(config.sprites[i]) == "string",
                "UnpoweredGlow.register: 'sprites' entries must be strings"
            )
        end
        return
    end
    if config.spritePrefix ~= nil then
        assert(
            type(config.spritePrefix) == "string" and #config.spritePrefix > 0,
            "UnpoweredGlow.register: 'spritePrefix' must be a non-empty string"
        )
        return
    end
    assert(
        type(config.match) == "function",
        "UnpoweredGlow.register: provide 'sprites' (array), 'spritePrefix' (string),"
            .. " or 'match' (function)"
    )
end

-- Drops every IsoLightSource we tracked for `oldEntry` from the cell and
-- returns the (x,y,z) tuples they sat at, so the caller can decide what to
-- light there with a replacement config.
local function dropLightsAndCollectPositions(oldEntry, cell)
    local positions = {}
    if oldEntry == nil or oldEntry.lights == nil then
        return positions
    end
    for k, light in pairs(oldEntry.lights) do
        if cell ~= nil then
            cell:removeLamppost(light)
        end
        local x, y, z = parseKey(k)
        if x ~= nil then
            positions[#positions + 1] = { x, y, z }
        end
    end
    return positions
end

function UnpoweredGlow.register(config)
    assert(type(config) == "table", "UnpoweredGlow.register: config must be a table")
    validateMatcher(config)
    -- The identity used to dedupe across reloads. Defaults to spritePrefix so
    -- the common case is reload-safe out of the box; sprites/custom-matcher
    -- configs must pass an explicit `name` to opt into replace-on-reregister.
    local name = config.name or config.spritePrefix
    assert(
        type(name) == "string" and #name > 0,
        "UnpoweredGlow.register: provide 'name' (string) or 'spritePrefix' (string) so"
            .. " reload-replace can identify this registration"
    )
    local entry = {
        name = name,
        sprites = config.sprites,
        spritePrefix = config.spritePrefix,
        match = config.match,
        r = config.r or 1.0,
        g = config.g or 1.0,
        b = config.b or 1.0,
        radius = config.radius or 6,
        lights = {},
    }
    for i = 1, #configs do
        if configs[i].name == name then
            -- Reload-replace path: only the config file was re-executed, so the
            -- old entry is still here with its tracked lights. Drop them and
            -- relight the same positions with the new color/radius right now.
            local cell = getCell()
            local positions = dropLightsAndCollectPositions(configs[i], cell)
            configs[i] = entry
            rebuildMatchIndex()
            installHooks()
            if cell ~= nil then
                for j = 1, #positions do
                    local pos = positions[j]
                    local square = cell:getGridSquare(pos[1], pos[2], pos[3])
                    if square ~= nil and squareHasMatch(square, entry) then
                        lightSquare(entry, pos[1], pos[2], pos[3])
                    end
                end
            end
            return entry
        end
    end
    configs[#configs + 1] = entry
    rebuildMatchIndex()
    installHooks()
    return entry
end

return UnpoweredGlow
