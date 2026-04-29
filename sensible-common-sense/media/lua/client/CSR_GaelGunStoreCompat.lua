--[[
    CSR_GaelGunStoreCompat.lua
    Neutralizes GaelGunStore's broken ISBaseTimedAction:begin() pcall wrapper.

    GGS wraps begin() in pcall(). On B42.15+, when the Java-side StartAction
    throws RuntimeException (e.g. ISOpenCloseDoor), pcall catches the exception
    but Kahlua's internal call frame state is left corrupted. This causes
    doors and gates to open then immediately close, and can produce
    NullPointerException in ReturnValues.put on subsequent actions.

    This patch captures the clean vanilla begin() in OnGameBoot (before GGS wraps it)
    and restores it in OnGameStart (after GGS has applied its broken wrapper).

    Jeeve's Patches mod attempts to fix this via file override, but the override
    mechanism can fail depending on load order and mod configuration.
    This patch serves as a reliable fallback.
]]

local _cleanBegin = nil

-- Capture vanilla begin() before GGS wraps it
-- CSR loads before GGS (alphabetically: CommonSenseReborn < GaelGunStore_B42)
-- so this OnGameBoot handler is registered and fires first
if Events and Events.OnGameBoot then
    Events.OnGameBoot.Add(function()
        if ISBaseTimedAction and ISBaseTimedAction.begin then
            _cleanBegin = ISBaseTimedAction.begin
        end
    end)
end

-- After all mods have loaded, check if GGS installed the broken pcall wrapper
-- and restore the clean version if so
if Events and Events.OnGameStart then
    Events.OnGameStart.Add(function()
        if ISBaseTimedAction and ISBaseTimedAction.__ggsBeginGuard and _cleanBegin then
            ISBaseTimedAction.begin = _cleanBegin
            -- Keep __ggsBeginGuard = true so GGS's OnGameStart handler doesn't re-apply
            print("[CSR] Neutralized GaelGunStore ISBaseTimedAction:begin() pcall wrapper")
        end
    end)
end
