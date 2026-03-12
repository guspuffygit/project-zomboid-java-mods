package com.sentientsimulations.projectzomboid.mapmetasqlite;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;
import java.sql.Statement;

public class SafeHouseDatabase implements AutoCloseable {

    private static final String CREATE_SAFEHOUSES =
            """
            CREATE TABLE IF NOT EXISTS safehouses (
                x INTEGER NOT NULL,
                y INTEGER NOT NULL,
                w INTEGER NOT NULL,
                h INTEGER NOT NULL,
                owner TEXT NOT NULL,
                hit_points INTEGER NOT NULL DEFAULT 0,
                last_visited INTEGER NOT NULL,
                title TEXT NOT NULL DEFAULT 'Safehouse',
                datetime_created INTEGER NOT NULL,
                location TEXT,
                PRIMARY KEY (x, y)
            )""";

    private static final String CREATE_PLAYERS =
            """
            CREATE TABLE IF NOT EXISTS safehouse_players (
                safehouse_x INTEGER NOT NULL,
                safehouse_y INTEGER NOT NULL,
                username TEXT NOT NULL,
                PRIMARY KEY (safehouse_x, safehouse_y, username),
                FOREIGN KEY (safehouse_x, safehouse_y)
                    REFERENCES safehouses(x, y) ON DELETE CASCADE
            )""";

    private static final String CREATE_RESPAWNS =
            """
            CREATE TABLE IF NOT EXISTS safehouse_respawns (
                safehouse_x INTEGER NOT NULL,
                safehouse_y INTEGER NOT NULL,
                username TEXT NOT NULL,
                PRIMARY KEY (safehouse_x, safehouse_y, username),
                FOREIGN KEY (safehouse_x, safehouse_y)
                    REFERENCES safehouses(x, y) ON DELETE CASCADE
            )""";

    private final Connection connection;

    public SafeHouseDatabase(String dbPath) throws SQLException {
        this.connection = DriverManager.getConnection("jdbc:sqlite:" + dbPath);
        try (Statement stmt = connection.createStatement()) {
            stmt.execute("PRAGMA journal_mode=WAL");
            stmt.execute("PRAGMA foreign_keys=ON");
        }
        createTables();
    }

    private void createTables() throws SQLException {
        try (Statement stmt = connection.createStatement()) {
            stmt.execute(CREATE_SAFEHOUSES);
            stmt.execute(CREATE_PLAYERS);
            stmt.execute(CREATE_RESPAWNS);
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
