package com.sentientsimulations.projectzomboid.atfcasino.roulette;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.sentientsimulations.projectzomboid.atfcasino.roulette.RouletteTable.Action;
import com.sentientsimulations.projectzomboid.atfcasino.roulette.RouletteTable.BetType;
import com.sentientsimulations.projectzomboid.atfcasino.roulette.RouletteTable.Phase;
import com.sentientsimulations.projectzomboid.atfcasino.roulette.RouletteTable.Seat;
import java.util.HashMap;
import java.util.Map;
import java.util.Random;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

class RouletteTableTest {

    private static final int MIN = 100;
    private static final int MAX = 10_000;

    /** In-memory bank with per-user balances; refuses when short. */
    private static final class FakeBank implements RouletteTable.Bank {
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

    /** Random whose first {@code nextInt} is fixed so the winning number is known. */
    private static final class RiggedRandom extends Random {
        private final int number;

        RiggedRandom(int number) {
            super(1L);
            this.number = number;
        }

        @Override
        public int nextInt(int bound) {
            return number;
        }
    }

    private FakeBank bank;
    private RouletteTable table;
    private long now;

    @BeforeEach
    void setUp() {
        bank = new FakeBank();
        table = new RouletteTable(bank, limits(), new Random(42L));
        now = 1_000_000L;
    }

