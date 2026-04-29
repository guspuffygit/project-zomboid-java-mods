local CSR_DualWieldUtils = require "CSR_DualWieldUtils"
require "TimedActions/ISBaseTimedAction"

local function getBodyPartPain(character, bodyPartType)
    local part = character:getBodyDamage():getBodyPart(bodyPartType)
    return part:getPain()
end

CSR_LeftHandAttackAction = ISBaseTimedAction:derive("CSR_LeftHandAttackAction")

function CSR_LeftHandAttackAction.isValidTarget(enemy, character, rangeSq, allowAttackFloor)
    if not enemy:isZombie() or enemy:isDead() or (not allowAttackFloor and enemy:isProne()) then
        return false, nil
    end
    local dist = enemy:DistToSquared(character)
    return dist <= rangeSq, dist
end

function CSR_LeftHandAttackAction.calcRange(character, weapon)
    local ignoreProneRange = Core.getInstance():getIgnoreProneZombieRange()
    local weaponRange = weapon:getMaxRange() * weapon:getRangeMod(character)
    local lungeStateExtraRange = 1
    local range = math.max(ignoreProneRange, weaponRange + lungeStateExtraRange)
    return range ^ 2
end

function CSR_LeftHandAttackAction.anyEnemyInRange(character, weapon, mode)
    local enemies = character:getSpottedList()
    local rangeSq = CSR_LeftHandAttackAction.calcRange(character, weapon)
    for i = 0, enemies:size() - 1 do
        local enemy = enemies:get(i)
        local valid = CSR_LeftHandAttackAction.isValidTarget(enemy, character, rangeSq, mode.ALLOWATTACKFLOOR)
        if valid then return true end
    end
    return false
end

function CSR_LeftHandAttackAction.getMaxHits(character, weapon, mode)
    local result = mode.MAXHITS_BASE or 1
    if mode.MAXHITS_PERKBONUS then
        local perk = weapon:getPerk()
        result = result + math.floor(character:getPerkLevel(perk) * mode.MAXHITS_PERKBONUS + 0.5)
    end
    return result
end

function CSR_LeftHandAttackAction.getSpeed(character, weapon, mode)
    local result = mode.SPEED_BASE or 1
    if mode.SPEED_PERKBONUS then
        local perk = weapon:getPerk()
        result = result + character:getPerkLevel(perk) * mode.SPEED_PERKBONUS
    end
    return result
end

function CSR_LeftHandAttackAction.getConditionMultiplier(character, weapon, mode)
    local result = mode.CONDITIONLOWER_BASE or 1
    if mode.CONDITIONLOWER_PERKBONUS then
        local perk = weapon:getPerk()
        result = result + character:getPerkLevel(perk) * mode.CONDITIONLOWER_PERKBONUS
    end
    return result
end

function CSR_LeftHandAttackAction.getMaxTime(character, weapon, mode)
    local res = CSR_DualWield.LEFT_ATTACK_TIME
    res = res * (1 + (character:getMoodles():getMoodleLevel(MoodleType.DRUNK) / 4))
    local maxPain = getBodyPartPain(character, BodyPartType.Hand_L)
        + getBodyPartPain(character, BodyPartType.ForeArm_L)
        + getBodyPartPain(character, BodyPartType.UpperArm_L)
    local speed = CSR_LeftHandAttackAction.getSpeed(character, weapon, mode)
    res = res * (1 + (maxPain / 300))
    res = res * character:getCombatSpeed() / speed
    return res
end

function CSR_LeftHandAttackAction.getAttackType(weapon, weaponMode)
    if weaponMode == CSR_DualWield.UnarmedMode then
        return "punch"
    end
    if weapon and weapon:getSwingAnim() == "Stab" then
        return "knife"
    end
    return "bash"
end

function CSR_LeftHandAttackAction:update()
    self.character:setMetabolicTarget(Metabolics.UsingTools)
    -- Safety fallback: if animEvent never fired (e.g. animation interrupted)
    if not self.attackDone and self:getJobDelta() >= 0.95 then
        self.attackDone = true
        self:doAttack()
    end
end

