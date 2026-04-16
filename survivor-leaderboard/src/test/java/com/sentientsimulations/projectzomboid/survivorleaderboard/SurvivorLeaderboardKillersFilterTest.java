package com.sentientsimulations.projectzomboid.survivorleaderboard;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.sentientsimulations.projectzomboid.survivorleaderboard.records.SurvivorRecord;
import java.io.File;
import java.util.List;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

class SurvivorLeaderboardKillersFilterTest {

    @TempDir File tempDir;

    private SurvivorLeaderboardDatabase db;
    private SurvivorLeaderboardRepository repo;

    @BeforeEach
    void setUp() throws Exception {
        db =
                new SurvivorLeaderboardDatabase(
                        new File(tempDir, "survivor_leaderboard.db").getAbsolutePath());
        repo = new SurvivorLeaderboardRepository(db.getConnection());

        // alice: 3 kills, bob: 1 kill, carol: 0 kills (excluded), dave: 5 kills.
        repo.insertSurvivor(1L, "alice");
        for (int i = 0; i < 3; i++) repo.incrementKillCount(1L, "alice");
        repo.insertSurvivor(2L, "bob");
        repo.incrementKillCount(2L, "bob");
        repo.insertSurvivor(3L, "carol");
        repo.insertSurvivor(4L, "dave");
        for (int i = 0; i < 5; i++) repo.incrementKillCount(4L, "dave");
    }

    @AfterEach
    void tearDown() throws Exception {
        if (db != null) {
            db.close();
        }
    }

    @Test
    void noFilterExcludesZeroKillRowsAndOrdersByKills() throws Exception {
        List<SurvivorRecord> rows = repo.loadKillersOrderedFiltered(null, null);
        assertEquals(
                List.of("dave", "alice", "bob"),
                rows.stream().map(SurvivorRecord::username).toList());
    }

    @Test
    void usernameFilterReturnsThatKiller() throws Exception {
        List<SurvivorRecord> rows = repo.loadKillersOrderedFiltered("alice", null);
        assertEquals(1, rows.size());
        assertEquals(3, rows.get(0).killCount());
    }

    @Test
    void steamIdFilterReturnsThatKiller() throws Exception {
        List<SurvivorRecord> rows = repo.loadKillersOrderedFiltered(null, 4L);
        assertEquals(1, rows.size());
        assertEquals("dave", rows.get(0).username());
    }

    @Test
    void zeroKillSurvivorIsExcludedEvenWhenFilteredByName() throws Exception {
        // carol exists in the survivors table with kill_count = 0; the killers query must still
        // omit her even when she is the explicit filter target.
        assertTrue(repo.loadKillersOrderedFiltered("carol", null).isEmpty());
        assertTrue(repo.loadKillersOrderedFiltered(null, 3L).isEmpty());
    }

    @Test
    void mismatchedPairReturnsEmpty() throws Exception {
        assertTrue(repo.loadKillersOrderedFiltered("alice", 4L).isEmpty());
    }

    @Test
    void unknownUserReturnsEmpty() throws Exception {
        assertTrue(repo.loadKillersOrderedFiltered("ghost", null).isEmpty());
        assertTrue(repo.loadKillersOrderedFiltered(null, 999L).isEmpty());
    }
}
