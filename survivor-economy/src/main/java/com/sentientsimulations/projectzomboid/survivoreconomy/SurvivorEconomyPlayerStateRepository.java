package com.sentientsimulations.projectzomboid.survivoreconomy;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;

/**
 * Reads and writes the {@code economy_player_state} table — small per-(username, steamId) counters
 * used by periodic events. Currently tracks {@code online_hours} for the paycheck mechanic.
 */
public class SurvivorEconomyPlayerStateRepository {

    private static final String SELECT_HOURS =
            "SELECT online_hours FROM economy_player_state"
                    + " WHERE player_username = ? AND player_steamid = ?";

    private static final String UPSERT_HOURS =
            "INSERT INTO economy_player_state"
                    + " (player_username, player_steamid, online_hours, last_clock_in_ms)"
                    + " VALUES (?, ?, ?, ?)"
                    + " ON CONFLICT(player_username, player_steamid) DO UPDATE SET"
                    + " online_hours = excluded.online_hours,"
                    + " last_clock_in_ms = excluded.last_clock_in_ms";

    private final Connection connection;

    public SurvivorEconomyPlayerStateRepository(Connection connection) {
        this.connection = connection;
    }

    /** Current online_hours for the player, or 0 if no row exists yet. */
    public int getOnlineHours(String username, long steamId) throws SQLException {
        try (PreparedStatement ps = connection.prepareStatement(SELECT_HOURS)) {
            ps.setString(1, username);
            ps.setLong(2, steamId);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    return rs.getInt("online_hours");
                }
            }
        }
        return 0;
    }

    /** Set online_hours to {@code hours} and stamp last_clock_in_ms. Upserts on first call. */
    public void setOnlineHours(String username, long steamId, int hours, long lastClockInMs)
            throws SQLException {
        try (PreparedStatement ps = connection.prepareStatement(UPSERT_HOURS)) {
            ps.setString(1, username);
            ps.setLong(2, steamId);
            ps.setInt(3, hours);
            ps.setLong(4, lastClockInMs);
            ps.executeUpdate();
        }
    }
}