function CSR_LeftHandAttackAction:animEvent(event, parameter)
    if event == "StartAttack" then
        local swingSound = self.weapon:getSwingSound()
        if swingSound and swingSound ~= "" then
            self.sound = self.character:playSound(swingSound)
        end
    elseif event == "AttackCollisionCheck" then
        if not self.attackDone then
            self.attackDone = true
            self:doAttack()
        end
    elseif event == "EndAttack" then
        self:forceComplete()
    end
end

function CSR_LeftHandAttackAction:restoreSecondaryWeapon()
    local sec = self.savedSecondary
    if not sec then return end
    -- v1.8.1 Part A: clear any attachedSlot the engine set on the off-hand
    -- weapon during the swing-state transition.  Without this the slot looks
    -- "occupied/holstered" to the hotbar and ISInventoryPaneContextMenu
    -- silently refuses to re-equip it -- which is the symptom of "secondary
    -- vanishes and becomes unequipable".  setSecondaryHandItem() on its own
    -- does NOT clear attachedSlot.
    if sec.getAttachedSlot and sec:getAttachedSlot() ~= -1 then
        if sec.setAttachedSlot      then sec:setAttachedSlot(-1) end
        if sec.setAttachedSlotType  then sec:setAttachedSlotType(nil) end
        if sec.setAttachedToModel   then sec:setAttachedToModel(nil) end
        if self.character.removeAttachedItem then
            self.character:removeAttachedItem(sec)
        end
    end
    -- Always re-apply directly; never use a nil intermediate.
    -- The nil->sec toggle was meant as a visual-refresh trick but moves the weapon
    -- to inventory first -- if the re-equip then fails (animation lock, post-shove
    -- recovery, etc.) the weapon stays in the bag with attachedSlot still set,
    -- making the slot appear occupied.  setOverrideHandModels() in start() already
    -- covers the visual during the animation; re-setting the same item after the
    -- action ends forces the engine to re-render without the bag-drop risk.
    self.character:setSecondaryHandItem(sec)
end

function CSR_LeftHandAttackAction:start()
    if self.weaponMode == CSR_DualWield.ArmedMode then
        if self.character:getSecondaryHandItem() ~= self.weapon then
            self:forceComplete()
            return
        end
    end
    -- Save secondary weapon reference (defense in depth; with proper L-hand
    -- weapon anims the engine should not clear the off-hand slot, but we
    -- still re-anchor on stop() if anything tampers).
    self.savedSecondary = self.character:getSecondaryHandItem()
    sendClientCommand(CSR_DualWield.COMMANDMODULE, CSR_DualWield.Commands.TRIGGERLEFTHANDATTACK, {})
    -- v1.8.12: Use the HCO/OffHandAttack pattern -- a real left-hand weapon
    -- swing animation (Bob_CSR_Attack1H_L / Bob_CSR_AttackKnife_L) instead of
    -- the punch anim that previously caused the engine to wipe the off-hand
    -- weapon slot. The XML node we trigger is selected via the LAttackType
    -- variable (CSR_LAttack_Bash.xml or CSR_LAttack_Knife.xml).
    if self.weaponMode == CSR_DualWield.ArmedMode then
        self.character:setVariable("LAttackType", self.attackType)
        self:setActionAnim("LAttack")
    else
        -- Unarmed off-hand still uses the legacy punch XML.
        self:setActionAnim("LeftHandPunch")
    end
    -- Tell engine to keep showing both weapons during the animation
    self:setOverrideHandModels(self.character:getPrimaryHandItem(), self.savedSecondary)
    self.character:setMeleeDelay(self.maxTime)
    self.character:setAuthorizeMeleeAction(false)
    self.character:setAuthorizeShoveStomp(false)
    self.character:setAuthorizedHandToHandAction(false)
end

function CSR_LeftHandAttackAction:stopSound()
    if self.sound and self.character:getEmitter():isPlaying(self.sound) then
        self.character:stopOrTriggerSound(self.sound)
    end
end

function CSR_LeftHandAttackAction:stop()
    self:stopSound()
    self:restoreSecondaryWeapon()
    if self.weaponMode == CSR_DualWield.ArmedMode then
        self.character:setVariable("LAttackType", "")
    end
    self.character:setAuthorizeMeleeAction(true)
    self.character:setAuthorizeShoveStomp(true)
    self.character:setAuthorizedHandToHandAction(true)
    ISBaseTimedAction.stop(self)
