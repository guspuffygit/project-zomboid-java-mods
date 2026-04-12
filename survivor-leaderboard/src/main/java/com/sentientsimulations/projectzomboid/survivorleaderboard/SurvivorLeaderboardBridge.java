package com.sentientsimulations.projectzomboid.survivorleaderboard;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import com.sentientsimulations.projectzomboid.survivorleaderboard.records.SurvivorRecord;
import java.io.File;
import java.sql.SQLException;
import java.util.List;
import se.krka.kahlua.vm.KahluaTable;
import zombie.Lua.LuaManager;
import zombie.ZomboidFileSystem;
import zombie.characters.IsoPlayer;
import zombie.network.GameServer;
import zombie.network.ServerWorldDatabase;

public final class SurvivorLeaderboardBridge {

    static final String MODULE = "Lifeboard";
    private static final String DB_FILENAME = "survivor_leaderboard.db";

    private SurvivorLeaderboardBridge() {}

    static String getDbPath() {
        File dbFile = ZomboidFileSystem.instance.getFileInCurrentSave(DB_FILENAME);
        String path = dbFile.getAbsolutePath();
        LOGGER.info("[Lifeboard] DB path: {}", path);
        return path;
    }

    /**
     * Insert the player into the leaderboard if not already present, then broadcast. Keyed on
     * (steamId, username) so a single Steam account may have multiple characters on the same
     * server.
     *
     * @return null on success, or an error message
     */
    public static String addPlayer(IsoPlayer player) {
        long steamId = player.getSteamID();
        String username = player.getUsername();
        try (SurvivorLeaderboardDatabase db = new SurvivorLeaderboardDatabase(getDbPath())) {
            SurvivorLeaderboardRepository repo =
                    new SurvivorLeaderboardRepository(db.getConnection());
            boolean inserted = repo.insertSurvivor(steamId, username);
            if (inserted) {
                LOGGER.info("[Lifeboard] Added survivor steamId={} username={}", steamId, username);
            } else {
                LOGGER.info(
                        "[Lifeboard] Survivor already present steamId={} username={}",
                        steamId,
                        username);
            }
            broadcast(repo);
            return null;
        } catch (SQLException e) {
            LOGGER.error(
                    "[Lifeboard] Failed to add survivor steamId={} username={}",
                    steamId,
                    username,
                    e);
            return "Database error adding player.";
        }
    }

    /** Rebroadcast the current board to everyone without touching the DB. */
    public static String refresh(IsoPlayer player) {
        try (SurvivorLeaderboardDatabase db = new SurvivorLeaderboardDatabase(getDbPath())) {
            SurvivorLeaderboardRepository repo =
                    new SurvivorLeaderboardRepository(db.getConnection());
            broadcast(repo);
            return null;
        } catch (SQLException e) {
            LOGGER.error("[Lifeboard] Failed to refresh board", e);
            return "Database error refreshing board.";
        }
    }

    /** Set the player's current day count and broadcast. */
    public static String incrementDays(IsoPlayer player, int daysSurvived) {
        long steamId = player.getSteamID();
        String username = player.getUsername();
        try (SurvivorLeaderboardDatabase db = new SurvivorLeaderboardDatabase(getDbPath())) {
            SurvivorLeaderboardRepository repo =
                    new SurvivorLeaderboardRepository(db.getConnection());
            boolean updated = repo.updateDayCount(steamId, username, daysSurvived);
            if (!updated) {
                // Not on the board yet — add and then set.
                repo.insertSurvivor(steamId, username);
                repo.updateDayCount(steamId, username, daysSurvived);
            }
            broadcast(repo);
            return null;
        } catch (SQLException e) {
            LOGGER.error(
                    "[Lifeboard] Failed to update days for steamId={} username={}",
                    steamId,
                    username,
                    e);
            return "Database error updating days.";
        }
    }

    /** Delete every entry whose Steam ID matches, then broadcast. */
    public static String deleteBySteamId(long steamId) {
        try (SurvivorLeaderboardDatabase db = new SurvivorLeaderboardDatabase(getDbPath())) {
            SurvivorLeaderboardRepository repo =
                    new SurvivorLeaderboardRepository(db.getConnection());
            int removed = repo.deleteBySteamId(steamId);
            LOGGER.info("[Lifeboard] Deleted {} entries for steamId={}", removed, steamId);
            broadcast(repo);
            return null;
        } catch (SQLException e) {
            LOGGER.error("[Lifeboard] Failed to delete entries for steamId={}", steamId, e);
            return "Database error deleting entries by Steam ID.";
        }
    }

