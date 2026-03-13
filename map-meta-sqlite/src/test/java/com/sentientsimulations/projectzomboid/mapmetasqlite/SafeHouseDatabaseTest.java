package com.sentientsimulations.projectzomboid.mapmetasqlite;

import static org.junit.jupiter.api.Assertions.*;

import java.io.File;
import java.sql.ResultSet;
import java.sql.Statement;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

class SafeHouseDatabaseTest {

    @TempDir File tempDir;
    private SafeHouseDatabase database;

    @BeforeEach
    void setUp() throws Exception {
        database = new SafeHouseDatabase(new File(tempDir, "map_meta.db").getAbsolutePath());
    }

    @AfterEach
    void tearDown() throws Exception {
        database.close();
    }

    @Test
    void createsAllTables() throws Exception {
        try (Statement stmt = database.getConnection().createStatement();
                ResultSet rs =
                        stmt.executeQuery(
                                "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")) {
            assertTrue(rs.next());
            assertEquals("safehouse_players", rs.getString("name"));
            assertTrue(rs.next());
            assertEquals("safehouse_respawns", rs.getString("name"));
            assertTrue(rs.next());
            assertEquals("safehouses", rs.getString("name"));
            assertFalse(rs.next());
        }
    }

    @Test
    void enablesWalMode() throws Exception {
        try (Statement stmt = database.getConnection().createStatement();
                ResultSet rs = stmt.executeQuery("PRAGMA journal_mode")) {
            assertTrue(rs.next());
            assertEquals("wal", rs.getString(1));
        }
    }

    @Test
    void enablesForeignKeys() throws Exception {
        try (Statement stmt = database.getConnection().createStatement();
                ResultSet rs = stmt.executeQuery("PRAGMA foreign_keys")) {
            assertTrue(rs.next());
            assertEquals(1, rs.getInt(1));
        }
    }

    @Test
    void connectionIsOpenAfterInit() throws Exception {
        assertFalse(database.getConnection().isClosed());
    }

    @Test
    void closeClosesConnection() throws Exception {
        database.close();
        assertTrue(database.getConnection().isClosed());
    }

    @Test
    void doubleCloseIsSafe() throws Exception {
        database.close();
        assertDoesNotThrow(() -> database.close());
    }

    @Test
    void safehousesTableHasCorrectColumns() throws Exception {
        try (Statement stmt = database.getConnection().createStatement();
                ResultSet rs = stmt.executeQuery("PRAGMA table_info(safehouses)")) {
            assertColumn(rs, "x", "INTEGER", true);
            assertColumn(rs, "y", "INTEGER", true);
            assertColumn(rs, "w", "INTEGER", true);
            assertColumn(rs, "h", "INTEGER", true);
            assertColumn(rs, "owner", "TEXT", true);
            assertColumn(rs, "hit_points", "INTEGER", true);
            assertColumn(rs, "last_visited", "INTEGER", true);
            assertColumn(rs, "title", "TEXT", true);
            assertColumn(rs, "datetime_created", "INTEGER", true);
            assertColumn(rs, "location", "TEXT", false);
            assertFalse(rs.next());
        }
    }

    private void assertColumn(ResultSet rs, String name, String type, boolean notNull)
            throws Exception {
        assertTrue(rs.next(), "Expected column: " + name);
        assertEquals(name, rs.getString("name"));
        assertEquals(type, rs.getString("type"));
        assertEquals(notNull ? 1 : 0, rs.getInt("notnull"));
    }
}
