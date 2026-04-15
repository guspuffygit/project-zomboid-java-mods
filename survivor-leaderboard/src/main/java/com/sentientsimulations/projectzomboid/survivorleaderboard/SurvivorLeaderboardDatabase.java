package com.sentientsimulations.projectzomboid.survivorleaderboard;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
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
                kill_count INTEGER NOT NULL DEFAULT 0,
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
        migrateSchema();
    }

    private void createTables() throws SQLException {
        try (Statement stmt = connection.createStatement()) {
            stmt.execute(CREATE_SURVIVORS);
        }
    }

    private void migrateSchema() throws SQLException {
        if (!hasColumn("survivors", "kill_count")) {
            try (Statement stmt = connection.createStatement()) {
                stmt.execute(
                        "ALTER TABLE survivors ADD COLUMN kill_count INTEGER NOT NULL DEFAULT 0");
            }
        }
    }

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
