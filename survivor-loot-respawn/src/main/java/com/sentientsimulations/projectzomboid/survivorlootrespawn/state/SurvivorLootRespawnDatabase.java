package com.sentientsimulations.projectzomboid.survivorlootrespawn.state;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import java.io.File;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;
import java.sql.Statement;
import zombie.ZomboidFileSystem;

public final class SurvivorLootRespawnDatabase {

    private static final String DB_FILENAME = "survivor-loot-respawn.db";

    private static final String CREATE_CONTAINER_LOOT_STATE =
            """
            CREATE TABLE IF NOT EXISTS container_loot_state (
                square_x         INTEGER NOT NULL,
                square_y         INTEGER NOT NULL,
                square_z         INTEGER NOT NULL,
                container_type   TEXT    NOT NULL,
                container_index  INTEGER NOT NULL,
                looted_game_hours       REAL    NOT NULL,
                item_count              INTEGER NOT NULL,
                respawn_queued_at_hours REAL,
                last_username           TEXT,
                last_steam_id           TEXT,
                PRIMARY KEY (square_x, square_y, square_z, container_type, container_index)
            ) WITHOUT ROWID""";

    private static final String CREATE_QUEUED_INDEX =
            """
            CREATE INDEX IF NOT EXISTS idx_container_loot_state_queued
                ON container_loot_state(square_x, square_y, square_z)
                WHERE respawn_queued_at_hours IS NOT NULL""";

    private static Connection connection;

    private SurvivorLootRespawnDatabase() {}

    public static synchronized Connection getConnection() throws SQLException {
        if (connection != null && !connection.isClosed()) {
            return connection;
        }

        File dbFile = ZomboidFileSystem.instance.getFileInCurrentSave(DB_FILENAME);
        String url = "jdbc:sqlite:" + dbFile.getAbsolutePath();
        LOGGER.info("Opening survivor-loot-respawn SQLite db at {}", dbFile.getAbsolutePath());

        connection = DriverManager.getConnection(url);
        try (Statement stmt = connection.createStatement()) {
            stmt.execute("PRAGMA journal_mode=WAL");
            stmt.execute("PRAGMA synchronous=NORMAL");
            stmt.execute(CREATE_CONTAINER_LOOT_STATE);
            stmt.execute(CREATE_QUEUED_INDEX);
        }
        return connection;
    }

    public static synchronized void close() {
        if (connection == null) {
            return;
        }
        try {
            if (!connection.isClosed()) {
                connection.close();
            }
        } catch (SQLException e) {
            LOGGER.warn("Error closing survivor-loot-respawn db", e);
        }
        connection = null;
    }
}
