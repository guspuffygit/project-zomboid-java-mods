package com.sentientsimulations.projectzomboid.jumpscareban;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;
import zombie.characters.IsoPlayer;
import zombie.core.raknet.UdpConnection;
import zombie.network.GameServer;

/**
 * Server-side helper invoked from {@link BanSystemPatch}. Sends the jumpscare server command to the
 * banned client and schedules the actual disconnect ~3 seconds later so the client has time to
 * render the full animation (~2.3s at 60 ticks/sec).
 *
 * <p>Kept out of the advice class so the advice body stays trivial — Byte Buddy advice is inlined
 * into the target method, so all real work lives here in a normal class call.
 */
public final class JumpscareBanService {

    private static final String BAN_DESCRIPTION = "command-banid";
    private static final String COMMAND_MODULE = "JumpscareBan";
    private static final String COMMAND_NAME = "trigger";
    private static final long KICK_DELAY_MS = 1500L;

    private static final ScheduledExecutorService SCHEDULER =
            Executors.newSingleThreadScheduledExecutor(
                    r -> {
                        Thread t = new Thread(r, "jumpscare-ban-delayed-kick");
                        t.setDaemon(true);
                        return t;
                    });

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

        try {
            GameServer.sendServerCommand(player, COMMAND_MODULE, COMMAND_NAME, null);
        } catch (Throwable t) {
            LOGGER.warn("JumpscareBan: failed to send jumpscare command to \"{}\"", username, t);
            return false;
        }

        SCHEDULER.schedule(
                new DelayedKick(connection, username), KICK_DELAY_MS, TimeUnit.MILLISECONDS);
        return true;
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
            try {
                GameServer.kick(connection, "You were banned", null);
                connection.forceDisconnect(BAN_DESCRIPTION);
                LOGGER.info("JumpscareBan: delayed kick fired for \"{}\"", username);
            } catch (Throwable t) {
                LOGGER.error("JumpscareBan: delayed kick failed for \"{}\"", username, t);
            }
        }
    }
}
