package com.sentientsimulations.projectzomboid.survivoreconomy;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Reads and writes the {@code economy_balance} table — a per-(username, steamId, currency)
 * denormalized view of the running balance. Updated in lockstep with {@code economy_transactions}
 * inside the same SQL transaction, so the transaction log remains the source of truth and these
 * rows can never drift from {@code SUM(amount)}.
 */
public class SurvivorEconomyBalanceRepository {

    private static final String UPSERT_BALANCE =
            "INSERT INTO economy_balance"
                    + " (player_username, player_steamid, currency, balance, updated_at_ms)"
                    + " VALUES (?, ?, ?, ?, ?)"
                    + " ON CONFLICT(player_username, player_steamid, currency) DO UPDATE SET"
                    + " balance = balance + excluded.balance,"
                    + " updated_at_ms = excluded.updated_at_ms";

    private static final String SELECT_BALANCES =
            "SELECT currency, balance FROM economy_balance"
                    + " WHERE player_username = ? AND player_steamid = ?";

    private final Connection connection;

    public SurvivorEconomyBalanceRepository(Connection connection) {
        this.connection = connection;
    }

    /**
     * Apply a signed delta to the player's balance for {@code currency}, creating the row on first
     * touch. Designed to be called from inside the same SQL transaction that inserts the matching
     * {@code economy_transactions} row.
     */
    public void applyDelta(String username, long steamId, String currency, double delta, long nowMs)
            throws SQLException {
        try (PreparedStatement ps = connection.prepareStatement(UPSERT_BALANCE)) {
            ps.setString(1, username);
            ps.setLong(2, steamId);
            ps.setString(3, currency);
            ps.setDouble(4, delta);
            ps.setLong(5, nowMs);
            ps.executeUpdate();
        }
    }

    /**
     * Load every balance row for the player, keyed by currency. Returns an empty map if the player
     * has never had a transaction recorded.
     */
    public Map<String, Double> getBalances(String username, long steamId) throws SQLException {
        Map<String, Double> balances = new LinkedHashMap<>();
        try (PreparedStatement ps = connection.prepareStatement(SELECT_BALANCES)) {
            ps.setString(1, username);
            ps.setLong(2, steamId);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    balances.put(rs.getString("currency"), rs.getDouble("balance"));
                }
            }
        }
        return balances;
    }
}
