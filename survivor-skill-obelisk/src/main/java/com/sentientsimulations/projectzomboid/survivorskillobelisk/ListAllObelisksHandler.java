package com.sentientsimulations.projectzomboid.survivorskillobelisk;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import io.pzstorm.storm.event.core.OnClientCommand;
import java.util.List;
import se.krka.kahlua.vm.KahluaTable;
import zombie.Lua.LuaManager;
import zombie.characters.IsoPlayer;
import zombie.network.GameServer;

/**
 * Handles the {@code SurvivorSkillObelisk:listAllObelisks} client command. Replies with every
 * configured obelisk's coordinates and bound perk so the client can render them on the world map.
 *
 * <p>Unconfigured obelisks (no row in {@code obelisk_types}) are intentionally not included — the
 * map shows admin-tagged shrines only.
 */
public final class ListAllObelisksHandler {

    private static final String MODULE = "SurvivorSkillObelisk";
    private static final String REPLY_COMMAND = "obeliskList";

    private ListAllObelisksHandler() {}

    @OnClientCommand
    public static void onListAllObelisks(ListAllObelisksCommand event) {
        IsoPlayer player = event.getPlayer();
        if (player == null) {
            LOGGER.warn("[SurvivorSkillObelisk] listAllObelisks from null player; dropping");
            return;
        }

        List<SurvivorSkillObeliskRepository.ObeliskTypeRow> rows;
        try (SurvivorSkillObeliskDatabase db =
                new SurvivorSkillObeliskDatabase(DeathEventHandler.getDbPath())) {
            SurvivorSkillObeliskRepository repo =
                    new SurvivorSkillObeliskRepository(db.getConnection());
            rows = repo.listAllObeliskTypes();
        } catch (Exception e) {
            LOGGER.error(
                    "[SurvivorSkillObelisk] listAllObelisks failed for {}",
                    player.getUsername(),
                    e);
            return;
        }

        try {
            KahluaTable reply = LuaManager.platform.newTable();
            KahluaTable rowsTable = LuaManager.platform.newTable();
            int i = 1;
            for (SurvivorSkillObeliskRepository.ObeliskTypeRow row : rows) {
                KahluaTable rowTable = LuaManager.platform.newTable();
                rowTable.rawset("x", (double) row.x());
                rowTable.rawset("y", (double) row.y());
                rowTable.rawset("z", (double) row.z());
                rowTable.rawset("type", row.type());
                rowsTable.rawset(i++, rowTable);
            }
            reply.rawset("rows", rowsTable);
            reply.rawset("count", (double) rows.size());
            GameServer.sendServerCommand(player, MODULE, REPLY_COMMAND, reply);
        } catch (Throwable t) {
            LOGGER.error(
                    "[SurvivorSkillObelisk] Failed to send obeliskList reply: {}",
                    t.getMessage(),
                    t);
        }
    }
}
