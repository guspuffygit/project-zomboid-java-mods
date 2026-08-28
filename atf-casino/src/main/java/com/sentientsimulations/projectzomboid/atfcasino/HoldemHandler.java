package com.sentientsimulations.projectzomboid.atfcasino;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import com.sentientsimulations.projectzomboid.atfcasino.blackjack.Card;
import com.sentientsimulations.projectzomboid.atfcasino.holdem.HoldemTable;
import com.sentientsimulations.projectzomboid.atfcasino.holdem.HoldemTable.Result;
import com.sentientsimulations.projectzomboid.atfcasino.holdem.HoldemTable.Seat;
import com.sentientsimulations.projectzomboid.atfcasino.npc.CasinoLayout;
import com.sentientsimulations.projectzomboid.atfcasino.npc.CasinoNpc;
import com.sentientsimulations.projectzomboid.atfcasino.npc.CasinoNpcManager;
import io.pzstorm.storm.event.core.OnClientCommand;
import io.pzstorm.storm.event.core.SubscribeEvent;
import io.pzstorm.storm.event.lua.OnPlayerDisconnectedEvent;
import io.pzstorm.storm.event.lua.OnTickEvent;
import java.security.SecureRandom;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.concurrent.ConcurrentLinkedQueue;
import org.jetbrains.annotations.Nullable;
import se.krka.kahlua.vm.KahluaTable;
import zombie.Lua.LuaManager;
import zombie.characters.IsoPlayer;
import zombie.network.GameServer;

/**
 * Server side of the Texas Hold'em table: turns {@code AtfCasino:holdem} client commands into
 * {@link HoldemTable} calls, drives the clock from the main-thread tick, enforces that players stay
 * within reach of the poker dealer, and pushes each viewer their own view of the table (own hole
 * cards, everyone else's face down until showdown) after every change.
 */
public final class HoldemHandler {

    private static final String MODULE = "AtfCasino";
    private static final String STATE_COMMAND = "hdState";
    private static final String ERROR_COMMAND = "hdError";
    private static final String CLOSED_COMMAND = "hdClosed";
    private static final String CURRENCY = "Scraps";
    private static final String HIDDEN_CARD = "??";

    private static final long PRESENCE_CHECK_MS = 1_000L;
    private static final int RECENT_LOG_LINES = 10;

    private static final HoldemTable TABLE =
            new HoldemTable(new EconomyBank(), new SandboxLimits(), new SecureRandom());

    /** Usernames with the table window open (seated or just watching). */
    private static final Set<String> VIEWERS = new LinkedHashSet<>();

    /** Tail of the table log, replayed into a window that (re)opens so it shows the hand so far. */
    private static final ArrayDeque<String> RECENT_LOG = new ArrayDeque<>();

    private static final ConcurrentLinkedQueue<String> DISCONNECTED = new ConcurrentLinkedQueue<>();
    private static long lastPresenceCheckMs;

    private HoldemHandler() {}

    /**
     * Stands the player up and closes their window here because they sat down at another game. Used
     * by {@link CasinoSeatGuard}; {@link HoldemTable#leave} cashes out the stack and folds a live
     * hand.
     */
    static void standUp(IsoPlayer player, long now) {
        String username = player.getUsername();
        if (TABLE.seatOf(username) == null) {
            return;
        }
        TABLE.leave(username, now);
        VIEWERS.remove(username);
        KahluaTable args = LuaManager.platform.newTable();
        args.rawset("reason", "OTHER_TABLE");
        GameServer.sendServerCommand(player, MODULE, CLOSED_COMMAND, args);
        broadcastIfDirty(now);
    }

    // --- client commands (server main thread) ---

