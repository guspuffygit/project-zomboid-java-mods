--
-- SurvivorSkillObeliskProtection.lua
-- Client half of obelisk indestructibility. The destroy cursor deliberately
-- still offers obelisks: the server refuses the removal, resyncs the object
-- back, kills the character server-side, and sends this "obeliskCurse" command
-- so the attacker hears the obelisk answer.
--
-- The kill is NOT done here. B42 player health is server-authoritative and the
-- persisted isDead flag is written from the server's IsoPlayer, so a
-- client-side Kill only played the death screen: the server character stayed
-- alive, "create new character" hung on a black screen, and rejoining restored
-- the old character. ObeliskCurseHandler kills on the server; the death reaches
-- this client through the normal PlayerDeath packet, which is also what feeds
-- the mod's death snapshot (the obelisk remembers its killer).
--

local MODULE = "SurvivorSkillObelisk"
local CURSE_COMMAND = "obeliskCurse"

local function onServerCommand(module, command, args)
    if module ~= MODULE or command ~= CURSE_COMMAND then
        return
    end
    local player = getSpecificPlayer(0)
    if not player then
        return
    end
    player:playSound("SurvivorSkillObeliskRecover")
end

Events.OnServerCommand.Add(onServerCommand)
