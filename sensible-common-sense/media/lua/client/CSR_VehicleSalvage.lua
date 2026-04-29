require "CSR_FeatureFlags"

--[[
    CSR_VehicleSalvage.lua
    Adds "Salvage Vehicle" context menu option to right-clicking vehicles.
    Salvaging requires a blowtorch + welding mask, Mechanics >= 3, MetalWelding >= 3.
    The vehicle is destroyed after salvaging and materials drop on the ground.
    Higher MetalWelding = more loot rolls + better odds per roll.
    Sandbox-togglable via EnableVehicleSalvage.
]]

CSR_VehicleSalvage = CSR_VehicleSalvage or {}

-- Vanilla-matching predicates (same pattern as ISVehicleMenu.lua)
local function predicateWeldingMask(item)
    return (ItemTag and ItemTag.WELDING_MASK and item:hasTag(ItemTag.WELDING_MASK)) or item:getType() == "WeldingMask"
end

local function comparatorDrainableUsesInt(item1, item2)
    return item1:getCurrentUses() - item2:getCurrentUses()
end

local function hasBlowTorch(player, minUses)
    local inv = player:getInventory()
    if not inv then return nil end
    local torch = inv:getBestTypeEvalRecurse("Base.BlowTorch", comparatorDrainableUsesInt)
    if torch and torch:getCurrentUses() >= minUses then
        return torch
    end
    return nil
end

local function hasWeldingMask(player)
    local inv = player:getInventory()
    if not inv then return false, nil end
    local mask = inv:getFirstEvalRecurse(predicateWeldingMask)
    if mask then return true, mask end
    return false, nil
end

local TORCH_USES = 1

local function onVehicleSalvage(worldobjects, player, vehicle)
    if not player or not vehicle then return end

    local torch = hasBlowTorch(player, TORCH_USES)
    if not torch then return end

    local hasMask, maskItem = hasWeldingMask(player)
    if not hasMask then return end

    -- Walk to vehicle
    local sq = vehicle:getSquare()
    if sq then
        luautils.walkAdj(player, sq, true)
    end

    -- Equip torch
    if torch then
        ISTimedActionQueue.add(ISEquipWeaponAction:new(player, torch, 50, true))
    end

    -- Wear mask if not worn
    if maskItem and not player:isEquippedClothing(maskItem) then
        ISTimedActionQueue.add(ISWearClothing:new(player, maskItem, 50))
    end

    -- Queue salvage action
    ISTimedActionQueue.add(CSR_ISVehicleSalvage:new(player, vehicle, torch))
end

local function patchVehicleMenu()
    if not ISVehicleMenu or ISVehicleMenu.__csr_salvage_patched then return end
    ISVehicleMenu.__csr_salvage_patched = true

    local origFill = ISVehicleMenu.FillMenuOutsideVehicle
    function ISVehicleMenu.FillMenuOutsideVehicle(player, context, vehicle, test)
        if origFill then origFill(player, context, vehicle, test) end

        if test or not CSR_FeatureFlags.isVehicleSalvageEnabled() then return end

        local playerObj = getSpecificPlayer(player)
        if not playerObj or not vehicle then return end

        -- Skip burnt vehicles
        if vehicle.isBurnt and vehicle:isBurnt() then return end

        local mechLvl = playerObj:getPerkLevel(Perks.Mechanics)
        local weldLvl = playerObj:getPerkLevel(Perks.MetalWelding)
        local torch = hasBlowTorch(playerObj, TORCH_USES)
        local hasMask, _ = hasWeldingMask(playerObj)

        local option = context:addOption("Salvage Vehicle", worldobjects, onVehicleSalvage, playerObj, vehicle)
        option.iconTexture = getTexture("Item_BlowTorch")

        -- Tooltip
        local tooltip = ISToolTip:new()
        tooltip:initialise()
        tooltip:setVisible(false)

        local lines = {}
        table.insert(lines, "Strip a vehicle for usable scrap materials.")
        table.insert(lines, "Higher Metal Welding = more & better materials.")
        table.insert(lines, " ")
        table.insert(lines, "Requirements:")

        if not torch then
            table.insert(lines, " <RGB:1,0,0> - Propane Torch (" .. TORCH_USES .. " uses)")
            option.notAvailable = true
        else
            table.insert(lines, " <RGB:1,1,1> - Propane Torch (" .. TORCH_USES .. " uses)")
        end

        if not hasMask then
            table.insert(lines, " <RGB:1,0,0> - Welding Mask (worn or inventory)")
            option.notAvailable = true
        else
            table.insert(lines, " <RGB:1,1,1> - Welding Mask (worn or inventory)")
        end

        if mechLvl < 1 then
            table.insert(lines, " <RGB:1,0,0> - Mechanics 1+ (current: " .. mechLvl .. ")")
            option.notAvailable = true
        else
            table.insert(lines, " <RGB:1,1,1> - Mechanics 1+ (current: " .. mechLvl .. ")")
        end

        if weldLvl < 1 then
            table.insert(lines, " <RGB:1,0,0> - Metal Welding 1+ (current: " .. weldLvl .. ")")
            option.notAvailable = true
        else
            table.insert(lines, " <RGB:1,1,1> - Metal Welding 1+ (current: " .. weldLvl .. ")")
        end

        table.insert(lines, " ")
        table.insert(lines, " <RGB:0.7,0.7,0.7> The vehicle will be permanently destroyed.")

        tooltip.description = table.concat(lines, " <LINE>")
        option.toolTip = tooltip
    end
end

if Events and Events.OnGameStart then
    Events.OnGameStart.Add(patchVehicleMenu)
end

return CSR_VehicleSalvage
