package com.sentientsimulations.projectzomboid.atfcasino.holdem;

import com.sentientsimulations.projectzomboid.atfcasino.blackjack.Card;
import com.sentientsimulations.projectzomboid.atfcasino.holdem.HandEvaluator.HandValue;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Random;
import java.util.TreeSet;
import org.jetbrains.annotations.Nullable;

/**
 * Server-authoritative no-limit Texas Hold'em table. Pure state machine like {@code
 * BlackjackTable}: no PZ types, no wall clock — every call takes {@code now} (ms) and money only
 * moves through the {@link Bank} port.
 *
 * <p>Chips live on the table: a player buys in (bank → stack) and cashes out when they leave (stack
 * → bank); hands are settled stack-to-stack. A hand starts only once at least {@link #MIN_PLAYERS}
 * seated players have chips, after a {@link Limits#startDelayMs()} countdown so late arrivals can
 * still buy in. Button rotates; heads-up the button posts the small blind and acts first pre-flop.
 * Leaving mid-hand folds (an all-in player stays in contention) and cashes out at once, with any
 * later winnings paid straight to the bank.
 */
public final class HoldemTable {

    public static final int MAX_SEATS = 5;
    public static final int MIN_PLAYERS = 2;
    public static final long TURN_MS = 20_000L;
    public static final long SETTLE_MS = 10_000L;
    public static final long START_DELAY_MS = 5_000L;

    public enum Phase {
        WAITING,
        PREFLOP,
        FLOP,
        TURN,
        RIVER,
        SHOWDOWN
    }

    public enum Action {
        OK,
        TABLE_FULL,
        ALREADY_SEATED,
        NOT_SEATED,
        NOT_YOUR_TURN,
        HAND_IN_PROGRESS,
        BAD_AMOUNT,
        BUYIN_TOO_LOW,
        BUYIN_TOO_HIGH,
        BANK_REFUSED,
        CANNOT_CHECK,
        RAISE_TOO_SMALL,
        RAISE_TOO_BIG
    }

    /** Result of a player request; {@code detail} carries a limit or the bank's refusal reason. */
    public record Result(Action action, @Nullable String detail) {
        public static final Result OK = new Result(Action.OK, null);

        static Result of(Action action) {
            return new Result(action, null);
        }

        static Result of(Action action, int detail) {
            return new Result(action, Integer.toString(detail));
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
        int bigBlind();

        int minBuyIn();

        int maxBuyIn();

        default long turnMs() {
            return TURN_MS;
        }

        default long settleMs() {
            return SETTLE_MS;
        }

        default long startDelayMs() {
            return START_DELAY_MS;
        }
    }

    public static final class Seat {
        final int index;
        final String username;
        final long steamId;
        final List<Card> cards = new ArrayList<>(2);
        int stack;
        int bet;
        int totalIn;
        boolean inHand;
        boolean folded;
        boolean allIn;
        boolean acted;
        boolean leaving;
        boolean showCards;
        int won;
        @Nullable String handName;

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

        public int stack() {
            return stack;
        }

        /** Chips committed on the current street. */
        public int bet() {
            return bet;
        }

        /** Chips committed over the whole hand. */
        public int totalIn() {
            return totalIn;
        }

        public List<Card> cards() {
            return Collections.unmodifiableList(cards);
        }

        public boolean isInHand() {
            return inHand;
        }

        public boolean isFolded() {
            return folded;
        }

        public boolean isAllIn() {
            return allIn;
        }

        public boolean isLeaving() {
            return leaving;
        }

        /** True once the hand is shown at showdown (everyone may see the cards). */
        public boolean isShowingCards() {
            return showCards;
        }

        public int won() {
            return won;
        }

        public @Nullable String handName() {
            return handName;
        }

        /** Dealt in and not folded. */
        boolean active() {
            return inHand && !folded;
        }

        boolean canAct() {
            return active() && !allIn;
        }

