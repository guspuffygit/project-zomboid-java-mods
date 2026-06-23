package com.sentientsimulations.projectzomboid.survivorskillobelisk;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import io.pzstorm.storm.event.core.OnClientCommand;
import java.util.List;
import se.krka.kahlua.vm.KahluaTable;
import zombie.Lua.LuaManager;
import zombie.characters.IsoPlayer;
import zombie.network.GameServer;

/**
 * Handles the {@code SurvivorSkillObelisk:listDeaths} client command. Reads the requesting player's
 * past-life death rows from the SQLite DB and ships them back to the client UI so the obelisk's
 * "Recover Skills" picker can render them.
 */
public final class ListDeathsHandler {

    private static final String MODULE = "SurvivorSkillObelisk";
    private static final String REPLY_COMMAND = "deathsList";
    private static final int DEFAULT_LIMIT = 200;
    private static final int MAX_LIMIT = 1000;

    private ListDeathsHandler() {}

    @OnClientCommand
    public static void onListDeaths(ListDeathsCommand event) {
        IsoPlayer player = event.getPlayer();
        if (player == null) {
            LOGGER.warn("[SurvivorSkillObelisk] listDeaths from null player; dropping");
            return;
        }
        long steamId = player.getSteamID();
        String username = player.getUsername();
        if (username == null || username.isBlank()) {
            LOGGER.warn(
                    "[SurvivorSkillObelisk] listDeaths from {} with no username; dropping",
                    steamId);
            return;
        }

        Integer requested = event.getLimit();
        int limit = requested == null ? DEFAULT_LIMIT : Math.min(Math.max(requested, 1), MAX_LIMIT);

        List<SurvivorSkillObeliskRepository.DeathSummary> rows;
        try (SurvivorSkillObeliskDatabase db =
                new SurvivorSkillObeliskDatabase(DeathEventHandler.getDbPath())) {
            SurvivorSkillObeliskRepository repo =
                    new SurvivorSkillObeliskRepository(db.getConnection());
            rows = repo.listDeathsByOwner(steamId, username, limit);
        } catch (Exception e) {
            LOGGER.error(
                    "[SurvivorSkillObelisk] listDeaths failed for {} ({}): {}",
                    username,
                    steamId,
                    e.getMessage(),
                    e);
            return;
        }

        KahluaTable reply = LuaManager.platform.newTable();
        KahluaTable rowsTable = LuaManager.platform.newTable();
        int i = 1;
        for (SurvivorSkillObeliskRepository.DeathSummary r : rows) {
            KahluaTable rowTable = LuaManager.platform.newTable();
            rowTable.rawset("id", (double) r.id());
            rowTable.rawset("ts", (double) r.ts());
            rowTable.rawset("username", r.username());
            rowTable.rawset("forename", r.forename());
            rowTable.rawset("surname", r.surname());
            rowTable.rawset("hoursSurvived", r.hoursSurvived());
            rowTable.rawset("zombieKills", (double) r.zombieKills());
            rowsTable.rawset(i++, rowTable);
        }
        reply.rawset("rows", rowsTable);
        reply.rawset("count", (double) rows.size());

        GameServer.sendServerCommand(player, MODULE, REPLY_COMMAND, reply);
    }
}
