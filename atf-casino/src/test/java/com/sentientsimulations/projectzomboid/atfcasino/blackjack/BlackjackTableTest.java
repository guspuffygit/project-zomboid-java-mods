package com.sentientsimulations.projectzomboid.atfcasino.blackjack;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.sentientsimulations.projectzomboid.atfcasino.blackjack.BlackjackTable.Action;
import com.sentientsimulations.projectzomboid.atfcasino.blackjack.BlackjackTable.Outcome;
import com.sentientsimulations.projectzomboid.atfcasino.blackjack.BlackjackTable.Phase;
import com.sentientsimulations.projectzomboid.atfcasino.blackjack.BlackjackTable.Seat;
import java.util.HashMap;
import java.util.Map;
import java.util.Random;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

class BlackjackTableTest {

    private static final int MIN = 100;
    private static final int MAX = 10_000;

    /** In-memory bank with per-user balances; refuses when short. */
    private static final class FakeBank implements BlackjackTable.Bank {
        final Map<String, Integer> balance = new HashMap<>();
        int takes;
        int gives;

        void fund(String user, int amount) {
            balance.merge(user, amount, Integer::sum);
        }

        @Override
        public String take(String username, long steamId, int amount, String reason) {
            int have = balance.getOrDefault(username, 0);
            if (have < amount) {
                return "INSUFFICIENT_BALANCE";
            }
            balance.put(username, have - amount);
            takes++;
            return null;
        }

        @Override
        public void give(String username, long steamId, int amount, String reason) {
            balance.merge(username, amount, Integer::sum);
            gives++;
        }
    }

    private FakeBank bank;
    private BlackjackTable table;
    private long now;

    @BeforeEach
    void setUp() {
        bank = new FakeBank();
        table = new BlackjackTable(bank, limits(), new Random(42L));
        now = 1_000_000L;
    }

    private static BlackjackTable.Limits limits() {
        return new BlackjackTable.Limits() {
            @Override
            public int minBet() {
                return MIN;
            }

            @Override
            public int maxBet() {
                return MAX;
            }
        };
    }

    @Test
    void sitAndLeave() {
        assertTrue(table.sit("alice", 1L).ok());
        assertEquals(Action.ALREADY_SEATED, table.sit("Alice", 1L).action());
        for (int i = 1; i < BlackjackTable.MAX_SEATS; i++) {
            assertTrue(table.sit("p" + i, i).ok());
        }
        assertEquals(Action.TABLE_FULL, table.sit("late", 99L).action());
        assertTrue(table.leave("p1", now).ok());
        assertTrue(table.hasFreeSeat());
        assertEquals(Action.NOT_SEATED, table.leave("p1", now).action());
    }

    @Test
    void betValidation() {
        bank.fund("alice", 500);
        assertEquals(Action.NOT_SEATED, table.bet("alice", 100, now).action());
        table.sit("alice", 1L);
        assertEquals(Action.BET_TOO_LOW, table.bet("alice", MIN - 1, now).action());
        assertEquals(Action.BET_TOO_HIGH, table.bet("alice", MAX + 1, now).action());
        BlackjackTable.Result refused = table.bet("alice", 400, now);
        assertEquals(Action.OK, refused.action());
        assertEquals(100, bank.balance.get("alice"));
        // solo player: round starts immediately once they bet
        assertEquals(Phase.PLAYING, table.phase());
        assertEquals(Action.NOT_BETTING_PHASE, table.bet("alice", 100, now).action());
    }

    @Test
    void insufficientFundsIsRefusedWithoutStateChange() {
        bank.fund("alice", 50);
        table.sit("alice", 1L);
        BlackjackTable.Result r = table.bet("alice", 100, now);
        assertEquals(Action.BANK_REFUSED, r.action());
        assertEquals("INSUFFICIENT_BALANCE", r.detail());
        assertEquals(Phase.BETTING, table.phase());
        assertEquals(0, table.seatOf("alice").bet());
    }

    @Test
    void bettingWindowOpensAtFirstBetAndStartsOnTimeout() {
        bank.fund("alice", 1000);
        bank.fund("bob", 1000);
        table.sit("alice", 1L);
        table.sit("bob", 2L);
        assertTrue(table.bet("alice", 100, now).ok());
        assertEquals(Phase.BETTING, table.phase());
        assertEquals(20, table.secondsLeft(now));
        table.tick(now + BlackjackTable.BET_WINDOW_MS - 1);
        assertEquals(Phase.BETTING, table.phase());
        table.tick(now + BlackjackTable.BET_WINDOW_MS);
        assertEquals(Phase.PLAYING, table.phase());
        // bob sat out: no cards, no stake taken
        assertEquals(0, table.seatOf("bob").hand().size());
        assertEquals(1000, bank.balance.get("bob"));
        assertEquals(2, table.seatOf("alice").hand().size());
        assertEquals(2, table.dealerHand().size());
    }

