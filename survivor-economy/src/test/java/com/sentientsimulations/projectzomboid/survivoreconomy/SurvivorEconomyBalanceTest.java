package com.sentientsimulations.projectzomboid.survivoreconomy;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.sentientsimulations.projectzomboid.survivoreconomy.records.TransactionDraft;
import java.io.File;
import java.sql.SQLException;
import java.util.Map;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

/**
 * Integration tests for the {@code economy_balance} table — verifying that every {@link
 * SurvivorEconomyRepository#insertSole} / {@link SurvivorEconomyRepository#insertPair} call applies
 * a matching delta in the same SQL transaction. The {@code economy_balance} row must always equal
 * {@code SUM(amount)} from {@code economy_transactions} for the same player + currency, and a
 * rollback on either side must leave both tables untouched.
 */
class SurvivorEconomyBalanceTest {

    @TempDir File tempDir;

    private SurvivorEconomyDatabase db;
    private SurvivorEconomyRepository repo;
    private SurvivorEconomyBalanceRepository balanceRepo;

    @BeforeEach
    void setUp() throws Exception {
        db =
                new SurvivorEconomyDatabase(
                        new File(tempDir, "survivor_economy.db").getAbsolutePath());
        repo = new SurvivorEconomyRepository(db.getConnection());
        balanceRepo = new SurvivorEconomyBalanceRepository(db.getConnection());
    }

    @AfterEach
    void tearDown() throws Exception {
        if (db != null) {
            db.close();
        }
    }

    @Test
    void insertSoleCreatesBalanceRowOnFirstTouch() throws Exception {
        repo.insertSole(TransactionDraft.basic("PAYCHECK", 100L, "alice", 1L, "primary", 200.0));

        Map<String, Double> balances = balanceRepo.getBalances("alice", 1L);
        assertEquals(1, balances.size());
        assertEquals(200.0, balances.get("primary"));
    }

    @Test
    void insertSoleAccumulatesAcrossMultipleInserts() throws Exception {
        repo.insertSole(TransactionDraft.basic("PAYCHECK", 100L, "alice", 1L, "primary", 200.0));
        repo.insertSole(TransactionDraft.basic("PAYCHECK", 200L, "alice", 1L, "primary", 200.0));
        repo.insertSole(
                TransactionDraft.basic("ZOMBIE_BOUNTY", 300L, "alice", 1L, "primary", 50.0));

        assertEquals(450.0, balanceRepo.getBalances("alice", 1L).get("primary"));
    }

    @Test
    void insertSoleNegativeAmountSubtractsFromBalance() throws Exception {
        repo.insertSole(
                TransactionDraft.basic("BANK_DEPOSIT", 100L, "alice", 1L, "primary", 1000.0));
        repo.insertSole(
                TransactionDraft.basic("BANK_WITHDRAW", 200L, "alice", 1L, "primary", -250.0));

        assertEquals(750.0, balanceRepo.getBalances("alice", 1L).get("primary"));
    }

    @Test
    void insertPairUpdatesBothSidesBalances() throws Exception {
        TransactionDraft from =
                TransactionDraft.basic(
                        "BANK_WIRE_TO_PLAYER", 1_000L, "alice", 1L, "primary", -100.0);
        TransactionDraft to =
                TransactionDraft.basic("BANK_WIRE_TO_PLAYER", 1_000L, "bob", 2L, "primary", 100.0);

        repo.insertPair(from, to);

        assertEquals(-100.0, balanceRepo.getBalances("alice", 1L).get("primary"));
        assertEquals(100.0, balanceRepo.getBalances("bob", 2L).get("primary"));
    }

