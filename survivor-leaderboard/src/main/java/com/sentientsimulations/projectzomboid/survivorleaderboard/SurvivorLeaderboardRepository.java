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

    private static final String DELETE_BY_USERNAME = "DELETE FROM survivors WHERE username = ?";

    private static final String DELETE_ALL = "DELETE FROM survivors";

    private static final String SELECT_ALL_ORDERED =
            "SELECT id, steam_id, username, day_count FROM survivors"
                    + " ORDER BY day_count DESC, username ASC";

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
     * @return number of rows deleted
     */
    public int deleteByUsername(String username) throws SQLException {
        try (PreparedStatement ps = connection.prepareStatement(DELETE_BY_USERNAME)) {
            ps.setString(1, username);
            return ps.executeUpdate();
        }
    }

    /**
     * @return number of rows deleted
     */
    public int deleteAll() throws SQLException {
        try (PreparedStatement ps = connection.prepareStatement(DELETE_ALL)) {
            return ps.executeUpdate();
        }
    }

    public List<SurvivorRecord> loadAllOrdered() throws SQLException {
        List<SurvivorRecord> results = new ArrayList<>();
        try (PreparedStatement ps = connection.prepareStatement(SELECT_ALL_ORDERED);
                ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                results.add(
                        new SurvivorRecord(
                                rs.getLong("id"),
                                rs.getLong("steam_id"),
                                rs.getString("username"),
                                rs.getInt("day_count")));
            }
        }
        return results;
    }
}