    private static RouletteTable.Limits limits() {
        return new RouletteTable.Limits() {
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

    private RouletteTable rigged(int number) {
        table = new RouletteTable(bank, limits(), new RiggedRandom(number));
        return table;
    }

    private void runToSettle() {
        now += RouletteTable.BET_WINDOW_MS;
        table.tick(now);
        assertEquals(Phase.SPINNING, table.phase());
        assertEquals(-1, table.winningNumber());
        now += RouletteTable.SPIN_MS;
        table.tick(now);
        assertEquals(Phase.SETTLE, table.phase());
    }

    @Test
    void sitAndLeave() {
        assertTrue(table.sit("alice", 1L).ok());
        assertEquals(Action.ALREADY_SEATED, table.sit("Alice", 1L).action());
        for (int i = 1; i < RouletteTable.MAX_SEATS; i++) {
            assertTrue(table.sit("p" + i, i).ok());
        }
        assertEquals(Action.TABLE_FULL, table.sit("late", 9L).action());
        assertFalse(table.hasFreeSeat());
        assertTrue(table.leave("p1").ok());
        assertTrue(table.hasFreeSeat());
        assertEquals(Action.NOT_SEATED, table.leave("p1").action());
    }

    @Test
    void betValidation() {
        bank.fund("alice", 50_000);
        assertEquals(Action.NOT_SEATED, table.bet("alice", BetType.RED, 0, 100, now).action());
        table.sit("alice", 1L);
        assertEquals(Action.BAD_BET, table.bet("alice", null, 0, 100, now).action());
        assertEquals(Action.BAD_BET, table.bet("alice", BetType.STRAIGHT, 37, 100, now).action());
        assertEquals(Action.BAD_BET, table.bet("alice", BetType.DOZEN, 0, 100, now).action());
        assertEquals(Action.BAD_BET, table.bet("alice", BetType.RED, 1, 100, now).action());
        assertEquals(Action.BET_TOO_LOW, table.bet("alice", BetType.RED, 0, 99, now).action());
        assertEquals(
                Action.BET_TOO_HIGH, table.bet("alice", BetType.RED, 0, MAX + 1, now).action());
        assertTrue(table.bet("alice", BetType.RED, 0, MAX, now).ok());
        // stacking past the max on the same spot is refused
        assertEquals(Action.BET_TOO_HIGH, table.bet("alice", BetType.RED, 0, 100, now).action());
        assertEquals(50_000 - MAX, bank.balance.get("alice"));
        assertEquals(1, bank.takes);
    }

    @Test
    void sameSpotStacksAndBetCapHolds() {
        bank.fund("alice", 1_000_000);
        table.sit("alice", 1L);
        assertTrue(table.bet("alice", BetType.STRAIGHT, 17, 100, now).ok());
        assertTrue(table.bet("alice", BetType.STRAIGHT, 17, 200, now).ok());
        Seat seat = table.seatOf("alice");
        assertNotNull(seat);
        assertEquals(1, seat.bets().size());
        assertEquals(300, seat.bets().get(0).amount());
        for (int n = 0; n < RouletteTable.MAX_BETS_PER_SEAT - 1; n++) {
            assertTrue(table.bet("alice", BetType.STRAIGHT, n, 100, now).ok());
        }
        assertEquals(RouletteTable.MAX_BETS_PER_SEAT, seat.bets().size());
        assertEquals(
                Action.TOO_MANY_BETS, table.bet("alice", BetType.STRAIGHT, 30, 100, now).action());
        // topping up an existing spot is still fine at the cap
        assertTrue(table.bet("alice", BetType.STRAIGHT, 17, 100, now).ok());
    }

    @Test
    void bankRefusalLeavesNoBet() {
        bank.fund("alice", 50);
        table.sit("alice", 1L);
        RouletteTable.Result r = table.bet("alice", BetType.BLACK, 0, 100, now);
        assertEquals(Action.BANK_REFUSED, r.action());
        assertEquals("INSUFFICIENT_BALANCE", r.detail());
        assertTrue(table.seatOf("alice").bets().isEmpty());
        assertEquals(0L, table.deadline());
    }

    @Test
    void firstBetOpensWindowAndSpinSettlesPayouts() {
        rigged(17); // 17 is black, odd, low, 2nd dozen, column 2
        bank.fund("alice", 10_000);
        bank.fund("bob", 10_000);
        table.sit("alice", 1L);
        table.sit("bob", 2L);
        assertEquals(0L, table.deadline());
        assertTrue(table.bet("alice", BetType.STRAIGHT, 17, 100, now).ok());
        assertEquals(now + RouletteTable.BET_WINDOW_MS, table.deadline());
        assertTrue(table.bet("alice", BetType.RED, 0, 200, now).ok());
        assertTrue(table.bet("bob", BetType.DOZEN, 2, 300, now).ok());
        assertTrue(table.bet("bob", BetType.COLUMN, 1, 400, now).ok());
        assertTrue(table.bet("bob", BetType.EVEN, 0, 500, now).ok());

        table.tick(now + RouletteTable.BET_WINDOW_MS - 1);
        assertEquals(Phase.BETTING, table.phase());
        runToSettle();
        assertEquals(17, table.winningNumber());
        assertEquals(1, table.round());
        assertEquals(java.util.List.of(17), table.history());

        Seat alice = table.seatOf("alice");
        Seat bob = table.seatOf("bob");
        assertEquals(3_600, alice.payout()); // straight 100 x 36
        assertEquals(900, bob.payout()); // dozen 300 x 3
        assertEquals(10_000 - 300 + 3_600, bank.balance.get("alice"));
        assertEquals(10_000 - 1_200 + 900, bank.balance.get("bob"));

        now += RouletteTable.SETTLE_MS;
        table.tick(now);
        assertEquals(Phase.BETTING, table.phase());
        assertEquals(-1, table.winningNumber());
        assertTrue(alice.bets().isEmpty());
        assertEquals(0, alice.payout());
        assertEquals(0L, table.deadline());
    }

    @Test
    void zeroOnlyPaysStraightZero() {
        rigged(0);
        bank.fund("alice", 10_000);
        table.sit("alice", 1L);
        for (BetType t : BetType.values()) {
            if (!t.hasTarget()) {
                assertTrue(table.bet("alice", t, 0, 100, now).ok(), t.name());
            }
        }
        assertTrue(table.bet("alice", BetType.DOZEN, 1, 100, now).ok());
        assertTrue(table.bet("alice", BetType.COLUMN, 1, 100, now).ok());
        assertTrue(table.bet("alice", BetType.STRAIGHT, 0, 100, now).ok());
        runToSettle();
        assertEquals(3_600, table.seatOf("alice").payout());
        assertEquals(10_000 - 900 + 3_600, bank.balance.get("alice"));
    }

    @Test
    void betTypeWinLogic() {
        assertTrue(BetType.RED.wins(1, 0));
        assertFalse(BetType.RED.wins(2, 0));
        assertTrue(BetType.BLACK.wins(2, 0));
        assertTrue(BetType.BLACK.wins(10, 0));
        assertTrue(BetType.RED.wins(19, 0));
        assertFalse(BetType.RED.wins(0, 0));
        assertFalse(BetType.BLACK.wins(0, 0));
        assertTrue(BetType.ODD.wins(35, 0));
        assertTrue(BetType.EVEN.wins(36, 0));
        assertFalse(BetType.EVEN.wins(0, 0));
        assertTrue(BetType.LOW.wins(18, 0));
        assertTrue(BetType.HIGH.wins(19, 0));
        assertTrue(BetType.DOZEN.wins(12, 1));
        assertTrue(BetType.DOZEN.wins(13, 2));
        assertTrue(BetType.DOZEN.wins(36, 3));
        assertTrue(BetType.COLUMN.wins(1, 1));
        assertTrue(BetType.COLUMN.wins(2, 2));
        assertTrue(BetType.COLUMN.wins(36, 3));
        assertFalse(BetType.COLUMN.wins(36, 1));
        assertEquals("red", RouletteTable.colorOf(32));
        assertEquals("black", RouletteTable.colorOf(33));
        assertEquals("green", RouletteTable.colorOf(0));
        assertEquals(BetType.DOZEN, BetType.fromWire("Dozen"));
        assertNull(BetType.fromWire("corner"));
    }

    @Test
    void clearBetsRefundsAndClosesWindow() {
        bank.fund("alice", 1_000);
        table.sit("alice", 1L);
        assertEquals(Action.NO_BETS, table.clearBets("alice").action());
        table.bet("alice", BetType.RED, 0, 100, now);
        table.bet("alice", BetType.STRAIGHT, 5, 200, now);
        assertEquals(700, bank.balance.get("alice"));
        assertTrue(table.clearBets("alice").ok());
        assertEquals(1_000, bank.balance.get("alice"));
        assertTrue(table.seatOf("alice").bets().isEmpty());
        assertEquals(0L, table.deadline());
        table.tick(now + RouletteTable.BET_WINDOW_MS);
        assertEquals(Phase.BETTING, table.phase());
        assertEquals(0, table.round());
    }

    @Test
    void leaveWhileBettingRefunds() {
        bank.fund("alice", 1_000);
        table.sit("alice", 1L);
        table.bet("alice", BetType.HIGH, 0, 300, now);
        assertTrue(table.leave("alice").ok());
        assertEquals(1_000, bank.balance.get("alice"));
        assertNull(table.seatOf("alice"));
        assertEquals(0L, table.deadline());
    }

    @Test
    void leaveWhileSpinningKeepsBetLiveAndPaysOut() {
        rigged(5);
        bank.fund("alice", 1_000);
        table.sit("alice", 1L);
        table.bet("alice", BetType.RED, 0, 300, now);
        now += RouletteTable.BET_WINDOW_MS;
        table.tick(now);
        assertEquals(Phase.SPINNING, table.phase());
        assertEquals(
                Action.NOT_BETTING_PHASE, table.bet("alice", BetType.RED, 0, 100, now).action());
        assertEquals(Action.NOT_BETTING_PHASE, table.clearBets("alice").action());
        assertTrue(table.leave("alice").ok());
        Seat seat = table.seatOf("alice");
        assertNotNull(seat);
        assertTrue(seat.isLeaving());
        now += RouletteTable.SPIN_MS;
        table.tick(now);
        assertEquals(600, seat.payout());
        assertEquals(1_000 - 300 + 600, bank.balance.get("alice"));
        now += RouletteTable.SETTLE_MS;
        table.tick(now);
        assertNull(table.seatOf("alice"));
    }

    @Test
    void limitsTimingOverridesDriveDeadlines() {
        RouletteTable.Limits fast =
                new RouletteTable.Limits() {
                    @Override
                    public int minBet() {
                        return MIN;
                    }

                    @Override
                    public int maxBet() {
                        return MAX;
                    }

                    @Override
                    public long betWindowMs() {
                        return 1_000L;
                    }

                    @Override
                    public long spinMs() {
                        return 2_000L;
                    }

                    @Override
                    public long settleMs() {
                        return 3_000L;
                    }
                };
        table = new RouletteTable(bank, fast, new Random(1L));
        bank.fund("alice", 1_000);
        table.sit("alice", 1L);
        table.bet("alice", BetType.ODD, 0, 100, now);
        table.tick(now + 999);
        assertEquals(Phase.BETTING, table.phase());
        table.tick(now + 1_000);
        assertEquals(Phase.SPINNING, table.phase());
        table.tick(now + 2_999);
        assertEquals(Phase.SPINNING, table.phase());
        table.tick(now + 3_000);
        assertEquals(Phase.SETTLE, table.phase());
        table.tick(now + 5_999);
        assertEquals(Phase.SETTLE, table.phase());
        table.tick(now + 6_000);
        assertEquals(Phase.BETTING, table.phase());
    }

    @Test
    void logAndDirtyTracking() {
        bank.fund("alice", 1_000);
        assertFalse(table.isDirty());
        table.sit("alice", 1L);
        assertTrue(table.isDirty());
        table.clearDirty();
        table.bet("alice", BetType.STRAIGHT, 7, 100, now);
        assertTrue(table.isDirty());
        java.util.List<String> log = table.drainLog();
        assertEquals(2, log.size());
        assertTrue(log.get(1).contains("100 on 7"), log.get(1));
        assertTrue(table.drainLog().isEmpty());
    }
}