        void resetForHand() {
            cards.clear();
            bet = 0;
            totalIn = 0;
            inHand = false;
            folded = false;
            allIn = false;
            acted = false;
            showCards = false;
            won = 0;
            handName = null;
        }
    }

    private static final String BUYIN_REASON = "casino_buyin_holdem";
    private static final String CASHOUT_REASON = "casino_cashout_holdem";
    private static final String PAYOUT_REASON = "casino_payout_holdem";

    private final Bank bank;
    private final Limits limits;
    private final Random rng;
    private final Seat[] seats = new Seat[MAX_SEATS];
    private final List<Card> deck = new ArrayList<>(52);
    private final List<Card> board = new ArrayList<>(5);
    private final List<String> log = new ArrayList<>();
    private @Nullable List<Card> stackedDeck;

    private Phase phase = Phase.WAITING;
    private long deadline;
    private long startAt;
    private int hand;
    private int button = -1;
    private int actingSeat = -1;
    private int handBigBlind;
    private int currentBet;
    private int minRaise;
    private boolean dirty;

    public HoldemTable(Bank bank, Limits limits, Random rng) {
        this.bank = bank;
        this.limits = limits;
        this.rng = rng;
    }

    // --- queries ---

    public Phase phase() {
        return phase;
    }

    public int hand() {
        return hand;
    }

    public int button() {
        return button;
    }

    public int actingSeat() {
        return actingSeat;
    }

    public int bigBlind() {
        return handBigBlind;
    }

    public int currentBet() {
        return currentBet;
    }

