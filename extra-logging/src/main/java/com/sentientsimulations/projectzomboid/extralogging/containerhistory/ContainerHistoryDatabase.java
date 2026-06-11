package com.sentientsimulations.projectzomboid.extralogging.containerhistory;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import java.io.File;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;
import java.sql.Statement;
import zombie.ZomboidFileSystem;

public final class ContainerHistoryDatabase {

    private static final String DB_FILENAME = "extra-logging-container-history.db";

    private static final String CREATE_TRANSFERS =
            """
            CREATE TABLE IF NOT EXISTS transfers (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                ts INTEGER NOT NULL,
                player_username TEXT NOT NULL,
                player_steam_id TEXT,
                item_type TEXT NOT NULL,
                item_name TEXT NOT NULL,
                item_id INTEGER NOT NULL,
                src_ref TEXT NOT NULL,
                dest_ref TEXT NOT NULL,
                uuid TEXT NOT NULL
            )""";

    private static final String CREATE_SRC_INDEX =
            "CREATE INDEX IF NOT EXISTS idx_transfers_src ON transfers(src_ref, ts DESC)";
    private static final String CREATE_DEST_INDEX =
            "CREATE INDEX IF NOT EXISTS idx_transfers_dest ON transfers(dest_ref, ts DESC)";

    private static Connection connection;

    private ContainerHistoryDatabase() {}

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
            stmt.execute(CREATE_TRANSFERS);
            stmt.execute(CREATE_SRC_INDEX);
            stmt.execute(CREATE_DEST_INDEX);
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
            LOGGER.warn("Error closing container-history db", e);
        }
        connection = null;
    }
}
