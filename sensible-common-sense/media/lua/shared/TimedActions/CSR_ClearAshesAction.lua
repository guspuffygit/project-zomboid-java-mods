require "TimedActions/ISClearAshes"

CSR_ClearAshesAction = ISClearAshes:derive("CSR_ClearAshesAction")

function CSR_ClearAshesAction:complete()
    -- Vanilla removes the ashes object from the square (MP-safe via
    -- transmitRemoveItemFromSquare). We chain into it so any future TIS
    -- additions stay intact.
    ISClearAshes.complete(self)

    -- Charcoal reward roll. Sandbox-tunable 0..100; default 33 set in
    -- sandbox-options.txt. Sandbox lookup is guarded for SP/MP parity.
    local chance = 33
    local sb = SandboxVars and SandboxVars.CommonSenseReborn
    if sb and sb.SweepAshesCharcoalChance ~= nil then
        chance = sb.SweepAshesCharcoalChance
    end
    if chance > 0 and self.character and ZombRand(100) < chance then
        local inv = self.character:getInventory()
        if inv then
            inv:AddItem("Base.Charcoal")
        end
    end

    return true
end

function CSR_ClearAshesAction:new(character, ashes)
    local o = ISClearAshes.new(self, character, ashes)
    return o
end
