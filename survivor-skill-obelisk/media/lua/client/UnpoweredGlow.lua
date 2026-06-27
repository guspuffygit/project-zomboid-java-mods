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
-- Usage:
--     require "UnpoweredGlow"
--     UnpoweredGlow.register({
--         spritePrefix = "survivor_skill_obelisk_",
--         r = 1.0, g = 0.75, b = 0.35,
--         radius = 6,
--     })
--
-- Custom matcher instead of a prefix:
--     UnpoweredGlow.register({
--         match = function(spriteName) return spriteName == "weird_lantern_07" end,
--         r = 0.3, g = 0.9, b = 1.0, radius = 4,
--     })
--

UnpoweredGlow = UnpoweredGlow or {}

local configs = {}
local hooksInstalled = false

local function keyOf(x, y, z)
    return x .. "," .. y .. "," .. z
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

local function matchersFor(spriteName)
    if spriteName == nil then
        return nil
    end
    local matched = nil
    for i = 1, #configs do
        local cfg = configs[i]
        if cfg.match(spriteName) then
            matched = matched or {}
            matched[#matched + 1] = cfg
        end
    end
    return matched
end

local function squareHasMatch(square, cfg)
    -- IsoGridSquare:getObjects() returns PZArrayList; indexed get(i) is the
    -- only safe traversal (iterator()/listIterator() throw).
    local objects = square:getObjects()
    if objects == nil then
        return false
    end
    for i = 0, objects:size() - 1 do
        local name = spriteNameOf(objects:get(i))
        if name ~= nil and cfg.match(name) then
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
    if cfg.lights[k] ~= nil then
        return
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
    if square == nil then
        return
    end
    local x, y, z = square:getX(), square:getY(), square:getZ()
    for i = 1, #configs do
        local cfg = configs[i]
        if squareHasMatch(square, cfg) then
            lightSquare(cfg, x, y, z)
        end
    end
end

local function onObjectAdded(obj)
    local matched = matchersFor(spriteNameOf(obj))
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
    local matched = matchersFor(spriteNameOf(obj))
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
    if hooksInstalled then
        return
    end
    Events.LoadGridsquare.Add(onLoadGridsquare)
    Events.OnObjectAdded.Add(onObjectAdded)
    Events.OnObjectAboutToBeRemoved.Add(onObjectAboutToBeRemoved)
    hooksInstalled = true
end

local function buildMatch(config)
    if config.match ~= nil then
        assert(
            type(config.match) == "function",
            "UnpoweredGlow.register: 'match' must be a function"
        )
        return config.match
    end
    local prefix = config.spritePrefix
    assert(
        type(prefix) == "string" and #prefix > 0,
        "UnpoweredGlow.register: provide 'spritePrefix' (string) or 'match' (function)"
    )
    local len = #prefix
    return function(name)
        return name ~= nil and string.sub(name, 1, len) == prefix
    end
end

function UnpoweredGlow.register(config)
    assert(type(config) == "table", "UnpoweredGlow.register: config must be a table")
    local entry = {
        match = buildMatch(config),
        r = config.r or 1.0,
        g = config.g or 1.0,
        b = config.b or 1.0,
        radius = config.radius or 6,
        lights = {},
    }
    configs[#configs + 1] = entry
    installHooks()
    return entry
end

return UnpoweredGlow
