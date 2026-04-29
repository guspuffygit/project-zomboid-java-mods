require "CSR_FeatureFlags"
local CSR_DualWieldUtils = require "CSR_DualWieldUtils"

-- =============================================================================
-- CSR_DualWieldHooks (v1.7.0 rewrite)
--
-- Restoration of an off-hand weapon that the engine briefly clears during a
-- primary-hand attack is handled entirely by:
--
--   1. CSR_LeftHandAttackAction (proactive TimedAction): saves the secondary
--      in :start() before the animation begins and restores it in
--      :stop()/:perform()/:forceCancel().  This is the DualWieldingAttacks
--      pattern -- the engine never gets to broadcast a nil secondary because
--      the action owns the slot for the duration of the swing.
--
--   2. Server-side anchor in CSR_ServerCommands.onDualWieldServerTick +
--      OnPlayerAttackFinished.  Defence-in-depth: if the server's Hit() ever
--      nulls the secondary, the server re-equips before the broadcast.
--
-- Previous client-side reactive helpers (lastKnownSecondary anchor,
-- tryRestoreSecondary, onAttackFinishedRestoreSecondary) have been removed.
-- They created a race against the proactive TimedAction's own start() save and,
-- in practice, sometimes ran AFTER the engine moved the weapon back to the
-- inventory's attached slot, which masked the slot as "occupied" and prevented
-- the proactive restore from re-applying it.  Letting the TimedAction be the
-- single source of truth fixes that.
--
-- This file now only handles:
--   * triggerLeftHandAttack: queues the proactive TimedAction.
--   * onUnarmedRightHandAttack: existing CSR unarmed-vs-zombie behaviour.
--   * changeUnarmedAnimation: keeps the unarmed animation variables in sync,
--     PLUS the new Issue-A primary-mirror promotion (see comment below).
-- =============================================================================

