package com.sentientsimulations.projectzomboid.atfcasino.blackjack;

import java.util.ArrayList;
import java.util.List;
import java.util.Random;
import org.jetbrains.annotations.Nullable;

/**
 * Server-authoritative multiplayer blackjack table. Pure state machine: no PZ types, no threads, no
 * wall clock — every call takes {@code now} (ms) so the driver decides cadence and tests are
 * deterministic. Money moves only through the {@link Bank} port; the engine never trusts a client
 * number beyond the bet amount it validates against {@link Limits}.
 *
 * <p>Round shape: {@link Phase#BETTING} (opens a {@link Limits#betWindowMs()} countdown at the
 * first bet, or starts at once when every seated player has bet) → {@link Phase#PLAYING} (seats act
 * in order, {@link Limits#actionMs()} each, timeout = stand) → dealer draws to 17 (stands on soft
 * 17) and pays → {@link Phase#SETTLE} for {@link Limits#settleMs()} → back to betting. Seated
 * players who don't bet simply sit the round out. Leaving mid-hand auto-stands; the hand still
 * settles and any payout goes to the seat's recorded identity, so walking away never voids a
 * winning hand.
 */
public final class BlackjackTable {

    public static final int MAX_SEATS = 5;
    public static final long BET_WINDOW_MS = 20_000L;
    public static final long ACTION_MS = 20_000L;
    public static final long SETTLE_MS = 8_000L;

    public enum Phase {
        BETTING,
        PLAYING,
        SETTLE
    }

    public enum Outcome {
        NONE,
        WIN,
        BLACKJACK,
        PUSH,
        LOSE,
        BUST
    }

    public enum Action {
        OK,
        TABLE_FULL,
        ALREADY_SEATED,
        NOT_SEATED,
        NOT_BETTING_PHASE,
        ALREADY_BET,
        BET_TOO_LOW,
        BET_TOO_HIGH,
        BANK_REFUSED,
        NOT_YOUR_TURN,
        CANNOT_DOUBLE
    }

    /** Result of a player request; {@code detail} carries the bank's refusal reason if any. */
    public record Result(Action action, @Nullable String detail) {
        public static final Result OK = new Result(Action.OK, null);

        static Result of(Action action) {
            return new Result(action, null);
        }

        public boolean ok() {
            return action == Action.OK;
        }
    }

    /** Economy port. {@link #take} returns null on success or a refusal reason. */
    public interface Bank {
        @Nullable
        String take(String username, long steamId, int amount, String reason);

        void give(String username, long steamId, int amount, String reason);
    }

    /** Table rules read fresh on every use so sandbox edits apply without a restart. */
    public interface Limits {
        int minBet();

        int maxBet();

        default long betWindowMs() {
            return BET_WINDOW_MS;
        }

        default long actionMs() {
            return ACTION_MS;
        }

        default long settleMs() {
            return SETTLE_MS;
        }
    }

    public static final class Seat {
        final int index;
        final String username;
        final long steamId;
        final Hand hand = new Hand();
        int bet;
        boolean doubled;
        boolean stood;
        boolean leaving;
        Outcome outcome = Outcome.NONE;
        int payout;

        Seat(int index, String username, long steamId) {
            this.index = index;
            this.username = username;
            this.steamId = steamId;
        }

        public int index() {
            return index;
        }

        public String username() {
            return username;
        }

        public long steamId() {
            return steamId;
        }

        public int bet() {
            return bet;
        }

        public Hand hand() {
            return hand;
        }

        public Outcome outcome() {
            return outcome;
        }

        public int payout() {
            return payout;
        }

        public boolean isLeaving() {
            return leaving;
        }

        boolean inPlay() {
            return bet > 0;
        }

        boolean live() {
            return inPlay() && !stood && !hand.isBust() && !hand.isBlackjack() && hand.total() < 21;
        }

        void reset() {
            hand.clear();
            bet = 0;
            doubled = false;
            stood = false;
            outcome = Outcome.NONE;
            payout = 0;
        }
    }

