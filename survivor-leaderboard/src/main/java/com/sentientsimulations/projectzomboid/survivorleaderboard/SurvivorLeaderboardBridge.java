package com.sentientsimulations.projectzomboid.survivorleaderboard;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import com.sentientsimulations.projectzomboid.survivorleaderboard.records.KillLogEntry;
import com.sentientsimulations.projectzomboid.survivorleaderboard.records.SqlExecutionResponse;
import com.sentientsimulations.projectzomboid.survivorleaderboard.records.SurvivorRecord;
import java.io.File;
import java.sql.Connection;
import java.sql.ResultSet;
import java.sql.ResultSetMetaData;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.List;
import org.jspecify.annotations.Nullable;
import se.krka.kahlua.vm.KahluaTable;
import zombie.Lua.LuaManager;
import zombie.ZomboidFileSystem;
import zombie.characters.Faction;
import zombie.characters.IsoPlayer;
import zombie.iso.areas.SafeHouse;
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

    /** Set the player's current day count and zombie kill count, then broadcast. */
    public static String incrementDays(IsoPlayer player, int daysSurvived, int zombieKills) {
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
            repo.updateZombieKills(steamId, username, zombieKills);
            broadcast(repo);
            return null;
        } catch (SQLException e) {
            LOGGER.error(
                    "[Lifeboard] Failed to update days/zombie kills for steamId={} username={}",
                    steamId,
                    username,
                    e);
            return "Database error updating days.";
        }
    }

    /**
     * Credit the killer with +1 PvP kill and reset the victim's kill count to 0 (only if it was
     * positive — negative values earned from ally-grief penalties are preserved so dying does not
     * wipe the debt). Upserts rows for both players if they are not yet on the board. Broadcasts on
     * success.
     *
     * @return null on success, or an error message
     */
    public static String recordPlayerKill(IsoPlayer killer, IsoPlayer victim, boolean isAlly) {
        long killerSteamId = killer.getSteamID();
        String killerUsername = killer.getUsername();
        long victimSteamId = victim.getSteamID();
        String victimUsername = victim.getUsername();
        try (SurvivorLeaderboardDatabase db = new SurvivorLeaderboardDatabase(getDbPath())) {
            SurvivorLeaderboardRepository repo =
                    new SurvivorLeaderboardRepository(db.getConnection());

            if (!repo.incrementKillCount(killerSteamId, killerUsername)) {
                repo.insertSurvivor(killerSteamId, killerUsername);
                repo.incrementKillCount(killerSteamId, killerUsername);
            }

            repo.insertSurvivor(victimSteamId, victimUsername);
            repo.resetKillCountIfPositive(victimSteamId, victimUsername);

            repo.insertKill(
                    killerSteamId,
                    killerUsername,
                    victimSteamId,
                    victimUsername,
                    isAlly,
                    System.currentTimeMillis());

            // The victim is dead; wipe their outgoing kill log so their history resets with them.
            int wiped = repo.deleteKillsByKiller(victimSteamId, victimUsername);
            if (wiped > 0) {
                LOGGER.info(
                        "[Lifeboard] Cleared {} kill log entries for victim={}",
                        wiped,
                        victimUsername);
            }

            LOGGER.info(
                    "[Lifeboard] Recorded PvP kill: killer={} victim={} isAlly={}",
                    killerUsername,
                    victimUsername,
                    isAlly);
            broadcast(repo);
            return null;
        } catch (SQLException e) {
            LOGGER.error(
                    "[Lifeboard] Failed to record PvP kill killer={} victim={}",
                    killerUsername,
                    victimUsername,
                    e);
            return "Database error recording kill.";
        }
    }

    /**
     * Reset the player's kill count to 0 when they die from a non-PvP cause, but only if it was
     * positive — negative values from ally-grief penalties are preserved. Upserts the row if
     * absent, then broadcasts.
     *
     * @return null on success, or an error message
     */
    public static String resetKillsForPlayer(IsoPlayer victim) {
        long steamId = victim.getSteamID();
        String username = victim.getUsername();
        try (SurvivorLeaderboardDatabase db = new SurvivorLeaderboardDatabase(getDbPath())) {
            SurvivorLeaderboardRepository repo =
                    new SurvivorLeaderboardRepository(db.getConnection());
            repo.insertSurvivor(steamId, username);
            repo.resetKillCountIfPositive(steamId, username);
            int wiped = repo.deleteKillsByKiller(steamId, username);
            LOGGER.info(
                    "[Lifeboard] Reset kills for victim={}, cleared {} kill log entries",
                    username,
                    wiped);
            broadcast(repo);
            return null;
        } catch (SQLException e) {
            LOGGER.error("[Lifeboard] Failed to reset kills for {}", username, e);
            return "Database error resetting kills.";
        }
    }

    /**
     * True when two players share a faction (mutual membership/ownership) or both belong to the
     * same safehouse as owner or member. Used to flag ally-on-ally PvP.
     */
    public static boolean areAllies(IsoPlayer a, IsoPlayer b) {
        if (a == null || b == null || a == b) {
            return false;
        }
        if (Faction.isInSameFaction(a, b)) {
            return true;
        }
        SafeHouse sa = SafeHouse.hasSafehouse(a);
        SafeHouse sb = SafeHouse.hasSafehouse(b);
        return sa != null && sa.equals(sb);
    }

    /** Rolling ally-kill window used by the hourly penalty processor. */
    static final long ALLY_KILL_WINDOW_MS = 60L * 60L * 1000L;

    /** Amount deducted from a killer's {@code kill_count} per qualifying ally kill. */
    static final int ALLY_KILL_PENALTY = 8;

    /**
     * Walk every un-decided ally kill (oldest first). For each one, if the same killer has another
     * ally kill in the preceding {@link #ALLY_KILL_WINDOW_MS}, deduct {@link #ALLY_KILL_PENALTY}
     * from their {@code kill_count}. Mark the row applied either way so it's skipped next tick.
     *
     * <p>The first ally kill in any rolling 60-min window is "free"; every ally kill after that
     * contributes a penalty. Kill counts are permitted to go negative so the penalty cannot be
     * immediately masked by new legitimate kills.
     *
     * @return number of penalties applied in this run
     */
    public static int processAllyKillPenalties() {
        try (SurvivorLeaderboardDatabase db = new SurvivorLeaderboardDatabase(getDbPath())) {
            SurvivorLeaderboardRepository repo =
                    new SurvivorLeaderboardRepository(db.getConnection());
            int penalties = processAllyKillPenalties(repo);
            if (penalties > 0) {
                broadcast(repo);
            }
            return penalties;
        } catch (SQLException e) {
            LOGGER.error("[Lifeboard] Failed to process ally-kill penalties", e);
            return 0;
        }
    }

    /**
     * Package-private overload used by the public entry point and by tests. Does not broadcast;
     * callers are responsible for that.
     *
     * @return number of penalties applied
     */
    static int processAllyKillPenalties(SurvivorLeaderboardRepository repo) throws SQLException {
        List<KillLogEntry> pending = repo.loadUnappliedAllyKills();
        if (pending.isEmpty()) {
            return 0;
        }
        int penalties = 0;
        for (KillLogEntry kill : pending) {
            boolean hasPredecessor =
                    repo.hasPrecedingAllyKill(
                            kill.killerSteamId(),
                            kill.killerUsername(),
                            kill.createdAt(),
                            ALLY_KILL_WINDOW_MS);
            if (hasPredecessor) {
                int rows =
                        repo.decrementKillCount(
                                kill.killerSteamId(), kill.killerUsername(), ALLY_KILL_PENALTY);
                if (rows > 0) {
                    penalties++;
                    LOGGER.info(
                            "[Lifeboard] Applied ally-kill penalty -{} to {} ({}) for kill id={}",
                            ALLY_KILL_PENALTY,
                            kill.killerUsername(),
                            kill.killerSteamId(),
                            kill.id());
                } else {
                    LOGGER.info(
                            "[Lifeboard] Penalty skipped, no survivor row for {} ({}) kill id={}",
                            kill.killerUsername(),
                            kill.killerSteamId(),
                            kill.id());
                }
            }
            repo.markPenaltyApplied(kill.id());
        }
        LOGGER.info(
                "[Lifeboard] Ally-kill sweep processed {} kill(s), applied {} penalty(ies)",
                pending.size(),
                penalties);
        return penalties;
    }

    /** Delete every entry whose Steam ID matches, then broadcast. */
    public static String deleteBySteamId(long steamId) {
        try (SurvivorLeaderboardDatabase db = new SurvivorLeaderboardDatabase(getDbPath())) {
            SurvivorLeaderboardRepository repo =
                    new SurvivorLeaderboardRepository(db.getConnection());
            int removed = repo.deleteBySteamId(steamId);
            int killsRemoved = repo.deleteKillsByKillerSteamId(steamId);
            LOGGER.info(
                    "[Lifeboard] Deleted {} survivor entries and {} kill log entries for"
                            + " steamId={}",
                    removed,
                    killsRemoved,
                    steamId);
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
                int killsRemoved = repo.deleteKillsByKillerSteamId(steamId);
                totalRemoved += removed;
                LOGGER.info(
                        "[Lifeboard] Pruned {} banned survivor entries and {} kill log entries"
                                + " for steamId={}",
                        removed,
                        killsRemoved,
                        steamId);
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
        return listSurvivors(null, null);
    }

    /**
     * List survivors ordered by day count, optionally restricted to a single (username, steamId)
     * tuple. Either filter may be null to leave that side unfiltered. When both are non-null they
     * must both match.
     */
    public static List<SurvivorRecord> listSurvivors(
            @Nullable String username, @Nullable Long steamId) {
        try (SurvivorLeaderboardDatabase db = new SurvivorLeaderboardDatabase(getDbPath())) {
            SurvivorLeaderboardRepository repo =
                    new SurvivorLeaderboardRepository(db.getConnection());
            return repo.loadAllOrderedFiltered(username, steamId);
        } catch (SQLException e) {
            LOGGER.error("[Lifeboard] Failed to list survivors", e);
            return List.of();
        }
    }

    /**
     * Execute arbitrary SQL against the leaderboard database. If the statement produces a result
     * set, the rows are materialized and returned; otherwise the update count is returned. Intended
     * as an admin/debug tool — there is no sanitization.
     */
    public static SqlExecutionResponse executeSql(String sql) {
        try (SurvivorLeaderboardDatabase db = new SurvivorLeaderboardDatabase(getDbPath())) {
            return executeSql(sql, db.getConnection());
        } catch (SQLException e) {
            LOGGER.error("[Lifeboard] SQL execution failed: {}", sql, e);
            return SqlExecutionResponse.error(e.getMessage());
        }
    }

    /** Package-private overload used by the public entry point and by tests. */
    static SqlExecutionResponse executeSql(String sql, Connection conn) {
        try (Statement stmt = conn.createStatement()) {
            boolean hasResultSet = stmt.execute(sql);
            if (hasResultSet) {
                try (ResultSet rs = stmt.getResultSet()) {
                    ResultSetMetaData meta = rs.getMetaData();
                    int columnCount = meta.getColumnCount();
                    List<String> columns = new ArrayList<>(columnCount);
                    for (int i = 1; i <= columnCount; i++) {
                        columns.add(meta.getColumnLabel(i));
                    }
                    List<List<Object>> rows = new ArrayList<>();
                    while (rs.next()) {
                        List<Object> row = new ArrayList<>(columnCount);
                        for (int i = 1; i <= columnCount; i++) {
                            row.add(rs.getObject(i));
                        }
                        rows.add(row);
                    }
                    return SqlExecutionResponse.rows(columns, rows);
                }
            }
            return SqlExecutionResponse.update(stmt.getUpdateCount());
        } catch (SQLException e) {
            LOGGER.error("[Lifeboard] SQL execution failed: {}", sql, e);
            return SqlExecutionResponse.error(e.getMessage());
        }
    }

    public static List<SurvivorRecord> listKillers() {
        return listKillers(null, null);
    }

    /**
     * List killers (kill_count != 0) ordered by kill count, optionally restricted to a single
     * (username, steamId) tuple.
     */
    public static List<SurvivorRecord> listKillers(
            @Nullable String username, @Nullable Long steamId) {
        try (SurvivorLeaderboardDatabase db = new SurvivorLeaderboardDatabase(getDbPath())) {
            SurvivorLeaderboardRepository repo =
                    new SurvivorLeaderboardRepository(db.getConnection());
            return repo.loadKillersOrderedFiltered(username, steamId);
        } catch (SQLException e) {
            LOGGER.error("[Lifeboard] Failed to list killers", e);
            return List.of();
        }
    }

    public static List<SurvivorRecord> listZombieKillers() {
        return listZombieKillers(null, null);
    }

    /**
     * List zombie killers (zombie_kills != 0) ordered by zombie kill count, optionally restricted
     * to a single (username, steamId) tuple.
     */
    public static List<SurvivorRecord> listZombieKillers(
            @Nullable String username, @Nullable Long steamId) {
        try (SurvivorLeaderboardDatabase db = new SurvivorLeaderboardDatabase(getDbPath())) {
            SurvivorLeaderboardRepository repo =
                    new SurvivorLeaderboardRepository(db.getConnection());
            return repo.loadZombieKillersOrderedFiltered(username, steamId);
        } catch (SQLException e) {
            LOGGER.error("[Lifeboard] Failed to list zombie killers", e);
            return List.of();
        }
    }

    /** Return the {@code limit} most recent kill log entries, newest first. */
    public static List<KillLogEntry> listKills(int limit) {
        return listKills(limit, null, null);
    }

    /**
     * Return the {@code limit} most recent kill log entries, newest first, optionally restricted to
     * entries where the player (matched on either side) is involved.
     */
    public static List<KillLogEntry> listKills(
            int limit, @Nullable String username, @Nullable Long steamId) {
        try (SurvivorLeaderboardDatabase db = new SurvivorLeaderboardDatabase(getDbPath())) {
            SurvivorLeaderboardRepository repo =
                    new SurvivorLeaderboardRepository(db.getConnection());
            return repo.loadRecentKillsFiltered(limit, username, steamId);
        } catch (SQLException e) {
            LOGGER.error("[Lifeboard] Failed to list kills", e);
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
     * <pre>{ board = [ {displayName, dayCount, killCount, zombieKillCount}, ... ] }</pre>
     *
     * Numbers are written as {@link Double} because Kahlua stores all Lua numbers that way.
     */
    private static KahluaTable buildBoardTable(SurvivorLeaderboardRepository repo)
            throws SQLException {
        List<SurvivorRecord> survivors = repo.loadOrderedWithActivity();
        KahluaTable args = LuaManager.platform.newTable();
        KahluaTable boardTable = LuaManager.platform.newTable();

        int idx = 1;
        for (SurvivorRecord s : survivors) {
            KahluaTable entry = LuaManager.platform.newTable();
            entry.rawset("displayName", s.username());
            entry.rawset("dayCount", (double) s.dayCount());
            entry.rawset("killCount", (double) s.killCount());
            entry.rawset("zombieKillCount", (double) s.zombieKills());
            boardTable.rawset(idx++, entry);
        }
        args.rawset("board", boardTable);
        return args;
    }
}
