package com.sentientsimulations.projectzomboid.survivoreconomy;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;

public class SurvivorEconomyDatabase implements AutoCloseable {

    // ---- economy_transactions ----
    // Double-entry style: one row per side. Two-sided events (transfers, fees, taxes,
    // vending purchases) emit a FROM row and a TO row that share the same event_id.
    // Single-sided events (system grants, admin creates, withdraw/deposit) use SOLE.
    // amount is signed from this row's player perspective: + means gained, - means lost.

    private static final String CREATE_TRANSACTIONS =
            """
            CREATE TABLE IF NOT EXISTS economy_transactions (
                id              INTEGER PRIMARY KEY AUTOINCREMENT,
                event_id        TEXT    NOT NULL,
                event_role      TEXT    NOT NULL CHECK(event_role IN ('SOLE','FROM','TO')),
                timestamp_ms    INTEGER NOT NULL,
                type            TEXT    NOT NULL,
                parent_event_id TEXT,
                reason          TEXT,
                player_username TEXT    NOT NULL,
                player_steamid  INTEGER NOT NULL,
                currency        TEXT    NOT NULL,
                amount          REAL    NOT NULL,
                item_id         TEXT,
                item_qty        INTEGER,
                vehicle_id      TEXT,
                shop_category   TEXT,
                wallet_id       TEXT,
                account_number  TEXT,
                death_x         REAL,
                death_y         REAL,
                death_z         REAL
            )""";

    private static final String CREATE_TRANSACTIONS_PLAYER_INDEX =
            "CREATE INDEX IF NOT EXISTS idx_econ_tx_player"
                    + " ON economy_transactions (player_username, player_steamid, timestamp_ms)";

    private static final String CREATE_TRANSACTIONS_EVENT_INDEX =
            "CREATE INDEX IF NOT EXISTS idx_econ_tx_event ON economy_transactions (event_id)";

    private static final String CREATE_TRANSACTIONS_TYPE_INDEX =
            "CREATE INDEX IF NOT EXISTS idx_econ_tx_type"
                    + " ON economy_transactions (type, timestamp_ms)";

    private static final String CREATE_TRANSACTIONS_PARENT_INDEX =
            "CREATE INDEX IF NOT EXISTS idx_econ_tx_parent"
                    + " ON economy_transactions (parent_event_id)";

    // ---- economy_player_state ----
    // Per-(username, steamId) counters that drive periodic events like the hourly paycheck.
    // online_hours is the attendance counter: bumped each EveryHoursEvent and decremented by
    // HoursUntilPaycheck when a paycheck fires (so the remainder carries forward).

    private static final String CREATE_PLAYER_STATE =
            """
            CREATE TABLE IF NOT EXISTS economy_player_state (
                player_username   TEXT    NOT NULL,
                player_steamid    INTEGER NOT NULL,
                online_hours      INTEGER NOT NULL DEFAULT 0,
                last_clock_in_ms  INTEGER,
                PRIMARY KEY (player_username, player_steamid)
            )""";

    private static final String CREATE_PLAYER_STATE_STEAMID_INDEX =
            "CREATE INDEX IF NOT EXISTS idx_econ_ps_steamid"
                    + " ON economy_player_state (player_steamid)";

    // ---- economy_balance ----
    // Per-(username, steamId, currency) running balance, kept in lockstep with
    // economy_transactions. Every row written to economy_transactions is paired with an
    // upsert here in the same SQL transaction, so SUM(amount) over economy_transactions
    // and SELECT balance from this table always agree. The transaction log remains the
    // source of truth; this table is a denormalized view that lets clients read a single
    // row without scanning history.

    private static final String CREATE_BALANCE =
            """
            CREATE TABLE IF NOT EXISTS economy_balance (
                player_username TEXT    NOT NULL,
                player_steamid  INTEGER NOT NULL,
                currency        TEXT    NOT NULL,
                balance         REAL    NOT NULL DEFAULT 0,
                updated_at_ms   INTEGER NOT NULL,
                PRIMARY KEY (player_username, player_steamid, currency)
            )""";

    private static final String CREATE_BALANCE_STEAMID_INDEX =
            "CREATE INDEX IF NOT EXISTS idx_econ_bal_steamid"
                    + " ON economy_balance (player_steamid)";

    private final Connection connection;

    public SurvivorEconomyDatabase(String dbPath) throws SQLException {
        this.connection = DriverManager.getConnection("jdbc:sqlite:" + dbPath);
        try (Statement stmt = connection.createStatement()) {
            stmt.execute("PRAGMA journal_mode=WAL");
            stmt.execute("PRAGMA foreign_keys=ON");
        }
        createTables();
        migrateSchema();
    }

    private void createTables() throws SQLException {
        try (Statement stmt = connection.createStatement()) {
            // economy_transactions
            stmt.execute(CREATE_TRANSACTIONS);
            stmt.execute(CREATE_TRANSACTIONS_PLAYER_INDEX);
            stmt.execute(CREATE_TRANSACTIONS_EVENT_INDEX);
            stmt.execute(CREATE_TRANSACTIONS_TYPE_INDEX);
            stmt.execute(CREATE_TRANSACTIONS_PARENT_INDEX);
            // economy_player_state
            stmt.execute(CREATE_PLAYER_STATE);
            stmt.execute(CREATE_PLAYER_STATE_STEAMID_INDEX);
            // economy_balance
            stmt.execute(CREATE_BALANCE);
            stmt.execute(CREATE_BALANCE_STEAMID_INDEX);
        }
    }

    /**
     * Apply additive schema changes that cannot be expressed as {@code CREATE TABLE IF NOT EXISTS}.
     * Add ALTER TABLE statements here as the schema evolves; use {@link #hasColumn} to make each
     * step idempotent.
     */
    private void migrateSchema() throws SQLException {
        // No migrations yet.
    }

    @SuppressWarnings("unused")
    private boolean hasColumn(String table, String column) throws SQLException {
        try (Statement stmt = connection.createStatement();
                ResultSet rs = stmt.executeQuery("PRAGMA table_info(" + table + ")")) {
            while (rs.next()) {
                if (column.equals(rs.getString("name"))) {
                    return true;
                }
            }
        }
        return false;
    }

    public Connection getConnection() {
        return connection;
    }

    @Override
    public void close() throws SQLException {
        if (connection != null && !connection.isClosed()) {
            connection.close();
        }
    }
}