    @OnClientCommand
    public static void onHoldem(HoldemCommand event) {
        IsoPlayer player = event.getPlayer();
        if (player == null) {
            return;
        }
        String action = event.getAction();
        String username = player.getUsername();
        long now = System.currentTimeMillis();
        if (!AtfCasinoConfig.isEnabled() || !AtfCasinoConfig.isGameEnabled(CasinoGame.HOLDEM)) {
            sendError(player, "DISABLED", null);
            return;
        }
        if (action == null) {
            return;
        }
        Result result = Result.OK;
        switch (action) {
            case "open" -> {
                if (player.isDead() || !player.isAlive()) {
                    sendError(player, "DEAD", null);
                    return;
                }
                if (!nearDealer(player)) {
                    sendError(player, "TOO_FAR", null);
                    return;
                }
                VIEWERS.add(username);
                sendState(player, now);
                return;
            }
            // Closing the window only stops the state feed; the seat and stack are kept so
            // reopening drops the player straight back into the hand. Walking away, dying or
            // logging off still cashes them out via enforcePresence/DISCONNECTED.
            case "close" -> {
                VIEWERS.remove(username);
                return;
            }
            case "sit" -> {
                if (!nearDealer(player)) {
                    sendError(player, "TOO_FAR", null);
                    return;
                }
                CasinoSeatGuard.standUpElsewhere(player, CasinoGame.HOLDEM, now);
                VIEWERS.add(username);
                result = TABLE.sit(username, player.getSteamID());
            }
            case "leave" -> result = TABLE.leave(username, now);
            case "buyin" -> result = TABLE.buyIn(username, event.getAmount());
            case "fold" -> result = TABLE.fold(username, now);
            case "check" -> result = TABLE.check(username, now);
            case "call" -> result = TABLE.call(username, now);
            case "raise" -> result = TABLE.raiseTo(username, event.getAmount(), now);
            case "allin" -> result = TABLE.allIn(username, now);
            default -> {
                LOGGER.warn("[AtfCasino] {} sent unknown holdem action {}", username, action);
                return;
            }
        }
        if (!result.ok()) {
            sendError(player, result.action().name(), result.detail());
        }
        broadcastIfDirty(now);
    }

    // --- clock ---

    @SubscribeEvent
    public static void onTick(OnTickEvent event) {
        if (!GameServer.server) {
            return;
        }
        try {
            long now = System.currentTimeMillis();
            String gone;
            while ((gone = DISCONNECTED.poll()) != null) {
                VIEWERS.remove(gone);
                if (TABLE.seatOf(gone) != null) {
                    TABLE.leave(gone, now);
                }
            }
            TABLE.tick(now);
            if (now - lastPresenceCheckMs >= PRESENCE_CHECK_MS) {
                lastPresenceCheckMs = now;
                enforcePresence(now);
            }
            broadcastIfDirty(now);
        } catch (Throwable t) {
            LOGGER.warn("[AtfCasino] holdem tick failed: {}", t.toString(), t);
        }
    }

    @SubscribeEvent
    public static void onPlayerDisconnected(OnPlayerDisconnectedEvent event) {
        if (event.username != null) {
            DISCONNECTED.add(event.username);
        }
    }

    /** Anyone who walked away from the dealer, logged off or died is cashed out and closed. */
    private static void enforcePresence(long now) {
        List<String> everyone = new ArrayList<>(VIEWERS);
        for (Seat s : TABLE.seatedPlayers()) {
            if (!everyone.contains(s.username())) {
                everyone.add(s.username());
            }
        }
        for (String username : everyone) {
            IsoPlayer p = GameServer.getPlayerByUserNameForCommand(username);
            boolean dead = p != null && (p.isDead() || !p.isAlive());
            if (p != null && !dead && nearDealer(p)) {
                continue;
            }
            VIEWERS.remove(username);
            if (TABLE.seatOf(username) != null) {
                TABLE.leave(username, now);
            }
            if (p != null) {
                KahluaTable args = LuaManager.platform.newTable();
                args.rawset("reason", dead ? "DEAD" : "TOO_FAR");
                GameServer.sendServerCommand(p, MODULE, CLOSED_COMMAND, args);
            }
        }
    }

