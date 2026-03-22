package com.sentientsimulations.projectzomboid.zonemarker;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;
import java.sql.Statement;

public class ZoneMarkerDatabase implements AutoCloseable {

    private static final String CREATE_CATEGORIES =
            """
            CREATE TABLE IF NOT EXISTS categories (
                id   INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL UNIQUE,
                r    REAL NOT NULL,
                g    REAL NOT NULL,
                b    REAL NOT NULL,
                a    REAL NOT NULL DEFAULT 1.0
            )""";

    private static final String CREATE_ZONES =
            """
            CREATE TABLE IF NOT EXISTS zones (
                id          INTEGER PRIMARY KEY AUTOINCREMENT,
                category_id INTEGER NOT NULL,
                x_start     REAL NOT NULL,
                y_start     REAL NOT NULL,
                x_end       REAL NOT NULL,
                y_end       REAL NOT NULL,
                region      TEXT NOT NULL,
                FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE CASCADE
            )""";

    private final Connection connection;

    public ZoneMarkerDatabase(String dbPath) throws SQLException {
        this.connection = DriverManager.getConnection("jdbc:sqlite:" + dbPath);
        try (Statement stmt = connection.createStatement()) {
            stmt.execute("PRAGMA journal_mode=WAL");
            stmt.execute("PRAGMA foreign_keys=ON");
        }
        createTables();
    }

    private void createTables() throws SQLException {
        try (Statement stmt = connection.createStatement()) {
            stmt.execute(CREATE_CATEGORIES);
            stmt.execute(CREATE_ZONES);
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