    private static final String STAKE_REASON = "casino_stake_blackjack";
    private static final String DOUBLE_REASON = "casino_double_blackjack";
    private static final String PAYOUT_REASON = "casino_payout_blackjack";
    private static final String REFUND_REASON = "casino_refund_blackjack";

    private final Bank bank;
    private final Limits limits;
    private final Shoe shoe;
    private final Seat[] seats = new Seat[MAX_SEATS];
    private final Hand dealer = new Hand();

    private Phase phase = Phase.BETTING;
    private long deadline;
    private int currentSeat = -1;
    private boolean holeHidden = true;
    private int round;
    private boolean dirty;
    private final List<String> log = new ArrayList<>();

    public BlackjackTable(Bank bank, Limits limits, Random rng) {
        this.bank = bank;
        this.limits = limits;
        this.shoe = new Shoe(rng);
    }

    // --- queries ---

    public Phase phase() {
        return phase;
    }

    public int round() {
        return round;
    }

    public int currentSeat() {
        return currentSeat;
    }

    public Hand dealerHand() {
        return dealer;
    }

    public boolean isHoleHidden() {
        return holeHidden;
    }

    public long deadline() {
        return deadline;
    }

    public int secondsLeft(long now) {
        if (deadline == 0L) {
            return 0;
        }
        return (int) Math.max(0L, (deadline - now + 999L) / 1000L);
    }

    public @Nullable Seat seat(int index) {
        return index >= 0 && index < MAX_SEATS ? seats[index] : null;
    }

    public @Nullable Seat seatOf(String username) {
        for (Seat s : seats) {
            if (s != null && s.username.equalsIgnoreCase(username)) {
                return s;
            }
        }
        return null;
    }

    public List<Seat> seatedPlayers() {
        List<Seat> out = new ArrayList<>();
        for (Seat s : seats) {
            if (s != null) {
                out.add(s);
            }
        }
        return out;
    }

    public boolean hasFreeSeat() {
        for (Seat s : seats) {
            if (s == null) {
                return true;
            }
        }
        return false;
    }

    /** True when the seat may double right now: their turn, first two cards, not yet doubled. */
    public boolean canDouble(Seat seat) {
        return phase == Phase.PLAYING
                && currentSeat == seat.index
                && seat.hand.size() == 2
                && !seat.doubled;
    }

    /** Drain-and-clear of human-readable events since the last call (for the client's log line). */
    public List<String> drainLog() {
        List<String> out = new ArrayList<>(log);
        log.clear();
        return out;
    }

    /** True if state changed since the last {@link #clearDirty()}; drivers use it to broadcast. */
    public boolean isDirty() {
        return dirty;
    }

    public void clearDirty() {
        dirty = false;
    }

    // --- player requests ---

    public Result sit(String username, long steamId) {
        if (seatOf(username) != null) {
            return Result.of(Action.ALREADY_SEATED);
        }
        for (int i = 0; i < MAX_SEATS; i++) {
            if (seats[i] == null) {
                seats[i] = new Seat(i, username, steamId);
                say(username + " sits down");
                dirty = true;
                return Result.OK;
            }
        }
        return Result.of(Action.TABLE_FULL);
    }

    /**
     * Leave the table. During betting an already-placed stake is refunded; mid-hand the seat is
     * marked leaving, auto-stands, and is removed after settlement so its payout still lands.
     */
    public Result leave(String username, long now) {
        Seat seat = seatOf(username);
        if (seat == null) {
            return Result.of(Action.NOT_SEATED);
        }
        dirty = true;
        if (phase == Phase.PLAYING && seat.inPlay()) {
            seat.leaving = true;
            say(username + " leaves the table");
            if (currentSeat == seat.index) {
                seat.stood = true;
                advance(now);
            }
            return Result.OK;
        }
        if (phase == Phase.BETTING && seat.bet > 0) {
            bank.give(seat.username, seat.steamId, seat.bet, REFUND_REASON);
            seat.bet = 0;
        }
        seats[seat.index] = null;
        say(username + " leaves the table");
        if (phase == Phase.BETTING && deadline != 0L && allSeatedHaveBet()) {
            startRound(now);
        }
        return Result.OK;
    }

