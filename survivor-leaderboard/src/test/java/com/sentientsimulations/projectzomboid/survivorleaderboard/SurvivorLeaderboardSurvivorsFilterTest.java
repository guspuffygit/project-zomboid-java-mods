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

class SurvivorLeaderboardSurvivorsFilterTest {

    @TempDir File tempDir;

    private SurvivorLeaderboardDatabase db;
    private SurvivorLeaderboardRepository repo;

    @BeforeEach
    void setUp() throws Exception {
        db =
                new SurvivorLeaderboardDatabase(
                        new File(tempDir, "survivor_leaderboard.db").getAbsolutePath());
        repo = new SurvivorLeaderboardRepository(db.getConnection());

        repo.insertSurvivor(1L, "alice");
        repo.updateDayCount(1L, "alice", 7);
        repo.insertSurvivor(2L, "bob");
        repo.updateDayCount(2L, "bob", 3);
        repo.insertSurvivor(3L, "carol");
        repo.updateDayCount(3L, "carol", 5);
    }

    @AfterEach
    void tearDown() throws Exception {
        if (db != null) {
            db.close();
        }
    }

    @Test
    void noFilterReturnsAllOrderedByDays() throws Exception {
        List<SurvivorRecord> rows = repo.loadAllOrderedFiltered(null, null);
        assertEquals(
                List.of("alice", "carol", "bob"),
                rows.stream().map(SurvivorRecord::username).toList());
    }

    @Test
    void usernameOnlyMatchesSingleRow() throws Exception {
        List<SurvivorRecord> rows = repo.loadAllOrderedFiltered("alice", null);
        assertEquals(1, rows.size());
        assertEquals("alice", rows.get(0).username());
        assertEquals(7, rows.get(0).dayCount());
    }

    @Test
    void steamIdOnlyMatchesSingleRow() throws Exception {
        List<SurvivorRecord> rows = repo.loadAllOrderedFiltered(null, 2L);
        assertEquals(1, rows.size());
        assertEquals("bob", rows.get(0).username());
    }

    @Test
    void bothFiltersMustMatchTogether() throws Exception {
        List<SurvivorRecord> match = repo.loadAllOrderedFiltered("alice", 1L);
        assertEquals(1, match.size());
        assertEquals("alice", match.get(0).username());

        List<SurvivorRecord> mismatch = repo.loadAllOrderedFiltered("alice", 2L);
        assertTrue(mismatch.isEmpty(), "username and steamId must match the same row");
    }

    @Test
    void unknownUsernameReturnsEmpty() throws Exception {
        assertTrue(repo.loadAllOrderedFiltered("nobody", null).isEmpty());
    }

    @Test
    void unknownSteamIdReturnsEmpty() throws Exception {
        assertTrue(repo.loadAllOrderedFiltered(null, 999L).isEmpty());
    }

    @Test
    void usernameIsCaseSensitive() throws Exception {
        assertTrue(repo.loadAllOrderedFiltered("ALICE", null).isEmpty());
    }
}
