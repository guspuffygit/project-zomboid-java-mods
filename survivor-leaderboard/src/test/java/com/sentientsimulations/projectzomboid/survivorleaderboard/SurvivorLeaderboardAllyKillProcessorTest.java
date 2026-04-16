package com.sentientsimulations.projectzomboid.survivorleaderboard;

import static com.sentientsimulations.projectzomboid.survivorleaderboard.SurvivorLeaderboardBridge.ALLY_KILL_PENALTY;
import static com.sentientsimulations.projectzomboid.survivorleaderboard.SurvivorLeaderboardBridge.ALLY_KILL_WINDOW_MS;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.io.File;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

/**
 * Integration test for {@link
 * SurvivorLeaderboardBridge#processAllyKillPenalties(SurvivorLeaderboardRepository)} — the
 * EveryHoursEvent-driven sweep that reads the kills table, applies delayed penalties, and marks
 * rows so they are not double-processed.
 */
class SurvivorLeaderboardAllyKillProcessorTest {

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
    void singleAllyKillYieldsNoPenalty() throws Exception {
        repo.insertSurvivor(1L, "alice");
        setKillCount(1L, "alice", 3);
        repo.insertKill(1L, "alice", 2L, "bob", true, 1_000L);

        int penalties = SurvivorLeaderboardBridge.processAllyKillPenalties(repo);

        assertEquals(0, penalties);
        assertEquals(3, killCountOf(1L, "alice"));
        assertEquals(1, penaltyAppliedOf(findKillId(1L, "alice", 2L, "bob", 1_000L)));
    }

    @Test
    void twoAllyKillsInWindowPenalizeTheSecond() throws Exception {
        repo.insertSurvivor(1L, "alice");
        setKillCount(1L, "alice", 10);
        long first = 1_000_000L;
        long second = first + 10L * 60L * 1000L; // +10 min
        repo.insertKill(1L, "alice", 2L, "bob", true, first);
        repo.insertKill(1L, "alice", 3L, "carol", true, second);

        int penalties = SurvivorLeaderboardBridge.processAllyKillPenalties(repo);

        assertEquals(1, penalties);
        assertEquals(10 - ALLY_KILL_PENALTY, killCountOf(1L, "alice"));
    }

    @Test
    void threeAllyKillsInWindowPenalizeSecondAndThird() throws Exception {
        repo.insertSurvivor(1L, "alice");
        setKillCount(1L, "alice", 20);
        long base = 1_000_000L;
        repo.insertKill(1L, "alice", 2L, "bob", true, base);
        repo.insertKill(1L, "alice", 3L, "carol", true, base + 10L * 60L * 1000L);
        repo.insertKill(1L, "alice", 4L, "dave", true, base + 20L * 60L * 1000L);

        int penalties = SurvivorLeaderboardBridge.processAllyKillPenalties(repo);

        assertEquals(2, penalties);
        assertEquals(20 - 2 * ALLY_KILL_PENALTY, killCountOf(1L, "alice"));
    }

    @Test
    void allyKillsOutsideWindowAreNotPenalized() throws Exception {
        repo.insertSurvivor(1L, "alice");
        setKillCount(1L, "alice", 10);
        long first = 1_000_000L;
        long second = first + ALLY_KILL_WINDOW_MS + 1; // just past 60 min
        repo.insertKill(1L, "alice", 2L, "bob", true, first);
        repo.insertKill(1L, "alice", 3L, "carol", true, second);

        int penalties = SurvivorLeaderboardBridge.processAllyKillPenalties(repo);

        assertEquals(0, penalties);
        assertEquals(10, killCountOf(1L, "alice"));
    }

    @Test
    void nonAllyKillsAreIgnoredAndStayUnapplied() throws Exception {
        repo.insertSurvivor(1L, "alice");
        setKillCount(1L, "alice", 10);
        repo.insertKill(1L, "alice", 2L, "bob", false, 1_000L);
        repo.insertKill(1L, "alice", 3L, "carol", false, 2_000L);

        int penalties = SurvivorLeaderboardBridge.processAllyKillPenalties(repo);

        assertEquals(0, penalties);
        assertEquals(10, killCountOf(1L, "alice"));
        // is_ally = 0 rows are skipped entirely; penalty_applied stays 0.
        assertEquals(0, penaltyAppliedOf(findKillId(1L, "alice", 2L, "bob", 1_000L)));
        assertEquals(0, penaltyAppliedOf(findKillId(1L, "alice", 3L, "carol", 2_000L)));
    }

