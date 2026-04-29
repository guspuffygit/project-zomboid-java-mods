local function initMode(mode)
    mode.SCRIPTITEM = getScriptManager():getItem(mode.SCRIPTITEMNAME)
    mode.ITEM = instanceItem(mode.SCRIPTITEMNAME)
end

initMode(CSR_DualWield.UnarmedMode)
initMode(CSR_DualWield.ShoveMode)

local CSR_DualWieldUtils = {}

function CSR_DualWieldUtils.getZombieID(zombie)
    if isClient() or isServer() then
        return zombie:getOnlineID()
    end
    return zombie:getID()
end

function CSR_DualWieldUtils.getZombieFromID(referencePlayer, zombieID)
    local square = referencePlayer:getSquare()
    if not square then return nil end
    local cell = square:getCell()
    if not cell then return nil end
    -- B42.17: getZombieList() removed; use getObjectListForLua() + instanceof filter
    local allObjects = (cell.getObjectListForLua and cell:getObjectListForLua()) or (cell.getZombieList and cell:getZombieList())
    if not allObjects then return nil end
    for i = 0, allObjects:size() - 1 do
        local zombie = allObjects:get(i)
        if zombie and instanceof(zombie, "IsoZombie") then
            if (isClient() or isServer()) then
                if zombie:getOnlineID() == zombieID then return zombie end
            elseif zombie:getID() == zombieID then
                return zombie
            end
        end
    end
    return nil
end

function CSR_DualWieldUtils.getPlayerID(player)
    if isClient() or isServer() then
        return player:getOnlineID()
    end
    return player:getIndex()
end

function CSR_DualWieldUtils.getPlayerFromID(playerID)
    if isClient() or isServer() then
        return getPlayerByOnlineID(playerID)
    end
    if playerID < getNumActivePlayers() then
        return getSpecificPlayer(playerID)
    end
    return nil
end

function CSR_DualWieldUtils.foreachPlayerDo(func)
    if isServer() then
        local players = getOnlinePlayers()
        if not players then return end
        for i = 0, players:size() - 1 do
            if func(players:get(i)) then return end
        end
    else
        for i = 0, getNumActivePlayers() - 1 do
            if func(getSpecificPlayer(i)) then return end
        end
    end
end

function CSR_DualWieldUtils.getCharacterID(character)
    if instanceof(character, "IsoPlayer") then
        return CSR_DualWieldUtils.getPlayerID(character)
    end
    return CSR_DualWieldUtils.getZombieID(character)
end

function CSR_DualWieldUtils.changeWeaponStats(handWeapon, valueSource, valueSourceScript)
    if not valueSource or not valueSourceScript then return end
    handWeapon:setCriticalChance(valueSource:getCriticalChance())
    handWeapon:setCriticalDamageMultiplier(valueSource:getCriticalDamageMultiplier())
    handWeapon:setDamageCategory(valueSource:getDamageCategory())
    handWeapon:setDamageMakeHole(valueSource:isDamageMakeHole())
    handWeapon:setDoorDamage(valueSource:getDoorDamage())
    handWeapon:setDoorHitSound(valueSource:getDoorHitSound())
    handWeapon:setEnduranceMod(valueSource:getEnduranceMod())
    handWeapon:setHitChance(valueSource:getHitChance())
    handWeapon:setImpactSound(valueSource:getImpactSound())
    handWeapon:setKnockdownMod(valueSource:getKnockdownMod())
    handWeapon:setMaxDamage(valueSource:getMaxDamage())
    handWeapon:setMaxHitCount(valueSource:getMaxHitCount())
    handWeapon:setMaxRange(valueSource:getMaxRange())
    handWeapon:setMinDamage(valueSource:getMinDamage())
    handWeapon:setPushBackMod(valueSource:getPushBackMod())
    handWeapon:setSplatBloodOnNoDeath(valueSource:isSplatBloodOnNoDeath())
    handWeapon:setSplatNumber(valueSource:getSplatNumber())
    handWeapon:setSwingSound(valueSource:getSwingSound())
    handWeapon:setToHitModifier(valueSource:getToHitModifier())
    handWeapon:setWeaponCategories(valueSourceScript:getWeaponCategories())
    handWeapon:setZombieHitSound(valueSource:getZombieHitSound())
    handWeapon:setHitFloorSound(valueSource:getHitFloorSound())
end

function CSR_DualWieldUtils.getUnarmedMode(player)
    if player:isDoShove() and not player:isDoStomp() then
        return CSR_DualWield.ShoveMode
    end
    return CSR_DualWield.UnarmedMode
end

function CSR_DualWieldUtils.getArmedMode(player)
    return CSR_DualWield.ArmedMode
end

function CSR_DualWieldUtils.isNonDefaultUnarmedAttack(attacker, target, onServer)
    if not instanceof(attacker, "IsoPlayer") then
        return false, nil
    end
    if not onServer and not attacker:isDoShove() then
        return false, nil
    end
    if not onServer and attacker:isDoStomp() then
        return false, nil
    end
    local mode = CSR_DualWieldUtils.getUnarmedMode(attacker)
    if not onServer and not mode.ALLOWATTACKFLOOR and target:isProne() then
        return false, nil
    end
    return true, mode
end

function CSR_DualWieldUtils.checkIfValidLeftHandAttack(player, onServer)
    if player:isDoShove() then
        return nil
    end
    if player:isDoStomp() then
        return nil
    end
    -- Don't trigger left-hand attack if primary weapon is a firearm
    local primaryWeapon = player:getPrimaryHandItem()
    if primaryWeapon and primaryWeapon.isRanged and primaryWeapon:isRanged() then
        return nil
    end
    -- v1.8.6: don't trigger left-hand follow-up while primary is a stab
    -- weapon (spear, etc.). The vanilla stab animation does not release
    -- in time for our setActionAnim("LeftHandPunch") + setMeleeDelay
    -- override, leaving the character locked in the stab pose ("stuck
    -- in stab animation" reports). Skipping the follow-up entirely is
    -- the safest fix and matches user expectation that spears are a
    -- two-handed combat style anyway.
    if primaryWeapon and primaryWeapon.getSwingAnim
            and primaryWeapon:getSwingAnim() == "Stab" then
        return nil
    end
    local secondWeapon = player:getSecondaryHandItem()
    local mode = nil
    local weapon = nil
    local xpPerk = nil

    if secondWeapon then
        if not secondWeapon:IsWeapon() or secondWeapon:isBroken()
            or secondWeapon:isRequiresEquippedBothHands()
            or (secondWeapon:isTwoHandWeapon() and player:isItemInBothHands(secondWeapon)) then
            return nil
        end
        mode = CSR_DualWieldUtils.getArmedMode(player)
        weapon = secondWeapon
        xpPerk = weapon:getPerk()
    else
        mode = CSR_DualWieldUtils.getUnarmedMode(player)
        weapon = mode.ITEM
    end

    if not mode.TRIGGERLEFTHANDATTACK then
        return nil
    end

    if not onServer and not CSR_LeftHandAttackAction.anyEnemyInRange(player, weapon, mode) then
        return nil
    end

    return {
        weapon = weapon,
        mode = mode,
        xpPerk = xpPerk,
    }
end

return CSR_DualWieldUtils
