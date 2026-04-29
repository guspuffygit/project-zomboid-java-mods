require "CSR_FeatureFlags"

--[[
    CSR_PointBlank.lua
    Point-blank accuracy boost for firearms.
    When aiming a gun and a zombie is within ~2 tiles, massively boost hit chance.
    Common sense: you shouldn't miss a zombie that's right in your face.
]]

local POINT_BLANK_RANGE_SQ = 2.0 * 2.0
local HIT_BOOST = 85

local boostedWeapon = nil
local originalToHit = nil

local function restoreWeapon()
    if boostedWeapon and originalToHit ~= nil then
        pcall(function() boostedWeapon:setToHitModifier(originalToHit) end)
    end
    boostedWeapon = nil
    originalToHit = nil
end

local function hasZombieInRange(player)
    local px, py, pz = player:getX(), player:getY(), player:getZ()
    local cell = player:getCell()
    if not cell or not cell.getGridSquare then return false end
    -- Bounded grid-square scan over a 5x5 block (POINT_BLANK_RANGE = 2 tiles).
    -- Replaces full-cell object walk (50k+ objects/frame while aiming).
    local ix, iy = math.floor(px), math.floor(py)
    local r = 2
    for tx = ix - r, ix + r do
        for ty = iy - r, iy + r do
            local sq = cell:getGridSquare(tx, ty, pz)
            if sq then
                local sqObjects = sq:getObjects()
                if sqObjects then
                    for i = 0, sqObjects:size() - 1 do
                        local zombie = sqObjects:get(i)
                        if zombie and instanceof(zombie, "IsoZombie") and not zombie:isDead() then
                            local dx = zombie:getX() - px
                            local dy = zombie:getY() - py
                            if dx * dx + dy * dy <= POINT_BLANK_RANGE_SQ then
                                return true
                            end
                        end
                    end
                end
            end
        end
    end
    return false
end

local function onPlayerUpdate(player)
    if not CSR_FeatureFlags.isPointBlankEnabled() then
        restoreWeapon()
        return
    end

    local weapon = player:getPrimaryHandItem()

    -- Only for ranged weapons while aiming
    if not weapon or not weapon.isRanged or not weapon:isRanged() or not player:isAiming() then
        restoreWeapon()
        return
    end

    if hasZombieInRange(player) then
        if boostedWeapon ~= weapon then
            restoreWeapon()
            originalToHit = weapon:getToHitModifier()
            boostedWeapon = weapon
        end
        weapon:setToHitModifier(originalToHit + HIT_BOOST)
    else
        restoreWeapon()
    end
end

-- Bonus damage at point-blank range
local function onWeaponHitCharacter(attacker, target, weapon, damage)
    if not CSR_FeatureFlags.isPointBlankEnabled() then return end
    if not instanceof(attacker, "IsoPlayer") then return end
    if not weapon or not weapon.isRanged or not weapon:isRanged() then return end

    local dx = target:getX() - attacker:getX()
    local dy = target:getY() - attacker:getY()
    if dx * dx + dy * dy <= POINT_BLANK_RANGE_SQ then
        local health = target:getHealth()
        if health > 0 then
            target:setHealth(health - damage * 0.5)
        end
    end
end

if not _G.__CSR_PointBlank_evRegistered then
    _G.__CSR_PointBlank_evRegistered = true
    Events.OnPlayerUpdate.Add(onPlayerUpdate)
    Events.OnWeaponHitCharacter.Add(onWeaponHitCharacter)
end
