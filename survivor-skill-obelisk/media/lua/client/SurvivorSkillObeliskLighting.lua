--
-- SurvivorSkillObeliskLighting.lua
-- Attach a permanent IsoLightSource to every placed obelisk via
-- IsoCell:addLamppost, which constructs an unpowered light (hydroPowered=false)
-- that is never gated by ItemContainer.isObjectPowered. This avoids the
-- generator requirement that LightR/LightG/LightB sprite properties would
-- otherwise trigger through IsoObject.addLightSourceToWorld.
--

local SPRITE_PREFIX = "survivor_skill_obelisk_"

-- Warm gold glow, ~6 tile radius. Floats are 0..1.
local GLOW_R = 1.00
local GLOW_G = 0.75
local GLOW_B = 0.35
local GLOW_RADIUS = 6

-- Keyed by "x,y,z" -> IsoLightSource. Dedupes against chunk-reload double-fires
-- and against the OnObjectAdded + LoadGridsquare both firing for a fresh place.
local lights = {}

local function keyOf(x, y, z)
    return x .. "," .. y .. "," .. z
end

local function isObeliskObject(obj)
    if obj == nil then
        return false
    end
    local sprite = obj:getSprite()
    if sprite == nil then
        return false
    end
    local name = sprite:getName()
    if name == nil then
        return false
    end
    return string.sub(name, 1, #SPRITE_PREFIX) == SPRITE_PREFIX
end

local function squareHasObelisk(square)
    -- IsoGridSquare:getObjects() returns PZArrayList; indexed get(i) is the
    -- only safe traversal (iterator()/listIterator() throw).
    local objects = square:getObjects()
    if objects == nil then
        return false
    end
    for i = 0, objects:size() - 1 do
        if isObeliskObject(objects:get(i)) then
            return true
        end
    end
    return false
end

local function lightSquare(x, y, z)
    local cell = getCell()
    if cell == nil then
        return
    end
    local k = keyOf(x, y, z)
    if lights[k] ~= nil then
        return
    end
    lights[k] = cell:addLamppost(x, y, z, GLOW_R, GLOW_G, GLOW_B, GLOW_RADIUS)
end

local function unlightSquare(x, y, z)
    local cell = getCell()
    if cell == nil then
        return
    end
    local k = keyOf(x, y, z)
    local light = lights[k]
    if light == nil then
        return
    end
    cell:removeLamppost(light)
    lights[k] = nil
end

local function onLoadGridsquare(square)
    if square == nil then
        return
    end
    if squareHasObelisk(square) then
        lightSquare(square:getX(), square:getY(), square:getZ())
    end
end

local function onObjectAdded(obj)
    if not isObeliskObject(obj) then
        return
    end
    local square = obj:getSquare()
    if square == nil then
        return
    end
    lightSquare(square:getX(), square:getY(), square:getZ())
end

local function onObjectAboutToBeRemoved(obj)
    if not isObeliskObject(obj) then
        return
    end
    local square = obj:getSquare()
    if square == nil then
        return
    end
    unlightSquare(square:getX(), square:getY(), square:getZ())
end

Events.LoadGridsquare.Add(onLoadGridsquare)
Events.OnObjectAdded.Add(onObjectAdded)
Events.OnObjectAboutToBeRemoved.Add(onObjectAboutToBeRemoved)
