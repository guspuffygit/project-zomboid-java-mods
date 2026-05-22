package com.sentientsimulations.projectzomboid.survivorleaderboard;

import static com.sentientsimulations.projectzomboid.survivorleaderboard.SurvivorLeaderboardBridge.REPEAT_VICTIM_KILL_PENALTY;
import static com.sentientsimulations.projectzomboid.survivorleaderboard.SurvivorLeaderboardBridge.REPEAT_VICTIM_KILL_WINDOW_MS;
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
 * SurvivorLeaderboardBridge#processRepeatVictimPenalties(SurvivorLeaderboardRepository)} — the
 * EveryHoursEvent-driven sweep that penalises killing the same victim 3+ times within an hour.
 * Independent of faction/safehouse; applies to every PvP kill.
 */
class SurvivorLeaderboardRepeatVictimProcessorTest {

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
    void singleKillYieldsNoPenalty() throws Exception {
        repo.insertSurvivor(1L, "alice");
        setKillCount(1L, "alice", 5);
        repo.insertKill(1L, "alice", 2L, "bob", false, 1_000L);

        int penalties = SurvivorLeaderboardBridge.processRepeatVictimPenalties(repo);

        assertEquals(0, penalties);
        assertEquals(5, killCountOf(1L, "alice"));
        assertEquals(1, repeatVictimPenaltyAppliedOf(findKillId(1L, "alice", 2L, "bob", 1_000L)));
    }

    @Test
    void twoKillsOfSameVictimYieldNoPenalty() throws Exception {
        repo.insertSurvivor(1L, "alice");
        setKillCount(1L, "alice", 10);
        long first = 1_000_000L;
        long second = first + 5L * 60L * 1000L; // +5 min
        repo.insertKill(1L, "alice", 2L, "bob", false, first);
        repo.insertKill(1L, "alice", 2L, "bob", false, second);

        int penalties = SurvivorLeaderboardBridge.processRepeatVictimPenalties(repo);

        assertEquals(0, penalties);
        assertEquals(10, killCountOf(1L, "alice"));
    }

    @Test
    void thirdKillOfSameVictimInWindowIsPenalized() throws Exception {
        repo.insertSurvivor(1L, "alice");
        setKillCount(1L, "alice", 10);
        long base = 1_000_000L;
        repo.insertKill(1L, "alice", 2L, "bob", false, base);
        repo.insertKill(1L, "alice", 2L, "bob", false, base + 10L * 60L * 1000L);
        repo.insertKill(1L, "alice", 2L, "bob", false, base + 20L * 60L * 1000L);

        int penalties = SurvivorLeaderboardBridge.processRepeatVictimPenalties(repo);

        assertEquals(1, penalties);
        assertEquals(10 - REPEAT_VICTIM_KILL_PENALTY, killCountOf(1L, "alice"));
    }

    @Test
    void fourthAndFifthKillsAlsoPenalized() throws Exception {
        repo.insertSurvivor(1L, "alice");
        setKillCount(1L, "alice", 30);
        long base = 1_000_000L;
        repo.insertKill(1L, "alice", 2L, "bob", false, base);
        repo.insertKill(1L, "alice", 2L, "bob", false, base + 5L * 60L * 1000L);
        repo.insertKill(1L, "alice", 2L, "bob", false, base + 10L * 60L * 1000L);
        repo.insertKill(1L, "alice", 2L, "bob", false, base + 15L * 60L * 1000L);
        repo.insertKill(1L, "alice", 2L, "bob", false, base + 20L * 60L * 1000L);

        int penalties = SurvivorLeaderboardBridge.processRepeatVictimPenalties(repo);

        assertEquals(3, penalties);
        assertEquals(30 - 3 * REPEAT_VICTIM_KILL_PENALTY, killCountOf(1L, "alice"));
    }

    @Test
    void killsOutsideWindowDoNotCount() throws Exception {
        repo.insertSurvivor(1L, "alice");
        setKillCount(1L, "alice", 10);
        long base = 1_000_000L;
        // First two kills fall outside the window of the third.
        repo.insertKill(1L, "alice", 2L, "bob", false, base);
        repo.insertKill(1L, "alice", 2L, "bob", false, base + 1_000L);
        repo.insertKill(1L, "alice", 2L, "bob", false, base + REPEAT_VICTIM_KILL_WINDOW_MS + 1L);

        int penalties = SurvivorLeaderboardBridge.processRepeatVictimPenalties(repo);

        assertEquals(0, penalties);
        assertEquals(10, killCountOf(1L, "alice"));
    }

    @Test
    void differentVictimsAreCountedSeparately() throws Exception {
        repo.insertSurvivor(1L, "alice");
        setKillCount(1L, "alice", 10);
        long base = 1_000_000L;
        // Three kills inside the window, but all different victims.
        repo.insertKill(1L, "alice", 2L, "bob", false, base);
        repo.insertKill(1L, "alice", 3L, "carol", false, base + 10L * 60L * 1000L);
        repo.insertKill(1L, "alice", 4L, "dave", false, base + 20L * 60L * 1000L);

        int penalties = SurvivorLeaderboardBridge.processRepeatVictimPenalties(repo);

        assertEquals(0, penalties);
        assertEquals(10, killCountOf(1L, "alice"));
    }

