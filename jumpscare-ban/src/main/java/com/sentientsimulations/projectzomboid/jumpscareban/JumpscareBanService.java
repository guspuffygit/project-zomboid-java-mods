package com.sentientsimulations.projectzomboid.jumpscareban;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import java.util.Iterator;
import java.util.concurrent.ConcurrentLinkedQueue;
import zombie.characters.IsoPlayer;
import zombie.core.raknet.UdpConnection;
import zombie.network.GameServer;
import zombie.network.chat.ChatServer;

/**
 * Server-side helper invoked from {@link BanSystemPatch}. Sends the jumpscare server command to the
 * banned client and defers the actual disconnect ~1.5 seconds so the client has time to render the
 * full animation, then broadcasts the follow-up sound cues.
 *
 * <p>Kept out of the advice class so the advice body stays trivial — Byte Buddy advice is inlined
 * into the target method, so all real work lives here in a normal class call.
 *
 * <p><b>Everything here runs on the server main loop.</b> Deferred work is parked in {@link
 * #PENDING} and executed by {@link #drainDueTasks()}, which {@link ServerMainLoopPatch} pumps once
 * per server frame step. Chat and {@link UdpConnection} writes are not safe off the main thread:
 * {@code ChatBase} takes its {@code memberLock} monitor and then the target connection's {@code
 * bufferLock}, while {@code GameServer.disconnect} takes those two in the opposite order, so a
 * background thread broadcasting chat deadlocks the whole server against a concurrent disconnect.
 * That is not hypothetical — it froze production with 62 players online.
 *
 * <p>Every path that reaches {@code BanSystem.KickUser} already runs on the main loop — the server
 * console only enqueues into {@code GameServer.consoleCommands}, RCON marshals through {@code
 * RCONServer.toMain} drained at {@code GameServer.main:996}, and the admin-UI packet, the in-game
 * admin chat command and {@code AntiCheat} all arrive via {@code mainLoopDealWithNetData}. The
 * executor this class used to own was the only off-main actor. The initial jumpscare command is
 * queued anyway so that the rule here is uniform and cheap to audit: nothing in this class touches
 * chat or a connection outside {@link #drainDueTasks()}.
 */
public final class JumpscareBanService {

    private static final String BAN_DESCRIPTION = "command-banid";
    private static final String COMMAND_MODULE = "JumpscareBan";
    private static final String COMMAND_NAME = "trigger";
    private static final String KACHOW_COMMAND_NAME = "playKachow";
    private static final String THUNDER_COMMAND_NAME = "playThunder";
    private static final long KICK_DELAY_MS = 1500L;
    private static final long THUNDER_DELAY_MS = KICK_DELAY_MS + 3000L;

    private static final ConcurrentLinkedQueue<PendingTask> PENDING = new ConcurrentLinkedQueue<>();

    private JumpscareBanService() {}

    /**
     * Returns {@code true} if the kick was deferred (and the original {@code KickUser} body should
     * be skipped). Returns {@code false} if this is not a ban-initiated kick or the player can't be
     * found, in which case the original method runs as normal.
     */
    public static boolean tryScheduleJumpscareKick(String username, String description) {
        if (!BAN_DESCRIPTION.equals(description)) {
            return false;
        }
        IsoPlayer player = GameServer.getPlayerByUserName(username);
        if (player == null) {
            return false;
        }
        UdpConnection connection = GameServer.getConnectionFromPlayer(player);
        if (connection == null) {
            return false;
        }

        LOGGER.info(
                "JumpscareBan: triggering jumpscare for banned user \"{}\", kick delayed {}ms",
                username,
                KICK_DELAY_MS);

        long now = System.currentTimeMillis();
        PENDING.add(new PendingTask(now, new Jumpscare(player, username)));
        PENDING.add(new PendingTask(now + KICK_DELAY_MS, new DelayedKick(connection, username)));
        PENDING.add(new PendingTask(now + THUNDER_DELAY_MS, new DelayedThunder()));
        return true;
    }

    /**
     * Runs every task whose delay has elapsed. Must only be called from the server main loop — see
     * {@link ServerMainLoopPatch}.
     */
    public static void drainDueTasks() {
        if (PENDING.isEmpty()) {
            return;
        }
        long now = System.currentTimeMillis();
        for (Iterator<PendingTask> it = PENDING.iterator(); it.hasNext(); ) {
            PendingTask task = it.next();
            if (task.dueAtMs > now) {
                continue;
            }
            it.remove();
            try {
                task.action.run();
            } catch (Throwable t) {
                LOGGER.error("JumpscareBan: deferred task failed", t);
            }
        }
    }

    /**
     * The ban itself is already durable before any of this runs — {@code BanSystem.BanUser} calls
     * {@code ServerWorldDatabase.banUser} and only then calls {@code KickUser}, which is all this
     * mod intercepts. {@code GameServer.kick} just logs and sends a {@code Kicked} packet, so
     * declining to kick a connection that has already gone away costs nothing but a dead packet.
     * {@code UdpConnection}s are never pooled and the list is mutated only from the main loop, so
     * this identity check can never match a different player.
     */
    private static boolean isStillConnected(UdpConnection connection) {
        return GameServer.udpEngine != null
                && GameServer.udpEngine.connections.contains(connection);
    }

    private static final class PendingTask {
        final long dueAtMs;
        final Runnable action;

        PendingTask(long dueAtMs, Runnable action) {
            this.dueAtMs = dueAtMs;
            this.action = action;
        }
    }

    private static final class Jumpscare implements Runnable {
        private final IsoPlayer player;
        private final String username;

        Jumpscare(IsoPlayer player, String username) {
            this.player = player;
            this.username = username;
        }

        @Override
        public void run() {
            try {
                GameServer.sendServerCommand(player, COMMAND_MODULE, COMMAND_NAME, null);
            } catch (Throwable t) {
                LOGGER.warn(
                        "JumpscareBan: failed to send jumpscare command to \"{}\"", username, t);
            }
        }
    }

    private static final class DelayedKick implements Runnable {
        private final UdpConnection connection;
        private final String username;

        DelayedKick(UdpConnection connection, String username) {
            this.connection = connection;
            this.username = username;
        }

        @Override
        public void run() {
            if (!isStillConnected(connection)) {
                LOGGER.info(
                        "JumpscareBan: \"{}\" already disconnected, no kick packet needed (ban"
                                + " itself was already persisted by BanSystem.BanUser)",
                        username);
            } else {
                try {
                    GameServer.kick(connection, "You were banned", null);
                    connection.forceDisconnect(BAN_DESCRIPTION);
                    LOGGER.info("JumpscareBan: delayed kick fired for \"{}\"", username);
                } catch (Throwable t) {
                    LOGGER.error("JumpscareBan: delayed kick failed for \"{}\"", username, t);
                }
            }

            try {
                ChatServer.getInstance().sendServerAlertMessageToServerChat("Kachow");
                GameServer.sendServerCommand(COMMAND_MODULE, KACHOW_COMMAND_NAME, null);
            } catch (Throwable t) {
                LOGGER.warn("JumpscareBan: failed to broadcast kachow command", t);
            }
        }
    }

    private static final class DelayedThunder implements Runnable {
        @Override
        public void run() {
            try {
                ChatServer.getInstance().sendServerAlertMessageToServerChat("THUNDER");
                GameServer.sendServerCommand(COMMAND_MODULE, THUNDER_COMMAND_NAME, null);
            } catch (Throwable t) {
                LOGGER.warn("JumpscareBan: failed to broadcast thunder command", t);
            }
        }
    }
}
