require "CSR_FeatureFlags"

--[[
    CSR_BulletPenetration.lua
    Bullets that kill a zombie can continue through and damage zombies behind it.
    Auto-detects penetration capability from weapon stats (MaxRange, MaxDamage,
    ProjectileCount) so it works with any gun mod out of the box.
]]

-- Re-entry guard: prevents infinite recursion when penetration damage triggers
-- OnWeaponHitCharacter again
local IN_PENETRATION_HIT = false

-- Cache: weaponFullType → { canPenetrate, maxTargets, damageScale, maxDistance, lateralTolerance }
local profileCache = {}

---------------------------------------------------------------------------
-- Auto-detect penetration profile from weapon script properties
-- Heuristic based on vanilla weapon stat ranges:
--   Pistol 9mm:   MaxRange=15,  MaxDamage=1.0, Projectilecount=1
--   HuntingRifle:  MaxRange=40,  MaxDamage=2.0, Projectilecount=1
--   Shotgun:       MaxRange=12,  MaxDamage=2.2, Projectilecount=9
---------------------------------------------------------------------------
local function buildProfile(weapon)
    -- Shotguns: projectile spread, no penetration
    if weapon.getProjectileCount and weapon:getProjectileCount() and weapon:getProjectileCount() > 1 then
        return { canPenetrate = false }
    end

    local maxRange = weapon.getMaxRange and weapon:getMaxRange() or 0
    local maxDamage = weapon.getMaxDamage and weapon:getMaxDamage() or 0

    -- Short-range / low-power weapons don't penetrate
    if maxRange < 10 or maxDamage < 0.8 then
        return { canPenetrate = false }
    end

    local sb = SandboxVars.CommonSenseReborn or {}
    local globalScale = sb.BulletPenetrationDamageScale or 0.4
    local globalMax = sb.BulletPenetrationMaxTargets or 2

    -- High-power rifles (long range + high damage): more penetration
    if maxRange >= 25 and maxDamage >= 1.5 then
        return {
            canPenetrate = true,
            maxTargets = math.min(globalMax, 3),
            damageScale = globalScale,
            maxDistance = 6.0,
            lateralTolerance = 0.6,
        }
    end

    -- Standard firearms (pistols, carbines, SMGs)
    return {
        canPenetrate = true,
        maxTargets = math.min(globalMax, 2),
        damageScale = globalScale * 0.7,
        maxDistance = 4.0,
        lateralTolerance = 0.5,
    }
end

local function getProfile(weapon)
    if not weapon then return nil end
    local fullType = weapon.getFullType and weapon:getFullType()
    if not fullType then return nil end

    local cached = profileCache[fullType]
    if cached ~= nil then return cached end

    local profile = buildProfile(weapon)
    profileCache[fullType] = profile
    return profile
end

---------------------------------------------------------------------------
-- Collect zombie candidates behind the primary target along the bullet's
-- direction vector. Uses dot product (ahead check) and cross product
-- magnitude (lateral tolerance).
---------------------------------------------------------------------------
local function collectCandidates(attacker, target, profile)
    local cell = attacker:getCell()
    if not cell then return {} end

    local ax, ay = attacker:getX(), attacker:getY()
    local tx, ty = target:getX(), target:getY()

    -- Direction vector from attacker to primary target
    local dx = tx - ax
    local dy = ty - ay
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist < 0.01 then return {} end

    -- Normalize direction
    local ndx = dx / dist
    local ndy = dy / dist

    local candidates = {}
    -- B42.17: getZombieList() removed; use getObjectListForLua() + instanceof filter
    local allObjects = (cell.getObjectListForLua and cell:getObjectListForLua()) or (cell.getZombieList and cell:getZombieList())
    if not allObjects then return candidates end

    for i = 0, allObjects:size() - 1 do
        local z = allObjects:get(i)
        if z and instanceof(z, "IsoZombie") and z ~= target and not z:isDead() then
            -- Same floor check
            if math.abs(z:getZ() - attacker:getZ()) < 1 then
                local zx = z:getX() - ax
                local zy = z:getY() - ay

                -- Dot product: how far along the shot direction
                local dot = zx * ndx + zy * ndy

                -- Must be beyond the primary target
                if dot > dist and dot <= dist + profile.maxDistance then
                    -- Cross product magnitude: lateral distance from line
                    local cross = math.abs(zx * ndy - zy * ndx)

                    if cross <= profile.lateralTolerance then
                        table.insert(candidates, { zombie = z, distance = dot })
                    end
                end
            end
        end
    end

    -- Sort by distance (closest first)
    table.sort(candidates, function(a, b) return a.distance < b.distance end)
    return candidates
end

---------------------------------------------------------------------------
-- Apply penetration damage to zombies behind the primary target
---------------------------------------------------------------------------
local function applyPenetrationDamage(attacker, weapon, target, baseDamage, profile)
    local candidates = collectCandidates(attacker, target, profile)
    if #candidates == 0 then return end

    local sb = SandboxVars.CommonSenseReborn or {}
    local mode = sb.BulletPenetrationMode or 1 -- 1=kill_only, 2=non_lethal

    for idx = 1, math.min(#candidates, profile.maxTargets) do
        local entry = candidates[idx]
        local z = entry.zombie

        -- Damage falls off per penetration: baseDamage * scale / penetrationIndex
        local penDamage = baseDamage * profile.damageScale / idx

        local health = z:getHealth()
        if health <= 0 then break end

        -- kill_only mode: only penetrate if damage would be lethal
        if mode == 1 and penDamage < health then
            break
        end

        -- Apply damage via direct HP manipulation (safe, no Hit() call)
        IN_PENETRATION_HIT = true
        local hpAfter = health - penDamage
        z:setHealth(hpAfter)

        if hpAfter <= 0 then
            z:kill(attacker)
        end
        IN_PENETRATION_HIT = false
    end
end

---------------------------------------------------------------------------
-- Main event handler
---------------------------------------------------------------------------
local function onWeaponHitCharacter(attacker, target, weapon, damage)
    -- Skip re-entrant calls from our own damage application
    if IN_PENETRATION_HIT then return end

    if not CSR_FeatureFlags.isBulletPenetrationEnabled() then return end
    if not attacker or not target or not weapon then return end
    if not instanceof(attacker, "IsoPlayer") then return end
    if not instanceof(target, "IsoZombie") then return end
    if not weapon.isRanged or not weapon:isRanged() then return end

    local profile = getProfile(weapon)
    if not profile or not profile.canPenetrate then return end

    -- Only penetrate if the primary target was killed by this hit
    local sb = SandboxVars.CommonSenseReborn or {}
    local mode = sb.BulletPenetrationMode or 1

    if mode == 1 then
        -- kill_only: only trigger penetration on lethal hits
        if target:getHealth() > 0 then return end
    else
        -- non_lethal: trigger on any hit above a damage threshold
        if damage < 0.3 then return end
    end

    local ok, err = pcall(applyPenetrationDamage, attacker, weapon, target, damage, profile)
    if not ok then
        print("[CSR] BulletPenetration error: " .. tostring(err))
    end
end

if not _G.__CSR_BulletPenetration_evRegistered then
    _G.__CSR_BulletPenetration_evRegistered = true
    Events.OnWeaponHitCharacter.Add(onWeaponHitCharacter)
end
