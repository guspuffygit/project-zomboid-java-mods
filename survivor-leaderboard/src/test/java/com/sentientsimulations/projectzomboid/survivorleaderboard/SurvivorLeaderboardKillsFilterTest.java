package com.sentientsimulations.projectzomboid.survivorleaderboard;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.sentientsimulations.projectzomboid.survivorleaderboard.records.KillLogEntry;
import java.io.File;
import java.util.List;
import java.util.Set;
import java.util.stream.Collectors;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

class SurvivorLeaderboardKillsFilterTest {

    @TempDir File tempDir;

    private SurvivorLeaderboardDatabase db;
    private SurvivorLeaderboardRepository repo;

    @BeforeEach
    void setUp() throws Exception {
        db =
                new SurvivorLeaderboardDatabase(
                        new File(tempDir, "survivor_leaderboard.db").getAbsolutePath());
        repo = new SurvivorLeaderboardRepository(db.getConnection());

        // alice(1) killed bob(2); bob(2) killed carol(3); carol(3) killed alice(1); dave(4) killed
        // eve(5).
        repo.insertKill(1L, "alice", 2L, "bob", false, 100L);
        repo.insertKill(2L, "bob", 3L, "carol", false, 200L);
        repo.insertKill(3L, "carol", 1L, "alice", true, 300L);
        repo.insertKill(4L, "dave", 5L, "eve", false, 400L);
    }

    @AfterEach
    void tearDown() throws Exception {
        if (db != null) {
            db.close();
        }
    }

    @Test
    void usernameMatchesKillerOrVictimSide() throws Exception {
        List<KillLogEntry> rows = repo.loadRecentKillsFiltered(10, "alice", null);
        assertEquals(2, rows.size());
        // Newest first: carol→alice (300), then alice→bob (100).
        assertEquals(300L, rows.get(0).createdAt());
        assertEquals(100L, rows.get(1).createdAt());
    }

    @Test
    void steamIdMatchesKillerOrVictimSide() throws Exception {
        List<KillLogEntry> rows = repo.loadRecentKillsFiltered(10, null, 2L);
        // alice→bob (victim=2) and bob→carol (killer=2).
        Set<Long> timestamps =
                rows.stream().map(KillLogEntry::createdAt).collect(Collectors.toSet());
        assertEquals(Set.of(100L, 200L), timestamps);
    }

    @Test
    void bothFiltersMustMatchSameSide() throws Exception {
        // alice has steamId 1. Both kills where alice is involved also have steamId 1 on her side.
        List<KillLogEntry> rows = repo.loadRecentKillsFiltered(10, "alice", 1L);
        assertEquals(2, rows.size());

        // Pair username=alice with someone else's steamId — must return empty.
        assertTrue(repo.loadRecentKillsFiltered(10, "alice", 2L).isEmpty());
    }

    @Test
    void unknownUserReturnsEmpty() throws Exception {
        assertTrue(repo.loadRecentKillsFiltered(10, "ghost", null).isEmpty());
        assertTrue(repo.loadRecentKillsFiltered(10, null, 999L).isEmpty());
    }

    @Test
    void limitAppliesAfterFilter() throws Exception {
        // Add several more alice-involved kills so we can assert the limit clips them.
        for (int i = 0; i < 10; i++) {
            repo.insertKill(1L, "alice", 99L, "mob-" + i, false, 1_000L + i);
        }
        List<KillLogEntry> rows = repo.loadRecentKillsFiltered(3, "alice", null);
        assertEquals(3, rows.size());
        // Newest-first: the three most recent alice rows are 1009, 1008, 1007.
        assertEquals(1_009L, rows.get(0).createdAt());
        assertEquals(1_008L, rows.get(1).createdAt());
        assertEquals(1_007L, rows.get(2).createdAt());
    }

    @Test
    void noFilterIsUnchanged() throws Exception {
        List<KillLogEntry> rows = repo.loadRecentKillsFiltered(10, null, null);
        assertEquals(4, rows.size());
        assertEquals(400L, rows.get(0).createdAt());
        assertEquals(100L, rows.get(3).createdAt());
    }
}