    public Result bet(String username, int amount, long now) {
        Seat seat = seatOf(username);
        if (seat == null) {
            return Result.of(Action.NOT_SEATED);
        }
        if (phase != Phase.BETTING) {
            return Result.of(Action.NOT_BETTING_PHASE);
        }
        if (seat.bet > 0) {
            return Result.of(Action.ALREADY_BET);
        }
        if (amount < limits.minBet()) {
            return Result.of(Action.BET_TOO_LOW);
        }
        if (amount > limits.maxBet()) {
            return Result.of(Action.BET_TOO_HIGH);
        }
        String refused = bank.take(seat.username, seat.steamId, amount, STAKE_REASON);
        if (refused != null) {
            return new Result(Action.BANK_REFUSED, refused);
        }
        seat.bet = amount;
        dirty = true;
        say(username + " bets " + amount);
        if (allSeatedHaveBet()) {
            startRound(now);
        } else if (deadline == 0L) {
            deadline = now + limits.betWindowMs();
        }
        return Result.OK;
    }

    public Result hit(String username, long now) {
        Seat seat = seatOf(username);
        if (seat == null) {
            return Result.of(Action.NOT_SEATED);
        }
        if (phase != Phase.PLAYING || currentSeat != seat.index) {
            return Result.of(Action.NOT_YOUR_TURN);
        }
        seat.hand.add(shoe.draw());
        dirty = true;
        if (seat.hand.isBust()) {
            say(username + " busts");
        }
        if (!seat.live()) {
            advance(now);
        } else {
            deadline = now + limits.actionMs();
        }
        return Result.OK;
    }

    public Result stand(String username, long now) {
        Seat seat = seatOf(username);
        if (seat == null) {
            return Result.of(Action.NOT_SEATED);
        }
        if (phase != Phase.PLAYING || currentSeat != seat.index) {
            return Result.of(Action.NOT_YOUR_TURN);
        }
        seat.stood = true;
        dirty = true;
        say(username + " stands on " + seat.hand.total());
        advance(now);
        return Result.OK;
    }

    public Result doubleDown(String username, long now) {
        Seat seat = seatOf(username);
        if (seat == null) {
            return Result.of(Action.NOT_SEATED);
        }
        if (phase != Phase.PLAYING || currentSeat != seat.index) {
            return Result.of(Action.NOT_YOUR_TURN);
        }
        if (!canDouble(seat)) {
            return Result.of(Action.CANNOT_DOUBLE);
        }
        String refused = bank.take(seat.username, seat.steamId, seat.bet, DOUBLE_REASON);
        if (refused != null) {
            return new Result(Action.BANK_REFUSED, refused);
        }
        seat.bet *= 2;
        seat.doubled = true;
        seat.hand.add(shoe.draw());
        seat.stood = true;
        dirty = true;
        say(username + " doubles down" + (seat.hand.isBust() ? " and busts" : ""));
        advance(now);
        return Result.OK;
    }

    // --- clock ---

    public void tick(long now) {
        switch (phase) {
            case BETTING -> {
                if (deadline != 0L && now >= deadline) {
                    if (anyBets()) {
                        startRound(now);
                    } else {
                        deadline = 0L;
                        dirty = true;
                    }
                }
            }
            case PLAYING -> {
                if (now >= deadline) {
                    Seat seat = currentSeat >= 0 ? seats[currentSeat] : null;
                    if (seat != null) {
                        seat.stood = true;
                        say(seat.username + " ran out of time and stands");
                    }
                    dirty = true;
                    advance(now);
                }
            }
            case SETTLE -> {
                if (now >= deadline) {
                    newRound();
                }
            }
        }
    }