    private static boolean nearDealer(IsoPlayer p) {
        CasinoNpc dealer = CasinoNpcManager.pokerDealer();
        return dealer.distanceTo(p.getX(), p.getY(), p.getZ()) <= CasinoLayout.TABLE_RADIUS;
    }

    // --- state push ---

    private static void broadcastIfDirty(long now) {
        if (!TABLE.isDirty()) {
            return;
        }
        TABLE.clearDirty();
        List<String> log = TABLE.drainLog();
        for (String line : log) {
            if (RECENT_LOG.size() == RECENT_LOG_LINES) {
                RECENT_LOG.pollFirst();
            }
            RECENT_LOG.addLast(line);
        }
        Set<String> recipients = new LinkedHashSet<>(VIEWERS);
        for (Seat s : TABLE.seatedPlayers()) {
            recipients.add(s.username());
        }
        for (String username : recipients) {
            IsoPlayer p = GameServer.getPlayerByUserNameForCommand(username);
            if (p != null) {
                GameServer.sendServerCommand(p, MODULE, STATE_COMMAND, buildState(p, now, log));
            }
        }
    }

    private static void sendState(IsoPlayer player, long now) {
        KahluaTable state = buildState(player, now, new ArrayList<>(RECENT_LOG));
        state.rawset("resetLog", true);
        GameServer.sendServerCommand(player, MODULE, STATE_COMMAND, state);
    }

    private static KahluaTable buildState(IsoPlayer viewer, long now, List<String> log) {
        String me = viewer.getUsername();
        Seat mine = TABLE.seatOf(me);
        boolean running = TABLE.handRunning();
        KahluaTable t = LuaManager.platform.newTable();
        t.rawset("phase", TABLE.phase().name());
        t.rawset("hand", (double) TABLE.hand());
        t.rawset("pot", (double) TABLE.pot());
        t.rawset("secondsLeft", (double) TABLE.secondsLeft(now));
        t.rawset("bigBlind", (double) AtfCasinoConfig.getHoldemBigBlind());
        t.rawset("minBuyIn", (double) AtfCasinoConfig.getHoldemMinBuyIn());
        t.rawset("maxBuyIn", (double) AtfCasinoConfig.getHoldemMaxBuyIn());
        t.rawset("minPlayers", (double) HoldemTable.MIN_PLAYERS);
        t.rawset("playersWithChips", (double) TABLE.playersWithChips());
        t.rawset("maxSeats", (double) HoldemTable.MAX_SEATS);
        t.rawset("you", (double) (mine == null ? 0 : mine.index() + 1));
        t.rawset("canSit", mine == null && TABLE.hasFreeSeat());
        t.rawset("canBuyIn", mine != null && TABLE.canBuyIn(mine));
        boolean canAct = mine != null && TABLE.isTurn(mine);
        t.rawset("canAct", canAct);
        if (mine != null) {
            t.rawset("canCheck", TABLE.canCheck(mine));
            t.rawset("callAmount", (double) TABLE.callAmount(mine));
            t.rawset("minRaise", (double) TABLE.minRaiseTo(mine));
            t.rawset("maxRaise", (double) TABLE.maxRaiseTo(mine));
        }
        KahluaTable board = LuaManager.platform.newTable();
        int b = 0;
        for (Card c : TABLE.board()) {
            board.rawset(++b, c.code());
        }
        t.rawset("board", board);

        KahluaTable seats = LuaManager.platform.newTable();
        int n = 0;
        for (Seat s : TABLE.seatedPlayers()) {
            boolean isMe = s.username().equalsIgnoreCase(me);
            KahluaTable st = LuaManager.platform.newTable();
            st.rawset("index", (double) (s.index() + 1));
            st.rawset("name", s.username());
            st.rawset("stack", (double) s.stack());
            st.rawset("bet", (double) s.bet());
            st.rawset("totalIn", (double) s.totalIn());
            st.rawset("inHand", s.isInHand());
            st.rawset("folded", s.isFolded());
            st.rawset("allIn", s.isAllIn());
            st.rawset("leaving", s.isLeaving());
            st.rawset("isButton", TABLE.button() == s.index() && TABLE.hand() > 0);
            st.rawset("isTurn", running && TABLE.actingSeat() == s.index());
            st.rawset("isYou", isMe);
            st.rawset("won", (double) s.won());
            if (s.handName() != null && s.isShowingCards()) {
                st.rawset("handName", s.handName());
            }
            KahluaTable cards = LuaManager.platform.newTable();
            int k = 0;
            for (Card c : s.cards()) {
                cards.rawset(++k, isMe || s.isShowingCards() ? c.code() : HIDDEN_CARD);
            }
            st.rawset("cards", cards);
            seats.rawset(++n, st);
        }
        t.rawset("seats", seats);

        KahluaTable logTable = LuaManager.platform.newTable();
        for (int i = 0; i < log.size(); i++) {
            logTable.rawset(i + 1, log.get(i));
        }
        t.rawset("log", logTable);
        return t;
    }

