package com.sentientsimulations.projectzomboid.atfcasino;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import com.sentientsimulations.projectzomboid.atfcasino.npc.CasinoLayout;
import com.sentientsimulations.projectzomboid.atfcasino.npc.CasinoNpc;
import com.sentientsimulations.projectzomboid.atfcasino.npc.CasinoNpcManager;
import com.sentientsimulations.projectzomboid.atfcasino.roulette.RouletteTable;
import com.sentientsimulations.projectzomboid.atfcasino.roulette.RouletteTable.Bet;
import com.sentientsimulations.projectzomboid.atfcasino.roulette.RouletteTable.BetType;
import com.sentientsimulations.projectzomboid.atfcasino.roulette.RouletteTable.Phase;
import com.sentientsimulations.projectzomboid.atfcasino.roulette.RouletteTable.Result;
import com.sentientsimulations.projectzomboid.atfcasino.roulette.RouletteTable.Seat;
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
 * Server side of the roulette table: turns {@code AtfCasino:roulette} client commands into {@link
 * RouletteTable} calls, drives the wheel from the main-thread tick, enforces that players stay
 * within reach of the croupier, and pushes the full table state to everyone watching after every
 * change. The client renders what it is told and nothing else — the winning number, payouts and
 * every chip on the board live here.
 */
public final class RouletteHandler {

    private static final String MODULE = "AtfCasino";
    private static final String STATE_COMMAND = "rlState";
    private static final String ERROR_COMMAND = "rlError";
    private static final String CLOSED_COMMAND = "rlClosed";
    private static final String CURRENCY = "Scraps";

    private static final long PRESENCE_CHECK_MS = 1_000L;
    private static final int RECENT_LOG_LINES = 8;

    private static final RouletteTable TABLE =
            new RouletteTable(new EconomyBank(), new SandboxLimits(), new SecureRandom());

    /** Usernames with the table window open (seated or just watching). */
    private static final Set<String> VIEWERS = new LinkedHashSet<>();

    /**
     * Tail of the table log, replayed into a window that (re)opens so it shows the round so far.
     */
    private static final ArrayDeque<String> RECENT_LOG = new ArrayDeque<>();

    private static final ConcurrentLinkedQueue<String> DISCONNECTED = new ConcurrentLinkedQueue<>();
    private static long lastPresenceCheckMs;

    private RouletteHandler() {}

    /**
     * Stands the player up and closes their window here because they sat down at another game. Used
     * by {@link CasinoSeatGuard}; chips on the board are settled by {@link RouletteTable#leave}.
     */
    static void standUp(IsoPlayer player, long now) {
        String username = player.getUsername();
        if (TABLE.seatOf(username) == null) {
            return;
        }
        TABLE.leave(username);
        VIEWERS.remove(username);
        KahluaTable args = LuaManager.platform.newTable();
        args.rawset("reason", "OTHER_TABLE");
        GameServer.sendServerCommand(player, MODULE, CLOSED_COMMAND, args);
        broadcastIfDirty(now);
    }

    // --- client commands (server main thread) ---