    @Test
    void killersAreIndependent() throws Exception {
        repo.insertSurvivor(1L, "alice");
        repo.insertSurvivor(5L, "eve");
        setKillCount(1L, "alice", 10);
        setKillCount(5L, "eve", 10);

        long base = 1_000_000L;
        repo.insertKill(1L, "alice", 2L, "bob", true, base);
        repo.insertKill(1L, "alice", 3L, "carol", true, base + 5L * 60L * 1000L);
        // eve has only one ally kill — no penalty.
        repo.insertKill(5L, "eve", 2L, "bob", true, base + 1_000L);

        int penalties = SurvivorLeaderboardBridge.processAllyKillPenalties(repo);

        assertEquals(1, penalties);
        assertEquals(10 - ALLY_KILL_PENALTY, killCountOf(1L, "alice"));
        assertEquals(10, killCountOf(5L, "eve"));
    }

    @Test
    void secondRunIsNoop() throws Exception {
        repo.insertSurvivor(1L, "alice");
        setKillCount(1L, "alice", 10);
        repo.insertKill(1L, "alice", 2L, "bob", true, 1_000L);
        repo.insertKill(1L, "alice", 3L, "carol", true, 11L * 60L * 1000L);

        int first = SurvivorLeaderboardBridge.processAllyKillPenalties(repo);
        int second = SurvivorLeaderboardBridge.processAllyKillPenalties(repo);

        assertEquals(1, first);
        assertEquals(0, second);
        assertEquals(10 - ALLY_KILL_PENALTY, killCountOf(1L, "alice"));
    }

    @Test
    void killCountCanGoNegative() throws Exception {
        repo.insertSurvivor(1L, "alice");
        setKillCount(1L, "alice", 2);
        long base = 1_000_000L;
        repo.insertKill(1L, "alice", 2L, "bob", true, base);
        repo.insertKill(1L, "alice", 3L, "carol", true, base + 5L * 60L * 1000L);

        SurvivorLeaderboardBridge.processAllyKillPenalties(repo);

        assertEquals(2 - ALLY_KILL_PENALTY, killCountOf(1L, "alice"));
        assertTrue(killCountOf(1L, "alice") < 0, "kill_count must be allowed to go negative");
    }

    @Test
    void allyKillsProcessedInChronologicalOrder() throws Exception {
        // Insert in reverse chronological order to verify the processor sorts by created_at ASC.
        repo.insertSurvivor(1L, "alice");
        setKillCount(1L, "alice", 15);
        long base = 1_000_000L;
        repo.insertKill(1L, "alice", 4L, "dave", true, base + 20L * 60L * 1000L);
        repo.insertKill(1L, "alice", 3L, "carol", true, base + 10L * 60L * 1000L);
        repo.insertKill(1L, "alice", 2L, "bob", true, base);

        int penalties = SurvivorLeaderboardBridge.processAllyKillPenalties(repo);

        assertEquals(2, penalties);
        assertEquals(15 - 2 * ALLY_KILL_PENALTY, killCountOf(1L, "alice"));
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
                                        + " username = ?")) {
            ps.setLong(1, steamId);
            ps.setString(2, username);
            try (ResultSet rs = ps.executeQuery()) {
                assertTrue(rs.next(), "survivor row not found");
                return rs.getInt(1);
            }
        }
    }

    private long findKillId(
            long killerSteamId,
            String killerUsername,
            long victimSteamId,
            String victimUsername,
            long createdAt)
            throws Exception {
        try (PreparedStatement ps =
                db.getConnection()
                        .prepareStatement(
                                "SELECT id FROM kills WHERE killer_steam_id = ? AND"
                                        + " killer_username = ? AND victim_steam_id = ? AND"
                                        + " victim_username = ? AND created_at = ?")) {
            ps.setLong(1, killerSteamId);
            ps.setString(2, killerUsername);
            ps.setLong(3, victimSteamId);
            ps.setString(4, victimUsername);
            ps.setLong(5, createdAt);
            try (ResultSet rs = ps.executeQuery()) {
                assertTrue(rs.next(), "kill row not found");
                return rs.getLong(1);
            }
        }
    }

    private int penaltyAppliedOf(long killId) throws Exception {
        try (PreparedStatement ps =
                db.getConnection()
                        .prepareStatement("SELECT penalty_applied FROM kills WHERE id = ?")) {
            ps.setLong(1, killId);
            try (ResultSet rs = ps.executeQuery()) {
                assertTrue(rs.next(), "kill row not found");
                return rs.getInt(1);
            }
        }
    }
}
