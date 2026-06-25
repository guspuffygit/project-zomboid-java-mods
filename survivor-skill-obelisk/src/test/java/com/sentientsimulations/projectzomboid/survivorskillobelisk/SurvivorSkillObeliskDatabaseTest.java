package com.sentientsimulations.projectzomboid.survivorskillobelisk;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.io.File;
import java.sql.ResultSet;
import java.sql.Statement;
import java.util.HashSet;
import java.util.Set;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

/**
 * Integration tests for the Survivor Skill Obelisk schema bootstrap and insert path. Uses a real
 * SQLite DB in a temp dir, matching the survivor-leaderboard test convention.
 */
class SurvivorSkillObeliskDatabaseTest {

    @TempDir File tempDir;

    private SurvivorSkillObeliskDatabase db;
    private SurvivorSkillObeliskRepository repo;

    @BeforeEach
    void setUp() throws Exception {
        db =
                new SurvivorSkillObeliskDatabase(
                        new File(tempDir, "survivor_skill_obelisk.db").getAbsolutePath());
        repo = new SurvivorSkillObeliskRepository(db.getConnection());
    }

    @AfterEach
    void tearDown() throws Exception {
        if (db != null) {
            db.close();
        }
    }

    @Test
    void schemaBootstrapsExpectedTables() throws Exception {
        Set<String> tables = new HashSet<>();
        try (Statement stmt = db.getConnection().createStatement();
                ResultSet rs =
                        stmt.executeQuery("SELECT name FROM sqlite_master WHERE type='table'")) {
            while (rs.next()) {
                tables.add(rs.getString("name"));
            }
        }
        assertTrue(tables.contains("deaths"), "deaths table should exist");
        assertTrue(tables.contains("death_skills"), "death_skills table should exist");
        assertTrue(tables.contains("death_recipes"), "death_recipes table should exist");
        assertTrue(
                tables.contains("death_read_literature"),
                "death_read_literature table should exist");
        assertTrue(
                tables.contains("death_read_print_media"),
                "death_read_print_media table should exist");
        assertTrue(
                tables.contains("death_watched_media"), "death_watched_media table should exist");
    }

    @Test
    void insertDeathWithSkillsPersists() throws Exception {
        long deathId =
                repo.insertDeath(
                        1_000L, "alice", 42L, "Alice", "Smith", 12.5f, 7, 100.0f, 200.0f, 0.0f);
        repo.insertSkill(deathId, "Woodwork", 3, 1234.5f);
        repo.insertSkill(deathId, "Aiming", 1, 50.0f);

        try (Statement stmt = db.getConnection().createStatement();
                ResultSet rs =
                        stmt.executeQuery(
                                "SELECT username, zombie_kills FROM deaths WHERE id = "
                                        + deathId)) {
            assertTrue(rs.next());
            assertEquals("alice", rs.getString("username"));
            assertEquals(7, rs.getInt("zombie_kills"));
        }

        try (Statement stmt = db.getConnection().createStatement();
                ResultSet rs =
                        stmt.executeQuery(
                                "SELECT COUNT(*) AS c FROM death_skills WHERE death_id = "
                                        + deathId)) {
            assertTrue(rs.next());
            assertEquals(2, rs.getInt("c"));
        }
    }

    @Test
    void insertProgressionChildRowsPersist() throws Exception {
        long deathId =
                repo.insertDeath(2_000L, "bob", 7L, "Bob", "Jones", 3.0f, 1, 0.0f, 0.0f, 0.0f);

        repo.insertRecipe(deathId, "Make Stir Fry");
        repo.insertReadLiterature(deathId, "Base.BookCarpentry1", 120);
        repo.insertReadPrintMedia(deathId, "Base.Newspaper_Dispatch_Day1");
        repo.insertWatchedMedia(
                deathId, "TapeHTV1", 5, "Home-VHS", 1, "Exercise Tape", 2, 3, false);

        assertEquals(1, countChildren("death_recipes", deathId));
        assertEquals(1, countChildren("death_read_literature", deathId));
        assertEquals(1, countChildren("death_read_print_media", deathId));
        assertEquals(1, countChildren("death_watched_media", deathId));

        try (Statement stmt = db.getConnection().createStatement();
                ResultSet rs =
                        stmt.executeQuery(
                                "SELECT pages_read FROM death_read_literature WHERE death_id = "
                                        + deathId)) {
            assertTrue(rs.next());
            assertEquals(120, rs.getInt("pages_read"));
        }

        try (Statement stmt = db.getConnection().createStatement();
                ResultSet rs =
                        stmt.executeQuery(
                                "SELECT lines_watched, line_count, fully_watched"
                                        + " FROM death_watched_media WHERE death_id = "
                                        + deathId)) {
            assertTrue(rs.next());
            assertEquals(2, rs.getInt("lines_watched"));
            assertEquals(3, rs.getInt("line_count"));
            assertEquals(0, rs.getInt("fully_watched"));
        }
    }

    private int countChildren(String table, long deathId) throws Exception {
        try (Statement stmt = db.getConnection().createStatement();
                ResultSet rs =
                        stmt.executeQuery(
                                "SELECT COUNT(*) AS c FROM "
                                        + table
                                        + " WHERE death_id = "
                                        + deathId)) {
            assertTrue(rs.next());
            return rs.getInt("c");
        }
    }
}
