package com.sentientsimulations.projectzomboid.survivorleaderboard;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.sentientsimulations.projectzomboid.survivorleaderboard.records.SurvivorRecord;
import java.io.File;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

/**
 * Integration test for {@link
 * SurvivorLeaderboardBridge#setKillCount(SurvivorLeaderboardRepository, long, String, int)} — the
 * admin-endpoint backing method that overwrites a player's kill_count.
 */
class SurvivorLeaderboardSetKillCountTest {

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
    void setsKillCountOnExistingSurvivor() throws Exception {
        repo.insertSurvivor(1L, "alice");
        setKillCountDirectly(1L, "alice", 3);

        SurvivorRecord updated = SurvivorLeaderboardBridge.setKillCount(repo, 1L, "alice", 25);

        assertNotNull(updated);
        assertEquals("alice", updated.username());
        assertEquals(1L, updated.steamId());
        assertEquals(25, updated.killCount());
        assertEquals(25, killCountOf(1L, "alice"));
    }

    @Test
    void upsertsSurvivorIfMissing() throws Exception {
        SurvivorRecord updated = SurvivorLeaderboardBridge.setKillCount(repo, 7L, "newbie", 10);

        assertNotNull(updated);
        assertEquals("newbie", updated.username());
        assertEquals(7L, updated.steamId());
        assertEquals(10, updated.killCount());
        // day_count stays 0 — setKillCount only touches kill_count.
        assertEquals(0, updated.dayCount());
    }

    @Test
    void allowsZero() throws Exception {
        repo.insertSurvivor(1L, "alice");
        setKillCountDirectly(1L, "alice", 9);

        SurvivorRecord updated = SurvivorLeaderboardBridge.setKillCount(repo, 1L, "alice", 0);

        assertNotNull(updated);
        assertEquals(0, updated.killCount());
    }

    @Test
    void allowsNegativeMirroringAllyGriefConvention() throws Exception {
        // Negative kill counts already exist in this schema (ally-grief penalty), so admins must
        // be able to set them too.
        repo.insertSurvivor(1L, "alice");

        SurvivorRecord updated = SurvivorLeaderboardBridge.setKillCount(repo, 1L, "alice", -16);

        assertNotNull(updated);
        assertEquals(-16, updated.killCount());
        assertTrue(killCountOf(1L, "alice") < 0);
    }

    @Test
    void differentUsernamesUnderSameSteamIdAreIndependent() throws Exception {
        // A single Steam account can host multiple characters — each (steamId, username) pair is
        // its own row.
        repo.insertSurvivor(1L, "alice");
        repo.insertSurvivor(1L, "alice_alt");

        SurvivorLeaderboardBridge.setKillCount(repo, 1L, "alice", 5);
        SurvivorLeaderboardBridge.setKillCount(repo, 1L, "alice_alt", 12);

        assertEquals(5, killCountOf(1L, "alice"));
        assertEquals(12, killCountOf(1L, "alice_alt"));
    }

    @Test
    void doesNotTouchOtherColumns() throws Exception {
        repo.insertSurvivor(1L, "alice");
        repo.updateDayCount(1L, "alice", 42);
        repo.updateZombieKills(1L, "alice", 999);

        SurvivorRecord updated = SurvivorLeaderboardBridge.setKillCount(repo, 1L, "alice", 7);

        assertNotNull(updated);
        assertEquals(42, updated.dayCount());
        assertEquals(7, updated.killCount());
        assertEquals(999, updated.zombieKills());
    }

    private void setKillCountDirectly(long steamId, String username, int count) throws Exception {
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
}