    @Test
    void differentCurrenciesTrackedAsSeparateRows() throws Exception {
        repo.insertSole(
                TransactionDraft.basic("BANK_DEPOSIT", 100L, "alice", 1L, "primary", 1000.0));
        repo.insertSole(TransactionDraft.basic("PAYCHECK", 200L, "alice", 1L, "paycheck", 75.0));
        repo.insertSole(TransactionDraft.basic("PAYCHECK", 300L, "alice", 1L, "paycheck", 75.0));

        Map<String, Double> balances = balanceRepo.getBalances("alice", 1L);
        assertEquals(2, balances.size());
        assertEquals(1000.0, balances.get("primary"));
        assertEquals(150.0, balances.get("paycheck"));
    }

    @Test
    void sameSteamIdDifferentUsernamesAreSeparateBalanceRows() throws Exception {
        repo.insertSole(
                TransactionDraft.basic("PAYCHECK", 100L, "alice-main", 1L, "primary", 100.0));
        repo.insertSole(
                TransactionDraft.basic("PAYCHECK", 200L, "alice-alt", 1L, "primary", 250.0));

        assertEquals(100.0, balanceRepo.getBalances("alice-main", 1L).get("primary"));
        assertEquals(250.0, balanceRepo.getBalances("alice-alt", 1L).get("primary"));
    }

    @Test
    void balanceMatchesSumOfTransactionsAfterMixedInserts() throws Exception {
        repo.insertSole(
                TransactionDraft.basic("BANK_DEPOSIT", 100L, "alice", 1L, "primary", 1000.0));
        repo.insertSole(
                TransactionDraft.basic("BANK_WITHDRAW", 200L, "alice", 1L, "primary", -250.0));
        repo.insertPair(
                TransactionDraft.basic("BANK_WIRE_TO_PLAYER", 300L, "alice", 1L, "primary", -100.0),
                TransactionDraft.basic("BANK_WIRE_TO_PLAYER", 300L, "bob", 2L, "primary", 100.0));

        // economy_balance and SUM(amount) over economy_transactions must agree.
        Map<String, Double> balanceTable = balanceRepo.getBalances("alice", 1L);
        Map<String, Double> sumOverTx = repo.loadBalances("alice", 1L);
        assertEquals(sumOverTx.get("primary"), balanceTable.get("primary"));
        assertEquals(650.0, balanceTable.get("primary"));
    }

    @Test
    void insertPairRollbackLeavesBalanceTableEmpty() throws Exception {
        // Force a NOT NULL violation on the TO row so the whole transaction rolls back. Both the
        // economy_transactions inserts and the economy_balance upserts must be undone together.
        TransactionDraft good = TransactionDraft.basic("WIRE", 1L, "alice", 1L, "primary", -10.0);
        TransactionDraft bad =
                new TransactionDraft(
                        null, 1L, null, null, "bob", 2L, "primary", 10.0, null, null, null, null,
                        null, null, null, null, null);

        assertThrows(SQLException.class, () -> repo.insertPair(good, bad));

        assertTrue(
                balanceRepo.getBalances("alice", 1L).isEmpty(),
                "expected rollback to leave alice's balance row absent");
        assertTrue(
                balanceRepo.getBalances("bob", 2L).isEmpty(),
                "expected rollback to leave bob's balance row absent");
    }

    @Test
    void getBalancesReturnsEmptyForUnknownPlayer() throws Exception {
        assertTrue(balanceRepo.getBalances("never-played", 999L).isEmpty());
    }

    @Test
    void insertSoleAfterRollbackStillCommitsCleanly() throws Exception {
        // Rollback path leaves auto-commit restored — a follow-up insert must still go through.
        TransactionDraft bad =
                new TransactionDraft(
                        null, 1L, null, null, "alice", 1L, "primary", 100.0, null, null, null, null,
                        null, null, null, null, null);
        assertThrows(SQLException.class, () -> repo.insertSole(bad));
        assertNull(balanceRepo.getBalances("alice", 1L).get("primary"));

        repo.insertSole(TransactionDraft.basic("PAYCHECK", 2L, "alice", 1L, "primary", 50.0));
        assertEquals(50.0, balanceRepo.getBalances("alice", 1L).get("primary"));
        assertTrue(db.getConnection().getAutoCommit());
    }
}
