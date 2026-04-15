package com.sentientsimulations.projectzomboid.survivorleaderboard;

import com.sentientsimulations.projectzomboid.survivorleaderboard.records.SurvivorRecord;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.ArrayList;
import java.util.List;

public class SurvivorLeaderboardRepository {

    private static final String INSERT_SURVIVOR =
            "INSERT OR IGNORE INTO survivors (steam_id, username, day_count) VALUES (?, ?, 0)";

    private static final String UPDATE_DAY_COUNT =
            "UPDATE survivors SET day_count = ? WHERE steam_id = ? AND username = ?";

    private static final String INCREMENT_KILL_COUNT =
            "UPDATE survivors SET kill_count = kill_count + 1 WHERE steam_id = ? AND username = ?";

    private static final String RESET_KILL_COUNT =
            "UPDATE survivors SET kill_count = 0 WHERE steam_id = ? AND username = ?";

    private static final String DELETE_BY_STEAM_ID = "DELETE FROM survivors WHERE steam_id = ?";

    private static final String SELECT_ALL_ORDERED =
            "SELECT id, steam_id, username, day_count, kill_count FROM survivors"
                    + " ORDER BY day_count DESC, username ASC";

    private static final String SELECT_ALL_ORDERED_BY_KILLS =
            "SELECT id, steam_id, username, day_count, kill_count FROM survivors"
                    + " ORDER BY kill_count DESC, username ASC";

    private static final String SELECT_DISTINCT_STEAM_IDS =
            "SELECT DISTINCT steam_id FROM survivors";

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
    public boolean incrementKillCount(long steamId, String username) throws SQLException {
        try (PreparedStatement ps = connection.prepareStatement(INCREMENT_KILL_COUNT)) {
            ps.setLong(1, steamId);
            ps.setString(2, username);
            return ps.executeUpdate() > 0;
        }
    }

    /**
     * @return true if a row was updated
     */
    public boolean resetKillCount(long steamId, String username) throws SQLException {
        try (PreparedStatement ps = connection.prepareStatement(RESET_KILL_COUNT)) {
            ps.setLong(1, steamId);
            ps.setString(2, username);
            return ps.executeUpdate() > 0;
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

    public List<SurvivorRecord> loadAllOrdered() throws SQLException {
        return loadAllOrdered(SELECT_ALL_ORDERED);
    }

    public List<SurvivorRecord> loadAllOrderedByKills() throws SQLException {
        return loadAllOrdered(SELECT_ALL_ORDERED_BY_KILLS);
    }

    private List<SurvivorRecord> loadAllOrdered(String query) throws SQLException {
        List<SurvivorRecord> results = new ArrayList<>();
        try (PreparedStatement ps = connection.prepareStatement(query);
                ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                results.add(
                        new SurvivorRecord(
                                rs.getLong("id"),
                                rs.getLong("steam_id"),
                                rs.getString("username"),
                                rs.getInt("day_count"),
                                rs.getInt("kill_count")));
            }
        }
        return results;
    }
}
