package com.sentientsimulations.projectzomboid.survivoreconomy;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.sentientsimulations.projectzomboid.survivoreconomy.records.TransactionDraft;
import com.sentientsimulations.projectzomboid.survivoreconomy.records.TransactionEntry;
import java.io.File;
import java.sql.SQLException;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

/**
 * Integration tests for the {@code economy_transactions} table — insert (SOLE and paired FROM/TO),
 * event lookup, recent-list filtering, balance aggregation, parent-event linkage, and paired-insert
 * atomicity. Uses a real SQLite DB in a temp dir.
 */
class SurvivorEconomyTransactionsTest {

    @TempDir File tempDir;

    private SurvivorEconomyDatabase db;
    private SurvivorEconomyRepository repo;

    @BeforeEach
    void setUp() throws Exception {
        db =
                new SurvivorEconomyDatabase(
                        new File(tempDir, "survivor_economy.db").getAbsolutePath());
        repo = new SurvivorEconomyRepository(db.getConnection());
    }

    @AfterEach
    void tearDown() throws Exception {
        if (db != null) {
            db.close();
        }
    }

    @Test
    void insertSolePersistsAllColumns() throws Exception {
        TransactionDraft draft =
                new TransactionDraft(
                        "ZOMBIE_BOUNTY",
                        1_000L,
                        "killed a zombie",
                        null,
                        "alice",
                        42L,
                        "primary",
                        15.5,
                        null,
                        null,
                        null,
                        null,
                        null,
                        null,
                        100.5,
                        200.5,
                        0.0);

        String eventId = repo.insertSole(draft);

        assertNotNull(eventId);
        assertTrue(eventId.startsWith("evt_"));
        List<TransactionEntry> rows = repo.loadByEventId(eventId);
        assertEquals(1, rows.size());
        TransactionEntry e = rows.get(0);
        assertEquals(eventId, e.eventId());
        assertEquals("SOLE", e.eventRole());
        assertEquals("ZOMBIE_BOUNTY", e.type());
        assertEquals("killed a zombie", e.reason());
        assertNull(e.parentEventId());
        assertEquals("alice", e.playerUsername());
        assertEquals(42L, e.playerSteamId());
        assertEquals("primary", e.currency());
        assertEquals(15.5, e.amount());
        assertEquals(100.5, e.deathX());
        assertEquals(200.5, e.deathY());
        assertEquals(0.0, e.deathZ());
        assertNull(e.itemId());
        assertNull(e.walletId());
    }

    @Test
    void insertPairSharesEventIdAndPersistsBothSides() throws Exception {
        TransactionDraft from =
                TransactionDraft.basic(
                        "BANK_WIRE_TO_PLAYER", 5_000L, "alice", 1L, "primary", -100.0);
        TransactionDraft to =
                TransactionDraft.basic("BANK_WIRE_TO_PLAYER", 5_000L, "bob", 2L, "primary", 100.0);

        String eventId = repo.insertPair(from, to);

        List<TransactionEntry> rows = repo.loadByEventId(eventId);
        assertEquals(2, rows.size());
        TransactionEntry first = rows.get(0);
        TransactionEntry second = rows.get(1);
        assertEquals("FROM", first.eventRole());
        assertEquals("TO", second.eventRole());
        assertEquals("alice", first.playerUsername());
        assertEquals("bob", second.playerUsername());
        assertEquals(-100.0, first.amount());
        assertEquals(100.0, second.amount());
        assertEquals(eventId, first.eventId());
        assertEquals(eventId, second.eventId());
    }

    @Test
    void loadRecentReturnsNewestFirstAndRespectsLimit() throws Exception {
        repo.insertSole(TransactionDraft.basic("PAYCHECK", 100L, "alice", 1L, "paycheck", 50.0));
        repo.insertSole(TransactionDraft.basic("PAYCHECK", 300L, "alice", 1L, "paycheck", 50.0));
        repo.insertSole(TransactionDraft.basic("PAYCHECK", 200L, "alice", 1L, "paycheck", 50.0));

        List<TransactionEntry> top2 = repo.loadRecent(2, null, null, null);

        assertEquals(2, top2.size());
        assertEquals(300L, top2.get(0).timestampMs());
        assertEquals(200L, top2.get(1).timestampMs());
    }

