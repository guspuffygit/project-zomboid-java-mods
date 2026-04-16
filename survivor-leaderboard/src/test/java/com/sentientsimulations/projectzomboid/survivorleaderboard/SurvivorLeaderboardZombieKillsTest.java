package com.sentientsimulations.projectzomboid.survivorleaderboard;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.sentientsimulations.projectzomboid.survivorleaderboard.records.SurvivorRecord;
import java.io.File;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.Statement;
import java.util.List;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

class SurvivorLeaderboardZombieKillsTest {

    @TempDir File tempDir;

    private SurvivorLeaderboardDatabase db;
    private SurvivorLeaderboardRepository repo;

    @BeforeEach
    void setUp() throws Exception {
        db =
                new SurvivorLeaderboardDatabase(
                        new File(tempDir, "survivor_leaderboard.db").getAbsolutePath());
        repo = new SurvivorLeaderboardRepository(db.getConnection());

        // alice: 30 zombies, bob: 5 zombies, carol: 0 zombies (excluded), dave: 100 zombies.
        repo.insertSurvivor(1L, "alice");
        repo.updateZombieKills(1L, "alice", 30);
        repo.insertSurvivor(2L, "bob");
        repo.updateZombieKills(2L, "bob", 5);
        repo.insertSurvivor(3L, "carol");
        repo.insertSurvivor(4L, "dave");
        repo.updateZombieKills(4L, "dave", 100);
    }

    @AfterEach
    void tearDown() throws Exception {
        if (db != null) {
            db.close();
        }
    }

    @Test
    void updateZombieKillsReturnsTrueOnExistingRowAndFalseWhenMissing() throws Exception {
        assertTrue(repo.updateZombieKills(1L, "alice", 42));
        assertFalse(repo.updateZombieKills(999L, "ghost", 1));
    }

    @Test
    void noFilterExcludesZeroZombieRowsAndOrdersByZombieKills() throws Exception {
        List<SurvivorRecord> rows = repo.loadZombieKillersOrderedFiltered(null, null);
        assertEquals(
                List.of("dave", "alice", "bob"),
                rows.stream().map(SurvivorRecord::username).toList());
    }

    @Test
    void usernameFilterReturnsThatZombieKiller() throws Exception {
        List<SurvivorRecord> rows = repo.loadZombieKillersOrderedFiltered("alice", null);
        assertEquals(1, rows.size());
        assertEquals(30, rows.get(0).zombieKills());
    }

    @Test
    void steamIdFilterReturnsThatZombieKiller() throws Exception {
        List<SurvivorRecord> rows = repo.loadZombieKillersOrderedFiltered(null, 4L);
        assertEquals(1, rows.size());
        assertEquals("dave", rows.get(0).username());
        assertEquals(100, rows.get(0).zombieKills());
    }

    @Test
    void zeroZombieSurvivorIsExcludedEvenWhenFilteredByName() throws Exception {
        assertTrue(repo.loadZombieKillersOrderedFiltered("carol", null).isEmpty());
        assertTrue(repo.loadZombieKillersOrderedFiltered(null, 3L).isEmpty());
    }

    @Test
    void zombieOnlySurvivorAppearsInActivityBroadcast() throws Exception {
        // eve has only zombie kills — no day_count, no kill_count. She must still be broadcast so
        // the UI's zombie kills list can render her.
        repo.insertSurvivor(5L, "eve");
        repo.updateZombieKills(5L, "eve", 7);

        List<String> names =
                repo.loadOrderedWithActivity().stream().map(SurvivorRecord::username).toList();
        assertTrue(names.contains("eve"), () -> "activity broadcast missed eve: " + names);
    }

    @Test
    void querySurvivorsHydratesZombieKillsField() throws Exception {
        List<SurvivorRecord> rows = repo.loadZombieKillersOrderedFiltered("dave", null);
        assertEquals(1, rows.size());
        SurvivorRecord r = rows.get(0);
        assertEquals(4L, r.steamId());
        assertEquals("dave", r.username());
        assertEquals(100, r.zombieKills());
    }

    /**
     * Simulate upgrading a pre-existing database that was created before the zombie_kills column
     * existed: create the old schema by hand, then open it via {@link SurvivorLeaderboardDatabase}
     * and confirm the ALTER migration adds the column with the expected default.
     */
    @Test
    void migrationAddsZombieKillsColumnToLegacyDatabase() throws Exception {
        File legacyFile = new File(tempDir, "legacy.db");
        try (Connection raw =
                        DriverManager.getConnection("jdbc:sqlite:" + legacyFile.getAbsolutePath());
                Statement stmt = raw.createStatement()) {
            stmt.execute(
                    "CREATE TABLE survivors ("
                            + "id INTEGER PRIMARY KEY AUTOINCREMENT,"
                            + "steam_id INTEGER NOT NULL,"
                            + "username TEXT NOT NULL,"
                            + "day_count INTEGER NOT NULL DEFAULT 0,"
                            + "kill_count INTEGER NOT NULL DEFAULT 0,"
                            + "UNIQUE (steam_id, username))");
            stmt.execute(
                    "INSERT INTO survivors (steam_id, username, day_count) VALUES (7, 'old', 3)");
        }

        try (SurvivorLeaderboardDatabase upgraded =
                new SurvivorLeaderboardDatabase(legacyFile.getAbsolutePath())) {
            try (Statement stmt = upgraded.getConnection().createStatement();
                    ResultSet rs =
                            stmt.executeQuery(
                                    "SELECT zombie_kills FROM survivors WHERE username = 'old'")) {
                assertTrue(rs.next());
                assertEquals(0, rs.getInt("zombie_kills"));
            }

            SurvivorLeaderboardRepository upgradedRepo =
                    new SurvivorLeaderboardRepository(upgraded.getConnection());
            assertTrue(upgradedRepo.updateZombieKills(7L, "old", 11));
            List<SurvivorRecord> rows = upgradedRepo.loadZombieKillersOrderedFiltered("old", null);
            assertEquals(1, rows.size());
            assertEquals(11, rows.get(0).zombieKills());
        }
    }
}