    // --- internals ---

    private boolean anyBets() {
        for (Seat s : seats) {
            if (s != null && s.bet > 0) {
                return true;
            }
        }
        return false;
    }

    private boolean allSeatedHaveBet() {
        boolean any = false;
        for (Seat s : seats) {
            if (s == null) {
                continue;
            }
            if (s.bet <= 0) {
                return false;
            }
            any = true;
        }
        return any;
    }

    private void startRound(long now) {
        round++;
        shoe.reshuffleIfLow();
        dealer.clear();
        holeHidden = true;
        for (Seat s : seats) {
            if (s != null && s.inPlay()) {
                s.hand.clear();
                s.hand.add(shoe.draw());
            }
        }
        dealer.add(shoe.draw());
        for (Seat s : seats) {
            if (s != null && s.inPlay()) {
                s.hand.add(shoe.draw());
            }
        }
        dealer.add(shoe.draw());
        phase = Phase.PLAYING;
        currentSeat = -1;
        dirty = true;
        say("Round " + round + ": cards dealt");
        if (dealer.isBlackjack()) {
            say("Dealer has blackjack");
            settle(now);
            return;
        }
        advance(now);
    }

    private void advance(long now) {
        for (int i = currentSeat + 1; i < MAX_SEATS; i++) {
            Seat s = seats[i];
            if (s != null && s.live() && !s.leaving) {
                currentSeat = i;
                deadline = now + limits.actionMs();
                dirty = true;
                return;
            }
        }
        currentSeat = -1;
        dealerPlay();
        settle(now);
    }

    private void dealerPlay() {
        holeHidden = false;
        boolean anyoneStanding = false;
        for (Seat s : seats) {
            if (s != null && s.inPlay() && !s.hand.isBust() && !s.hand.isBlackjack()) {
                anyoneStanding = true;
            }
        }
        if (!anyoneStanding) {
            return;
        }
        while (dealer.total() < 17) {
            dealer.add(shoe.draw());
        }
    }

    private void settle(long now) {
        holeHidden = false;
        int dealerTotal = dealer.total();
        boolean dealerBj = dealer.isBlackjack();
        boolean dealerBust = dealer.isBust();
        for (Seat s : seats) {
            if (s == null || !s.inPlay()) {
                continue;
            }
            int total = s.hand.total();
            if (s.hand.isBust()) {
                s.outcome = Outcome.BUST;
                s.payout = 0;
            } else if (s.hand.isBlackjack()) {
                if (dealerBj) {
                    s.outcome = Outcome.PUSH;
                    s.payout = s.bet;
                } else {
                    s.outcome = Outcome.BLACKJACK;
                    s.payout = s.bet + (s.bet * 3) / 2;
                }
            } else if (dealerBj || (!dealerBust && dealerTotal > total)) {
                s.outcome = Outcome.LOSE;
                s.payout = 0;
            } else if (dealerBust || total > dealerTotal) {
                s.outcome = Outcome.WIN;
                s.payout = s.bet * 2;
            } else {
                s.outcome = Outcome.PUSH;
                s.payout = s.bet;
            }
            if (s.payout > 0) {
                bank.give(s.username, s.steamId, s.payout, PAYOUT_REASON);
            }
            say(s.username + ": " + s.outcome.name().toLowerCase() + " (" + s.payout + ")");
        }
        phase = Phase.SETTLE;
        deadline = now + limits.settleMs();
        dirty = true;
    }

    private void newRound() {
        for (int i = 0; i < MAX_SEATS; i++) {
            Seat s = seats[i];
            if (s == null) {
                continue;
            }
            if (s.leaving) {
                seats[i] = null;
            } else {
                s.reset();
            }
        }
        dealer.clear();
        holeHidden = true;
        phase = Phase.BETTING;
        deadline = 0L;
        currentSeat = -1;
        dirty = true;
    }

    private void say(String message) {
        log.add(message);
    }
}
