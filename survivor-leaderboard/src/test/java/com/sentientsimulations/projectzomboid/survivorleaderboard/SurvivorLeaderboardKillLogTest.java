package com.sentientsimulations.projectzomboid.survivorleaderboard;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.sentientsimulations.projectzomboid.survivorleaderboard.records.KillLogEntry;
import java.io.File;
import java.util.List;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

/**
 * Integration tests for the kill log table — insert, delete by killer, delete by Steam ID, and
 * recent-kills query ordering. Uses a real SQLite DB in a temp dir.
 */
class SurvivorLeaderboardKillLogTest {

    @TempDir File tempDir;

    private SurvivorLeaderboardDatabase db;
    private SurvivorLeaderboardRepository repo;

    @BeforeEach
    void setUp() throws Exception {
        db =
                new SurvivorLeaderboardDatabase(
                        new File(tempDir, "survivor_leaderboard.db").getAbsolutePath());
        repo = new SurvivorLeaderboardRepository(db.getConnection());
    }

    @AfterEach
    void tearDown() throws Exception {
        if (db != null) {
            db.close();
        }
    }

    @Test
    void insertKillPersistsAllColumns() throws Exception {
        assertTrue(repo.insertKill(1L, "alice", 2L, "bob", true, 1_000L));
        assertTrue(repo.insertKill(3L, "carol", 4L, "dave", false, 2_000L));

        List<KillLogEntry> entries = repo.loadRecentKills(10);

        assertEquals(2, entries.size());
        KillLogEntry newest = entries.get(0);
        assertEquals(3L, newest.killerSteamId());
        assertEquals("carol", newest.killerUsername());
        assertEquals(4L, newest.victimSteamId());
        assertEquals("dave", newest.victimUsername());
        assertFalse(newest.isAlly());
        assertEquals(2_000L, newest.createdAt());
        assertTrue(entries.get(1).isAlly());
    }

    @Test
    void loadRecentKillsReturnsNewestFirstAndRespectsLimit() throws Exception {
        repo.insertKill(1L, "alice", 2L, "bob", false, 100L);
        repo.insertKill(1L, "alice", 3L, "carol", false, 300L);
        repo.insertKill(1L, "alice", 4L, "dave", false, 200L);

        List<KillLogEntry> top2 = repo.loadRecentKills(2);

        assertEquals(2, top2.size());
        assertEquals("carol", top2.get(0).victimUsername());
        assertEquals("dave", top2.get(1).victimUsername());
    }

    @Test
    void deleteKillsByKillerRemovesOnlyMatchingKiller() throws Exception {
        repo.insertKill(1L, "alice", 2L, "bob", false, 100L);
        repo.insertKill(1L, "alice", 3L, "carol", true, 200L);
        repo.insertKill(5L, "eve", 2L, "bob", false, 300L);

        int removed = repo.deleteKillsByKiller(1L, "alice");

        assertEquals(2, removed);
        List<KillLogEntry> remaining = repo.loadRecentKills(10);
        assertEquals(1, remaining.size());
        assertEquals("eve", remaining.get(0).killerUsername());
    }

    @Test
    void deleteKillsByKillerSteamIdRemovesEveryCharacterForThatAccount() throws Exception {
        repo.insertKill(1L, "alice-main", 2L, "bob", false, 100L);
        repo.insertKill(1L, "alice-alt", 3L, "carol", true, 200L);
        repo.insertKill(5L, "eve", 2L, "bob", false, 300L);

        int removed = repo.deleteKillsByKillerSteamId(1L);

        assertEquals(2, removed);
        List<KillLogEntry> remaining = repo.loadRecentKills(10);
        assertEquals(1, remaining.size());
        assertEquals(5L, remaining.get(0).killerSteamId());
    }

    @Test
    void deleteOnEmptyKillLogReturnsZero() throws Exception {
        assertEquals(0, repo.deleteKillsByKiller(999L, "ghost"));
        assertEquals(0, repo.deleteKillsByKillerSteamId(999L));
    }
}