    @Test
    void roundStartsWhenEveryoneHasBet() {
        bank.fund("alice", 1000);
        bank.fund("bob", 1000);
        table.sit("alice", 1L);
        table.sit("bob", 2L);
        table.bet("alice", 100, now);
        assertEquals(Phase.BETTING, table.phase());
        table.bet("bob", 200, now);
        assertEquals(Phase.PLAYING, table.phase());
        assertEquals(1, table.round());
    }

    @Test
    void leavingDuringBettingRefunds() {
        bank.fund("alice", 1000);
        bank.fund("bob", 1000);
        table.sit("alice", 1L);
        table.sit("bob", 2L);
        table.bet("alice", 300, now);
        assertEquals(700, bank.balance.get("alice"));
        table.leave("alice", now);
        assertEquals(1000, bank.balance.get("alice"));
        assertNull(table.seatOf("alice"));
        assertEquals(Phase.BETTING, table.phase());
    }

    @Test
    void fullRoundSettlesAndReturnsToBetting() {
        bank.fund("alice", 1000);
        table.sit("alice", 1L);
        table.bet("alice", 100, now);
        assertEquals(Phase.PLAYING, table.phase());
        // Play every hand to a conclusion by standing; whatever the shoe dealt, money must balance.
        int safety = 0;
        while (table.phase() == Phase.PLAYING && safety++ < 10) {
            Seat s = table.seatOf("alice");
            if (table.currentSeat() == s.index()) {
                table.stand("alice", now);
            } else {
                table.tick(now);
            }
        }
        assertEquals(Phase.SETTLE, table.phase());
        Seat s = table.seatOf("alice");
        assertTrue(s.outcome() != Outcome.NONE);
        assertFalse(table.isHoleHidden());
        int expected =
                switch (s.outcome()) {
                    case WIN -> 200;
                    case BLACKJACK -> 250;
                    case PUSH -> 100;
                    default -> 0;
                };
        assertEquals(expected, s.payout());
        assertEquals(900 + expected, bank.balance.get("alice"));
        // Dealer must have drawn to at least 17 unless alice busted/blackjacked.
        if (s.outcome() == Outcome.WIN
                || s.outcome() == Outcome.LOSE
                || s.outcome() == Outcome.PUSH) {
            assertTrue(table.dealerHand().total() >= 17);
        }
        table.tick(now + BlackjackTable.SETTLE_MS);
        assertEquals(Phase.BETTING, table.phase());
        assertEquals(0, table.seatOf("alice").bet());
        assertEquals(0, table.seatOf("alice").hand().size());
        assertTrue(table.isHoleHidden());
    }

    @Test
    void actionTimeoutStandsForThePlayer() {
        bank.fund("alice", 1000);
        table.sit("alice", 1L);
        table.bet("alice", 100, now);
        if (table.phase() != Phase.PLAYING || table.currentSeat() < 0) {
            return; // natural blackjack on the deal: nothing to time out
        }
        table.tick(now + BlackjackTable.ACTION_MS);
        assertEquals(Phase.SETTLE, table.phase());
    }

    @Test
    void limitsTimingOverridesDrivePhaseDeadlines() {
        BlackjackTable.Limits fast =
                new BlackjackTable.Limits() {
                    @Override
                    public int minBet() {
                        return MIN;
                    }

                    @Override
                    public int maxBet() {
                        return MAX;
                    }

                    @Override
                    public long actionMs() {
                        return 3_000L;
                    }

                    @Override
                    public long settleMs() {
                        return 2_000L;
                    }
                };
        table = new BlackjackTable(bank, fast, new Random(42L));
        bank.fund("alice", 1000);
        table.sit("alice", 1L);
        table.bet("alice", 100, now);
        if (table.phase() != Phase.PLAYING || table.currentSeat() < 0) {
            return; // natural blackjack on the deal: nothing to time out
        }
        table.tick(now + 2_999L);
        assertEquals(Phase.PLAYING, table.phase());
        table.tick(now + 3_000L);
        assertEquals(Phase.SETTLE, table.phase());
        long settled = now + 3_000L;
        table.tick(settled + 1_999L);
        assertEquals(Phase.SETTLE, table.phase());
        table.tick(settled + 2_000L);
        assertEquals(Phase.BETTING, table.phase());
    }