end

function CSR_LeftHandAttackAction:forceCancel()
    self:restoreSecondaryWeapon()
    if self.weaponMode == CSR_DualWield.ArmedMode then
        self.character:setVariable("LAttackType", "")
    end
    self.character:setAuthorizeMeleeAction(true)
    self.character:setAuthorizeShoveStomp(true)
    self.character:setAuthorizedHandToHandAction(true)
end

function CSR_LeftHandAttackAction:findClosestEnemies()
    local result = {}
    local enemies = self.character:getSpottedList()
    if enemies:size() <= 0 then return result end
    for i = 0, enemies:size() - 1 do
        local enemy = enemies:get(i)
        local valid, dist = CSR_LeftHandAttackAction.isValidTarget(enemy, self.character, self.rangeSq, self.allowAttackFloor)
        if valid then
            local inserted = false
            for index, other in ipairs(result) do
                if dist < other.dist then
                    table.insert(result, index, { enemy = enemy, dist = dist })
                    inserted = true
                    break
                end
            end
            if not inserted and #result < self.maxHits then
                table.insert(result, { enemy = enemy, dist = dist })
            elseif #result > self.maxHits then
                table.remove(result)
            end
        end
    end
    return result
end

function CSR_LeftHandAttackAction:doAttack()
    local targets = self:findClosestEnemies()
    if #targets <= 0 then return end
    self.character:playSound(self.weapon:getZombieHitSound())
    local targetIDs = {}
    for _, target in ipairs(targets) do
        table.insert(targetIDs, CSR_DualWieldUtils.getCharacterID(target.enemy))
    end
    sendClientCommand(CSR_DualWield.COMMANDMODULE, CSR_DualWield.Commands.TRIGGERLEFTHANDHIT, targetIDs)
end

function CSR_LeftHandAttackAction:perform()
    self:restoreSecondaryWeapon()
    if self.weaponMode == CSR_DualWield.ArmedMode then
        self.character:setVariable("LAttackType", "")
    end
    self.character:setAuthorizeMeleeAction(true)
    self.character:setAuthorizeShoveStomp(true)
    self.character:setAuthorizedHandToHandAction(true)
    ISBaseTimedAction.perform(self)
end

function CSR_LeftHandAttackAction:adjustMaxTime(maxTime)
    return maxTime
end

function CSR_LeftHandAttackAction:isValid()
    if self.weaponMode == CSR_DualWield.ArmedMode then
        -- Check savedSecondary (anchored at start) rather than live hand state.
        -- The server's Hit() can briefly clear the secondary hand item during
        -- combat processing, which would prematurely cancel this action.
        local sec = self.character:getSecondaryHandItem()
        if sec ~= self.weapon then
            -- Allow brief desync if we have a saved reference and weapon isn't broken
            if self.savedSecondary and self.savedSecondary == self.weapon and not self.weapon:isBroken() then
                -- Re-anchor the weapon back to the hand
                self.character:setSecondaryHandItem(self.weapon)
            else
                return false
            end
        end
    end
    return CSR_LeftHandAttackAction.anyEnemyInRange(self.character, self.weapon, self.weaponMode)
end

function CSR_LeftHandAttackAction:new(character, weapon, weaponMode)
    local o = ISBaseTimedAction.new(self, character)
    o.weapon = weapon
    o.weaponMode = weaponMode
    o.attackType = CSR_LeftHandAttackAction.getAttackType(weapon, weaponMode)
    o.speed = CSR_LeftHandAttackAction.getSpeed(character, weapon, weaponMode)
    o.allowAttackFloor = weaponMode.ALLOWATTACKFLOOR
    o.stopWalking = false
    o.stopOnWalk = false
    o.stopOnRun = true
    o.stopOnAim = false
    o.useProgressBar = false
    o.maxTime = CSR_LeftHandAttackAction.getMaxTime(character, weapon, weaponMode)
    o.rangeSq = CSR_LeftHandAttackAction.calcRange(character, weapon)
    o.attackDone = false
    o.maxHits = CSR_LeftHandAttackAction.getMaxHits(character, weapon, weaponMode)
    return o
end
