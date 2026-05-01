package com.sentientsimulations.projectzomboid.survivoreconomy;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.sentientsimulations.projectzomboid.survivoreconomy.records.TransactionEntry;
import java.io.File;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

/**
 * Tests for {@link SurvivorEconomyPaycheck} — clock-in tick mechanic, threshold payout, hour
 * carry-over, multi-character isolation, and persistence across DB close/open. Uses a real SQLite
 * DB in a temp dir and drives {@code processClockIn} with explicit sandbox values so tests don't
 * depend on a live {@code SandboxOptions.instance}.
 */
class SurvivorEconomyPaycheckTest {

    private static final int H = 3;
    private static final int V = 200;
    private static final boolean ISSUE = true;

    @TempDir File tempDir;

    private File dbFile;
    private SurvivorEconomyDatabase db;
    private SurvivorEconomyRepository txRepo;
    private SurvivorEconomyPlayerStateRepository stateRepo;

    @BeforeEach
    void setUp() throws Exception {
        dbFile = new File(tempDir, "survivor_economy.db");
        openDb();
    }

    @AfterEach
    void tearDown() throws Exception {
        if (db != null) {
            db.close();
        }
    }

    private void openDb() throws Exception {
        db = new SurvivorEconomyDatabase(dbFile.getAbsolutePath());
        txRepo = new SurvivorEconomyRepository(db.getConnection());
        stateRepo = new SurvivorEconomyPlayerStateRepository(db.getConnection());
    }

    private @org.jspecify.annotations.Nullable String tick(
            String username, long steamId, long nowMs) throws Exception {
        return SurvivorEconomyPaycheck.processClockIn(
                txRepo, stateRepo, username, steamId, nowMs, ISSUE, H, V);
    }

    @Test
    void clockInBelowThresholdIncrementsHoursAndDoesNotPay() throws Exception {
        for (int i = 0; i < H - 1; i++) {
            String eventId = tick("alice", 1L, 1_000L + i);
            assertNull(eventId, "should not pay out below threshold");
        }
        assertEquals(H - 1, stateRepo.getOnlineHours("alice", 1L));
        assertTrue(txRepo.loadRecent(10, null, null, null).isEmpty());
    }

    @Test
    void clockInAtThresholdPaysAndDecrementsHours() throws Exception {
        for (int i = 0; i < H - 1; i++) {
            tick("alice", 1L, 1_000L + i);
        }
        String eventId = tick("alice", 1L, 9_000L);

        assertNotNull(eventId);
        assertTrue(eventId.startsWith("evt_"));
        assertEquals(0, stateRepo.getOnlineHours("alice", 1L));

        List<TransactionEntry> rows = txRepo.loadByEventId(eventId);
        assertEquals(1, rows.size());
        TransactionEntry e = rows.get(0);
        assertEquals("PAYCHECK", e.type());
        assertEquals("SOLE", e.eventRole());
        assertEquals("alice", e.playerUsername());
        assertEquals(1L, e.playerSteamId());
        assertEquals(SurvivorEconomyPaycheck.PAYCHECK_CURRENCY, e.currency());
        assertEquals((double) V, e.amount());
        assertEquals(9_000L, e.timestampMs());

        Map<String, Double> balances = txRepo.loadBalances("alice", 1L);
        assertEquals((double) V, balances.get(SurvivorEconomyPaycheck.PAYCHECK_CURRENCY));
    }

    @Test
    void accumulatedHoursCarryAcrossPayouts() throws Exception {
        int payouts = 0;
        for (int i = 0; i < 2 * H; i++) {
            String eventId = tick("alice", 1L, 1_000L + i);
            if (eventId != null) {
                payouts++;
            }
        }
        assertEquals(2, payouts);
        assertEquals(0, stateRepo.getOnlineHours("alice", 1L));
        assertEquals(
                2.0 * V,
                txRepo.loadBalances("alice", 1L).get(SurvivorEconomyPaycheck.PAYCHECK_CURRENCY));
    }

    @Test
    void multipleCharactersOnOneSteamIdTrackIndependently() throws Exception {
        for (int i = 0; i < H; i++) {
            tick("alice-main", 1L, 1_000L + i);
        }
        for (int i = 0; i < H - 1; i++) {
            tick("alice-alt", 1L, 2_000L + i);
        }

        assertEquals(0, stateRepo.getOnlineHours("alice-main", 1L));
        assertEquals(H - 1, stateRepo.getOnlineHours("alice-alt", 1L));

        Map<String, Double> mainBal = txRepo.loadBalances("alice-main", 1L);
        Map<String, Double> altBal = txRepo.loadBalances("alice-alt", 1L);
        assertEquals((double) V, mainBal.get(SurvivorEconomyPaycheck.PAYCHECK_CURRENCY));
        assertNull(altBal.get(SurvivorEconomyPaycheck.PAYCHECK_CURRENCY));
    }

    @Test
    void onlineHoursPersistAcrossDatabaseReopen() throws Exception {
        stateRepo.setOnlineHours("alice", 1L, 7, 5_000L);
        db.close();

        openDb();

        assertEquals(7, stateRepo.getOnlineHours("alice", 1L));
    }

    @Test
    void issuePaychecksFalseStillResetsHoursButDoesNotPay() throws Exception {
        // Hours decrement OUTSIDE the IssuePaychecks guard: toggling paychecks off should not
        // silently accumulate hours past the threshold, but no PAYCHECK row should be inserted.
        String eventId = null;
        for (int i = 0; i < H; i++) {
            eventId =
                    SurvivorEconomyPaycheck.processClockIn(
                            txRepo, stateRepo, "alice", 1L, 1_000L + i, false, H, V);
        }
        assertNull(eventId);
        assertEquals(0, stateRepo.getOnlineHours("alice", 1L));
        assertTrue(txRepo.loadRecent(10, null, null, null).isEmpty());
        assertNull(txRepo.loadBalances("alice", 1L).get(SurvivorEconomyPaycheck.PAYCHECK_CURRENCY));
    }
}
