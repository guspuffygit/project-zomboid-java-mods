-- SafeLogin: DISABLED — cleanup mode only
-- Clears persisted godmode/invisible/ghost from all players on login,
-- then forces a max-weight recalculation so carry capacity is correct.
-- Remove this mod once all affected players have logged in.

Events.OnCreatePlayer.Add(function(playerIndex, player)
    if getAccessLevel() == "admin" or getAccessLevel() == "Admin" then
        print("[SafeLogin] Player is admin — skipping cleanup.")
        return
    end

    player:setGodMod(false, true)
    player:setInvisible(false, true)
    player:setGhostMode(false, true)

    -- Recalculate maxWeightDelta from current traits (mirrors IsoPlayer constructor logic)
    local traits = player:getCharacterTraits()
    if traits:get(CharacterTrait.STRONG) then
        player:setMaxWeightDelta(1.5)
    elseif traits:get(CharacterTrait.WEAK) then
        player:setMaxWeightDelta(0.75)
    elseif traits:get(CharacterTrait.FEEBLE) then
        player:setMaxWeightDelta(0.9)
    elseif traits:get(CharacterTrait.STOUT) then
        player:setMaxWeightDelta(1.25)
    else
        player:setMaxWeightDelta(1.0)
    end

    -- Force immediate max-weight recalculation from current Strength level and moodles
    player:getBodyDamage():UpdateStrength()

    print(
        "[SafeLogin] Cleared persisted cheats and recalculated carry capacity for "
            .. tostring(player:getUsername())
    )
end)
