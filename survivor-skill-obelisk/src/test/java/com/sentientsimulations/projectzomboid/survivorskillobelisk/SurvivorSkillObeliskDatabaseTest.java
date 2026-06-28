package com.sentientsimulations.projectzomboid.survivorskillobelisk;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.io.File;
import java.sql.ResultSet;
import java.sql.Statement;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
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
        assertTrue(
                tables.contains("death_learned_songs"), "death_learned_songs table should exist");
        assertTrue(tables.contains("death_ambitions"), "death_ambitions table should exist");
    }

    @Test
    void insertDeathWithSkillsPersists() throws Exception {
        long deathId =
                repo.insertDeath(
                        1_000L, "alice", 42L, "Alice", "Smith", 12.5, 7, 100.0f, 200.0f, 0.0f);
        repo.insertSkill(deathId, "Woodwork", 3, 1234.5f);
        repo.insertSkill(deathId, "Aiming", 1, 50.0f);

        try (Statement stmt = db.getConnection().createStatement();
                ResultSet rs =
                        stmt.executeQuery(
                                "SELECT username, zombie_kills, hours_survived FROM deaths"
                                        + " WHERE id = "
                                        + deathId)) {
            assertTrue(rs.next());
            assertEquals("alice", rs.getString("username"));
            assertEquals(7, rs.getInt("zombie_kills"));
            assertEquals(12.5, rs.getDouble("hours_survived"), 0.0001);
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
    void insertSkillsWithZeroXpRoundTripThroughRepo() throws Exception {
        // DeathEventHandler now saves every perk in PerkFactory.PerkList, including ones the dead
        // character never earned anything in (level=baseline grant, xp=0). The recovery loop
        // iterates these rows to reset the live character's matching perks back to baseline. The
        // DB layer has to carry the xp=0 rows back out of listSkillsByDeath verbatim or the reset
        // never happens.
        long deathId = repo.insertDeath(4_000L, "dan", 11L, "Dan", "Park", 1.0, 0, 0f, 0f, 0f);
        repo.insertSkill(deathId, "Strength", 5, 0f);
        repo.insertSkill(deathId, "Fitness", 5, 0f);
        repo.insertSkill(deathId, "Running", 0, 0f);
        repo.insertSkill(deathId, "Cooking", 7, 12345.5f);

        List<SurvivorSkillObeliskRepository.SkillRow> rows = repo.listSkillsByDeath(deathId);
        assertEquals(4, rows.size(), "every inserted row should come back, including xp=0 ones");

        Map<String, SurvivorSkillObeliskRepository.SkillRow> byPerk = new HashMap<>();
        for (SurvivorSkillObeliskRepository.SkillRow row : rows) {
            byPerk.put(row.perk(), row);
        }
        assertEquals(0f, byPerk.get("Strength").xp());
        assertEquals(5, byPerk.get("Strength").level());
        assertEquals(0f, byPerk.get("Running").xp());
        assertEquals(0, byPerk.get("Running").level());
        assertEquals(12345.5f, byPerk.get("Cooking").xp());
        assertEquals(7, byPerk.get("Cooking").level());
    }

    @Test
    void insertProgressionChildRowsPersist() throws Exception {
        long deathId =
                repo.insertDeath(2_000L, "bob", 7L, "Bob", "Jones", 3.0, 1, 0.0f, 0.0f, 0.0f);

        repo.insertRecipe(deathId, "Make Stir Fry");
        repo.insertReadLiterature(deathId, "BookCarpentry1_translation_42");
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
                                "SELECT literature_title FROM death_read_literature"
                                        + " WHERE death_id = "
                                        + deathId)) {
            assertTrue(rs.next());
            assertEquals("BookCarpentry1_translation_42", rs.getString("literature_title"));
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

    @Test
    void insertLifestylesProgressionPersists() throws Exception {
        long deathId =
                repo.insertDeath(3_000L, "carol", 9L, "Carol", "Lee", 8.0, 4, 0.0f, 0.0f, 0.0f);

        repo.insertLearnedSong(deathId, "Piano", "ContextMenu_00_01_B", "Piano00LastPost");
        repo.insertLearnedSong(deathId, "Banjo", "ContextMenu_02_03_B", "Banjo02HappyBirthday");

        repo.insertAmbition(
                deathId,
                "LSTerminator",
                "Combat",
                false,
                true,
                false,
                new String[] {"5000", "pain", "0", null, null, null},
                new String[] {"137", "false", "0", null, null, null});
        repo.insertAmbition(
                deathId,
                "LSBladeMaster",
                "Combat",
                true,
                false,
                false,
                new String[] {"100", null, null, null, null, null},
                new String[] {"100", null, null, null, null, null});

        assertEquals(2, countChildren("death_learned_songs", deathId));
        assertEquals(2, countChildren("death_ambitions", deathId));

        try (Statement stmt = db.getConnection().createStatement();
                ResultSet rs =
                        stmt.executeQuery(
                                "SELECT instrument, song_name, sound FROM death_learned_songs"
                                        + " WHERE death_id = "
                                        + deathId
                                        + " ORDER BY id")) {
            assertTrue(rs.next());
            assertEquals("Piano", rs.getString("instrument"));
            assertEquals("ContextMenu_00_01_B", rs.getString("song_name"));
            assertEquals("Piano00LastPost", rs.getString("sound"));
            assertTrue(rs.next());
            assertEquals("Banjo", rs.getString("instrument"));
        }

        try (Statement stmt = db.getConnection().createStatement();
                ResultSet rs =
                        stmt.executeQuery(
                                "SELECT name, category, completed, is_active, goal1, goal2,"
                                        + " goal1_progress FROM death_ambitions"
                                        + " WHERE death_id = "
                                        + deathId
                                        + " ORDER BY id")) {
            assertTrue(rs.next());
            assertEquals("LSTerminator", rs.getString("name"));
            assertEquals("Combat", rs.getString("category"));
            assertEquals(0, rs.getInt("completed"));
            assertEquals(1, rs.getInt("is_active"));
            assertEquals("5000", rs.getString("goal1"));
            assertEquals("pain", rs.getString("goal2"));
            assertEquals("137", rs.getString("goal1_progress"));
            assertTrue(rs.next());
            assertEquals("LSBladeMaster", rs.getString("name"));
            assertEquals(1, rs.getInt("completed"));
        }
    }

    @Test
    void markObeliskNoneInsertsRowWithNoneType() throws Exception {
        repo.markObeliskNone(100, 200, 0, 5_000L);

        assertEquals("None", repo.findObeliskType(100, 200, 0));
        assertEquals(1, countObeliskRows());

        try (Statement stmt = db.getConnection().createStatement();
                ResultSet rs =
                        stmt.executeQuery(
                                "SELECT set_by_username, set_by_steam_id, set_ts"
                                        + " FROM obelisk_types WHERE x = 100 AND y = 200"
                                        + " AND z = 0")) {
            assertTrue(rs.next());
            assertEquals(null, rs.getString("set_by_username"));
            assertEquals(0L, rs.getLong("set_by_steam_id"));
            assertEquals(5_000L, rs.getLong("set_ts"));
        }
    }

    @Test
    void markObeliskNoneOverridesPriorAdminConfiguredType() throws Exception {
        // Admin configures the obelisk.
        repo.upsertObeliskType(100, 200, 0, "Strength", "admin", 42L, 1_000L);
        assertEquals("Strength", repo.findObeliskType(100, 200, 0));

        // Player picks it up + drops it back at the same spot — the placement event
        // resets the type to None and clears setter attribution.
        repo.markObeliskNone(100, 200, 0, 9_999L);

        assertEquals("None", repo.findObeliskType(100, 200, 0));
        try (Statement stmt = db.getConnection().createStatement();
                ResultSet rs =
                        stmt.executeQuery(
                                "SELECT set_by_username, set_by_steam_id, set_ts"
                                        + " FROM obelisk_types WHERE x = 100 AND y = 200"
                                        + " AND z = 0")) {
            assertTrue(rs.next());
            assertEquals(null, rs.getString("set_by_username"));
            assertEquals(0L, rs.getLong("set_by_steam_id"));
            assertEquals(9_999L, rs.getLong("set_ts"));
        }
    }

    @Test
    void deleteObeliskTypeRemovesRow() throws Exception {
        repo.upsertObeliskType(50, 60, 1, "Aiming", "admin", 42L, 1_000L);
        assertEquals(1, countObeliskRows());

        repo.deleteObeliskType(50, 60, 1);

        assertEquals(0, countObeliskRows());
        assertEquals(null, repo.findObeliskType(50, 60, 1));
    }

    @Test
    void deleteObeliskTypeIsNoOpWhenAbsent() throws Exception {
        // Removal-event handlers may fire redundantly (e.g. OnDestroyIsoThumpable +
        // OnObjectAboutToBeRemoved + OnTileRemoved for one sledgehammer hit). DELETE
        // against a missing row must not throw.
        repo.deleteObeliskType(0, 0, 0);
        assertEquals(0, countObeliskRows());
    }

    private int countObeliskRows() throws Exception {
        try (Statement stmt = db.getConnection().createStatement();
                ResultSet rs = stmt.executeQuery("SELECT COUNT(*) AS c FROM obelisk_types")) {
            assertTrue(rs.next());
            return rs.getInt("c");
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
