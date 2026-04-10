package com.sentientsimulations.projectzomboid.survivorleaderboard;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;
import java.sql.Statement;

public class SurvivorLeaderboardDatabase implements AutoCloseable {

    private static final String CREATE_SURVIVORS =
            """
            CREATE TABLE IF NOT EXISTS survivors (
                id         INTEGER PRIMARY KEY AUTOINCREMENT,
                steam_id   INTEGER NOT NULL,
                username   TEXT NOT NULL,
                day_count  INTEGER NOT NULL DEFAULT 0,
                UNIQUE (steam_id, username)
            )""";

    private final Connection connection;

    public SurvivorLeaderboardDatabase(String dbPath) throws SQLException {
        this.connection = DriverManager.getConnection("jdbc:sqlite:" + dbPath);
        try (Statement stmt = connection.createStatement()) {
            stmt.execute("PRAGMA journal_mode=WAL");
            stmt.execute("PRAGMA foreign_keys=ON");
        }
        createTables();
    }

    private void createTables() throws SQLException {
        try (Statement stmt = connection.createStatement()) {
            stmt.execute(CREATE_SURVIVORS);
        }
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