    @Test
    void loadRecentFiltersByPlayerAndType() throws Exception {
        repo.insertSole(TransactionDraft.basic("PAYCHECK", 100L, "alice", 1L, "paycheck", 50.0));
        repo.insertSole(TransactionDraft.basic("PAYCHECK", 200L, "bob", 2L, "paycheck", 50.0));
        repo.insertSole(TransactionDraft.basic("BANK_INTEREST", 300L, "alice", 1L, "primary", 5.0));

        List<TransactionEntry> aliceOnly = repo.loadRecent(10, "alice", 1L, null);
        assertEquals(2, aliceOnly.size());

        List<TransactionEntry> alicePaycheck = repo.loadRecent(10, "alice", 1L, "PAYCHECK");
        assertEquals(1, alicePaycheck.size());
        assertEquals("PAYCHECK", alicePaycheck.get(0).type());

        List<TransactionEntry> bySteamOnly = repo.loadRecent(10, null, 2L, null);
        assertEquals(1, bySteamOnly.size());
        assertEquals("bob", bySteamOnly.get(0).playerUsername());
    }

    @Test
    void loadBalancesAggregatesByCurrency() throws Exception {
        repo.insertSole(
                TransactionDraft.basic("BANK_DEPOSIT", 100L, "alice", 1L, "primary", 1000.0));
        repo.insertSole(
                TransactionDraft.basic("BANK_WITHDRAW", 200L, "alice", 1L, "primary", -250.0));
        repo.insertSole(TransactionDraft.basic("PAYCHECK", 300L, "alice", 1L, "paycheck", 75.0));
        repo.insertSole(TransactionDraft.basic("PAYCHECK", 400L, "alice", 1L, "paycheck", 75.0));

        Map<String, Double> balances = repo.loadBalances("alice", 1L);

        assertEquals(2, balances.size());
        assertEquals(750.0, balances.get("primary"));
        assertEquals(150.0, balances.get("paycheck"));
    }

    @Test
    void parentEventIdLinksFollowOnRows() throws Exception {
        // A withdraw spawns a fee. Insert the withdraw first, then a paired fee whose rows
        // both reference the withdraw via parent_event_id.
        String withdrawId =
                repo.insertSole(
                        TransactionDraft.basic(
                                "BANK_WITHDRAW", 1_000L, "alice", 1L, "cash_primary", 1000.0));

        TransactionDraft feeFrom =
                new TransactionDraft(
                        "BANK_FEES",
                        1_000L,
                        "withdraw fee",
                        withdrawId,
                        "alice",
                        1L,
                        "primary",
                        -50.0,
                        null,
                        null,
                        null,
                        null,
                        null,
                        null,
                        null,
                        null,
                        null);
        TransactionDraft feeTo =
                new TransactionDraft(
                        "BANK_FEES",
                        1_000L,
                        "withdraw fee",
                        withdrawId,
                        "bank_owner",
                        999L,
                        "primary",
                        50.0,
                        null,
                        null,
                        null,
                        null,
                        null,
                        null,
                        null,
                        null,
                        null);
        String feeEventId = repo.insertPair(feeFrom, feeTo);

        assertNotEquals(withdrawId, feeEventId);
        List<TransactionEntry> all = repo.loadRecent(10, null, null, null);
        assertEquals(3, all.size());
        for (TransactionEntry e : all) {
            if (e.type().equals("BANK_FEES")) {
                assertEquals(withdrawId, e.parentEventId());
            } else {
                assertNull(e.parentEventId());
            }
        }
    }

    @Test
    void sameSteamIdDifferentUsernamesAreSeparateBalances() throws Exception {
        // Two characters on the same Steam account: alice-main and alice-alt with steamId=1.
        repo.insertSole(
                TransactionDraft.basic("PAYCHECK", 100L, "alice-main", 1L, "primary", 100.0));
        repo.insertSole(
                TransactionDraft.basic("PAYCHECK", 200L, "alice-alt", 1L, "primary", 250.0));

        assertEquals(100.0, repo.loadBalances("alice-main", 1L).get("primary"));
        assertEquals(250.0, repo.loadBalances("alice-alt", 1L).get("primary"));
    }

    @Test
    void insertPairRollsBackOnFailure() throws Exception {
        TransactionDraft good = TransactionDraft.basic("WIRE", 1L, "alice", 1L, "primary", -10.0);
        // type is NOT NULL in the schema, so passing null forces a constraint violation on the
        // second insert; the first insert should be rolled back along with it.
        TransactionDraft bad =
                new TransactionDraft(
                        null, 1L, null, null, "bob", 2L, "primary", 10.0, null, null, null, null,
                        null, null, null, null, null);

        assertThrows(SQLException.class, () -> repo.insertPair(good, bad));

        List<TransactionEntry> remaining = repo.loadRecent(10, null, null, null);
        assertTrue(
                remaining.isEmpty(),
                "expected rollback to leave the table empty, got " + remaining.size() + " row(s)");
        assertTrue(
                db.getConnection().getAutoCommit(),
                "expected auto-commit to be restored after rollback");
    }

    @Test
    void loadByEventIdReturnsEmptyForUnknownId() throws Exception {
        assertTrue(repo.loadByEventId("evt_does_not_exist").isEmpty());
    }
}