    @OnClientCommand
    public static void onRoulette(RouletteCommand event) {
        IsoPlayer player = event.getPlayer();
        if (player == null) {
            return;
        }
        String action = event.getAction();
        String username = player.getUsername();
        long now = System.currentTimeMillis();
        if (!AtfCasinoConfig.isEnabled() || !AtfCasinoConfig.isGameEnabled(CasinoGame.ROULETTE)) {
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
                if (!nearCroupier(player)) {
                    sendError(player, "TOO_FAR", null);
                    return;
                }
                VIEWERS.add(username);
                sendState(player, now);
                return;
            }
            // Closing the window only stops the state feed; the seat and any chips on the board
            // are kept so reopening drops the player straight back into their round. Walking
            // away, dying or logging off still stands them up via enforcePresence/DISCONNECTED.
            case "close" -> {
                VIEWERS.remove(username);
                return;
            }
            case "sit" -> {
                if (!nearCroupier(player)) {
                    sendError(player, "TOO_FAR", null);
                    return;
                }
                CasinoSeatGuard.standUpElsewhere(player, CasinoGame.ROULETTE, now);
                VIEWERS.add(username);
                result = TABLE.sit(username, player.getSteamID());
            }
            case "leave" -> result = TABLE.leave(username);
            case "bet" ->
                    result =
                            TABLE.bet(
                                    username,
                                    BetType.fromWire(event.getBetType()),
                                    event.getTarget(),
                                    event.getAmount(),
                                    now);
            case "clear" -> result = TABLE.clearBets(username);
            default -> {
                LOGGER.warn("[AtfCasino] {} sent unknown roulette action {}", username, action);
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
                    TABLE.leave(gone);
                }
            }
            TABLE.tick(now);
            if (now - lastPresenceCheckMs >= PRESENCE_CHECK_MS) {
                lastPresenceCheckMs = now;
                enforcePresence();
            }
            broadcastIfDirty(now);
        } catch (Throwable t) {
            LOGGER.warn("[AtfCasino] roulette tick failed: {}", t.toString(), t);
        }
    }

    @SubscribeEvent
    public static void onPlayerDisconnected(OnPlayerDisconnectedEvent event) {
        if (event.username != null) {
            DISCONNECTED.add(event.username);
        }
    }

    /** Anyone who walked away from the croupier, logged off or died is stood up and closed. */
    private static void enforcePresence() {
        List<String> everyone = new ArrayList<>(VIEWERS);
        for (Seat s : TABLE.seatedPlayers()) {
            if (!everyone.contains(s.username())) {
                everyone.add(s.username());
            }
        }
        for (String username : everyone) {
            IsoPlayer p = GameServer.getPlayerByUserNameForCommand(username);
            boolean dead = p != null && (p.isDead() || !p.isAlive());
            if (p != null && !dead && nearCroupier(p)) {
                continue;
            }
            VIEWERS.remove(username);
            if (TABLE.seatOf(username) != null) {
                TABLE.leave(username);
            }
            if (p != null) {
                KahluaTable args = LuaManager.platform.newTable();
                args.rawset("reason", dead ? "DEAD" : "TOO_FAR");
                GameServer.sendServerCommand(p, MODULE, CLOSED_COMMAND, args);
            }
        }
    }

    private static boolean nearCroupier(IsoPlayer p) {
        CasinoNpc croupier = CasinoNpcManager.croupier();
        return croupier.distanceTo(p.getX(), p.getY(), p.getZ()) <= CasinoLayout.TABLE_RADIUS;
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
        KahluaTable t = LuaManager.platform.newTable();
        t.rawset("phase", TABLE.phase().name());
        t.rawset("round", (double) TABLE.round());
        t.rawset("secondsLeft", (double) TABLE.secondsLeft(now));
        t.rawset("minBet", (double) AtfCasinoConfig.getMinBet());
        t.rawset("maxBet", (double) AtfCasinoConfig.getMaxBet());
        t.rawset("maxSeats", (double) RouletteTable.MAX_SEATS);
        t.rawset("maxBets", (double) RouletteTable.MAX_BETS_PER_SEAT);
        t.rawset("you", (double) (mine == null ? 0 : mine.index() + 1));
        t.rawset("canSit", mine == null && TABLE.hasFreeSeat());
        t.rawset("canBet", mine != null && TABLE.phase() == Phase.BETTING);
        t.rawset(
                "canClear",
                mine != null && TABLE.phase() == Phase.BETTING && !mine.bets().isEmpty());
        int winning = TABLE.winningNumber();
        t.rawset("winningNumber", (double) winning);
        if (winning >= 0) {
            t.rawset("winningColor", RouletteTable.colorOf(winning));
        }
        KahluaTable history = LuaManager.platform.newTable();
        int h = 0;
        for (int n : TABLE.history()) {
            history.rawset(++h, Double.valueOf(n));
        }
        t.rawset("history", history);

        KahluaTable seats = LuaManager.platform.newTable();
        int n = 0;
        for (Seat s : TABLE.seatedPlayers()) {
            KahluaTable st = LuaManager.platform.newTable();
            st.rawset("index", (double) (s.index() + 1));
            st.rawset("name", s.username());
            st.rawset("staked", (double) s.staked());
            st.rawset("payout", (double) s.payout());
            st.rawset("leaving", s.isLeaving());
            st.rawset("isYou", s.username().equalsIgnoreCase(me));
            KahluaTable bets = LuaManager.platform.newTable();
            int k = 0;
            for (Bet b : s.bets()) {
                KahluaTable bt = LuaManager.platform.newTable();
                bt.rawset("type", b.type().wire());
                bt.rawset("target", (double) b.target());
                bt.rawset("amount", (double) b.amount());
                bt.rawset("label", b.label());
                if (winning >= 0) {
                    bt.rawset("won", b.wins(winning));
                    bt.rawset("payout", (double) b.payout());
                }
                bets.rawset(++k, bt);
            }
            st.rawset("bets", bets);
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

    private static final class SandboxLimits implements RouletteTable.Limits {
        @Override
        public int minBet() {
            return AtfCasinoConfig.getMinBet();
        }

        @Override
        public int maxBet() {
            return AtfCasinoConfig.getMaxBet();
        }

        @Override
        public long betWindowMs() {
            return AtfCasinoConfig.getRouletteBetWindowSeconds() * 1_000L;
        }

        @Override
        public long spinMs() {
            return AtfCasinoConfig.getRouletteSpinSeconds() * 1_000L;
        }

        @Override
        public long settleMs() {
            return AtfCasinoConfig.getRoulettePauseSeconds() * 1_000L;
        }
    }

    /**
     * Stakes come out through the economy's player-bound deduct (atomic balance check); payouts go
     * in through the username+steamId grant so a player who walked off still gets paid.
     */
    private static final class EconomyBank implements RouletteTable.Bank {
        @Override
        public @Nullable String take(String username, long steamId, int amount, String reason) {
            IsoPlayer p = GameServer.getPlayerByUserNameForCommand(username);
            if (p == null) {
                return "PLAYER_OFFLINE";
            }
            AtfEconomyBridge.DeductResult r = AtfEconomyBridge.deduct(p, CURRENCY, amount, reason);
            if (!r.ok()) {
                LOGGER.info(
                        "[AtfCasino] {} could not stake {} {}: {}",
                        username,
                        amount,
                        CURRENCY,
                        r.reason());
                return r.reason() == null ? "ECONOMY_ERROR" : r.reason();
            }
            LOGGER.info("[AtfCasino] {} staked {} {} ({})", username, amount, CURRENCY, reason);
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
