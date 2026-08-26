package com.sentientsimulations.projectzomboid.atfcasino.roulette;

import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Deque;
import java.util.List;
import java.util.Locale;
import java.util.Random;
import java.util.Set;
import org.jetbrains.annotations.Nullable;

/**
 * Server-authoritative multiplayer European roulette table (single zero, 0–36). Pure state machine:
 * no PZ types, no threads, no wall clock — every call takes {@code now} (ms) so the driver decides
 * cadence and tests are deterministic. Money moves only through the {@link Bank} port; the engine
 * never trusts a client number beyond the bet amount it validates against {@link Limits}.
 *
 * <p>Round shape: {@link Phase#BETTING} (opens a {@link Limits#betWindowMs()} countdown at the
 * first bet; seated players may stack several bets) → {@link Phase#SPINNING} for {@link
 * Limits#spinMs()} (the number is drawn when the wheel starts but hidden until it stops) → payouts
 * → {@link Phase#SETTLE} for {@link Limits#settleMs()} → back to betting. Seated players with no
 * bets simply watch the round. Leaving while the wheel spins keeps the bets live; the payout still
 * goes to the seat's recorded identity, so walking away never voids a winning bet.
 */
public final class RouletteTable {

    public static final int MAX_SEATS = 5;
    public static final int MAX_BETS_PER_SEAT = 12;
    public static final int HISTORY_SIZE = 12;
    public static final long BET_WINDOW_MS = 30_000L;
    public static final long SPIN_MS = 6_000L;
    public static final long SETTLE_MS = 8_000L;

    private static final Set<Integer> RED_NUMBERS =
            Set.of(1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36);

    public enum Phase {
        BETTING,
        SPINNING,
        SETTLE
    }

    public enum Action {
        OK,
        TABLE_FULL,
        ALREADY_SEATED,
        NOT_SEATED,
        NOT_BETTING_PHASE,
        BET_TOO_LOW,
        BET_TOO_HIGH,
        TOO_MANY_BETS,
        BAD_BET,
        NO_BETS,
        BANK_REFUSED
    }

    /** Result of a player request; {@code detail} carries the bank's refusal reason if any. */
    public record Result(Action action, @Nullable String detail) {
        public static final Result OK = new Result(Action.OK, null);

        public static Result of(Action action) {
            return new Result(action, null);
        }

        public boolean ok() {
            return action == Action.OK;
        }
    }

    /**
     * Every bet the board accepts. {@code odds} is the winnings-to-stake ratio (a straight-up win
     * pays 35:1, so the seat gets stake × 36 back). {@code targets} is how many distinct targets
     * the type has (0 = none).
     */
    public enum BetType {
        STRAIGHT("straight", 35, 37),
        RED("red", 1, 0),
        BLACK("black", 1, 0),
        ODD("odd", 1, 0),
        EVEN("even", 1, 0),
        LOW("low", 1, 0),
        HIGH("high", 1, 0),
        DOZEN("dozen", 2, 3),
        COLUMN("column", 2, 3);

        private final String wire;
        private final int odds;
        private final int targets;

        BetType(String wire, int odds, int targets) {
            this.wire = wire;
            this.odds = odds;
            this.targets = targets;
        }

        public String wire() {
            return wire;
        }

        public int odds() {
            return odds;
        }

        public boolean hasTarget() {
            return targets > 0;
        }

        /** Valid targets: straight 0–36, dozen/column 1–3, everything else exactly 0. */
        public boolean acceptsTarget(int target) {
            if (this == STRAIGHT) {
                return target >= 0 && target < targets;
            }
            if (targets == 0) {
                return target == 0;
            }
            return target >= 1 && target <= targets;
        }

        public boolean wins(int number, int target) {
            if (number == 0) {
                return this == STRAIGHT && target == 0;
            }
            return switch (this) {
                case STRAIGHT -> number == target;
                case RED -> RED_NUMBERS.contains(number);
                case BLACK -> !RED_NUMBERS.contains(number);
                case ODD -> number % 2 == 1;
                case EVEN -> number % 2 == 0;
                case LOW -> number <= 18;
                case HIGH -> number >= 19;
                case DOZEN -> (number - 1) / 12 + 1 == target;
                case COLUMN -> (number - 1) % 3 + 1 == target;
            };
        }

        public static @Nullable BetType fromWire(@Nullable String wire) {
            if (wire == null) {
                return null;
            }
            for (BetType t : values()) {
                if (t.wire.equalsIgnoreCase(wire)) {
                    return t;
                }
            }
            return null;
        }
    }

