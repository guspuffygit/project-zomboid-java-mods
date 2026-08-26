package com.sentientsimulations.projectzomboid.atfcasino.holdem;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.sentientsimulations.projectzomboid.atfcasino.holdem.HoldemTable.Action;
import com.sentientsimulations.projectzomboid.atfcasino.holdem.HoldemTable.Phase;
import com.sentientsimulations.projectzomboid.atfcasino.holdem.HoldemTable.Result;
import com.sentientsimulations.projectzomboid.atfcasino.holdem.HoldemTable.Seat;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Random;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

class HoldemTableTest {

    private static final int BB = 100;
    private static final int MIN_BUYIN = 500;
    private static final int MAX_BUYIN = 5_000;
    private static final long TURN_MS = 20_000L;
    private static final long SETTLE_MS = 10_000L;
    private static final long START_MS = 5_000L;

    /** In-memory bank with per-user balances; refuses when short. */
    private static final class FakeBank implements HoldemTable.Bank {
        final Map<String, Integer> balance = new HashMap<>();
        int takes;
        int gives;

        void fund(String user, int amount) {
            balance.merge(user, amount, Integer::sum);
        }

        int of(String user) {
            return balance.getOrDefault(user, 0);
        }

        @Override
        public String take(String username, long steamId, int amount, String reason) {
            int have = of(username);
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
    private HoldemTable table;
    private long now;

    @BeforeEach
    void setUp() {
        bank = new FakeBank();
        table = new HoldemTable(bank, limits(), new Random(7L));
        now = 1_000_000L;
    }

    private static HoldemTable.Limits limits() {
        return new HoldemTable.Limits() {
            @Override
            public int bigBlind() {
                return BB;
            }

            @Override
            public int minBuyIn() {
                return MIN_BUYIN;
            }

            @Override
            public int maxBuyIn() {
                return MAX_BUYIN;
            }

            @Override
            public long turnMs() {
                return TURN_MS;
            }

            @Override
            public long settleMs() {
                return SETTLE_MS;
            }

            @Override
            public long startDelayMs() {
                return START_MS;
            }
        };
    }

    private void seatAndBuy(String user, int amount) {
        bank.fund(user, amount);
        assertTrue(table.sit(user, user.hashCode()).ok(), user + " sits");
        Result r = table.buyIn(user, amount);
        assertTrue(r.ok(), user + " buys in: " + r);
    }

    /** Runs the clock through the start countdown and into the first hand. */
    private void startHand() {
        table.tick(now);
        assertEquals(Phase.WAITING, table.phase());
        assertTrue(table.deadline() > 0, "countdown armed");
        now += START_MS;
        table.tick(now);
        assertTrue(table.handRunning(), "hand started, phase=" + table.phase());
    }

    private void ok(Result r) {
        assertTrue(r.ok(), r.toString());
    }

    private Seat seat(String user) {
        Seat s = table.seatOf(user);
        assertNotNull(s, user);
        return s;
    }

    private String acting() {
        return table.seat(table.actingSeat()).username();
    }

    // --- start gate ---

    @Test
    void noHandUntilTwoSeatedPlayersHaveChips() {
        seatAndBuy("alice", 1_000);
        table.tick(now);
        assertEquals(Phase.WAITING, table.phase());
        assertEquals(0L, table.deadline());

        bank.fund("bob", 1_000);
        ok(table.sit("bob", 2));
        table.tick(now);
        assertEquals(Phase.WAITING, table.phase());
        assertEquals(0L, table.deadline(), "a seated player without chips doesn't count");

        ok(table.buyIn("bob", 1_000));
        table.tick(now);
        assertEquals(Phase.WAITING, table.phase());
        assertEquals(now + START_MS, table.deadline());
        now += START_MS - 1;
        table.tick(now);
        assertEquals(Phase.WAITING, table.phase());
        now += 1;
        table.tick(now);
        assertEquals(Phase.PREFLOP, table.phase());
        assertEquals(1, table.hand());
        assertEquals(2, seat("alice").cards().size());
        assertEquals(2, seat("bob").cards().size());
    }

    @Test
    void countdownCancelsWhenSomeoneLeaves() {
        seatAndBuy("alice", 1_000);
        seatAndBuy("bob", 1_000);
        table.tick(now);
        assertTrue(table.deadline() > 0);
        ok(table.leave("bob", now));
        assertEquals(1_000, bank.of("bob"), "cashed out");
        table.tick(now);
        assertEquals(0L, table.deadline());
        now += START_MS;
        table.tick(now);
        assertEquals(Phase.WAITING, table.phase());
        assertEquals(0, table.hand());
    }

    @Test
    void brokePlayerStaysSeatedButIsNotDealt() {
        seatAndBuy("alice", 1_000);
        seatAndBuy("bob", 1_000);
        bank.fund("carol", 0);
        ok(table.sit("carol", 3));
        startHand();
        assertTrue(seat("alice").isInHand());
        assertTrue(seat("bob").isInHand());
        assertFalse(seat("carol").isInHand());
        assertEquals(0, seat("carol").cards().size());
    }

    // --- buy-in ---

    @Test
    void buyInEnforcesLimitsAndBank() {
        bank.fund("alice", 10_000);
        assertEquals(Action.NOT_SEATED, table.buyIn("alice", 1_000).action());
        ok(table.sit("alice", 1));
        assertEquals(Action.BAD_AMOUNT, table.buyIn("alice", 0).action());
        Result low = table.buyIn("alice", MIN_BUYIN - 1);
        assertEquals(Action.BUYIN_TOO_LOW, low.action());
        assertEquals(Integer.toString(MIN_BUYIN), low.detail());
        Result high = table.buyIn("alice", MAX_BUYIN + 1);
        assertEquals(Action.BUYIN_TOO_HIGH, high.action());
        assertEquals(Integer.toString(MAX_BUYIN), high.detail());
        ok(table.buyIn("alice", 1_000));
        assertEquals(1_000, seat("alice").stack());
        ok(table.buyIn("alice", 50));
        assertEquals(1_050, seat("alice").stack(), "top-ups may be below the minimum");
        Result over = table.buyIn("alice", MAX_BUYIN);
        assertEquals(Action.BUYIN_TOO_HIGH, over.action());
        assertEquals(Integer.toString(MAX_BUYIN - 1_050), over.detail());

        ok(table.sit("bob", 2));
        Result broke = table.buyIn("bob", 1_000);
        assertEquals(Action.BANK_REFUSED, broke.action());
        assertEquals("INSUFFICIENT_BALANCE", broke.detail());
        assertEquals(0, seat("bob").stack());
    }

    @Test
    void noBuyInWhileDealtIntoAHand() {
        seatAndBuy("alice", 1_000);
        seatAndBuy("bob", 1_000);
        bank.fund("alice", 1_000);
        startHand();
        assertEquals(Action.HAND_IN_PROGRESS, table.buyIn("alice", 500).action());
        bank.fund("carol", 1_000);
        ok(table.sit("carol", 3));
        ok(table.buyIn("carol", 1_000));
        assertFalse(seat("carol").isInHand(), "joins the next hand");
    }

    // --- hand flow ---

    @Test
    void headsUpButtonPostsSmallBlindAndActsFirst() {
        seatAndBuy("alice", 1_000);
        seatAndBuy("bob", 1_000);
        startHand();
        assertEquals(0, table.button());
        assertEquals(50, seat("alice").bet());
        assertEquals(100, seat("bob").bet());
        assertEquals("alice", acting());
        assertEquals(50, table.callAmount(seat("alice")));
        assertEquals(Action.NOT_YOUR_TURN, table.check("bob", now).action());
        assertEquals(Action.CANNOT_CHECK, table.check("alice", now).action());

        ok(table.call("alice", now));
        assertEquals(Phase.PREFLOP, table.phase(), "big blind still has the option");
        assertEquals("bob", acting());
        assertTrue(table.canCheck(seat("bob")));
        ok(table.check("bob", now));
        assertEquals(Phase.FLOP, table.phase());
        assertEquals(3, table.board().size());
        assertEquals(200, table.pot());
        assertEquals("bob", acting(), "post-flop the non-button acts first heads-up");
        assertEquals(0, seat("alice").bet());
    }

    @Test
    void foldHandsPotToLastPlayerStanding() {
        seatAndBuy("alice", 1_000);
        seatAndBuy("bob", 1_000);
        startHand();
        ok(table.raiseTo("alice", 300, now));
        assertEquals("bob", acting());
        assertEquals(200, table.callAmount(seat("bob")));
        ok(table.fold("bob", now));
        assertEquals(Phase.SHOWDOWN, table.phase());
        assertEquals(1_100, seat("alice").stack());
        assertEquals(900, seat("bob").stack());
        assertEquals(400, seat("alice").won());
        assertFalse(seat("alice").isShowingCards(), "no showdown, no reveal");
        assertTrue(table.drainLog().stream().anyMatch(l -> l.contains("alice wins 400")));

        now += SETTLE_MS;
        table.tick(now);
        assertEquals(Phase.WAITING, table.phase());
        table.tick(now);
        now += START_MS;
        table.tick(now);
        assertEquals(2, table.hand());
        assertEquals(1, table.button(), "button rotates");
        assertEquals("bob", acting());
    }

    @Test
    void raiseRulesNoLimit() {
        seatAndBuy("alice", 1_000);
        seatAndBuy("bob", 1_000);
        startHand();
        Result small = table.raiseTo("alice", 150, now);
        assertEquals(Action.RAISE_TOO_SMALL, small.action());
        assertEquals("200", small.detail());
        Result big = table.raiseTo("alice", 1_001, now);
        assertEquals(Action.RAISE_TOO_BIG, big.action());
        assertEquals("1000", big.detail());
        ok(table.raiseTo("alice", 300, now));
        assertEquals(500, table.minRaiseTo(seat("bob")), "min re-raise is the last raise size");
        ok(table.raiseTo("bob", 700, now));
        assertEquals("alice", acting());
        assertEquals(1_000, table.minRaiseTo(seat("alice")), "min raise capped by stack");
        assertEquals(1_000, table.maxRaiseTo(seat("alice")));
        ok(table.allIn("alice", now));
        assertTrue(seat("alice").isAllIn());
        assertEquals("bob", acting());
        assertEquals(300, table.callAmount(seat("bob")));
        ok(table.call("bob", now));
        assertEquals(Phase.SHOWDOWN, table.phase(), "nobody left to bet: board runs out");
        assertEquals(5, table.board().size());
        assertEquals(2_000, seat("alice").stack() + seat("bob").stack());
    }

    @Test
    void showdownPaysBestHand() {
        seatAndBuy("alice", 1_000);
        seatAndBuy("bob", 1_000);
        seatAndBuy("carol", 1_000);
        table.stackDeck(
                HandEvaluatorTest.cards(
                        "As", "Ks", "7s", "Ad", "Kd", "2d", "3h", "5d", "8c", "9s", "Jh"));
        startHand();
        assertEquals(0, table.button());
        assertEquals(50, seat("bob").bet());
        assertEquals(100, seat("carol").bet());
        assertEquals("alice", acting());
        ok(table.call("alice", now));
        ok(table.call("bob", now));
        ok(table.check("carol", now));
        assertEquals(Phase.FLOP, table.phase());
        assertEquals("bob", acting());
        for (String street : List.of("flop", "turn", "river")) {
            ok(table.check("bob", now));
            ok(table.check("carol", now));
            ok(table.check("alice", now));
        }
        assertEquals(Phase.SHOWDOWN, table.phase());
        assertEquals("Pair of Aces", seat("alice").handName());
        assertEquals("Pair of Kings", seat("bob").handName());
        assertEquals("Jack high", seat("carol").handName());
        assertEquals(1_200, seat("alice").stack());
        assertEquals(900, seat("bob").stack());
        assertEquals(900, seat("carol").stack());
        assertTrue(seat("bob").isShowingCards());
        assertTrue(
                table.drainLog().stream()
                        .anyMatch(l -> l.equals("alice wins 300 with Pair of Aces")));
    }

    @Test
    void sidePotsGoToWhoeverCoveredThem() {
        seatAndBuy("alice", 500);
        seatAndBuy("bob", 1_000);
        seatAndBuy("carol", 1_000);
        ok(table.leave("alice", now));
        bank.fund("alice", 0);
        ok(table.sit("alice", 1));
        ok(table.buyIn("alice", 500));
        // alice is now in seat 0 again with a 500 stack (minimum buy-in), short-stacked.
        table.stackDeck(
                HandEvaluatorTest.cards(
                        "As", "Ks", "7s", "Ad", "Kd", "2d", "3h", "5d", "8c", "9s", "Jh"));
        startHand();
        assertEquals("alice", acting());
        ok(table.allIn("alice", now));
        assertEquals(500, seat("alice").totalIn());
        ok(table.call("bob", now));
        ok(table.call("carol", now));
        assertEquals(Phase.FLOP, table.phase());
        assertEquals("bob", acting());
        ok(table.raiseTo("bob", 400, now));
        ok(table.call("carol", now));
        assertEquals(Phase.TURN, table.phase());
        ok(table.check("bob", now));
        ok(table.check("carol", now));
        ok(table.check("bob", now));
        ok(table.check("carol", now));
        assertEquals(Phase.SHOWDOWN, table.phase());
        // main pot 1500 (3 x 500) -> alice; side pot 800 (2 x 400) -> bob
        assertEquals(1_500, seat("alice").stack());
        assertEquals(1_000 - 900 + 800, seat("bob").stack());
        assertEquals(100, seat("carol").stack());
        assertEquals(1_500, seat("alice").won());
        assertEquals(800, seat("bob").won());
    }

    @Test
    void uncalledChipsComeBack() {
        seatAndBuy("alice", 1_000);
        seatAndBuy("bob", 500);
        // bob (seat 1) is the big blind and wins the showdown.
        table.stackDeck(
                HandEvaluatorTest.cards("7s", "As", "2d", "Ad", "3h", "5d", "8c", "9s", "Jh"));
        startHand();
        ok(table.allIn("alice", now));
        ok(table.call("bob", now));
        assertEquals(Phase.SHOWDOWN, table.phase());
        assertEquals(1_000, seat("bob").stack());
        assertEquals(500, seat("alice").stack(), "uncalled 500 returned before the pot is paid");
        assertEquals(1_000, seat("bob").won());
    }

    @Test
    void timeoutChecksWhenPossibleOtherwiseFolds() {
        seatAndBuy("alice", 1_000);
        seatAndBuy("bob", 1_000);
        startHand();
        assertEquals("alice", acting());
        now += TURN_MS;
        table.tick(now);
        assertTrue(seat("alice").isFolded());
        assertEquals(Phase.SHOWDOWN, table.phase());
        assertEquals(1_050, seat("bob").stack());
        assertTrue(
                table.drainLog().stream().anyMatch(l -> l.contains("ran out of time and folds")));

        now += SETTLE_MS;
        table.tick(now);
        table.tick(now);
        now += START_MS;
        table.tick(now);
        assertEquals("bob", acting());
        ok(table.call("bob", now));
        assertEquals("alice", acting());
        now += TURN_MS;
        table.tick(now);
        assertFalse(seat("alice").isFolded(), "checks for free when no bet is pending");
        assertEquals(Phase.FLOP, table.phase());
    }

    @Test
    void leavingMidHandFoldsAndCashesOutButAllInStaysLive() {
        seatAndBuy("alice", 1_000);
        seatAndBuy("bob", 1_000);
        seatAndBuy("carol", 1_000);
        startHand();
        assertEquals("alice", acting());
        ok(table.leave("alice", now));
        assertTrue(seat("alice").isFolded());
        assertTrue(seat("alice").isLeaving());
        assertEquals(1_000, bank.of("alice"), "remaining stack cashed out at once");
        assertEquals("bob", acting());
        ok(table.call("bob", now));
        ok(table.check("carol", now));
        assertEquals(Phase.FLOP, table.phase());
        ok(table.check("bob", now));
        ok(table.check("carol", now));
        ok(table.check("bob", now));
        ok(table.check("carol", now));
        ok(table.check("bob", now));
        ok(table.check("carol", now));
        assertEquals(Phase.SHOWDOWN, table.phase());
        assertNotNull(table.seatOf("alice"), "seat shown through the showdown");
        now += SETTLE_MS;
        table.tick(now);
        assertNull(table.seatOf("alice"), "gone once the hand is over");
        assertEquals(2, table.seatedPlayers().size());
    }

    @Test
    void leavingAllInPlayerStillGetsPaidThroughTheBank() {
        seatAndBuy("alice", 1_000);
        seatAndBuy("bob", 1_000);
        table.stackDeck(
                HandEvaluatorTest.cards("As", "7s", "Ad", "2d", "3h", "5d", "8c", "9s", "Jh"));
        startHand();
        ok(table.allIn("alice", now));
        ok(table.call("bob", now));
        assertEquals(Phase.SHOWDOWN, table.phase());
        assertEquals(2_000, seat("alice").stack());
    }

    @Test
    void leavingAfterShovingIsPaidToTheBank() {
        seatAndBuy("alice", 1_000);
        seatAndBuy("bob", 1_000);
        seatAndBuy("carol", 1_000);
        table.stackDeck(
                HandEvaluatorTest.cards(
                        "As", "Ks", "7s", "Ad", "Kd", "2d", "3h", "5d", "8c", "9s", "Jh"));
        startHand();
        ok(table.allIn("alice", now));
        ok(table.leave("alice", now));
        assertTrue(seat("alice").isLeaving());
        assertFalse(seat("alice").isFolded(), "an all-in stack can't be folded");
        ok(table.call("bob", now));
        ok(table.call("carol", now));
        assertEquals(Phase.SHOWDOWN, table.phase(), "everyone else all-in/called: runs out");
        assertEquals(3_000, bank.of("alice"), "pot paid straight to the bank");
        assertEquals(0, seat("alice").stack());
    }

    @Test
    void tableFullAndDoubleSeating() {
        for (int i = 0; i < HoldemTable.MAX_SEATS; i++) {
            ok(table.sit("p" + i, i));
        }
        assertEquals(Action.TABLE_FULL, table.sit("late", 99).action());
        assertEquals(Action.ALREADY_SEATED, table.sit("P1", 1).action());
        assertFalse(table.hasFreeSeat());
    }
}
