package com.sentientsimulations.projectzomboid.avcs.safehouse;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;
import java.sql.Statement;

public class SafehouseAccessDatabase implements AutoCloseable {

    private static final String CREATE_SAFEHOUSE_ACCESS =
            """
            CREATE TABLE IF NOT EXISTS safehouse_access (
                id                INTEGER PRIMARY KEY AUTOINCREMENT,
                owner_username    TEXT NOT NULL,
                allowed_username  TEXT NOT NULL,
                UNIQUE(owner_username, allowed_username)
            )""";

    private final Connection connection;

    public SafehouseAccessDatabase(String dbPath) throws SQLException {
        this.connection = DriverManager.getConnection("jdbc:sqlite:" + dbPath);
        try (Statement stmt = connection.createStatement()) {
            stmt.execute("PRAGMA journal_mode=WAL");
            stmt.execute("PRAGMA foreign_keys=ON");
        }
        createTables();
    }

    private void createTables() throws SQLException {
        try (Statement stmt = connection.createStatement()) {
            stmt.execute(CREATE_SAFEHOUSE_ACCESS);
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
