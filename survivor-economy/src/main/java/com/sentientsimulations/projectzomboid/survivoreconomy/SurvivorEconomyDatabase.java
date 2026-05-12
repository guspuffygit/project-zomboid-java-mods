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

    // ---- discord_links ----
    // Established Discord ↔ Steam ID associations. One Discord user may link multiple Steam IDs;
    // the PK enforces no duplicate (discord, steam) pairs. discord_username is informational and
    // refreshed on re-link. Source of truth — the beacon bot writes through this table via the
    // mod's HTTP API rather than persisting links locally.

    private static final String CREATE_DISCORD_LINKS =
            """
            CREATE TABLE IF NOT EXISTS discord_links (
                discord_id        TEXT    NOT NULL,
                discord_username  TEXT,
                steamid           INTEGER NOT NULL,
                created_at_ms     INTEGER NOT NULL,
                updated_at_ms     INTEGER NOT NULL,
                PRIMARY KEY (discord_id, steamid)
            )""";

    private static final String CREATE_DISCORD_LINKS_STEAMID_INDEX =
            "CREATE INDEX IF NOT EXISTS idx_discord_links_steamid" + " ON discord_links (steamid)";

    // ---- discord_link_codes ----
    // Pending claim codes. direction = 'INGAME' means the code was minted from a player's in-game
    // action and the consumer is a Discord user (steamid + username are set at creation, discord_id
    // + discord_username at consume). direction = 'DISCORD' is the inverse: discord_id +
    // discord_username at creation, steamid + username at consume. consumed_at_ms is null until
    // claimed; expired codes are kept for audit.

    private static final String CREATE_DISCORD_LINK_CODES =
            """
            CREATE TABLE IF NOT EXISTS discord_link_codes (
                code              TEXT    PRIMARY KEY,
                direction         TEXT    NOT NULL CHECK(direction IN ('INGAME','DISCORD')),
                discord_id        TEXT,
                discord_username  TEXT,
                steamid           INTEGER,
                username          TEXT,
                created_at_ms     INTEGER NOT NULL,
                expires_at_ms     INTEGER NOT NULL,
                consumed_at_ms    INTEGER
            )""";

    private static final String CREATE_DISCORD_LINK_CODES_DISCORD_INDEX =
            "CREATE INDEX IF NOT EXISTS idx_discord_link_codes_discord"
                    + " ON discord_link_codes (discord_id)";

    private static final String CREATE_DISCORD_LINK_CODES_STEAMID_INDEX =
            "CREATE INDEX IF NOT EXISTS idx_discord_link_codes_steamid"
                    + " ON discord_link_codes (steamid)";

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
            // discord_links
            stmt.execute(CREATE_DISCORD_LINKS);
            stmt.execute(CREATE_DISCORD_LINKS_STEAMID_INDEX);
            // discord_link_codes
            stmt.execute(CREATE_DISCORD_LINK_CODES);
            stmt.execute(CREATE_DISCORD_LINK_CODES_DISCORD_INDEX);
            stmt.execute(CREATE_DISCORD_LINK_CODES_STEAMID_INDEX);
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