local frameCounter = 0
-- ---------------------------------------------------------------------------
-- Issue A (primary mirror anchor)
--
-- When a player dual-wields and unequips the primary, the engine leaves the
-- secondary in the off-hand slot and immediately switches the character into
-- the unarmed-punching animation state -- producing a visual glitch where the
-- character is "punching" with one hand while a weapon dangles in the other,
-- and the remaining weapon cannot fire its primary swing because primary is
-- nil.  The intuitive UX is for the remaining weapon to become the active
-- primary hand item.
--
-- We track the most recently observed primary so we can detect the transition
-- "primary was a weapon last tick, primary is nil this tick, secondary is a
-- non-broken weapon".  When that fires we move the secondary into the primary
-- slot (and clear the secondary slot) BEFORE the unarmed-animation block
-- runs, so the next state is clean: armed with one weapon, no off-hand
-- weapon, no unarmed-punching variables set.
--
-- Guards:
--   * Skip while a TimedAction is queued (don't fight the swing pipeline).
--   * Skip if the secondary is broken or no longer in inventory.
--   * Skip if the secondary item has just been moved into an attached slot
--     (player intentionally holstering both -- see getAttachedSlot()).
--   * Only fire on the transition tick (not every frame the slot is empty).
-- ---------------------------------------------------------------------------
local lastKnownPrimary = false  -- false = uninitialized, nil = empty last tick
local lastKnownPrimaryFrame = 0
local PRIMARY_PROMOTE_FRAME_WINDOW = 30  -- frames; ~500ms at 60fps

-- ---------------------------------------------------------------------------
-- Issue C (v1.8.2): Quick Equip swap -- MANUAL hotkey only
--
-- v1.8.0 / v1.8.1 attempted to detect the engine's mid-combat "secondary
-- vanished into a holster slot" symptom and auto-swap the stuck off-hand
-- back into the primary.  Every heuristic we tried either fired during the
-- engine's legitimate 1-tick clears (causing weapons to vanish in combat)
-- or didn't fire at all on the genuine bug.  v1.8.2 retires auto-swap
-- entirely and exposes the same swap behind an explicit hotkey on the
-- numpad -- KEY_NUMPAD7 ("Numpad 7").  Pressing it equips the most recently
-- remembered off-hand weapon as the new primary, with the prior primary
-- moved to the off-hand.
-- ---------------------------------------------------------------------------
local lastKnownSecondary = nil

local function isPrimary2H(item)
    if not item then return false end
    if item.isRequiresEquippedBothHands and item:isRequiresEquippedBothHands() then return true end
    if item.isTwoHandWeapon and item:isTwoHandWeapon() then return true end
    return false
end

local function clearAttachedSlot(player, item)
    if not item then return end
    local ok, slot = pcall(function() return item:getAttachedSlot() end)
    if not ok or not slot or slot == -1 then return end
    if item.setAttachedSlot     then pcall(function() item:setAttachedSlot(-1) end) end
    if item.setAttachedSlotType then pcall(function() item:setAttachedSlotType(nil) end) end
    if item.setAttachedToModel  then pcall(function() item:setAttachedToModel(nil) end) end
    if player and player.removeAttachedItem then
        pcall(function() player:removeAttachedItem(item) end)
    end
end

local function triggerLeftHandAttack(player)
    if not CSR_FeatureFlags.isDualWieldEnabled() then return end
    if not player or player:isDead() then return end
    local leftHandAttackInfo = CSR_DualWieldUtils.checkIfValidLeftHandAttack(player)
    if not leftHandAttackInfo then return end
    player:setAuthorizeMeleeAction(false)
    player:setAuthorizeShoveStomp(false)
    player:setAuthorizedHandToHandAction(false)
    ISTimedActionQueue.add(CSR_LeftHandAttackAction:new(player, leftHandAttackInfo.weapon, leftHandAttackInfo.mode))
end

local function onUnarmedRightHandAttack(attacker, target, weapon, damageSplit)
    if not CSR_FeatureFlags.isDualWieldEnabled() then return end
    if not attacker or not target then return end
    -- Don't override when using firearms
    if weapon and weapon.isRanged and weapon:isRanged() then return end
    local valid, mode = CSR_DualWieldUtils.isNonDefaultUnarmedAttack(attacker, target)
    if not valid then return end
    sendClientCommand(CSR_DualWield.COMMANDMODULE, CSR_DualWield.Commands.UNARMEDRIGHTHANDATTACK, {
        CSR_DualWieldUtils.getCharacterID(target), damageSplit
    })
end

local unarmedPlayerMode = nil

-- Returns true when the player has any timed action queued -- we must not
-- move hand items mid-swing or mid-equip.
local function isPlayerBusyAction(player)
    local ok, q = pcall(function()
        return ISTimedActionQueue.getTimedActionQueue and ISTimedActionQueue.getTimedActionQueue(player) or nil
    end)
    if ok and q and q.queue and #q.queue > 0 then return true end
    return false
end

-- Returns true when the item's attachedSlot is set (player holstered rather
-- than unequipped completely -- don't promote in that case).
local function isItemAttached(item)
    if not item then return false end
    local ok, slot = pcall(function() return item:getAttachedSlot() end)
    return ok and slot and slot ~= -1 or false
end

local function tryPromoteSecondaryToPrimary(player, secondary, lastPrimary)
    if not secondary or secondary:isBroken() then return end
    if not secondary.IsWeapon or not secondary:IsWeapon() then return end
    -- v1.7.6: never promote a 2H weapon that the engine is in the process of
    -- unequipping.  Vanilla holds the SAME item reference in both primary and
    -- secondary slots while a 2H weapon is wielded; on unequip the primary
    -- clears one tick before the secondary, and without this guard we would
    -- "promote" the still-mirrored secondary back into the primary slot --
    -- which is exactly the symptom of the unequipped 2H weapon visually
    -- staying stuck in the off-hand and being un-stowable.
    if lastPrimary and secondary == lastPrimary then return end
    if secondary.isRequiresEquippedBothHands and secondary:isRequiresEquippedBothHands() then return end
    if secondary.isTwoHandWeapon and secondary:isTwoHandWeapon() then return end
    if isItemAttached(secondary) then return end
    if isPlayerBusyAction(player) then return end
    -- Inventory:contains() is recursive in B42, so a weapon that briefly
    -- ended up in a nested container still resolves correctly.
    if not player:getInventory():contains(secondary) then return end
    -- Atomic swap: clear secondary first so setPrimaryHandItem doesn't refuse
    -- the same item already held in the off-hand.
    player:setSecondaryHandItem(nil)
    player:setPrimaryHandItem(secondary)
end

local function changeUnarmedAnimation(player)
    if not CSR_FeatureFlags.isDualWieldEnabled() then return end
    if not player or player:isDead() then return end

    -- Advance frame counter once per update so freshness checks stay accurate.
    frameCounter = frameCounter + 1

    local primaryItem = player:getPrimaryHandItem()
    local secondaryItem = player:getSecondaryHandItem()

    -- v1.8.2: auto Emergency Swap was removed.  The same operation is now
    -- triggered manually on KEY_NUMPAD7 (see CSR_DualWieldHooks.onQuickEquipKey
    -- registered below).  Auto-detection produced too many false positives
    -- (weapons vanishing during legitimate engine clears).

    -- ---------- Issue A: primary-mirror promotion ----------
    -- Transition detector: primary was a weapon last frame, primary is nil
    -- this frame, secondary is still a real weapon -> promote it.
    if primaryItem == nil
       and lastKnownPrimary
       and lastKnownPrimary ~= false
       and (frameCounter - lastKnownPrimaryFrame) <= PRIMARY_PROMOTE_FRAME_WINDOW
       and secondaryItem ~= nil then
        tryPromoteSecondaryToPrimary(player, secondaryItem, lastKnownPrimary)
        -- Re-read after the swap so the rest of this tick uses correct state.
        primaryItem = player:getPrimaryHandItem()
        secondaryItem = player:getSecondaryHandItem()
    end

    -- Anchor the current primary for next tick's transition detection.
    if primaryItem ~= nil then
        lastKnownPrimary = primaryItem
        lastKnownPrimaryFrame = frameCounter
    else
        lastKnownPrimary = nil
    end
    -- ---------- end Issue A ----------

    -- Anchor the current secondary for Issue C emergency-swap detection.
    -- Only remember real, non-broken, non-2H weapons that are NOT the same
    -- reference as primary (filters out the 2H mirror state).
    if secondaryItem ~= nil
       and secondaryItem ~= primaryItem
       and secondaryItem.IsWeapon and secondaryItem:IsWeapon()
       and not secondaryItem:isBroken()
       and not isPrimary2H(secondaryItem) then
        lastKnownSecondary = secondaryItem
    end

    if primaryItem ~= nil then
        -- Clear unarmed animation state when a weapon is equipped
        if unarmedPlayerMode ~= nil then
            player:setVariable("UnarmedPunching", false)
            unarmedPlayerMode = nil
        end
        return
    end
    local unarmedMode = CSR_DualWieldUtils.getUnarmedMode(player)
    player:setVariable("UnarmedPunching", unarmedMode.UNARMEDPUNCHINGVALUE)
    if unarmedPlayerMode == unarmedMode then return end
    local weapon = player:getAttackingWeapon()
    if not weapon then return end
    if weapon:getScriptItem() ~= unarmedMode.SCRIPTITEM then
        CSR_DualWieldUtils.changeWeaponStats(weapon, unarmedMode.ITEM, unarmedMode.SCRIPTITEM)
    end
    unarmedPlayerMode = unarmedMode
end

if not CSR_DualWieldHooks then CSR_DualWieldHooks = {} end

-- v1.8.5.1: Quick Equip swap on KEY_NUMPAD7. Rewrite of v1.8.2.
--
-- Bug history: v1.8.2 worked correctly for the visible "primary moves to
-- secondary" step but the engine bounced the freshly-equipped target back
-- out of the primary slot one tick later, because the previous code never
-- called the canonical "release attached" sequence that vanilla
-- ISEquipWeaponAction:animEvent('detachConnect') uses
-- (player:removeAttachedItem(item) + clearAttachedSlot). Without that, the
-- engine's hotbar attachment system still treated the weapon as
-- holstered and pulled it back to its slot, leaving the player with the
-- old primary in secondary and an empty primary -- visually "the weapon
-- vanished".
--
-- Rewrite intent (per user spec): "User sees no offhand, clicks button,
-- primary gets shifted to secondary, the previous secondary now gets
-- found in the inventory and equipped to primary".
--
-- Removed guardrails (per user request -- they were silently aborting
-- the swap without preventing the lost-item path):
--   * isPlayerBusyAction() bail
--   * strict inv:contains(stuck) bail (replaced with type-fallback)
--   * rollback branch on equip-failure
function CSR_DualWieldHooks.onQuickEquipKey(key)
    if not key or not Keyboard or key ~= Keyboard.KEY_NUMPAD7 then return end
    if not CSR_FeatureFlags or not CSR_FeatureFlags.isDualWieldEnabled
        or not CSR_FeatureFlags.isDualWieldEnabled() then return end
    local player = getPlayer()
    if not player or player:isDead() then return end
    if MainScreen and MainScreen.instance and MainScreen.instance:isVisible() then return end

    local inv = player:getInventory()
    if not inv then return end

    -- Resolve the target weapon. Prefer the live anchored reference; fall
    -- back to "any item of the same fullType still in inventory" so a
    -- server-side item-recreate doesn't strand the hotkey on a stale ref.
    local target = lastKnownSecondary
    if target and (target:isBroken() or not inv:contains(target)) then
        local fullType = target.getFullType and target:getFullType()
        target = (fullType and inv.getFirstTypeRecurse) and inv:getFirstTypeRecurse(fullType) or nil
    end
    if not target then return end
    if not target.IsWeapon or not target:IsWeapon() then return end
    if target:isBroken() then return end
    if isPrimary2H(target) then return end

    local oldPrim = player:getPrimaryHandItem()
    if oldPrim == target then return end          -- already primary
    if isPrimary2H(oldPrim) then return end       -- never split a 2H mirror

    -- 1) Release any holster/belt attachment on target. This is the step
    --    the previous version was missing -- vanilla ISEquipWeaponAction
    --    calls removeAttachedItem on detachConnect, and without it the
    --    engine bounces the equip back to the holster on the next tick.
    if player.removeAttachedItem then
        pcall(function() player:removeAttachedItem(target) end)
    end
    clearAttachedSlot(player, target)

    -- 2) Drop any mirror references in either hand slot so setPrimaryHandItem
    --    won't see "already held" conflict.
    if player:getSecondaryHandItem() == target then player:setSecondaryHandItem(nil) end
    if player:getPrimaryHandItem()   == target then player:setPrimaryHandItem(nil)   end

    -- 3) Move old primary into secondary first (frees primary cleanly).
    --    Skip if old primary is gone, broken, or 2H (would corrupt mirror).
    if oldPrim and (not oldPrim.isBroken or not oldPrim:isBroken())
       and not isPrimary2H(oldPrim) then
        player:setSecondaryHandItem(oldPrim)
    else
        player:setSecondaryHandItem(nil)
    end

    -- 4) Canonical vanilla force-equip: nil-then-set.
    player:setPrimaryHandItem(nil)
    player:setPrimaryHandItem(target)

    if player.setHaloNote then
        pcall(function() player:setHaloNote("Quick Equip", 200, 220, 100, 150) end)
    end
end

if not CSR_DualWieldHooks._animRegistered then
    CSR_DualWieldHooks._animRegistered = true
    Events.OnPlayerAttackFinished.Add(triggerLeftHandAttack)
    Events.OnWeaponHitCharacter.Add(onUnarmedRightHandAttack)
    Events.OnPlayerUpdate.Add(changeUnarmedAnimation)
    if Events.OnKeyPressed then
        Events.OnKeyPressed.Add(CSR_DualWieldHooks.onQuickEquipKey)
    end
end
