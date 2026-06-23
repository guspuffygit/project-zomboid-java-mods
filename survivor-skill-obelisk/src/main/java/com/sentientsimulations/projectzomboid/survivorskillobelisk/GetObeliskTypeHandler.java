package com.sentientsimulations.projectzomboid.survivorskillobelisk;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import io.pzstorm.storm.event.core.OnClientCommand;
import se.krka.kahlua.vm.KahluaTable;
import zombie.Lua.LuaManager;
import zombie.characters.IsoPlayer;
import zombie.network.GameServer;

/**
 * Handles the {@code SurvivorSkillObelisk:getObeliskType} client command. Returns the obelisk's
 * configured perk id (or {@code "None"}) for the given coords. Used by the Configure Obelisk window
 * to pre-select its skill combo so reopening doesn't silently reset to None on save.
 */
public final class GetObeliskTypeHandler {

    private static final String MODULE = "SurvivorSkillObelisk";
    private static final String REPLY_COMMAND = "obeliskType";
    private static final String NONE = "None";

    private GetObeliskTypeHandler() {}

    @OnClientCommand
    public static void onGetObeliskType(GetObeliskTypeCommand event) {
        IsoPlayer player = event.getPlayer();
        if (player == null) {
            LOGGER.warn("[SurvivorSkillObelisk] getObeliskType from null player; dropping");
            return;
        }
        Integer x = event.getX();
        Integer y = event.getY();
        Integer z = event.getZ();
        if (x == null || y == null || z == null) {
            LOGGER.warn(
                    "[SurvivorSkillObelisk] getObeliskType from {} with missing coords"
                            + " (x={}, y={}, z={}); dropping",
                    player.getUsername(),
                    x,
                    y,
                    z);
            return;
        }

        String type = NONE;
        try (SurvivorSkillObeliskDatabase db =
                new SurvivorSkillObeliskDatabase(DeathEventHandler.getDbPath())) {
            SurvivorSkillObeliskRepository repo =
                    new SurvivorSkillObeliskRepository(db.getConnection());
            String stored = repo.findObeliskType(x, y, z);
            if (stored != null && !stored.isBlank()) {
                type = stored;
            }
        } catch (Exception e) {
            LOGGER.error(
                    "[SurvivorSkillObelisk] getObeliskType failed for {} at ({}, {}, {})",
                    player.getUsername(),
                    x,
                    y,
                    z,
                    e);
            return;
        }

        try {
            KahluaTable reply = LuaManager.platform.newTable();
            reply.rawset("x", (double) x);
            reply.rawset("y", (double) y);
            reply.rawset("z", (double) z);
            reply.rawset("type", type);
            GameServer.sendServerCommand(player, MODULE, REPLY_COMMAND, reply);
        } catch (Throwable t) {
            LOGGER.error(
                    "[SurvivorSkillObelisk] Failed to send obeliskType reply: {}", t.getMessage(), t);
        }
    }
}
