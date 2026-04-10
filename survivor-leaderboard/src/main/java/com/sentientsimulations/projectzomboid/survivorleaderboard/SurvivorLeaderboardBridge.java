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

    /** Delete every entry whose username matches, then broadcast. */
    public static String deleteEntry(String username) {
        try (SurvivorLeaderboardDatabase db = new SurvivorLeaderboardDatabase(getDbPath())) {
            SurvivorLeaderboardRepository repo =
                    new SurvivorLeaderboardRepository(db.getConnection());
            int removed = repo.deleteByUsername(username);
            LOGGER.info("[Lifeboard] Deleted {} entries for username={}", removed, username);
            broadcast(repo);
            return null;
        } catch (SQLException e) {
            LOGGER.error("[Lifeboard] Failed to delete entry for username={}", username, e);
            return "Database error deleting entry.";
        }
    }

    /** Clear the whole board and broadcast the empty result. */
    public static String deleteAllEntries() {
        try (SurvivorLeaderboardDatabase db = new SurvivorLeaderboardDatabase(getDbPath())) {
            SurvivorLeaderboardRepository repo =
                    new SurvivorLeaderboardRepository(db.getConnection());
            int removed = repo.deleteAll();
            LOGGER.info("[Lifeboard] Deleted {} entries (all)", removed);
            broadcast(repo);
            return null;
        } catch (SQLException e) {
            LOGGER.error("[Lifeboard] Failed to delete all entries", e);
            return "Database error deleting all entries.";
        }
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
