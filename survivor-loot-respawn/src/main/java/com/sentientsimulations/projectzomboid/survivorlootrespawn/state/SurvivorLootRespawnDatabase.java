package com.sentientsimulations.projectzomboid.survivorlootrespawn.state;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import java.io.File;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import zombie.ZomboidFileSystem;

public final class SurvivorLootRespawnDatabase {

    private static final String DB_FILENAME = "survivor_loot_respawn.db";

    private static final String CREATE_CONTAINER_LOOT_STATE =
            """
            CREATE TABLE IF NOT EXISTS container_loot_state (
                square_x         INTEGER NOT NULL,
                square_y         INTEGER NOT NULL,
                square_z         INTEGER NOT NULL,
                container_type   TEXT    NOT NULL,
                container_index  INTEGER NOT NULL,
                looted_game_hours       REAL    NOT NULL,
                respawn_queued_at_hours REAL,
                fill_added_nothing_count INTEGER NOT NULL DEFAULT 0,
                PRIMARY KEY (square_x, square_y, square_z, container_type, container_index)
            ) WITHOUT ROWID""";

    private static final String CREATE_QUEUED_INDEX =
            """
            CREATE INDEX IF NOT EXISTS idx_container_loot_state_queued
                ON container_loot_state(square_x, square_y, square_z)
                WHERE respawn_queued_at_hours IS NOT NULL""";

    private static final String ADD_FILL_ADDED_NOTHING_COUNT_COLUMN =
            "ALTER TABLE container_loot_state"
                    + " ADD COLUMN fill_added_nothing_count INTEGER NOT NULL DEFAULT 0";

    private static Connection connection;
    private static ExecutorService executor;

    private SurvivorLootRespawnDatabase() {}

    public static synchronized void submit(Runnable task) {
        if (executor == null) {
            executor =
                    Executors.newSingleThreadExecutor(
                            r -> {
                                Thread t = new Thread(r, "SurvivorLootRespawn-DB");
                                t.setDaemon(true);
                                return t;
                            });
        }
        executor.execute(
                () -> {
                    try {
                        task.run();
                    } catch (Throwable e) {
                        LOGGER.error("(SurvivorLootRespawn) DB executor task failed", e);
                    }
                });
    }

    public static synchronized Connection getConnection() throws SQLException {
        if (connection != null && !connection.isClosed()) {
            return connection;
        }

        File dbFile = ZomboidFileSystem.instance.getFileInCurrentSave(DB_FILENAME);
        String url = "jdbc:sqlite:" + dbFile.getAbsolutePath();

        connection = DriverManager.getConnection(url);
        try (Statement stmt = connection.createStatement()) {
            stmt.execute("PRAGMA journal_mode=WAL");
            stmt.execute("PRAGMA synchronous=NORMAL");
            stmt.execute(CREATE_CONTAINER_LOOT_STATE);
            stmt.execute(CREATE_QUEUED_INDEX);
            migrateAddFillAddedNothingCountIfMissing(stmt);
        }
        return connection;
    }

    private static void migrateAddFillAddedNothingCountIfMissing(Statement stmt)
            throws SQLException {
        boolean exists = false;
        try (ResultSet rs = stmt.executeQuery("PRAGMA table_info(container_loot_state)")) {
            while (rs.next()) {
                if ("fill_added_nothing_count".equals(rs.getString("name"))) {
                    exists = true;
                    break;
                }
            }
        }
        if (!exists) {
            stmt.execute(ADD_FILL_ADDED_NOTHING_COUNT_COLUMN);
            LOGGER.info(
                    "(SurvivorLootRespawn) Migrated container_loot_state: added"
                            + " fill_added_nothing_count column.");
        }
    }

    public static synchronized void close() {
        if (executor != null) {
            executor.shutdown();
            executor = null;
        }
        if (connection == null) {
            return;
        }
        try {
            if (!connection.isClosed()) {
                connection.close();
            }
        } catch (SQLException e) {
            LOGGER.warn("(SurvivorLootRespawn) Error closing db", e);
        }
        connection = null;
    }
}