    /**
     * Remove every leaderboard entry whose Steam ID is currently banned per {@link
     * ServerWorldDatabase}. Intended to run once on server startup.
     *
     * @return number of rows removed
     */
    public static int pruneBannedSurvivors() {
        try (SurvivorLeaderboardDatabase db = new SurvivorLeaderboardDatabase(getDbPath())) {
            SurvivorLeaderboardRepository repo =
                    new SurvivorLeaderboardRepository(db.getConnection());
            return pruneBannedSurvivors(repo);
        } catch (SQLException e) {
            LOGGER.error("[Lifeboard] Failed to prune banned survivors", e);
            return 0;
        }
    }

    /**
     * Package-private overload used by the public entry point and by tests. Iterates distinct Steam
     * IDs from the given repository, queries {@link ServerWorldDatabase} for ban status, and
     * deletes all rows for each banned Steam ID.
     *
     * @return number of rows removed
     */
    static int pruneBannedSurvivors(SurvivorLeaderboardRepository repo) throws SQLException {
        List<Long> steamIds = repo.loadDistinctSteamIds();
        LOGGER.info(
                "[Lifeboard] Pruning banned survivors, checking {} distinct Steam IDs",
                steamIds.size());

        int totalRemoved = 0;
        for (Long steamId : steamIds) {
            String bannedSteamId;
            try {
                bannedSteamId =
                        ServerWorldDatabase.instance.isSteamIdBanned(Long.toString(steamId));
            } catch (Exception e) {
                LOGGER.error("[Lifeboard] Error checking ban status for steamId={}", steamId, e);
                continue;
            }
            if (bannedSteamId != null) {
                int removed = repo.deleteBySteamId(steamId);
                totalRemoved += removed;
                LOGGER.info(
                        "[Lifeboard] Pruned {} banned entries for steamId={}", removed, steamId);
            }
        }
        if (totalRemoved > 0) {
            LOGGER.info("[Lifeboard] Ban prune complete, removed {} total entries", totalRemoved);
        } else {
            LOGGER.info("[Lifeboard] Ban prune complete, no banned entries found");
        }
        return totalRemoved;
    }

    public static List<SurvivorRecord> listSurvivors() {
        try (SurvivorLeaderboardDatabase db = new SurvivorLeaderboardDatabase(getDbPath())) {
            SurvivorLeaderboardRepository repo =
                    new SurvivorLeaderboardRepository(db.getConnection());
            return repo.loadAllOrdered();
        } catch (SQLException e) {
            LOGGER.error("[Lifeboard] Failed to list survivors", e);
            return List.of();
        }
    }

    // ---- Network ----

    /** Broadcast the full leaderboard to every connected client. */
    private static void broadcast(SurvivorLeaderboardRepository repo) throws SQLException {
        KahluaTable args = buildBoardTable(repo);
        GameServer.sendServerCommand(MODULE, "UpdateBoard", args);
        LOGGER.info("[Lifeboard] Broadcast UpdateBoard to all clients");
    }

    /** Send the full leaderboard to a single player. */
    public static void syncToPlayer(IsoPlayer player) {
        try (SurvivorLeaderboardDatabase db = new SurvivorLeaderboardDatabase(getDbPath())) {
            SurvivorLeaderboardRepository repo =
                    new SurvivorLeaderboardRepository(db.getConnection());
            KahluaTable args = buildBoardTable(repo);
            GameServer.sendServerCommand(player, MODULE, "UpdateBoard", args);
            LOGGER.info("[Lifeboard] Sent UpdateBoard to {}", player.getUsername());
        } catch (SQLException e) {
            LOGGER.error("[Lifeboard] Failed to sync board to player", e);
        }
    }

    /**
     * Wire format consumed by LifeBoard_UI.lua's {@code OnServerCommand}:
     *
     * <pre>{ board = [ {displayName, dayCount}, ... ] }</pre>
     *
     * Numbers are written as {@link Double} because Kahlua stores all Lua numbers that way.
     */
    private static KahluaTable buildBoardTable(SurvivorLeaderboardRepository repo)
            throws SQLException {
        List<SurvivorRecord> survivors = repo.loadAllOrdered();
        KahluaTable args = LuaManager.platform.newTable();
        KahluaTable boardTable = LuaManager.platform.newTable();

        int idx = 1;
        for (SurvivorRecord s : survivors) {
            KahluaTable entry = LuaManager.platform.newTable();
            entry.rawset("displayName", s.username());
            entry.rawset("dayCount", (double) s.dayCount());
            boardTable.rawset(idx++, entry);
        }
        args.rawset("board", boardTable);
        return args;
    }
}
