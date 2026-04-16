package com.sentientsimulations.projectzomboid.survivorleaderboard;

import com.sentientsimulations.projectzomboid.survivorleaderboard.records.KillLogEntry;
import com.sentientsimulations.projectzomboid.survivorleaderboard.records.SurvivorRecord;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.ArrayList;
import java.util.List;
import org.jspecify.annotations.Nullable;

public class SurvivorLeaderboardRepository {

    private static final String INSERT_SURVIVOR =
            "INSERT OR IGNORE INTO survivors (steam_id, username, day_count) VALUES (?, ?, 0)";

    private static final String UPDATE_DAY_COUNT =
            "UPDATE survivors SET day_count = ? WHERE steam_id = ? AND username = ?";

    private static final String UPDATE_ZOMBIE_KILLS =
            "UPDATE survivors SET zombie_kills = ? WHERE steam_id = ? AND username = ?";

    private static final String INCREMENT_KILL_COUNT =
            "UPDATE survivors SET kill_count = kill_count + 1 WHERE steam_id = ? AND username = ?";

    private static final String RESET_KILL_COUNT_IF_POSITIVE =
            "UPDATE survivors SET kill_count = 0"
                    + " WHERE steam_id = ? AND username = ? AND kill_count > 0";

    private static final String DECREMENT_KILL_COUNT =
            "UPDATE survivors SET kill_count = kill_count - ? WHERE steam_id = ? AND username = ?";

    private static final String DELETE_BY_STEAM_ID = "DELETE FROM survivors WHERE steam_id = ?";

    private static final String SELECT_SURVIVORS_BASE =
            "SELECT id, steam_id, username, day_count, kill_count, zombie_kills FROM survivors";

    private static final String ORDER_BY_DAYS = " ORDER BY day_count DESC, username ASC";

    private static final String ORDER_BY_KILLS = " ORDER BY kill_count DESC, username ASC";

    private static final String ORDER_BY_ZOMBIE_KILLS = " ORDER BY zombie_kills DESC, username ASC";

    private static final String SELECT_KILLS_BASE =
            "SELECT id, killer_steam_id, killer_username, victim_steam_id, victim_username,"
                    + " is_ally, created_at FROM kills";

    private static final String ORDER_KILLS_NEWEST = " ORDER BY created_at DESC, id DESC LIMIT ?";

    private static final String SELECT_DISTINCT_STEAM_IDS =
            "SELECT DISTINCT steam_id FROM survivors";

    private static final String INSERT_KILL =
            "INSERT INTO kills"
                    + " (killer_steam_id, killer_username, victim_steam_id, victim_username,"
                    + " is_ally, created_at)"
                    + " VALUES (?, ?, ?, ?, ?, ?)";

    private static final String DELETE_KILLS_BY_KILLER =
            "DELETE FROM kills WHERE killer_steam_id = ? AND killer_username = ?";

    private static final String DELETE_KILLS_BY_KILLER_STEAM_ID =
            "DELETE FROM kills WHERE killer_steam_id = ?";

    private static final String SELECT_UNAPPLIED_ALLY_KILLS =
            "SELECT id, killer_steam_id, killer_username, victim_steam_id, victim_username,"
                    + " is_ally, created_at FROM kills"
                    + " WHERE is_ally = 1 AND penalty_applied = 0"
                    + " ORDER BY created_at ASC, id ASC";

    private static final String EXISTS_PRECEDING_ALLY_KILL =
            "SELECT 1 FROM kills"
                    + " WHERE killer_steam_id = ? AND killer_username = ?"
                    + " AND is_ally = 1"
                    + " AND created_at >= ? AND created_at < ?"
                    + " LIMIT 1";

    private static final String MARK_PENALTY_APPLIED =
            "UPDATE kills SET penalty_applied = 1 WHERE id = ?";

    private final Connection connection;

    public SurvivorLeaderboardRepository(Connection connection) {
        this.connection = connection;
    }

    /**
     * Insert a survivor with day_count = 0 if no row exists for (steamId, username).
     *
     * @return true if a new row was inserted
     */
    public boolean insertSurvivor(long steamId, String username) throws SQLException {
        try (PreparedStatement ps = connection.prepareStatement(INSERT_SURVIVOR)) {
            ps.setLong(1, steamId);
            ps.setString(2, username);
            return ps.executeUpdate() > 0;
        }
    }