    @Test
    void hitAndDoubleRules() {
        bank.fund("alice", 1000);
        table.sit("alice", 1L);
        assertEquals(Action.NOT_YOUR_TURN, table.hit("alice", now).action());
        table.bet("alice", 100, now);
        Seat s = table.seatOf("alice");
        if (table.currentSeat() != s.index()) {
            return; // dealt a natural; covered elsewhere
        }
        assertTrue(table.canDouble(s));
        assertTrue(table.hit("alice", now).ok());
        if (table.phase() == Phase.PLAYING) {
            assertFalse(table.canDouble(s));
            assertEquals(Action.CANNOT_DOUBLE, table.doubleDown("alice", now).action());
        }
    }

    @Test
    void doubleDownTakesSecondStakeAndEndsTurn() {
        // Search seeds for a deal where alice's first action is available, then double.
        for (long seed = 0; seed < 50; seed++) {
            bank = new FakeBank();
            bank.fund("alice", 1000);
            table = new BlackjackTable(bank, limits(), new Random(seed));
            table.sit("alice", 1L);
            table.bet("alice", 100, now);
            Seat s = table.seatOf("alice");
            if (table.currentSeat() != s.index()) {
                continue;
            }
            assertTrue(table.doubleDown("alice", now).ok());
            assertEquals(200, s.bet());
            assertEquals(3, s.hand().size());
            assertEquals(Phase.SETTLE, table.phase());
            int expected =
                    switch (s.outcome()) {
                        case WIN -> 400;
                        case PUSH -> 200;
                        default -> 0;
                    };
            assertEquals(800 + expected, bank.balance.get("alice"));
            return;
        }
        throw new AssertionError("no seed produced a double-down opportunity");
    }

    @Test
    void leavingMidHandAutoStandsAndStillPaysOut() {
        bank.fund("alice", 1000);
        bank.fund("bob", 1000);
        table.sit("alice", 1L);
        table.sit("bob", 2L);
        table.bet("alice", 100, now);
        table.bet("bob", 100, now);
        assertEquals(Phase.PLAYING, table.phase());
        assertTrue(table.leave("alice", now).ok());
        Seat alice = table.seatOf("alice");
        assertNotNull(alice, "seat is kept until the hand settles");
        assertTrue(alice.isLeaving());
        // finish bob's hand
        int safety = 0;
        while (table.phase() == Phase.PLAYING && safety++ < 10) {
            if (table.currentSeat() == table.seatOf("bob").index()) {
                table.stand("bob", now);
            } else {
                table.tick(now);
            }
        }
        assertEquals(Phase.SETTLE, table.phase());
        assertTrue(alice.outcome() != Outcome.NONE);
        assertEquals(900 + alice.payout(), bank.balance.get("alice"));
        table.tick(now + BlackjackTable.SETTLE_MS);
        assertNull(table.seatOf("alice"));
        assertNotNull(table.seatOf("bob"));
    }

    @Test
    void handScoring() {
        Hand h = new Hand();
        h.add(new Card(1, 's'));
        h.add(new Card(13, 'h'));
        assertEquals(21, h.total());
        assertTrue(h.isBlackjack());
        assertTrue(h.isSoft());
        h.add(new Card(5, 'd'));
        assertEquals(16, h.total());
        assertFalse(h.isSoft());
        assertFalse(h.isBlackjack());
        Hand two = new Hand();
        two.add(new Card(1, 's'));
        two.add(new Card(1, 'c'));
        assertEquals(12, two.total());
        assertEquals("10h", new Card(10, 'h').code());
        assertEquals("As", new Card(1, 's').code());
        assertEquals("Kd", new Card(13, 'd').code());
    }

    @Test
    void moneyIsConservedOverManyRounds() {
        Random rng = new Random(7L);
        bank.fund("alice", 100_000);
        bank.fund("bob", 100_000);
        table.sit("alice", 1L);
        table.sit("bob", 2L);
        int houseDelta = 0;
        int startTotal = 200_000;
        for (int round = 0; round < 200; round++) {
            table.bet("alice", 100, now);
            table.bet("bob", 100, now);
            int safety = 0;
            while (table.phase() == Phase.PLAYING && safety++ < 20) {
                int cur = table.currentSeat();
                Seat s = table.seat(cur);
                if (s == null) {
                    table.tick(now);
                    continue;
                }
                if (rng.nextBoolean() && s.hand().total() < 17) {
                    table.hit(s.username(), now);
                } else {
                    table.stand(s.username(), now);
                }
            }
            assertEquals(Phase.SETTLE, table.phase());
            table.tick(now + BlackjackTable.SETTLE_MS);
            assertEquals(Phase.BETTING, table.phase());
        }
        int endTotal = bank.balance.get("alice") + bank.balance.get("bob");
        // Player money only changes via take/give, and the engine never pays more than
        // 2.5x a stake: total must remain within [start - 2*200*200, start + 1.5*200*200].
        assertTrue(endTotal >= startTotal - 80_000 && endTotal <= startTotal + 60_000);
        assertTrue(bank.takes > 0 && bank.gives > 0);
    }
}
