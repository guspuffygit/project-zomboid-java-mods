require "CSR_FeatureFlags"
require "Foraging/forageSystem"

--[[
    CSR_ConeVisionOutline.lua
    Highlights targets within the player's forward vision cone when aiming.
    Default: vibrant purple outline. Color configurable via sandbox options.
    Inspired by ConeVisionOutline (Workshop 3659137034).
]]

local lastHighlighted = {}
local PLAYER_NUM = 0
local CONE_HALF_ANGLE_COS = 0.5  -- cos(60°): 120° total cone
local RAW_PCALL = pcall

local function safePCall(fn, ...)
    if type(RAW_PCALL) == "function" then
        return RAW_PCALL(fn, ...)
    end
    -- Fallback when another mod overwrites global pcall
    fn(...)
    return true
end

-- Direction vectors for IsoDirections
local DIR_VECTORS = nil
local function buildDirVectors()
    if DIR_VECTORS then return end
    if not IsoDirections then return end
    DIR_VECTORS = {
        [IsoDirections.N]  = {  0,    -1    },
        [IsoDirections.S]  = {  0,     1    },
        [IsoDirections.E]  = {  1,     0    },
        [IsoDirections.W]  = { -1,     0    },
        [IsoDirections.NE] = {  0.707, -0.707 },
        [IsoDirections.SE] = {  0.707,  0.707 },
        [IsoDirections.NW] = { -0.707, -0.707 },
        [IsoDirections.SW] = { -0.707,  0.707 },
    }
end

local function isInVisionCone(character, dx, dy)
    if not character or not character.getDir then return false end
    buildDirVectors()
    local dir = character:getDir()
    if not dir or not DIR_VECTORS or not DIR_VECTORS[dir] then return false end
    local v = DIR_VECTORS[dir]
    local dot = dx * v[1] + dy * v[2]
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.01 then return true end
    return (dot / len) >= CONE_HALF_ANGLE_COS
end

local function clearOutline(obj)
    safePCall(function()
        if obj and obj.setOutlineHighlight then
            obj:setOutlineHighlight(PLAYER_NUM, false)
        end
    end)
end

local function clearAll()
    for obj, _ in pairs(lastHighlighted) do
        clearOutline(obj)
    end
    lastHighlighted = {}
end

local function getMaxRange()
    local sv = SandboxVars and SandboxVars.CommonSenseReborn
    if sv and sv.ConeVisionOutlineRange then
        return sv.ConeVisionOutlineRange
    end
    return 50
end

-- Outline color from sandbox options (default: vibrant purple)
local function getOutlineColor()
    local sv = SandboxVars and SandboxVars.CommonSenseReborn
    if not sv then return 0.7, 0.2, 1.0, 0.35 end
    local r = (sv.ConeVisionOutlineColorR or 178) / 255
    local g = (sv.ConeVisionOutlineColorG or 51) / 255
    local b = (sv.ConeVisionOutlineColorB or 255) / 255
    local a = (sv.ConeVisionOutlineAlpha or 35) / 100
    return r, g, b, a
end

local function isShortSightedWithoutGlasses(character)
    if not character:hasTrait(CharacterTrait.SHORT_SIGHTED) then
        return false
    end
    return forageSystem.doGlassesCheck(character, nil, "visionBonus")
end

local function isTarget(obj)
    return (instanceof(obj, "IsoZombie") and not obj:isDead())
        or (instanceof(obj, "IsoAnimal") and obj:isExistInTheWorld())
end

local function getObjSquare(obj)
    if obj.getCurrentSquare then
        return obj:getCurrentSquare()
    end
    if obj.getSquare then
        return obj:getSquare()
    end
    return nil
end