    /**
     * @return true if a row was updated
     */
    public boolean updateDayCount(long steamId, String username, int dayCount) throws SQLException {
        try (PreparedStatement ps = connection.prepareStatement(UPDATE_DAY_COUNT)) {
            ps.setInt(1, dayCount);
            ps.setLong(2, steamId);
            ps.setString(3, username);
            return ps.executeUpdate() > 0;
        }
    }

    /**
     * @return true if a row was updated
     */
    public boolean updateZombieKills(long steamId, String username, int zombieKills)
            throws SQLException {
        try (PreparedStatement ps = connection.prepareStatement(UPDATE_ZOMBIE_KILLS)) {
            ps.setInt(1, zombieKills);
            ps.setLong(2, steamId);
            ps.setString(3, username);
            return ps.executeUpdate() > 0;
        }
    }

    /**
     * @return true if a row was updated
     */
    public boolean incrementKillCount(long steamId, String username) throws SQLException {
        try (PreparedStatement ps = connection.prepareStatement(INCREMENT_KILL_COUNT)) {
            ps.setLong(1, steamId);
            ps.setString(2, username);
            return ps.executeUpdate() > 0;
        }
    }

    /**
     * Reset {@code kill_count} to 0 only when it is currently positive. Negative values (earned
     * from ally-grief penalties) are preserved so a penalized player cannot wipe their debt by
     * dying.
     *
     * @return number of rows updated (0 if the row is absent or already &le; 0)
     */
    public int resetKillCountIfPositive(long steamId, String username) throws SQLException {
        try (PreparedStatement ps = connection.prepareStatement(RESET_KILL_COUNT_IF_POSITIVE)) {
            ps.setLong(1, steamId);
            ps.setString(2, username);
            return ps.executeUpdate();
        }
    }

    /**
     * Subtract {@code amount} from kill_count. Values may go negative by design; penalised players
     * keep a negative score until enough new kills bring them back up.
     *
     * @return number of rows updated
     */
    public int decrementKillCount(long steamId, String username, int amount) throws SQLException {
        try (PreparedStatement ps = connection.prepareStatement(DECREMENT_KILL_COUNT)) {
            ps.setInt(1, amount);
            ps.setLong(2, steamId);
            ps.setString(3, username);
            return ps.executeUpdate();
        }
    }

    /**
     * @return number of rows deleted (may be &gt; 1 if the same Steam account has multiple
     *     characters)
     */
    public int deleteBySteamId(long steamId) throws SQLException {
        try (PreparedStatement ps = connection.prepareStatement(DELETE_BY_STEAM_ID)) {
            ps.setLong(1, steamId);
            return ps.executeUpdate();
        }
    }

