package com.sentientsimulations.projectzomboid.survivorskillobelisk;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import io.pzstorm.storm.event.core.SubscribeEvent;
import io.pzstorm.storm.event.lua.OnTickEvent;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentLinkedQueue;
import se.krka.kahlua.vm.KahluaTable;
import zombie.Lua.LuaManager;
import zombie.characters.IsoGameCharacter;
import zombie.characters.IsoPlayer;
import zombie.core.raknet.UdpConnection;
import zombie.network.GameServer;
import zombie.network.chat.ChatServer;

/**
 * Delivers the obelisk curse: when a non-admin tries to sledgehammer an obelisk, the action guard
 * ({@link SurvivorSkillObeliskApi}, primary B42 path) or the packet guard ({@code
 * patch.ObeliskProtection}, legacy/forged-packet path) enqueues their connection here, and the next
 * tick kills the character <em>server-side</em>.
 *
 * <p>The kill must happen here, not on the client. B42 player health is server-authoritative (the
 * server pushes {@code PlayerHealth}/{@code PlayerDamage}/{@code PlayerInjuries} to the owner), and
 * the persisted {@code networkPlayers.isDead} flag is written from the server's {@code IsoPlayer}.
 * A client-only {@code IsoPlayer:Kill} showed the death screen but left the server character alive,
 * so "create new character" hung on a black screen and rejoining restored the old character. {@link
 * IsoGameCharacter#Kill} runs {@code DoDeath} (vanilla death log, "is dead" announcement, {@code
 * OnCharacterDeath} — including this mod's own death snapshot) and {@code die()} builds the corpse,
 * persists the dead flag via {@code removeSaveFile}, and broadcasts {@code PlayerDeath} so the
 * owning client plays out the death locally.
 *
 * <p>The client command that remains is flavor only: it plays the obelisk sound on the attacker's
 * machine.
 *
 * <p>Queued rather than run inline because packet {@code processServer} runs off the main thread
 * and neither {@code sendServerCommand} nor the death path is thread-safe (same split as {@link
 * ObeliskLifecycleHandler}).
 */
public final class ObeliskCurseHandler {

    private static final String MODULE = "SurvivorSkillObelisk";
    private static final String CURSE_COMMAND = "obeliskCurse";

    private record PendingCurse(UdpConnection connection, IsoPlayer player, int x, int y, int z) {}

    private static final ConcurrentLinkedQueue<PendingCurse> PENDING =
            new ConcurrentLinkedQueue<>();

    /**
     * One destroy attempt can reach the guard twice — the server-side action guard blocks the
     * synced timed action, and the client's own {@code complete()} additionally sends the legacy
     * {@code SledgehammerDestroy} packet that the packet guard blocks. Both enqueue; without a
     * window one swing would kill once but announce the smite twice.
     */
    private static final long DEDUPE_WINDOW_MILLIS = 3000L;

    private static final ConcurrentHashMap<String, Long> LAST_CURSE_BY_USERNAME =
            new ConcurrentHashMap<>();

    private ObeliskCurseHandler() {}

    /** Called from the packet guard (packet thread), which has no character to hand us. */
    public static void enqueueCurse(Object connectionObj, int x, int y, int z) {
        enqueueCurse(connectionObj, null, x, y, z);
    }

    /** Called from the Lua action guard (main thread), which knows the acting character. */
    public static void enqueueCurse(Object connectionObj, Object playerObj, int x, int y, int z) {
        if (!(connectionObj instanceof UdpConnection)) {
            return;
        }
        UdpConnection connection = (UdpConnection) connectionObj;
        String username = connection.getUserName();
        if (username != null) {
            long now = System.currentTimeMillis();
            Long last = LAST_CURSE_BY_USERNAME.put(username, now);
            if (last != null && now - last < DEDUPE_WINDOW_MILLIS) {
                return;
            }
        }
        IsoPlayer player = playerObj instanceof IsoPlayer ? (IsoPlayer) playerObj : null;
        PENDING.offer(new PendingCurse(connection, player, x, y, z));
    }

    @SubscribeEvent
    public static void onTick(OnTickEvent event) {
        PendingCurse curse;
        while ((curse = PENDING.poll()) != null) {
            deliver(curse);
        }
    }

    private static void deliver(PendingCurse curse) {
        try {
            UdpConnection connection = curse.connection();
            if (!connection.isFullyConnected()) {
                return;
            }
            IsoPlayer player = curse.player();
            if (player == null) {
                player = GameServer.getAnyPlayerFromConnection(connection);
            }
            if (player == null || player.isDead()) {
                return;
            }
            KahluaTable args = LuaManager.platform.newTable();
            args.rawset("x", (double) curse.x());
            args.rawset("y", (double) curse.y());
            args.rawset("z", (double) curse.z());
            GameServer.sendServerCommand(MODULE, CURSE_COMMAND, args, connection);
            player.Kill(null);
            player.die();
            announceSmite(connection.getUserName());
            LOGGER.info(
                    "[SurvivorSkillObelisk] Cursed \"{}\" for sledgehammering the obelisk"
                            + " at ({}, {}, {})",
                    connection.getUserName(),
                    curse.x(),
                    curse.y(),
                    curse.z());
        } catch (Throwable t) {
            LOGGER.error(
                    "[SurvivorSkillObelisk] Failed to deliver obelisk curse at ({}, {}, {})",
                    curse.x(),
                    curse.y(),
                    curse.z(),
                    t);
        }
    }

    /**
     * Server-chat broadcast, same idiom as vanilla {@code PVPLogTool.logKill} death announcements.
     * Must only run on the main thread — {@code ChatBase.memberLock} vs {@code
     * UdpConnection.bufferLock} invert when chat is touched from packet threads.
     */
    private static void announceSmite(String username) {
        try {
            if (!ChatServer.isInited()) {
                return;
            }
            ChatServer.getInstance()
                    .sendMessageToServerChat(username + " has been smited by the mighty Obelisk");
        } catch (Throwable t) {
            LOGGER.error("[SurvivorSkillObelisk] Failed to announce smite of \"{}\"", username, t);
        }
    }
}