local function updateConeOutline()
    safePCall(function()
        if not CSR_FeatureFlags.isConeVisionOutlineEnabled() then
            clearAll()
            return
        end

        local character = getPlayer()
        if not character then
            clearAll()
            return
        end

        PLAYER_NUM = character:getPlayerNum()

        -- Only when aiming or looking while in vehicle
        local isLooking = character:isAiming() or character:isLookingWhileInVehicle()
        if not isLooking then
            clearAll()
            return
        end

        -- Respect the vanilla melee outline setting
        if not getCore():getOptionMeleeOutline() then
            clearAll()
            return
        end

        if isShortSightedWithoutGlasses(character) then
            clearAll()
            return
        end

        local cell = getCell()
        if not cell or not cell.getGridSquare then return end

        local maxRange = getMaxRange()
        local maxRangeSq = maxRange * maxRange
        local plX, plY, plZ = character:getX(), character:getY(), character:getZ()
        local cr, cg, cb, ca = getOutlineColor()

        -- Pre-compute forward cone vector for early reject (avoid per-object cone math)
        buildDirVectors()
        local dir = character:getDir()
        local dirVec = DIR_VECTORS and DIR_VECTORS[dir]

        local newHighlighted = {}

        -- Bounded grid-square scan (vs. walking the entire cell's object list of 50k+ objects).
        -- Mirrors the pattern used in CSR_ZombieDensityOverlay (v1.5.4 perf fix).
        local r = math.ceil(maxRange)
        local ix, iy = math.floor(plX), math.floor(plY)
        for tx = ix - r, ix + r do
            for ty = iy - r, iy + r do
                local dx = tx + 0.5 - plX
                local dy = ty + 0.5 - plY
                local distSq = dx * dx + dy * dy
                if distSq <= maxRangeSq then
                    -- Early cone reject on square center
                    local inCone = true
                    if dirVec then
                        local len = math.sqrt(distSq)
                        if len >= 0.5 then
                            if (dx * dirVec[1] + dy * dirVec[2]) / len < CONE_HALF_ANGLE_COS then
                                inCone = false
                            end
                        end
                    end
                    if inCone then
                        local sq = cell:getGridSquare(tx, ty, plZ)
                        if sq then
                            -- Zombies/animals live in getMovingObjects(), NOT getObjects().
                            -- getObjects() only contains static IsoObjects (terrain, world items, doors).
                            local movers = sq.getMovingObjects and sq:getMovingObjects() or nil
                            if movers then
                                local visible = nil
                                for oi = 0, movers:size() - 1 do
                                    local obj = movers:get(oi)
                                    if obj and isTarget(obj) then
                                        if visible == nil then
                                            visible = sq:isCanSee(PLAYER_NUM)
                                        end
                                        if visible then
                                            if obj.setOutlineHighlight then
                                                obj:setOutlineHighlight(PLAYER_NUM, true)
                                            end
                                            if obj.setOutlineHighlightCol then
                                                obj:setOutlineHighlightCol(PLAYER_NUM, cr, cg, cb, ca)
                                            end
                                            newHighlighted[obj] = true
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end

        -- Clear outlines for targets that left the cone
        for obj, _ in pairs(lastHighlighted) do
            if not newHighlighted[obj] then
                clearOutline(obj)
            end
        end

        lastHighlighted = newHighlighted
    end)
end

-- v1.8.7: gate event registration on the feature flag (Phoenix II).
-- When the feature is OFF the OnPlayerUpdate handler is never installed, so
-- there is no per-update cost on disabled installs. Re-checked at OnGameStart
-- so a sandbox flip on a server restart picks up correctly.
if not CSR_ConeVisionOutline then CSR_ConeVisionOutline = {} end
local function ensureConeRegistered()
    if CSR_ConeVisionOutline._registered then return end
    if not (CSR_FeatureFlags and CSR_FeatureFlags.isConeVisionOutlineEnabled
        and CSR_FeatureFlags.isConeVisionOutlineEnabled()) then return end
    CSR_ConeVisionOutline._registered = true
    Events.OnPlayerUpdate.Add(updateConeOutline)
    Events.OnPlayerDeath.Add(clearAll)
end
Events.OnGameStart.Add(ensureConeRegistered)
