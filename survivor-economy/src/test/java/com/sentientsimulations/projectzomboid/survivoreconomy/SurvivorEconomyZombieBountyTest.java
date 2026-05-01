package com.sentientsimulations.projectzomboid.survivoreconomy;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.sentientsimulations.projectzomboid.survivoreconomy.records.BountyResult;
import com.sentientsimulations.projectzomboid.survivoreconomy.records.TransactionEntry;
import java.io.File;
import java.util.List;
import java.util.Map;
import java.util.function.IntSupplier;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

/**
 * Tests for {@link SurvivorEconomyZombieBounty}. Drives {@code processKill} with deterministic
 * {@link IntSupplier} rolls and explicit sandbox values so tests don't depend on a live {@code
 * SandboxOptions.instance} or {@code ThreadLocalRandom}. Uses a real SQLite DB in a temp dir.
 */
class SurvivorEconomyZombieBountyTest {

    private static final int CHANCE = 50;
    private static final int MIN = 5;
    private static final int MAX = 10;

    @TempDir File tempDir;

    private File dbFile;
    private SurvivorEconomyDatabase db;
    private SurvivorEconomyRepository txRepo;

    @BeforeEach
    void setUp() throws Exception {
        dbFile = new File(tempDir, "survivor_economy.db");
        db = new SurvivorEconomyDatabase(dbFile.getAbsolutePath());
        txRepo = new SurvivorEconomyRepository(db.getConnection());
    }

    @AfterEach
    void tearDown() throws Exception {
        if (db != null) {
            db.close();
        }
    }

    private static IntSupplier always(int value) {
        return () -> value;
    }

    @Test
    void payBountyFalseNeverInsertsRow() throws Exception {
        BountyResult result =
                SurvivorEconomyZombieBounty.processKill(
                        txRepo,
                        "alice",
                        1L,
                        1_000L,
                        always(0),
                        always(MAX),
                        false,
                        CHANCE,
                        MIN,
                        MAX);

        assertNull(result);
        assertTrue(txRepo.loadRecent(10, null, null, null).isEmpty());
    }

    @Test
    void chanceMissDoesNotInsertRow() throws Exception {
        BountyResult result =
                SurvivorEconomyZombieBounty.processKill(
                        txRepo,
                        "alice",
                        1L,
                        1_000L,
                        always(CHANCE + 1),
                        always(MAX),
                        true,
                        CHANCE,
                        MIN,
                        MAX);

        assertNull(result);
        assertTrue(txRepo.loadRecent(10, null, null, null).isEmpty());
    }

    @Test
    void chanceHitInsertsBountyRow() throws Exception {
        long now = 9_000L;
        int amount = 7;
        BountyResult result =
                SurvivorEconomyZombieBounty.processKill(
                        txRepo,
                        "alice",
                        1L,
                        now,
                        always(0),
                        always(amount),
                        true,
                        CHANCE,
                        MIN,
                        MAX);

        assertNotNull(result);
        assertTrue(result.eventId().startsWith("evt_"));
        assertEquals(amount, result.amount());

        List<TransactionEntry> rows = txRepo.loadByEventId(result.eventId());
        assertEquals(1, rows.size());
        TransactionEntry e = rows.get(0);
        assertEquals(SurvivorEconomyZombieBounty.BOUNTY_TYPE, e.type());
        assertEquals("SOLE", e.eventRole());
        assertEquals("alice", e.playerUsername());
        assertEquals(1L, e.playerSteamId());
        assertEquals(SurvivorEconomyZombieBounty.BOUNTY_CURRENCY, e.currency());
        assertEquals((double) amount, e.amount());
        assertEquals(now, e.timestampMs());
        assertEquals(SurvivorEconomyZombieBounty.BOUNTY_REASON, e.reason());

        Map<String, Double> balances = txRepo.loadBalances("alice", 1L);
        assertEquals((double) amount, balances.get(SurvivorEconomyZombieBounty.BOUNTY_CURRENCY));
    }

    @Test
    void chanceRollEqualToChanceStillCountsAsHit() throws Exception {
        // chance roll uses `roll <= chance` — boundary is inclusive.
        BountyResult result =
                SurvivorEconomyZombieBounty.processKill(
                        txRepo,
                        "alice",
                        1L,
                        1_000L,
                        always(CHANCE),
                        always(MIN),
                        true,
                        CHANCE,
                        MIN,
                        MAX);

        assertNotNull(result);
    }

    @Test
    void bountyAmountAtMinAndMaxBoundsAreInclusive() throws Exception {
        BountyResult minResult =
                SurvivorEconomyZombieBounty.processKill(
                        txRepo,
                        "alice",
                        1L,
                        1_000L,
                        always(0),
                        always(MIN),
                        true,
                        CHANCE,
                        MIN,
                        MAX);
        BountyResult maxResult =
                SurvivorEconomyZombieBounty.processKill(
                        txRepo,
                        "alice",
                        1L,
                        2_000L,
                        always(0),
                        always(MAX),
                        true,
                        CHANCE,
                        MIN,
                        MAX);

        assertNotNull(minResult);
        assertNotNull(maxResult);
        assertEquals(MIN, minResult.amount());
        assertEquals(MAX, maxResult.amount());
    }

    @Test
    void multipleKillsAccumulateInBalance() throws Exception {
        int[] amounts = {5, 7, 10};
        for (int i = 0; i < amounts.length; i++) {
            int amount = amounts[i];
            BountyResult result =
                    SurvivorEconomyZombieBounty.processKill(
                            txRepo,
                            "alice",
                            1L,
                            1_000L + i,
                            always(0),
                            always(amount),
                            true,
                            CHANCE,
                            MIN,
                            MAX);
            assertNotNull(result);
            assertEquals(amount, result.amount());
        }

        Map<String, Double> balances = txRepo.loadBalances("alice", 1L);
        assertEquals(
                (double) (5 + 7 + 10), balances.get(SurvivorEconomyZombieBounty.BOUNTY_CURRENCY));
        assertEquals(
                3,
                txRepo.loadRecent(10, "alice", 1L, SurvivorEconomyZombieBounty.BOUNTY_TYPE).size());
    }

    @Test
    void multipleCharactersOnOneSteamIdTrackIndependently() throws Exception {
        SurvivorEconomyZombieBounty.processKill(
                txRepo, "alice-main", 1L, 1_000L, always(0), always(MAX), true, CHANCE, MIN, MAX);
        SurvivorEconomyZombieBounty.processKill(
                txRepo,
                "alice-alt",
                1L,
                2_000L,
                always(CHANCE + 1),
                always(MAX),
                true,
                CHANCE,
                MIN,
                MAX);

        Map<String, Double> mainBal = txRepo.loadBalances("alice-main", 1L);
        Map<String, Double> altBal = txRepo.loadBalances("alice-alt", 1L);
        assertEquals((double) MAX, mainBal.get(SurvivorEconomyZombieBounty.BOUNTY_CURRENCY));
        assertNull(altBal.get(SurvivorEconomyZombieBounty.BOUNTY_CURRENCY));
    }
}
