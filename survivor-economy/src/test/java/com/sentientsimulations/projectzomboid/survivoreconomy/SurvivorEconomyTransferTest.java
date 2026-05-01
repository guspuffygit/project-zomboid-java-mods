package com.sentientsimulations.projectzomboid.survivoreconomy;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.sentientsimulations.projectzomboid.survivoreconomy.records.TransactionDraft;
import com.sentientsimulations.projectzomboid.survivoreconomy.records.TransactionEntry;
import com.sentientsimulations.projectzomboid.survivoreconomy.records.TransferFailureReason;
import com.sentientsimulations.projectzomboid.survivoreconomy.records.TransferResult;
import java.io.File;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

/**
 * Tests for {@link SurvivorEconomyTransfer}. Drives {@code processTransfer} directly with explicit
 * usernames / steam ids / amounts so tests don't depend on a live {@code IsoPlayer}, {@code
 * SandboxOptions.instance}, or {@code GameServer}. Uses a real SQLite DB in a temp dir.
 */
class SurvivorEconomyTransferTest {

    private static final String CURRENCY = "primary";

    @TempDir File tempDir;

    private File dbFile;
    private SurvivorEconomyDatabase db;
    private SurvivorEconomyRepository txRepo;
    private SurvivorEconomyBalanceRepository balanceRepo;

    @BeforeEach
    void setUp() throws Exception {
        dbFile = new File(tempDir, "survivor_economy.db");
        db = new SurvivorEconomyDatabase(dbFile.getAbsolutePath());
        txRepo = new SurvivorEconomyRepository(db.getConnection());
        balanceRepo = new SurvivorEconomyBalanceRepository(db.getConnection());
    }

    @AfterEach
    void tearDown() throws Exception {
        if (db != null) {
            db.close();
        }
    }

    private void seedBalance(String username, long steamId, double amount) throws Exception {
        txRepo.insertSole(
                TransactionDraft.basic("ADMIN_GRANT", 1L, username, steamId, CURRENCY, amount));
    }

    @Test
    void transferDebitsAndCreditsBothSidesAtomically() throws Exception {
        seedBalance("alice", 1L, 100.0);

        TransferResult result =
                SurvivorEconomyTransfer.processTransfer(
                        txRepo, balanceRepo, "alice", 1L, "bob", 2L, CURRENCY, 30.0, 5_000L);

        assertTrue(result.ok());
        assertNotNull(result.eventId());
        assertNull(result.failureReason());

        Map<String, Double> aliceBal = balanceRepo.getBalances("alice", 1L);
        Map<String, Double> bobBal = balanceRepo.getBalances("bob", 2L);
        assertEquals(70.0, aliceBal.get(CURRENCY));
        assertEquals(30.0, bobBal.get(CURRENCY));

        List<TransactionEntry> rows = txRepo.loadByEventId(result.eventId());
        assertEquals(2, rows.size());
        TransactionEntry from = rows.get(0);
        TransactionEntry to = rows.get(1);
        assertEquals("FROM", from.eventRole());
        assertEquals("TO", to.eventRole());
        assertEquals("alice", from.playerUsername());
        assertEquals(-30.0, from.amount());
        assertEquals("bob", to.playerUsername());
        assertEquals(30.0, to.amount());
    }

    @Test
    void transferFailsWithInsufficientBalance() throws Exception {
        seedBalance("alice", 1L, 30.0);

        TransferResult result =
                SurvivorEconomyTransfer.processTransfer(
                        txRepo, balanceRepo, "alice", 1L, "bob", 2L, CURRENCY, 50.0, 5_000L);

        assertFalse(result.ok());
        assertEquals(TransferFailureReason.INSUFFICIENT_BALANCE, result.failureReason());

        Map<String, Double> aliceBal = balanceRepo.getBalances("alice", 1L);
        Map<String, Double> bobBal = balanceRepo.getBalances("bob", 2L);
        assertEquals(30.0, aliceBal.get(CURRENCY));
        assertNull(bobBal.get(CURRENCY));
        // Only the seed row exists, no transfer rows.
        assertEquals(1, txRepo.loadRecent(10, null, null, null).size());
    }

    @Test
    void transferToSelfReturnsSamePlayer() throws Exception {
        seedBalance("alice", 1L, 100.0);

        TransferResult result =
                SurvivorEconomyTransfer.processTransfer(
                        txRepo, balanceRepo, "alice", 1L, "alice", 1L, CURRENCY, 10.0, 5_000L);

        assertFalse(result.ok());
        assertEquals(TransferFailureReason.SAME_PLAYER, result.failureReason());
        assertEquals(100.0, balanceRepo.getBalances("alice", 1L).get(CURRENCY));
    }