    @Test
    void differentKillersAreCountedSeparately() throws Exception {
        repo.insertSurvivor(1L, "alice");
        repo.insertSurvivor(5L, "eve");
        setKillCount(1L, "alice", 10);
        setKillCount(5L, "eve", 10);
        long base = 1_000_000L;
        // alice kills bob twice — no penalty.
        repo.insertKill(1L, "alice", 2L, "bob", false, base);
        repo.insertKill(1L, "alice", 2L, "bob", false, base + 5L * 60L * 1000L);
        // eve kills bob once — no penalty either.
        repo.insertKill(5L, "eve", 2L, "bob", false, base + 10L * 60L * 1000L);

        int penalties = SurvivorLeaderboardBridge.processRepeatVictimPenalties(repo);

        assertEquals(0, penalties);
        assertEquals(10, killCountOf(1L, "alice"));
        assertEquals(10, killCountOf(5L, "eve"));
    }

    @Test
    void appliesEvenWhenKillIsNotAlly() throws Exception {
        // Sanity check that is_ally is irrelevant — penalty is based purely on victim repetition.
        repo.insertSurvivor(1L, "alice");
        setKillCount(1L, "alice", 10);
        long base = 1_000_000L;
        repo.insertKill(1L, "alice", 2L, "bob", false, base);
        repo.insertKill(1L, "alice", 2L, "bob", false, base + 5L * 60L * 1000L);
        repo.insertKill(1L, "alice", 2L, "bob", false, base + 10L * 60L * 1000L);

        int penalties = SurvivorLeaderboardBridge.processRepeatVictimPenalties(repo);

        assertEquals(1, penalties);
        assertEquals(10 - REPEAT_VICTIM_KILL_PENALTY, killCountOf(1L, "alice"));
    }

    @Test
    void secondRunIsNoop() throws Exception {
        repo.insertSurvivor(1L, "alice");
        setKillCount(1L, "alice", 10);
        long base = 1_000_000L;
        repo.insertKill(1L, "alice", 2L, "bob", false, base);
        repo.insertKill(1L, "alice", 2L, "bob", false, base + 5L * 60L * 1000L);
        repo.insertKill(1L, "alice", 2L, "bob", false, base + 10L * 60L * 1000L);

        int first = SurvivorLeaderboardBridge.processRepeatVictimPenalties(repo);
        int second = SurvivorLeaderboardBridge.processRepeatVictimPenalties(repo);

        assertEquals(1, first);
        assertEquals(0, second);
        assertEquals(10 - REPEAT_VICTIM_KILL_PENALTY, killCountOf(1L, "alice"));
    }

    @Test
    void killCountCanGoNegative() throws Exception {
        repo.insertSurvivor(1L, "alice");
        setKillCount(1L, "alice", 2);
        long base = 1_000_000L;
        repo.insertKill(1L, "alice", 2L, "bob", false, base);
        repo.insertKill(1L, "alice", 2L, "bob", false, base + 5L * 60L * 1000L);
        repo.insertKill(1L, "alice", 2L, "bob", false, base + 10L * 60L * 1000L);

        SurvivorLeaderboardBridge.processRepeatVictimPenalties(repo);

        assertEquals(2 - REPEAT_VICTIM_KILL_PENALTY, killCountOf(1L, "alice"));
        assertTrue(killCountOf(1L, "alice") < 0, "kill_count must be allowed to go negative");
    }

    @Test
    void killsProcessedInChronologicalOrder() throws Exception {
        // Insert in reverse chronological order to verify the processor sorts by created_at ASC.
        repo.insertSurvivor(1L, "alice");
        setKillCount(1L, "alice", 20);
        long base = 1_000_000L;
        repo.insertKill(1L, "alice", 2L, "bob", false, base + 20L * 60L * 1000L);
        repo.insertKill(1L, "alice", 2L, "bob", false, base + 10L * 60L * 1000L);
        repo.insertKill(1L, "alice", 2L, "bob", false, base);

        int penalties = SurvivorLeaderboardBridge.processRepeatVictimPenalties(repo);

        assertEquals(1, penalties);
        assertEquals(20 - REPEAT_VICTIM_KILL_PENALTY, killCountOf(1L, "alice"));
    }

    @Test
    void victimIdentifiedBySteamIdNotUsername() throws Exception {
        // Same victim Steam account rejoins with new character names between kills — still counts
        // as the same person.
        repo.insertSurvivor(1L, "alice");
        setKillCount(1L, "alice", 10);
        long base = 1_000_000L;
        repo.insertKill(1L, "alice", 2L, "bob", false, base);
        repo.insertKill(1L, "alice", 2L, "bob_v2", false, base + 5L * 60L * 1000L);
        repo.insertKill(1L, "alice", 2L, "bob_v3", false, base + 10L * 60L * 1000L);

        int penalties = SurvivorLeaderboardBridge.processRepeatVictimPenalties(repo);

        assertEquals(1, penalties);
        assertEquals(10 - REPEAT_VICTIM_KILL_PENALTY, killCountOf(1L, "alice"));
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

    private int repeatVictimPenaltyAppliedOf(long killId) throws Exception {
        try (PreparedStatement ps =
                db.getConnection()
                        .prepareStatement(
                                "SELECT repeat_victim_penalty_applied FROM kills WHERE id = ?")) {
            ps.setLong(1, killId);
            try (ResultSet rs = ps.executeQuery()) {
                assertTrue(rs.next(), "kill row not found");
                return rs.getInt(1);
            }
        }
    }
}