    /** One chip stack on the board; same type+target stacks merge into one entry. */
    public static final class Bet {
        private final BetType type;
        private final int target;
        private int amount;
        private int payout;

        Bet(BetType type, int target, int amount) {
            this.type = type;
            this.target = target;
            this.amount = amount;
        }

        public BetType type() {
            return type;
        }

        public int target() {
            return target;
        }

        public int amount() {
            return amount;
        }

        /** Total returned on this bet after the spin (stake + winnings), 0 if it lost. */
        public int payout() {
            return payout;
        }

        public boolean wins(int number) {
            return type.wins(number, target);
        }

        /** Human label, e.g. {@code 17}, {@code Red}, {@code 2nd 12}, {@code Column 3}. */
        public String label() {
            return switch (type) {
                case STRAIGHT -> Integer.toString(target);
                case DOZEN -> (target == 1 ? "1st" : target == 2 ? "2nd" : "3rd") + " 12";
                case COLUMN -> "Column " + target;
                case LOW -> "1-18";
                case HIGH -> "19-36";
                default -> {
                    String w = type.wire;
                    yield Character.toUpperCase(w.charAt(0)) + w.substring(1);
                }
            };
        }
    }

    public static final class Seat {
        private final int index;
        private final String username;
        private final long steamId;
        private final List<Bet> bets = new ArrayList<>();
        private int payout;
        private boolean leaving;

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

        public List<Bet> bets() {
            return Collections.unmodifiableList(bets);
        }

        public int staked() {
            int sum = 0;
            for (Bet b : bets) {
                sum += b.amount;
            }
            return sum;
        }

        /** Total returned this round (stakes of winning bets + winnings), 0 if nothing hit. */
        public int payout() {
            return payout;
        }

        public boolean isLeaving() {
            return leaving;
        }

        boolean hasBets() {
            return !bets.isEmpty();
        }

        void reset() {
            bets.clear();
            payout = 0;
        }
    }

    /** Money port. {@code take} returns null on success or a refusal reason. */
    public interface Bank {
        @Nullable
        String take(String username, long steamId, int amount, String reason);

        void give(String username, long steamId, int amount, String reason);
    }

    /** Table limits port; bet limits are read per call so sandbox edits apply live. */
    public interface Limits {
        int minBet();

        int maxBet();

        default long betWindowMs() {
            return BET_WINDOW_MS;
        }

        default long spinMs() {
            return SPIN_MS;
        }

        default long settleMs() {
            return SETTLE_MS;
        }
    }

    private static final String STAKE_REASON = "casino_stake_roulette";
    private static final String PAYOUT_REASON = "casino_payout_roulette";
    private static final String REFUND_REASON = "casino_refund_roulette";

    private final Bank bank;
    private final Limits limits;
    private final Random rng;
    private final Seat[] seats = new Seat[MAX_SEATS];
    private final Deque<Integer> history = new ArrayDeque<>();

    private Phase phase = Phase.BETTING;
    private long deadline;
    private int round;
    private int winningNumber = -1;
    private boolean dirty;
    private final List<String> log = new ArrayList<>();

    public RouletteTable(Bank bank, Limits limits, Random rng) {
        this.bank = bank;
        this.limits = limits;
        this.rng = rng;
    }

    // --- queries ---

    public Phase phase() {
        return phase;
    }

