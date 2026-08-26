package com.sentientsimulations.projectzomboid.atfcasino.npc;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import com.sentientsimulations.projectzomboid.atfcasino.AtfCasinoConfig;
import java.lang.reflect.Field;
import java.util.Queue;
import java.util.concurrent.ConcurrentLinkedQueue;
import org.jetbrains.annotations.Nullable;
import zombie.characters.IsoPlayer;
import zombie.core.raknet.UdpConnection;
import zombie.network.GameServer;
import zombie.network.IConnection;
import zombie.network.fields.hit.Player;
import zombie.network.packets.hit.PlayerHit;
import zombie.network.packets.hit.PlayerHitPlayerPacket;

/**
 * Collects melee/shove/gunshot attacks on the casino NPCs so the guards can retaliate.
 *
 * <p>The NPCs are synthetic players that are never registered in {@link GameServer#IDToPlayerMap},
 * so when a client hits one, the vanilla server drops the {@link PlayerHitPlayerPacket} at {@code
 * isConsistent} (target unresolvable) and {@code processServer} never runs — which is why this
 * hooks {@code parse} (via {@code PlayerHitPlayerPacketParsePatch}) instead of Storm's packet
 * events. The attack still does nothing to the NPC; this only records who swung.
 *
 * <p>{@link #onHitParsed} runs on whatever thread drains the net-data queue; the queue is drained
 * and acted on from {@link CasinoNpcManager}'s tick on the server main thread.
 */
public final class CasinoAssaultWatch {

    /** One reported attack on a casino NPC, pending guard retaliation. */
    static final class Assault {
        final UdpConnection connection;
        final short attackerOnlineId;
        final long atMs;

        Assault(UdpConnection connection, short attackerOnlineId, long atMs) {
            this.connection = connection;
            this.attackerOnlineId = attackerOnlineId;
            this.atMs = atMs;
        }
    }

    /** Backstop against a hit-packet flood; the queue is drained every tick. */
    private static final int MAX_PENDING = 32;

    private static final Queue<Assault> PENDING = new ConcurrentLinkedQueue<>();

    private static volatile @Nullable Field wielderField;

    private CasinoAssaultWatch() {}

    /**
     * Called from the parse-exit advice on {@link PlayerHitPlayerPacket}. Queues an assault when
     * the packet targets a casino NPC and the claimed wielder actually belongs to the sending
     * connection (the wielder id in the packet is client-supplied and spoofable). Never throws.
     */
    public static void onHitParsed(PlayerHitPlayerPacket packet, IConnection connection) {
        try {
            if (!GameServer.server) {
                return;
            }
            if (!CasinoNpcManager.isNpcId(packet.target.getID())) {
                return;
            }
            if (!AtfCasinoConfig.isEnabled() || !(connection instanceof UdpConnection udp)) {
                return;
            }
            IsoPlayer attacker = ownedWielder(packet, udp);
            if (attacker == null || attacker.getUsername() == null) {
                return;
            }
            if (PENDING.size() >= MAX_PENDING) {
                return;
            }
            PENDING.add(new Assault(udp, attacker.getOnlineID(), System.currentTimeMillis()));
        } catch (Throwable t) {
            LOGGER.warn("[AtfCasino] assault watch failed: {}", t.toString());
        }
    }

    static @Nullable Assault poll() {
        return PENDING.poll();
    }

    static void requeue(Assault assault) {
        PENDING.add(assault);
    }

    static void clear() {
        PENDING.clear();
    }

    private static @Nullable IsoPlayer ownedWielder(PlayerHitPlayerPacket packet, UdpConnection udp)
            throws ReflectiveOperationException {
        Player wielder = (Player) wielderFieldHandle().get(packet);
        IsoPlayer claimed = wielder == null ? null : wielder.getPlayer();
        if (claimed == null) {
            return null;
        }
        for (int i = 0; i < 4; i++) {
            if (udp.getPlayerAt(i) == claimed) {
                return claimed;
            }
        }
        return null;
    }

    private static Field wielderFieldHandle() throws ReflectiveOperationException {
        Field f = wielderField;
        if (f == null) {
            f = PlayerHit.class.getDeclaredField("wielder");
            f.setAccessible(true);
            wielderField = f;
        }
        return f;
    }
}
