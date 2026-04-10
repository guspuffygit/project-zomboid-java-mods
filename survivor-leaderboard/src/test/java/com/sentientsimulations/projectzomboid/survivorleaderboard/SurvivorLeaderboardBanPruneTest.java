package com.sentientsimulations.projectzomboid.survivorleaderboard;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.sentientsimulations.projectzomboid.survivorleaderboard.records.SurvivorRecord;
import java.io.File;
import java.lang.reflect.Field;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.Statement;
import java.util.List;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import zombie.network.ServerWorldDatabase;

/**
 * Integration test for {@link SurvivorLeaderboardBridge#pruneBannedSurvivors(
 * SurvivorLeaderboardRepository)}.
 *
 * <p>Sets up a real leaderboard SQLite DB in a temp dir and an in-memory SQLite DB that stands in
 * for PZ's user database. The latter is injected into {@link ServerWorldDatabase#instance} via
 * reflection on its package-private {@code conn} field so {@code isSteamIdBanned} queries against
 * our test data instead of needing a real PZ server environment.
 */
class SurvivorLeaderboardBanPruneTest {

    private static final long BANNED_STEAM_ID = 76561197960265729L;
    private static final long OTHER_STEAM_ID = 76561197960265730L;

    @TempDir File tempDir;

    private SurvivorLeaderboardDatabase leaderboardDb;
    private SurvivorLeaderboardRepository repo;
    private Connection banDbConn;
    private Connection originalServerWorldDbConn;

    @BeforeEach
    void setUp() throws Exception {
        leaderboardDb =
                new SurvivorLeaderboardDatabase(
                        new File(tempDir, "survivor_leaderboard.db").getAbsolutePath());
        repo = new SurvivorLeaderboardRepository(leaderboardDb.getConnection());

        // Stand-in for PZ's user database: a minimal bannedid table matching what
        // ServerWorldDatabase.isSteamIdBanned expects to query.
        banDbConn = DriverManager.getConnection("jdbc:sqlite::memory:");
        try (Statement stmt = banDbConn.createStatement()) {
            stmt.execute("CREATE TABLE bannedid (steamid TEXT NOT NULL, reason TEXT)");
        }
        try (PreparedStatement ps =
                banDbConn.prepareStatement(
                        "INSERT INTO bannedid (steamid, reason) VALUES (?, ?)")) {
            ps.setString(1, Long.toString(BANNED_STEAM_ID));
            ps.setString(2, "test ban");
            ps.executeUpdate();
        }

        // Inject the test connection into ServerWorldDatabase.instance.conn so the bridge's ban
        // lookup sees our test data. Stash the original so we can restore it in tearDown.
        originalServerWorldDbConn = swapServerWorldDbConn(banDbConn);
    }

    @AfterEach
    void tearDown() throws Exception {
        swapServerWorldDbConn(originalServerWorldDbConn);
        if (banDbConn != null) {
            banDbConn.close();
        }
        if (leaderboardDb != null) {
            leaderboardDb.close();
        }
    }

    @Test
    void pruneRemovesEntriesForBannedSteamId() throws Exception {
        repo.insertSurvivor(BANNED_STEAM_ID, "bannedUser");
        repo.insertSurvivor(OTHER_STEAM_ID, "cleanUser");
        repo.updateDayCount(BANNED_STEAM_ID, "bannedUser", 10);
        repo.updateDayCount(OTHER_STEAM_ID, "cleanUser", 5);

        int removed = SurvivorLeaderboardBridge.pruneBannedSurvivors(repo);

        assertEquals(1, removed, "expected exactly one row removed");

        List<SurvivorRecord> remaining = repo.loadAllOrdered();
        assertEquals(1, remaining.size(), "expected only the unbanned survivor to remain");

        SurvivorRecord survivor = remaining.get(0);
        assertEquals(OTHER_STEAM_ID, survivor.steamId());
        assertEquals("cleanUser", survivor.username());
        assertEquals(5, survivor.dayCount());
    }

    @Test
    void pruneRemovesAllCharactersForBannedSteamId() throws Exception {
        // One Steam account with multiple characters — all should be pruned.
        repo.insertSurvivor(BANNED_STEAM_ID, "bannedChar1");
        repo.insertSurvivor(BANNED_STEAM_ID, "bannedChar2");
        repo.insertSurvivor(OTHER_STEAM_ID, "cleanUser");

        int removed = SurvivorLeaderboardBridge.pruneBannedSurvivors(repo);

        assertEquals(2, removed, "expected both characters of the banned Steam account removed");

        List<SurvivorRecord> remaining = repo.loadAllOrdered();
        assertEquals(1, remaining.size());
        assertEquals(OTHER_STEAM_ID, remaining.get(0).steamId());
        assertEquals("cleanUser", remaining.get(0).username());

        List<Long> steamIds = repo.loadDistinctSteamIds();
        assertFalse(
                steamIds.contains(BANNED_STEAM_ID),
                "banned Steam ID should no longer appear in the leaderboard");
    }

    @Test
    void pruneIsNoopWhenNothingBanned() throws Exception {
        repo.insertSurvivor(OTHER_STEAM_ID, "cleanUser");

        int removed = SurvivorLeaderboardBridge.pruneBannedSurvivors(repo);

        assertEquals(0, removed);
        assertEquals(1, repo.loadAllOrdered().size());
    }

    @Test
    void pruneIsNoopOnEmptyLeaderboard() throws Exception {
        int removed = SurvivorLeaderboardBridge.pruneBannedSurvivors(repo);

        assertEquals(0, removed);
        assertTrue(repo.loadAllOrdered().isEmpty());
    }

    /**
     * Reflectively replace {@link ServerWorldDatabase#instance}.conn with the given connection.
     *
     * @return the prior value so the caller can restore it
     */
    private static Connection swapServerWorldDbConn(Connection replacement) throws Exception {
        Field connField = ServerWorldDatabase.class.getDeclaredField("conn");
        connField.setAccessible(true);
        Connection previous = (Connection) connField.get(ServerWorldDatabase.instance);
        connField.set(ServerWorldDatabase.instance, replacement);
        return previous;
    }
}