    public int round() {
        return round;
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

    /** The number the ball landed on this round; -1 while betting or before it is revealed. */
    public int winningNumber() {
        return phase == Phase.SETTLE ? winningNumber : -1;
    }

    /** Most recent results, newest first. */
    public List<Integer> history() {
        return new ArrayList<>(history);
    }

    public static String colorOf(int number) {
        if (number == 0) {
            return "green";
        }
        return RED_NUMBERS.contains(number) ? "red" : "black";
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
     * Leave the table. During betting every chip on the board is refunded; while the wheel spins
     * the seat is marked leaving and removed after settlement so its payout still lands.
     */
    public Result leave(String username) {
        Seat seat = seatOf(username);
        if (seat == null) {
            return Result.of(Action.NOT_SEATED);
        }
        dirty = true;
        if (phase == Phase.SPINNING && seat.hasBets()) {
            seat.leaving = true;
            say(username + " leaves the table");
            return Result.OK;
        }
        if (phase == Phase.BETTING) {
            refund(seat);
        }
        seats[seat.index] = null;
        say(username + " leaves the table");
        if (phase == Phase.BETTING && deadline != 0L && !anyBets()) {
            deadline = 0L;
        }
        return Result.OK;
    }

    /**
     * Put {@code amount} on {@code type}/{@code target}. Same-spot bets stack into one entry; each
     * individual placement is checked against the table limits and taken from the bank at once.
     */
    public Result bet(String username, @Nullable BetType type, int target, int amount, long now) {
        Seat seat = seatOf(username);
        if (seat == null) {
            return Result.of(Action.NOT_SEATED);
        }
        if (phase != Phase.BETTING) {
            return Result.of(Action.NOT_BETTING_PHASE);
        }
        if (type == null || !type.acceptsTarget(target)) {
            return Result.of(Action.BAD_BET);
        }
        if (amount < limits.minBet()) {
            return Result.of(Action.BET_TOO_LOW);
        }
        if (amount > limits.maxBet()) {
            return Result.of(Action.BET_TOO_HIGH);
        }
        Bet existing = findBet(seat, type, target);
        if (existing == null && seat.bets.size() >= MAX_BETS_PER_SEAT) {
            return Result.of(Action.TOO_MANY_BETS);
        }
        if (existing != null && (long) existing.amount + amount > limits.maxBet()) {
            return Result.of(Action.BET_TOO_HIGH);
        }
        String refused = bank.take(seat.username, seat.steamId, amount, STAKE_REASON);
        if (refused != null) {
            return new Result(Action.BANK_REFUSED, refused);
        }
        if (existing != null) {
            existing.amount += amount;
        } else {
            existing = new Bet(type, target, amount);
            seat.bets.add(existing);
        }
        dirty = true;
        say(username + " puts " + amount + " on " + existing.label());
        if (deadline == 0L) {
            deadline = now + limits.betWindowMs();
        }
        return Result.OK;
    }

    /** Take every chip of the seat off the board and refund it; only while betting is open. */
    public Result clearBets(String username) {
        Seat seat = seatOf(username);
        if (seat == null) {
            return Result.of(Action.NOT_SEATED);
        }
        if (phase != Phase.BETTING) {
            return Result.of(Action.NOT_BETTING_PHASE);
        }
        if (!seat.hasBets()) {
            return Result.of(Action.NO_BETS);
        }
        refund(seat);
        say(username + " takes their chips back");
        dirty = true;
        if (!anyBets()) {
            deadline = 0L;
        }
        return Result.OK;
    }

    // --- clock ---

    public void tick(long now) {
        switch (phase) {
            case BETTING -> {
                if (deadline != 0L && now >= deadline) {
                    if (anyBets()) {
                        spin(now);
                    } else {
                        deadline = 0L;
                        dirty = true;
                    }
                }
            }
            case SPINNING -> {
                if (now >= deadline) {
                    settle(now);
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

    private @Nullable Bet findBet(Seat seat, BetType type, int target) {
        for (Bet b : seat.bets) {
            if (b.type == type && b.target == target) {
                return b;
            }
        }
        return null;
    }

    private boolean anyBets() {
        for (Seat s : seats) {
            if (s != null && s.hasBets()) {
                return true;
            }
        }
        return false;
    }

    private void refund(Seat seat) {
        int staked = seat.staked();
        if (staked > 0) {
            bank.give(seat.username, seat.steamId, staked, REFUND_REASON);
        }
        seat.bets.clear();
    }

    private void spin(long now) {
        round++;
        phase = Phase.SPINNING;
        winningNumber = rng.nextInt(37);
        deadline = now + limits.spinMs();
        say("No more bets - the croupier spins the wheel");
        dirty = true;
    }

    private void settle(long now) {
        phase = Phase.SETTLE;
        deadline = now + limits.settleMs();
        if (history.size() == HISTORY_SIZE) {
            history.pollLast();
        }
        history.addFirst(winningNumber);
        say(
                "The ball lands on "
                        + winningNumber
                        + " "
                        + colorOf(winningNumber).toUpperCase(Locale.ROOT));
        for (Seat s : seats) {
            if (s == null || !s.hasBets()) {
                continue;
            }
            int total = 0;
            for (Bet b : s.bets) {
                if (b.wins(winningNumber)) {
                    b.payout = b.amount * (b.type.odds + 1);
                    total += b.payout;
                }
            }
            s.payout = total;
            if (total > 0) {
                bank.give(s.username, s.steamId, total, PAYOUT_REASON);
                say(s.username + " wins " + total);
            } else {
                say(s.username + " loses " + s.staked());
            }
        }
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
        phase = Phase.BETTING;
        deadline = 0L;
        winningNumber = -1;
        dirty = true;
    }

    private void say(String message) {
        log.add(message);
    }
}