    public List<Long> loadDistinctSteamIds() throws SQLException {
        List<Long> results = new ArrayList<>();
        try (PreparedStatement ps = connection.prepareStatement(SELECT_DISTINCT_STEAM_IDS);
                ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                results.add(rs.getLong("steam_id"));
            }
        }
        return results;
    }

    /**
     * Load every survivor row ordered by day count. No board-visibility filter is applied — the
     * HTTP endpoints use {@link #loadAllOrderedFiltered} and the in-game broadcast uses {@link
     * #loadOrderedWithActivity}; this raw query exists for tests and for operations that need the
     * full dataset (e.g. ban prune verification).
     */
    public List<SurvivorRecord> loadAllOrdered() throws SQLException {
        return querySurvivors(SELECT_SURVIVORS_BASE, null, ORDER_BY_DAYS, null, null);
    }

    public List<SurvivorRecord> loadAllOrderedByKills() throws SQLException {
        return loadKillersOrderedFiltered(null, null);
    }

    /**
     * Load survivors for the survivors board, ordered by day count. Rows with {@code day_count = 0}
     * are excluded — a newly-added player does not appear until they've survived at least one day.
     * Optionally filtered to a single (username, steamId) tuple; either or both filters may be
     * null. When both are non-null both must match (AND).
     */
    public List<SurvivorRecord> loadAllOrderedFiltered(
            @Nullable String username, @Nullable Long steamId) throws SQLException {
        return querySurvivors(
                SELECT_SURVIVORS_BASE, "day_count <> 0", ORDER_BY_DAYS, username, steamId);
    }

    /**
     * Load every row eligible to appear on at least one in-game board — i.e. {@code day_count <> 0
     * OR kill_count <> 0}. Used to populate the broadcast payload; the client then filters per tab
     * so zero-metric rows don't leak into the opposing view.
     */
    public List<SurvivorRecord> loadOrderedWithActivity() throws SQLException {
        return querySurvivors(
                SELECT_SURVIVORS_BASE,
                "(day_count <> 0 OR kill_count <> 0 OR zombie_kills <> 0)",
                ORDER_BY_DAYS,
                null,
                null);
    }

    /**
     * Load survivors with non-zero kill count ordered by kill count, optionally filtered to a
     * single (username, steamId) tuple.
     */
    public List<SurvivorRecord> loadKillersOrderedFiltered(
            @Nullable String username, @Nullable Long steamId) throws SQLException {
        return querySurvivors(
                SELECT_SURVIVORS_BASE, "kill_count <> 0", ORDER_BY_KILLS, username, steamId);
    }

    /**
     * Load survivors with non-zero zombie kill count ordered by zombie kills, optionally filtered
     * to a single (username, steamId) tuple.
     */
    public List<SurvivorRecord> loadZombieKillersOrderedFiltered(
            @Nullable String username, @Nullable Long steamId) throws SQLException {
        return querySurvivors(
                SELECT_SURVIVORS_BASE,
                "zombie_kills <> 0",
                ORDER_BY_ZOMBIE_KILLS,
                username,
                steamId);
    }

    /**
     * Append a kill to the kill log.
     *
     * @return true if a row was inserted
     */
    public boolean insertKill(
            long killerSteamId,
            String killerUsername,
            long victimSteamId,
            String victimUsername,
            boolean isAlly,
            long createdAt)
            throws SQLException {
        try (PreparedStatement ps = connection.prepareStatement(INSERT_KILL)) {
            ps.setLong(1, killerSteamId);
            ps.setString(2, killerUsername);
            ps.setLong(3, victimSteamId);
            ps.setString(4, victimUsername);
            ps.setInt(5, isAlly ? 1 : 0);
            ps.setLong(6, createdAt);
            return ps.executeUpdate() > 0;
        }
    }

    /**
     * Remove every kill log row where the given player is the killer.
     *
     * @return number of rows removed
     */
    public int deleteKillsByKiller(long steamId, String username) throws SQLException {
        try (PreparedStatement ps = connection.prepareStatement(DELETE_KILLS_BY_KILLER)) {
            ps.setLong(1, steamId);
            ps.setString(2, username);
            return ps.executeUpdate();
        }
    }

    /**
     * Remove every kill log row for the given Steam ID across every character. Used when a Steam
     * account is banned.
     *
     * @return number of rows removed
     */
    public int deleteKillsByKillerSteamId(long steamId) throws SQLException {
        try (PreparedStatement ps = connection.prepareStatement(DELETE_KILLS_BY_KILLER_STEAM_ID)) {
            ps.setLong(1, steamId);
            return ps.executeUpdate();
        }
    }

    /** Load the {@code limit} most recent kill log entries, newest first. */
    public List<KillLogEntry> loadRecentKills(int limit) throws SQLException {
        return loadRecentKillsFiltered(limit, null, null);
    }

    /**
     * Load every ally kill whose delayed penalty has not yet been decided, oldest first. Used by
     * the hourly processor to apply penalties in chronological order.
     */
    public List<KillLogEntry> loadUnappliedAllyKills() throws SQLException {
        List<KillLogEntry> results = new ArrayList<>();
        try (PreparedStatement ps = connection.prepareStatement(SELECT_UNAPPLIED_ALLY_KILLS);
                ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                results.add(
                        new KillLogEntry(
                                rs.getLong("id"),
                                rs.getLong("killer_steam_id"),
                                rs.getString("killer_username"),
                                rs.getLong("victim_steam_id"),
                                rs.getString("victim_username"),
                                rs.getInt("is_ally") != 0,
                                rs.getLong("created_at")));
            }
        }
        return results;
    }

    /**
     * @return true if the given killer has at least one other ally kill in the half-open window
     *     {@code [createdAt - windowMs, createdAt)}.
     */
    public boolean hasPrecedingAllyKill(
            long killerSteamId, String killerUsername, long createdAt, long windowMs)
            throws SQLException {
        try (PreparedStatement ps = connection.prepareStatement(EXISTS_PRECEDING_ALLY_KILL)) {
            ps.setLong(1, killerSteamId);
            ps.setString(2, killerUsername);
            ps.setLong(3, createdAt - windowMs);
            ps.setLong(4, createdAt);
            try (ResultSet rs = ps.executeQuery()) {
                return rs.next();
            }
        }
    }

    /**
     * Mark a specific kill row as having had its penalty decision applied, so the hourly processor
     * will skip it on subsequent runs.
     *
     * @return number of rows updated (0 if the id no longer exists)
     */
    public int markPenaltyApplied(long killId) throws SQLException {
        try (PreparedStatement ps = connection.prepareStatement(MARK_PENALTY_APPLIED)) {
            ps.setLong(1, killId);
            return ps.executeUpdate();
        }
    }

    /**
     * Load the {@code limit} most recent kill log entries, newest first. If {@code username} is
     * non-null, the user must appear on either the killer or victim side; same for {@code steamId}.
     * When both are given, the username/steamId pair must match together on the same side (so a
     * kill where alice (steamId 1) is killer matches {@code ("alice", 1L)}, but a kill where alice
     * killed someone with steamId 1 does not).
     */
    public List<KillLogEntry> loadRecentKillsFiltered(
            int limit, @Nullable String username, @Nullable Long steamId) throws SQLException {
        StringBuilder sql = new StringBuilder(SELECT_KILLS_BASE);
        List<Object> params = new ArrayList<>();
        String predicate = buildKillsPredicate(username, steamId, params);
        if (predicate != null) {
            sql.append(" WHERE ").append(predicate);
        }
        sql.append(ORDER_KILLS_NEWEST);
        params.add(limit);

        List<KillLogEntry> results = new ArrayList<>();
        try (PreparedStatement ps = connection.prepareStatement(sql.toString())) {
            bindParams(ps, params);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    results.add(
                            new KillLogEntry(
                                    rs.getLong("id"),
                                    rs.getLong("killer_steam_id"),
                                    rs.getString("killer_username"),
                                    rs.getLong("victim_steam_id"),
                                    rs.getString("victim_username"),
                                    rs.getInt("is_ally") != 0,
                                    rs.getLong("created_at")));
                }
            }
        }
        return results;
    }

    private List<SurvivorRecord> querySurvivors(
            String baseSelect,
            @Nullable String extraPredicate,
            String orderClause,
            @Nullable String username,
            @Nullable Long steamId)
            throws SQLException {
        StringBuilder sql = new StringBuilder(baseSelect);
        List<Object> params = new ArrayList<>();
        List<String> predicates = new ArrayList<>();
        if (extraPredicate != null) {
            predicates.add(extraPredicate);
        }
        if (username != null) {
            predicates.add("username = ?");
            params.add(username);
        }
        if (steamId != null) {
            predicates.add("steam_id = ?");
            params.add(steamId);
        }
        if (!predicates.isEmpty()) {
            sql.append(" WHERE ").append(String.join(" AND ", predicates));
        }
        sql.append(orderClause);

        List<SurvivorRecord> results = new ArrayList<>();
        try (PreparedStatement ps = connection.prepareStatement(sql.toString())) {
            bindParams(ps, params);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    results.add(
                            new SurvivorRecord(
                                    rs.getLong("id"),
                                    rs.getLong("steam_id"),
                                    rs.getString("username"),
                                    rs.getInt("day_count"),
                                    rs.getInt("kill_count"),
                                    rs.getInt("zombie_kills")));
                }
            }
        }
        return results;
    }

    private static @Nullable String buildKillsPredicate(
            @Nullable String username, @Nullable Long steamId, List<Object> params) {
        if (username == null && steamId == null) {
            return null;
        }
        // Each side (killer | victim) must match every supplied filter together, so a row qualifies
        // only when the same side carries both the username and the steamId we asked for.
        StringBuilder killerSide = new StringBuilder();
        StringBuilder victimSide = new StringBuilder();
        if (username != null) {
            killerSide.append("killer_username = ?");
            victimSide.append("victim_username = ?");
        }
        if (steamId != null) {
            if (killerSide.length() > 0) {
                killerSide.append(" AND ");
                victimSide.append(" AND ");
            }
            killerSide.append("killer_steam_id = ?");
            victimSide.append("victim_steam_id = ?");
        }
        // Bind order matches "(killerSide) OR (victimSide)" — username then steamId on each side.
        if (username != null) {
            params.add(username);
        }
        if (steamId != null) {
            params.add(steamId);
        }
        if (username != null) {
            params.add(username);
        }
        if (steamId != null) {
            params.add(steamId);
        }
        return "(" + killerSide + ") OR (" + victimSide + ")";
    }

    private static void bindParams(PreparedStatement ps, List<Object> params) throws SQLException {
        for (int i = 0; i < params.size(); i++) {
            Object value = params.get(i);
            if (value instanceof Long l) {
                ps.setLong(i + 1, l);
            } else if (value instanceof Integer n) {
                ps.setInt(i + 1, n);
            } else if (value instanceof String s) {
                ps.setString(i + 1, s);
            } else {
                ps.setObject(i + 1, value);
            }
        }
    }
}