    private static void sendError(IsoPlayer player, String reason, @Nullable String detail) {
        KahluaTable args = LuaManager.platform.newTable();
        args.rawset("reason", reason);
        if (detail != null) {
            args.rawset("detail", detail);
        }
        GameServer.sendServerCommand(player, MODULE, ERROR_COMMAND, args);
    }

    // --- ports ---

    private static final class SandboxLimits implements HoldemTable.Limits {
        @Override
        public int bigBlind() {
            return AtfCasinoConfig.getHoldemBigBlind();
        }

        @Override
        public int minBuyIn() {
            return AtfCasinoConfig.getHoldemMinBuyIn();
        }

        @Override
        public int maxBuyIn() {
            return AtfCasinoConfig.getHoldemMaxBuyIn();
        }

        @Override
        public long turnMs() {
            return AtfCasinoConfig.getHoldemTurnSeconds() * 1_000L;
        }

        @Override
        public long settleMs() {
            return AtfCasinoConfig.getHoldemPauseSeconds() * 1_000L;
        }

        @Override
        public long startDelayMs() {
            return AtfCasinoConfig.getHoldemStartDelaySeconds() * 1_000L;
        }
    }

    /**
     * Buy-ins come out through the economy's player-bound deduct (atomic balance check); cash-outs
     * and payouts go in through the username+steamId grant so a player who walked off still gets
     * their chips back.
     */
    private static final class EconomyBank implements HoldemTable.Bank {
        @Override
        public @Nullable String take(String username, long steamId, int amount, String reason) {
            IsoPlayer p = GameServer.getPlayerByUserNameForCommand(username);
            if (p == null) {
                return "PLAYER_OFFLINE";
            }
            AtfEconomyBridge.DeductResult r = AtfEconomyBridge.deduct(p, CURRENCY, amount, reason);
            if (!r.ok()) {
                LOGGER.info(
                        "[AtfCasino] {} could not buy in for {} {}: {}",
                        username,
                        amount,
                        CURRENCY,
                        r.reason());
                return r.reason() == null ? "ECONOMY_ERROR" : r.reason();
            }
            LOGGER.info(
                    "[AtfCasino] {} bought in for {} {} ({})", username, amount, CURRENCY, reason);
            return null;
        }

        @Override
        public void give(String username, long steamId, int amount, String reason) {
            AtfEconomyBridge.GrantResult r =
                    AtfEconomyBridge.grant(username, steamId, CURRENCY, amount, reason);
            if (!r.ok()) {
                LOGGER.error(
                        "[AtfCasino] payout of {} {} to {} ({}) FAILED: {}",
                        amount,
                        CURRENCY,
                        username,
                        reason,
                        r.reason());
                return;
            }
            LOGGER.info("[AtfCasino] paid {} {} to {} ({})", amount, CURRENCY, username, reason);
        }
    }
}