    @Test
    void transferZeroOrNegativeAmountReturnsInvalidAmount() throws Exception {
        seedBalance("alice", 1L, 100.0);

        TransferResult zero =
                SurvivorEconomyTransfer.processTransfer(
                        txRepo, balanceRepo, "alice", 1L, "bob", 2L, CURRENCY, 0.0, 5_000L);
        TransferResult negative =
                SurvivorEconomyTransfer.processTransfer(
                        txRepo, balanceRepo, "alice", 1L, "bob", 2L, CURRENCY, -10.0, 5_000L);

        assertEquals(TransferFailureReason.INVALID_AMOUNT, zero.failureReason());
        assertEquals(TransferFailureReason.INVALID_AMOUNT, negative.failureReason());
        assertEquals(100.0, balanceRepo.getBalances("alice", 1L).get(CURRENCY));
    }

    @Test
    void transferTypeAndReasonPersisted() throws Exception {
        seedBalance("alice", 1L, 100.0);

        TransferResult result =
                SurvivorEconomyTransfer.processTransfer(
                        txRepo, balanceRepo, "alice", 1L, "bob", 2L, CURRENCY, 25.0, 5_000L);

        List<TransactionEntry> rows = txRepo.loadByEventId(result.eventId());
        for (TransactionEntry row : rows) {
            assertEquals(SurvivorEconomyTransfer.TRANSFER_TYPE, row.type());
            assertEquals(SurvivorEconomyTransfer.TRANSFER_REASON, row.reason());
        }
    }

    @Test
    void multipleTransfersAccumulate() throws Exception {
        seedBalance("alice", 1L, 100.0);

        SurvivorEconomyTransfer.processTransfer(
                txRepo, balanceRepo, "alice", 1L, "bob", 2L, CURRENCY, 10.0, 5_000L);
        SurvivorEconomyTransfer.processTransfer(
                txRepo, balanceRepo, "alice", 1L, "bob", 2L, CURRENCY, 20.0, 6_000L);
        SurvivorEconomyTransfer.processTransfer(
                txRepo, balanceRepo, "alice", 1L, "bob", 2L, CURRENCY, 5.0, 7_000L);

        assertEquals(65.0, balanceRepo.getBalances("alice", 1L).get(CURRENCY));
        assertEquals(35.0, balanceRepo.getBalances("bob", 2L).get(CURRENCY));
        assertEquals(
                3,
                txRepo.loadRecent(10, "alice", 1L, SurvivorEconomyTransfer.TRANSFER_TYPE).size());
        assertEquals(
                3, txRepo.loadRecent(10, "bob", 2L, SurvivorEconomyTransfer.TRANSFER_TYPE).size());
    }

    @Test
    void transferAcrossDifferentCurrenciesIsolated() throws Exception {
        seedBalance("alice", 1L, 100.0);
        txRepo.insertSole(TransactionDraft.basic("ADMIN_GRANT", 1L, "alice", 1L, "paycheck", 50.0));

        SurvivorEconomyTransfer.processTransfer(
                txRepo, balanceRepo, "alice", 1L, "bob", 2L, "primary", 30.0, 5_000L);
        SurvivorEconomyTransfer.processTransfer(
                txRepo, balanceRepo, "alice", 1L, "bob", 2L, "paycheck", 10.0, 6_000L);

        Map<String, Double> aliceBal = balanceRepo.getBalances("alice", 1L);
        Map<String, Double> bobBal = balanceRepo.getBalances("bob", 2L);
        assertEquals(70.0, aliceBal.get("primary"));
        assertEquals(40.0, aliceBal.get("paycheck"));
        assertEquals(30.0, bobBal.get("primary"));
        assertEquals(10.0, bobBal.get("paycheck"));
    }

    @Test
    void transferFromZeroBalanceReturnsInsufficient() throws Exception {
        TransferResult result =
                SurvivorEconomyTransfer.processTransfer(
                        txRepo, balanceRepo, "alice", 1L, "bob", 2L, CURRENCY, 1.0, 5_000L);

        assertFalse(result.ok());
        assertEquals(TransferFailureReason.INSUFFICIENT_BALANCE, result.failureReason());
        assertTrue(txRepo.loadRecent(10, null, null, null).isEmpty());
    }
}
