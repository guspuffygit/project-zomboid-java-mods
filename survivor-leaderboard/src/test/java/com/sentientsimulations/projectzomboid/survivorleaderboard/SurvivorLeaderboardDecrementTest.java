package com.sentientsimulations.projectzomboid.survivorleaderboard;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.sentientsimulations.projectzomboid.survivorleaderboard.records.SurvivorRecord;
import java.io.File;
import java.sql.PreparedStatement;
import java.util.List;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

/**
 * Integration test for {@link SurvivorLeaderboardRepository#decrementKillCount(long, String, int)}
 * and the zero-kill filter applied by {@link
 * SurvivorLeaderboardRepository#loadAllOrderedByKills()}. Uses a real leaderboard SQLite DB in a
 * temp dir.
 */
class SurvivorLeaderboardDecrementTest {

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
    void decrementBelowZeroIsAllowed() throws Exception {
        repo.insertSurvivor(1L, "alice");
        setKillCount(1L, "alice", 3);

        int updated = repo.decrementKillCount(1L, "alice", 5);

        assertEquals(1, updated);
        assertEquals(-2, killCountOf(1L, "alice"));
    }

    @Test
    void decrementSubtractsAmountExactly() throws Exception {
        repo.insertSurvivor(2L, "bob");
        setKillCount(2L, "bob", 10);

        repo.decrementKillCount(2L, "bob", 5);

        assertEquals(5, killCountOf(2L, "bob"));
    }

    @Test
    void decrementOnMissingRowReturnsZero() throws Exception {
        int updated = repo.decrementKillCount(999L, "ghost", 5);
        assertEquals(0, updated);
    }

    @Test
    void killersBoardHidesZeroKillSurvivorsButShowsNegative() throws Exception {
        repo.insertSurvivor(1L, "alice");
        repo.insertSurvivor(2L, "bob");
        repo.insertSurvivor(3L, "carol");
        repo.insertSurvivor(4L, "dave");
        setKillCount(1L, "alice", 5);
        setKillCount(2L, "bob", 0);
        setKillCount(3L, "carol", -2);
        setKillCount(4L, "dave", 3);

        List<SurvivorRecord> killers = repo.loadAllOrderedByKills();

        assertEquals(3, killers.size());
        assertEquals("alice", killers.get(0).username());
        assertEquals(5, killers.get(0).killCount());
        assertEquals("dave", killers.get(1).username());
        assertEquals("carol", killers.get(2).username());
        assertTrue(
                killers.stream().noneMatch(r -> r.killCount() == 0),
                "zero-kill rows must be filtered out of the killers board");
    }

    @Test
    void resetKillCountIfPositiveZeroesPositiveRow() throws Exception {
        repo.insertSurvivor(1L, "alice");
        setKillCount(1L, "alice", 7);

        int updated = repo.resetKillCountIfPositive(1L, "alice");

        assertEquals(1, updated);
        assertEquals(0, killCountOf(1L, "alice"));
    }

    @Test
    void resetKillCountIfPositivePreservesNegativeRow() throws Exception {
        repo.insertSurvivor(1L, "alice");
        setKillCount(1L, "alice", -3);

        int updated = repo.resetKillCountIfPositive(1L, "alice");

        assertEquals(0, updated);
        assertEquals(-3, killCountOf(1L, "alice"));
    }

    @Test
    void resetKillCountIfPositiveIsNoopOnZero() throws Exception {
        repo.insertSurvivor(1L, "alice");
        setKillCount(1L, "alice", 0);

        int updated = repo.resetKillCountIfPositive(1L, "alice");

        assertEquals(0, updated);
        assertEquals(0, killCountOf(1L, "alice"));
    }

    @Test
    void survivorsBoardIncludesZeroKillPlayersWithDays() throws Exception {
        repo.insertSurvivor(1L, "alice");
        repo.insertSurvivor(2L, "bob");
        repo.updateDayCount(1L, "alice", 5);
        repo.updateDayCount(2L, "bob", 3);
        setKillCount(1L, "alice", 0);
        setKillCount(2L, "bob", 3);

        List<SurvivorRecord> survivors = repo.loadAllOrderedFiltered(null, null);
        assertEquals(2, survivors.size());
    }

    @Test
    void survivorsBoardHidesZeroDaySurvivors() throws Exception {
        repo.insertSurvivor(1L, "alice");
        repo.insertSurvivor(2L, "bob");
        repo.updateDayCount(2L, "bob", 4);

        List<SurvivorRecord> survivors = repo.loadAllOrderedFiltered(null, null);

        assertEquals(1, survivors.size());
        assertEquals("bob", survivors.get(0).username());
        assertTrue(
                survivors.stream().noneMatch(r -> r.dayCount() == 0),
                "zero-day rows must be filtered out of the survivors board");
    }

    @Test
    void broadcastFilterIncludesAnyActivity() throws Exception {
        repo.insertSurvivor(1L, "alice");
        repo.insertSurvivor(2L, "bob");
        repo.insertSurvivor(3L, "carol");
        repo.updateDayCount(1L, "alice", 5);
        setKillCount(2L, "bob", -3);
        // carol: day_count = 0 AND kill_count = 0 — excluded.

        List<SurvivorRecord> rows = repo.loadOrderedWithActivity();

        assertEquals(2, rows.size());
        assertTrue(
                rows.stream().noneMatch(r -> r.username().equals("carol")),
                "carol has no activity and must be excluded from the broadcast");
    }

    private void setKillCount(long steamId, String username, int count) throws Exception {
        try (PreparedStatement ps =
                db.getConnection()
                        .prepareStatement(
                                "UPDATE survivors SET kill_count = ? WHERE steam_id = ? AND"
                                        + " username = ?")) {
            ps.setInt(1, count);
            ps.setLong(2, steamId);
            ps.setString(3, username);
            ps.executeUpdate();
        }
    }

    private int killCountOf(long steamId, String username) throws Exception {
        try (PreparedStatement ps =
                        db.getConnection()
                                .prepareStatement(
                                        "SELECT kill_count FROM survivors WHERE steam_id = ? AND"
                                                + " username = ?");
                var rs = bindAndRun(ps, steamId, username)) {
            assertTrue(rs.next(), "row not found");
            return rs.getInt(1);
        }
    }

    private static java.sql.ResultSet bindAndRun(
            PreparedStatement ps, long steamId, String username) throws Exception {
        ps.setLong(1, steamId);
        ps.setString(2, username);
        return ps.executeQuery();
    }
}