    public List<Card> board() {
        return Collections.unmodifiableList(board);
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

    /** Everything committed this hand by everyone, including the current street's bets. */
    public int pot() {
        int total = 0;
        for (Seat s : seats) {
            if (s != null) {
                total += s.totalIn;
            }
        }
        return total;
    }

    public boolean handRunning() {
        return phase != Phase.WAITING && phase != Phase.SHOWDOWN;
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

    /** Seated players who would be dealt into the next hand. */
    public int playersWithChips() {
        int n = 0;
        for (Seat s : seats) {
            if (eligible(s)) {
                n++;
            }
        }
        return n;
    }

    public boolean isTurn(Seat seat) {
        return handRunning() && actingSeat == seat.index;
    }

    public boolean canCheck(Seat seat) {
        return seat.bet == currentBet;
    }

    public int callAmount(Seat seat) {
        return Math.max(0, Math.min(currentBet - seat.bet, seat.stack));
    }

    /** Smallest legal total bet for a raise, capped at all-in. */
    public int minRaiseTo(Seat seat) {
        return Math.min(currentBet + minRaise, maxRaiseTo(seat));
    }

    public int maxRaiseTo(Seat seat) {
        return seat.bet + seat.stack;
    }

    /** Buy-in may happen between hands or while sitting out, never while dealt into a live hand. */
    public boolean canBuyIn(Seat seat) {
        return !(handRunning() && seat.inHand);
    }

    /** Drain-and-clear of human-readable events since the last call (for the client's log line). */
    public List<String> drainLog() {
        List<String> out = new ArrayList<>(log);
        log.clear();
        return out;
    }

    public boolean isDirty() {
        return dirty;
    }

    public void clearDirty() {
        dirty = false;
    }

    // --- seating & chips ---

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

    public Result buyIn(String username, int amount) {
        Seat seat = seatOf(username);
        if (seat == null) {
            return Result.of(Action.NOT_SEATED);
        }
        if (!canBuyIn(seat)) {
            return Result.of(Action.HAND_IN_PROGRESS);
        }
        if (amount <= 0) {
            return Result.of(Action.BAD_AMOUNT);
        }
        int min = limits.minBuyIn();
        int max = limits.maxBuyIn();
        if (seat.stack == 0 && amount < min) {
            return Result.of(Action.BUYIN_TOO_LOW, min);
        }
        if (seat.stack + amount > max) {
            return Result.of(Action.BUYIN_TOO_HIGH, Math.max(0, max - seat.stack));
        }
        String refusal = bank.take(username, seat.steamId, amount, BUYIN_REASON);
        if (refusal != null) {
            return new Result(Action.BANK_REFUSED, refusal);
        }
        seat.stack += amount;
        say(username + " buys in for " + amount);
        dirty = true;
        return Result.OK;
    }

    public Result leave(String username, long now) {
        Seat seat = seatOf(username);
        if (seat == null) {
            return Result.of(Action.NOT_SEATED);
        }
        dirty = true;
        if (seat.stack > 0) {
            bank.give(username, seat.steamId, seat.stack, CASHOUT_REASON);
            seat.stack = 0;
        }
        if (handRunning() && seat.inHand) {
            seat.leaving = true;
            say(username + " leaves the table");
            if (seat.canAct()) {
                seat.folded = true;
                seat.acted = true;
                if (actingSeat == seat.index) {
                    afterAction(now);
                } else if (activeCount() <= 1) {
                    awardUncontested(now);
                }
            }
            return Result.OK;
        }
        seats[seat.index] = null;
        say(username + " leaves the table");
        if (phase == Phase.WAITING) {
            startAt = 0L;
            deadline = 0L;
        }
        return Result.OK;
    }

    // --- betting actions ---

    public Result fold(String username, long now) {
        Seat seat = seatOf(username);
        Result turn = requireTurn(seat);
        if (turn != null) {
            return turn;
        }
        seat.folded = true;
        seat.acted = true;
        say(username + " folds");
        dirty = true;
        afterAction(now);
        return Result.OK;
    }

    public Result check(String username, long now) {
        Seat seat = seatOf(username);
        Result turn = requireTurn(seat);
        if (turn != null) {
            return turn;
        }
        if (!canCheck(seat)) {
            return Result.of(Action.CANNOT_CHECK, callAmount(seat));
        }
        seat.acted = true;
        say(username + " checks");
        dirty = true;
        afterAction(now);
        return Result.OK;
    }

    public Result call(String username, long now) {
        Seat seat = seatOf(username);
        Result turn = requireTurn(seat);
        if (turn != null) {
            return turn;
        }
        if (canCheck(seat)) {
            return check(username, now);
        }
        int amount = callAmount(seat);
        put(seat, amount);
        seat.acted = true;
        say(username + " calls " + amount + (seat.allIn ? " and is all-in" : ""));
        dirty = true;
        afterAction(now);
        return Result.OK;
    }

    /** Raise (or open) so the seat's total bet on this street becomes {@code to}. */
    public Result raiseTo(String username, int to, long now) {
        Seat seat = seatOf(username);
        Result turn = requireTurn(seat);
        if (turn != null) {
            return turn;
        }
        int max = maxRaiseTo(seat);
        if (to > max) {
            return Result.of(Action.RAISE_TOO_BIG, max);
        }
        boolean shove = to == max;
        int raiseSize = to - currentBet;
        if (to <= currentBet || (raiseSize < minRaise && !shove)) {
            return Result.of(Action.RAISE_TOO_SMALL, minRaiseTo(seat));
        }
        boolean opening = currentBet == 0;
        put(seat, to - seat.bet);
        // Only a full raise re-opens the action; a short all-in leaves earlier actors with just
        // the call to make (nextToAct still returns them because their bet is now short).
        if (raiseSize >= minRaise) {
            minRaise = raiseSize;
            for (Seat s : seats) {
                if (s != null && s != seat) {
                    s.acted = false;
                }
            }
        }
        currentBet = to;
        seat.acted = true;
        say(
                username
                        + (opening ? " bets " : " raises to ")
                        + to
                        + (seat.allIn ? " and is all-in" : ""));
        dirty = true;
        afterAction(now);
        return Result.OK;
    }

    public Result allIn(String username, long now) {
        Seat seat = seatOf(username);
        Result turn = requireTurn(seat);
        if (turn != null) {
            return turn;
        }
        int max = maxRaiseTo(seat);
        if (max <= currentBet) {
            return call(username, now);
        }
        return raiseTo(username, max, now);
    }

    // --- clock ---

    public void tick(long now) {
        switch (phase) {
            case WAITING -> {
                if (playersWithChips() >= MIN_PLAYERS) {
                    if (startAt == 0L) {
                        startAt = now + limits.startDelayMs();
                        deadline = startAt;
                        dirty = true;
                    } else if (now >= startAt) {
                        startHand(now);
                    }
                } else if (startAt != 0L) {
                    startAt = 0L;
                    deadline = 0L;
                    dirty = true;
                }
            }
            case PREFLOP, FLOP, TURN, RIVER -> {
                if (now >= deadline) {
                    timeout(now);
                }
            }
            case SHOWDOWN -> {
                if (now >= deadline) {
                    finishHand();
                }
            }
        }
    }

    // --- hand flow ---

    private void startHand(long now) {
        hand++;
        startAt = 0L;
        board.clear();
        shuffle();
        for (Seat s : seats) {
            if (s != null) {
                s.resetForHand();
                s.inHand = eligible(s);
            }
        }
        handBigBlind = Math.max(2, limits.bigBlind());
        int smallBlind = handBigBlind / 2;
        currentBet = handBigBlind;
        minRaise = handBigBlind;
        button = nextInHand(button);
        int sbSeat;
        int bbSeat;
        if (inHandCount() == 2) {
            sbSeat = button;
            bbSeat = nextInHand(button);
        } else {
            sbSeat = nextInHand(button);
            bbSeat = nextInHand(sbSeat);
        }
        say(
                "Hand "
                        + hand
                        + ": blinds "
                        + smallBlind
                        + "/"
                        + handBigBlind
                        + ", "
                        + seats[button].username
                        + " has the button");
        postBlind(seats[sbSeat], smallBlind);
        postBlind(seats[bbSeat], handBigBlind);
        for (int round = 0; round < 2; round++) {
            for (Seat s : seats) {
                if (s != null && s.inHand) {
                    s.cards.add(deck.remove(deck.size() - 1));
                }
            }
        }
        phase = Phase.PREFLOP;
        dirty = true;
        actingSeat = nextToAct(bbSeat);
        if (actingSeat == -1) {
            advanceStreet(now);
        } else {
            deadline = now + limits.turnMs();
        }
    }

    private void postBlind(Seat seat, int amount) {
        int posted = Math.min(amount, seat.stack);
        put(seat, posted);
        say(seat.username + " posts " + posted + (seat.allIn ? " and is all-in" : ""));
    }

    private void put(Seat seat, int amount) {
        seat.stack -= amount;
        seat.bet += amount;
        seat.totalIn += amount;
        if (seat.stack == 0) {
            seat.allIn = true;
        }
    }

    private void timeout(long now) {
        Seat seat = seats[actingSeat];
        if (seat == null) {
            afterAction(now);
            return;
        }
        seat.acted = true;
        if (canCheck(seat)) {
            say(seat.username + " ran out of time and checks");
        } else {
            seat.folded = true;
            say(seat.username + " ran out of time and folds");
        }
        dirty = true;
        afterAction(now);
    }

    private void afterAction(long now) {
        if (activeCount() <= 1) {
            awardUncontested(now);
            return;
        }
        int next = nextToAct(actingSeat);
        if (next != -1) {
            actingSeat = next;
            deadline = now + limits.turnMs();
            return;
        }
        advanceStreet(now);
    }

    private void advanceStreet(long now) {
        do {
            for (Seat s : seats) {
                if (s != null) {
                    s.bet = 0;
                    s.acted = false;
                }
            }
            currentBet = 0;
            minRaise = handBigBlind;
            switch (phase) {
                case PREFLOP -> {
                    phase = Phase.FLOP;
                    dealBoard(3);
                    say("Flop: " + boardTail(3));
                }
                case FLOP -> {
                    phase = Phase.TURN;
                    dealBoard(1);
                    say("Turn: " + boardTail(1));
                }
                case TURN -> {
                    phase = Phase.RIVER;
                    dealBoard(1);
                    say("River: " + boardTail(1));
                }
                default -> {
                    showdown(now);
                    return;
                }
            }
            // With at most one player still able to bet there is nobody to bet against: run the
            // board out to the showdown.
        } while (canActCount() < 2);
        actingSeat = nextToAct(button);
        deadline = now + limits.turnMs();
        dirty = true;
    }

    private void dealBoard(int n) {
        for (int i = 0; i < n; i++) {
            board.add(deck.remove(deck.size() - 1));
        }
    }

    private String boardTail(int n) {
        StringBuilder sb = new StringBuilder();
        for (int i = board.size() - n; i < board.size(); i++) {
            if (sb.length() > 0) {
                sb.append(' ');
            }
            sb.append(board.get(i).code());
        }
        return sb.toString();
    }

    private void awardUncontested(long now) {
        Seat winner = null;
        for (Seat s : seats) {
            if (s != null && s.active()) {
                winner = s;
            }
        }
        int total = pot();
        if (winner != null) {
            credit(winner, total);
            say(winner.username + " wins " + total + " — everyone else folded");
        }
        endHand(now);
    }

    private void showdown(long now) {
        phase = Phase.SHOWDOWN;
        List<Seat> contenders = new ArrayList<>();
        for (Seat s : seats) {
            if (s != null && s.active()) {
                contenders.add(s);
            }
        }
        List<HandValue> values = new ArrayList<>();
        for (Seat s : contenders) {
            List<Card> seven = new ArrayList<>(s.cards);
            seven.addAll(board);
            HandValue v = HandEvaluator.best(seven);
            values.add(v);
            s.handName = v.name();
            s.showCards = true;
            say(
                    s.username
                            + " shows "
                            + s.cards.get(0).code()
                            + " "
                            + s.cards.get(1).code()
                            + " — "
                            + v.name());
        }
        returnUncalled(contenders);
        // Side pots: one pot per distinct all-in level, shared by everyone who reached it.
        TreeSet<Integer> levels = new TreeSet<>();
        for (Seat s : contenders) {
            levels.add(s.totalIn);
        }
        int prev = 0;
        int distributed = 0;
        for (int level : levels) {
            int amount = 0;
            for (Seat s : seats) {
                if (s != null && s.inHand) {
                    amount += Math.max(0, Math.min(s.totalIn, level) - prev);
                }
            }
            prev = level;
            if (amount == 0) {
                continue;
            }
            long best = Long.MIN_VALUE;
            for (int i = 0; i < contenders.size(); i++) {
                if (contenders.get(i).totalIn >= level) {
                    best = Math.max(best, values.get(i).score());
                }
            }
            List<Seat> winners = new ArrayList<>();
            for (int i = 0; i < contenders.size(); i++) {
                if (contenders.get(i).totalIn >= level && values.get(i).score() == best) {
                    winners.add(contenders.get(i));
                }
            }
            int share = amount / winners.size();
            int remainder = amount - share * winners.size();
            Seat first = firstAfterButton(winners);
            for (Seat w : winners) {
                credit(w, share + (w == first ? remainder : 0));
            }
            distributed += amount;
        }
        int leftover = pot() - distributed;
        if (leftover > 0 && !contenders.isEmpty()) {
            credit(firstAfterButton(contenders), leftover);
        }
        for (Seat s : contenders) {
            if (s.won > 0) {
                say(s.username + " wins " + s.won + " with " + s.handName);
            }
        }
        endHand(now);
    }

    /** Chips the top bettor put in that nobody matched go straight back to them. */
    private void returnUncalled(List<Seat> contenders) {
        Seat top = null;
        int second = 0;
        for (Seat s : contenders) {
            if (top == null || s.totalIn > top.totalIn) {
                second = top == null ? 0 : Math.max(second, top.totalIn);
                top = s;
            } else {
                second = Math.max(second, s.totalIn);
            }
        }
        if (top == null) {
            return;
        }
        int excess = top.totalIn - second;
        if (excess > 0) {
            top.totalIn -= excess;
            if (top.leaving) {
                bank.give(top.username, top.steamId, excess, CASHOUT_REASON);
            } else {
                top.stack += excess;
            }
        }
    }

    private void credit(Seat seat, int amount) {
        if (amount <= 0) {
            return;
        }
        seat.won += amount;
        if (seat.leaving) {
            bank.give(seat.username, seat.steamId, amount, PAYOUT_REASON);
        } else {
            seat.stack += amount;
        }
    }

    private void endHand(long now) {
        phase = Phase.SHOWDOWN;
        actingSeat = -1;
        deadline = now + limits.settleMs();
        dirty = true;
    }

    private void finishHand() {
        for (int i = 0; i < MAX_SEATS; i++) {
            Seat s = seats[i];
            if (s == null) {
                continue;
            }
            if (s.leaving) {
                seats[i] = null;
            } else if (s.inHand && s.stack == 0) {
                say(s.username + " is out of chips");
            }
        }
        phase = Phase.WAITING;
        deadline = 0L;
        startAt = 0L;
        dirty = true;
    }

    // --- helpers ---

    private @Nullable Result requireTurn(@Nullable Seat seat) {
        if (seat == null) {
            return Result.of(Action.NOT_SEATED);
        }
        if (!isTurn(seat)) {
            return Result.of(Action.NOT_YOUR_TURN);
        }
        return null;
    }

    private static boolean eligible(@Nullable Seat s) {
        return s != null && !s.leaving && s.stack > 0;
    }

    private int inHandCount() {
        int n = 0;
        for (Seat s : seats) {
            if (s != null && s.inHand) {
                n++;
            }
        }
        return n;
    }

    private int activeCount() {
        int n = 0;
        for (Seat s : seats) {
            if (s != null && s.active()) {
                n++;
            }
        }
        return n;
    }

    private int canActCount() {
        int n = 0;
        for (Seat s : seats) {
            if (s != null && s.canAct()) {
                n++;
            }
        }
        return n;
    }

    /** Next in-hand seat clockwise after {@code from} (wrapping); {@code from} itself last. */
    private int nextInHand(int from) {
        for (int step = 1; step <= MAX_SEATS; step++) {
            int i = Math.floorMod(from + step, MAX_SEATS);
            if (seats[i] != null && seats[i].inHand) {
                return i;
            }
        }
        throw new IllegalStateException("no players in hand");
    }

    /** Next seat after {@code from} that still owes an action this street, or -1. */
    private int nextToAct(int from) {
        for (int step = 1; step <= MAX_SEATS; step++) {
            int i = Math.floorMod(from + step, MAX_SEATS);
            Seat s = seats[i];
            if (s != null && s.canAct() && (!s.acted || s.bet < currentBet)) {
                return i;
            }
        }
        return -1;
    }

    private Seat firstAfterButton(List<Seat> candidates) {
        for (int step = 1; step <= MAX_SEATS; step++) {
            int i = Math.floorMod(button + step, MAX_SEATS);
            for (Seat s : candidates) {
                if (s.index == i) {
                    return s;
                }
            }
        }
        return candidates.get(0);
    }

    /** Test seam: the next hand deals {@code dealOrder} front to back instead of shuffling. */
    void stackDeck(List<Card> dealOrder) {
        stackedDeck = new ArrayList<>(dealOrder);
    }

    private void shuffle() {
        deck.clear();
        if (stackedDeck != null) {
            // Cards are drawn from the end, so reverse the requested order.
            for (int i = stackedDeck.size() - 1; i >= 0; i--) {
                deck.add(stackedDeck.get(i));
            }
            stackedDeck = null;
            return;
        }
        for (char suit : new char[] {'s', 'h', 'd', 'c'}) {
            for (int rank = 1; rank <= 13; rank++) {
                deck.add(new Card(rank, suit));
            }
        }
        Collections.shuffle(deck, rng);
    }

    private void say(String message) {
        log.add(message);
    }
}
