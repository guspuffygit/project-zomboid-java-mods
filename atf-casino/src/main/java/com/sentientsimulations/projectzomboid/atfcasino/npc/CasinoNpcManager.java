package com.sentientsimulations.projectzomboid.atfcasino.npc;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import com.sentientsimulations.projectzomboid.atfcasino.AtfCasinoConfig;
import io.pzstorm.storm.event.core.SubscribeEvent;
import io.pzstorm.storm.event.lua.OnTickEvent;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import org.jetbrains.annotations.Nullable;
import se.krka.kahlua.vm.KahluaTable;
import zombie.Lua.LuaManager;
import zombie.characters.IsoPlayer;
import zombie.core.network.ByteBufferWriter;
import zombie.core.raknet.UdpConnection;
import zombie.inventory.InventoryItem;
import zombie.inventory.types.HandWeapon;
import zombie.network.GameServer;
import zombie.network.PacketTypes;
import zombie.network.chat.ChatServer;
import zombie.network.packets.sound.PlayWorldSoundPacket;

/**
 * Owns the casino's five Creepy Spiffos (two guards, the blackjack dealer, the roulette croupier,
 * the poker dealer) and drives them from the server main-thread tick: keeps them streamed to every
 * client that has the floor loaded, and runs the guards' rules — anyone on the casino floor who
 * pulls out a firearm, or who is there with god mode enabled, is shot dead on the spot, and so is
 * anyone who shoves or hits any of the five Spiffos (reported by {@link CasinoAssaultWatch}).
 *
 * <p>Positions and facings come from the {@code AtfCasino.<Npc>X/Y/Facing} + {@code FloorZ} sandbox
 * options (defaults in {@link CasinoLayout}) and are re-read every tick, so an admin can move and
 * turn the Spiffos live; the table anchors follow. Disabling {@code AtfCasino.Enabled} despawns all
 * five client-side.
 *
 * <p>Everything here runs inside {@link OnTickEvent} (server main thread, ~10 Hz), which is the
 * only place the kill path, chat and {@code sendServerCommand} are safe.
 */
public final class CasinoNpcManager {

    private static final String MODULE = "AtfCasino";
    private static final String SHOT_COMMAND = "guardShot";
    private static final String GUARD_WEAPON = "Base.AssaultRifle";
    private static final String SHOT_SOUND = "M16Shoot";
    private static final float SHOT_SOUND_RADIUS = 60.0F;
    private static final float FACE_SOUTH =
            CasinoLayout.facingRadians(CasinoLayout.FACING_SOUTH_INDEX);

    private static final long UPDATE_MS = 250L;
    private static final long REINTRO_MS = 4_000L;
    // Don't re-shoot the same player within this window even if the kill path left them alive:
    // one volley per offence.
    private static final long RESHOOT_MS = 10_000L;
    // A reported assault is only actionable this long; after that (attacker vanished, square never
    // materialised) it's dropped rather than executing someone long after the fact.
    private static final long ASSAULT_TTL_MS = 5_000L;

    private static final CasinoNpc[] NPCS = {
        new CasinoNpc(
                0,
                CasinoLayout.GUARD_NAME,
                CasinoLayout.GUARD_LEFT_X,
                CasinoLayout.GUARD_LEFT_Y,
                CasinoLayout.Z,
                FACE_SOUTH,
                GUARD_WEAPON),
        new CasinoNpc(
                1,
                CasinoLayout.GUARD_NAME,
                CasinoLayout.GUARD_RIGHT_X,
                CasinoLayout.GUARD_RIGHT_Y,
                CasinoLayout.Z,
                FACE_SOUTH,
                GUARD_WEAPON),
        new CasinoNpc(
                2,
                CasinoLayout.DEALER_NAME,
                CasinoLayout.DEALER_X,
                CasinoLayout.DEALER_Y,
                CasinoLayout.Z,
                FACE_SOUTH,
                null),
        new CasinoNpc(
                3,
                CasinoLayout.CROUPIER_NAME,
                CasinoLayout.CROUPIER_X,
                CasinoLayout.CROUPIER_Y,
                CasinoLayout.Z,
                FACE_SOUTH,
                null),
        new CasinoNpc(
                4,
                CasinoLayout.POKER_DEALER_NAME,
                CasinoLayout.POKER_DEALER_X,
                CasinoLayout.POKER_DEALER_Y,
                CasinoLayout.Z,
                FACE_SOUTH,
                null),
    };
    private static final CasinoNpc[] GUARDS = {NPCS[0], NPCS[1]};

    // Sandbox option prefixes (AtfCasino.<prefix>X / <prefix>Y) and default tiles, aligned
    // with NPCS.
    private static final String[] NPC_OPTION_PREFIXES = {
        "GuardLeft", "GuardRight", "Dealer", "Croupier", "PokerDealer"
    };
    private static final int[] NPC_DEFAULT_TILE_X = {
        CasinoLayout.GUARD_LEFT_X,
        CasinoLayout.GUARD_RIGHT_X,
        CasinoLayout.DEALER_X,
        CasinoLayout.CROUPIER_X,
        CasinoLayout.POKER_DEALER_X,
    };
    private static final int[] NPC_DEFAULT_TILE_Y = {
        CasinoLayout.GUARD_LEFT_Y,
        CasinoLayout.GUARD_RIGHT_Y,
        CasinoLayout.DEALER_Y,
        CasinoLayout.CROUPIER_Y,
        CasinoLayout.POKER_DEALER_Y,
    };

    private static final Map<String, Long> LAST_SHOT_BY_USER = new HashMap<>();
    private static long lastUpdateMs;
    private static long lastReintroMs;
    private static boolean wasVisible;

    private CasinoNpcManager() {}

    /** The blackjack dealer. */
    public static CasinoNpc dealer() {
        return NPCS[2];
    }

    /** The roulette croupier. */
    public static CasinoNpc croupier() {
        return NPCS[3];
    }

    /** The Texas Hold'em dealer. */
    public static CasinoNpc pokerDealer() {
        return NPCS[4];
    }

    /** Whether an online id belongs to one of the casino NPCs. */
    public static boolean isNpcId(short id) {
        for (CasinoNpc npc : NPCS) {
            if (npc.id() == id) {
                return true;
            }
        }
        return false;
    }

    @SubscribeEvent
    public static void onTick(OnTickEvent event) {
        if (!GameServer.server) {
            return;
        }
        try {
            tick(System.currentTimeMillis());
        } catch (Throwable t) {
            LOGGER.warn("[AtfCasino] NPC tick failed: {}", t.toString(), t);
        }
    }

    private static void tick(long now) {
        boolean enabled = AtfCasinoConfig.isEnabled();
        List<UdpConnection> conns = connections();
        if (!enabled) {
            if (wasVisible) {
                for (CasinoNpc npc : NPCS) {
                    for (UdpConnection c : conns) {
                        npc.sendTimeout(c);
                    }
                }
                wasVisible = false;
            }
            CasinoAssaultWatch.clear();
            return;
        }
        wasVisible = true;
        applyLayoutOptions();
        for (CasinoNpc npc : NPCS) {
            if (!npc.build()) {
                return;
            }
        }
        drainAssaults(now);
        if (now - lastUpdateMs < UPDATE_MS) {
            return;
        }
        lastUpdateMs = now;
        boolean reintro = now - lastReintroMs >= REINTRO_MS;
        if (reintro) {
            lastReintroMs = now;
        }
        for (UdpConnection c : conns) {
            if (c == null || !c.isFullyConnected()) {
                continue;
            }
            for (CasinoNpc npc : NPCS) {
                if (!c.isRelevantTo(npc.x(), npc.y())) {
                    continue;
                }
                if (reintro) {
                    npc.introduce(c);
                }
                npc.sendUpdate(c);
            }
            watchFloor(c, now);
        }
    }

    private static void applyLayoutOptions() {
        int z = AtfCasinoConfig.getFloorZ(CasinoLayout.Z);
        for (int i = 0; i < NPCS.length; i++) {
            NPCS[i].moveTo(
                    AtfCasinoConfig.getNpcTileX(NPC_OPTION_PREFIXES[i], NPC_DEFAULT_TILE_X[i]),
                    AtfCasinoConfig.getNpcTileY(NPC_OPTION_PREFIXES[i], NPC_DEFAULT_TILE_Y[i]),
                    z);
            NPCS[i].faceTo(
                    CasinoLayout.facingRadians(
                            AtfCasinoConfig.getNpcFacingIndex(
                                    NPC_OPTION_PREFIXES[i], CasinoLayout.FACING_SOUTH_INDEX)));
        }
    }

    // --- guards ---

    private static void drainAssaults(long now) {
        List<CasinoAssaultWatch.Assault> retry = null;
        for (CasinoAssaultWatch.Assault a = CasinoAssaultWatch.poll();
                a != null;
                a = CasinoAssaultWatch.poll()) {
            if (now - a.atMs > ASSAULT_TTL_MS || !a.connection.isFullyConnected()) {
                continue;
            }
            IsoPlayer p = playerOnConnection(a.connection, a.attackerOnlineId);
            if (p == null || p.isDead() || !p.isAlive()) {
                continue;
            }
            if (p.getCurrentSquare() == null) {
                // Same teleport guard as watchFloor: die() NPEs on a null square. Retry until
                // the square exists or the TTL runs out.
                if (retry == null) {
                    retry = new ArrayList<>();
                }
                retry.add(a);
                continue;
            }
            Long last = LAST_SHOT_BY_USER.get(p.getUsername());
            if (last != null && now - last < RESHOOT_MS) {
                continue;
            }
            LAST_SHOT_BY_USER.put(p.getUsername(), now);
            shoot(p, a.connection, ShotReason.ASSAULT);
        }
        if (retry != null) {
            for (CasinoAssaultWatch.Assault a : retry) {
                CasinoAssaultWatch.requeue(a);
            }
        }
    }

    private static @Nullable IsoPlayer playerOnConnection(UdpConnection c, short onlineId) {
        for (int i = 0; i < 4; i++) {
            IsoPlayer p = c.getPlayerAt(i);
            if (p != null && p.getOnlineID() == onlineId) {
                return p;
            }
        }
        return null;
    }

    private static void watchFloor(UdpConnection c, long now) {
        for (int i = 0; i < 4; i++) {
            IsoPlayer p = c.getPlayerAt(i);
            if (p == null || p.isDead() || !p.isAlive()) {
                continue;
            }
            // Right after a teleport the server knows the new position before the square/chunk
            // exists; die() -> becomeCorpse NPEs on a null square, so wait until they're standing.
            if (p.getCurrentSquare() == null || !onCasinoFloor(p)) {
                continue;
            }
            ShotReason reason;
            if (p.isGodMod()) {
                reason = ShotReason.GOD_MODE;
            } else if (isHoldingFirearm(p)) {
                reason = ShotReason.FIREARM;
            } else {
                continue;
            }
            Long last = LAST_SHOT_BY_USER.get(p.getUsername());
            if (last != null && now - last < RESHOOT_MS) {
                continue;
            }
            LAST_SHOT_BY_USER.put(p.getUsername(), now);
            shoot(p, c, reason);
        }
    }

    /** Why the guards opened fire; {@code wire} is what the client's halo text keys on. */
    private enum ShotReason {
        FIREARM(
                "firearm",
                "drew a firearm",
                "%s was gunned down by the Creepy Spiffos for drawing a weapon in the casino"),
        // Kill()+die() bypasses god mode, so this is a hard eviction, not a warning shot:
        // god-mode admins are not welcome on the casino floor at all.
        GOD_MODE(
                "godmode",
                "has god mode enabled",
                "%s was gunned down by the Creepy Spiffos. There are no gods in the casino"),
        ASSAULT(
                "assault",
                "attacked casino staff",
                "%s was gunned down by the Creepy Spiffos for laying hands on the staff");

        final String wire;
        final String logVerb;
        final String announceFormat;

        ShotReason(String wire, String logVerb, String announceFormat) {
            this.wire = wire;
            this.logVerb = logVerb;
            this.announceFormat = announceFormat;
        }

        String announcement(String username) {
            return String.format(announceFormat, username);
        }
    }

    private static boolean onCasinoFloor(IsoPlayer p) {
        for (CasinoNpc guard : GUARDS) {
            if (guard.distanceTo(p.getX(), p.getY(), p.getZ()) <= CasinoLayout.GUARD_WATCH_RADIUS) {
                return true;
            }
        }
        return false;
    }

    private static boolean isHoldingFirearm(IsoPlayer p) {
        return isFirearm(p.getPrimaryHandItem()) || isFirearm(p.getSecondaryHandItem());
    }

    private static boolean isFirearm(InventoryItem item) {
        return item instanceof HandWeapon hw && HandWeapon.isAimedFirearm(hw);
    }

    private static void shoot(IsoPlayer victim, UdpConnection victimConn, ShotReason reason) {
        String username = victim.getUsername();
        LOGGER.info(
                "[AtfCasino] {} {} on the casino floor at {},{},{} — guards open fire",
                username,
                reason.logVerb,
                victim.getX(),
                victim.getY(),
                victim.getZ());
        for (CasinoNpc guard : GUARDS) {
            playShot(guard);
        }
        KahluaTable args = LuaManager.platform.newTable();
        args.rawset("x", (double) GUARDS[0].x());
        args.rawset("y", (double) GUARDS[0].y());
        args.rawset("z", (double) GUARDS[0].z());
        args.rawset("reason", reason.wire);
        GameServer.sendServerCommand(MODULE, SHOT_COMMAND, args, victimConn);
        // Same kill path the obelisk smite uses: B42 health is server-authoritative, and
        // Kill+die persists the death and broadcasts PlayerDeath to every relevant client.
        // Live-verified 2026-08-21: this kills through god mode too.
        try {
            victim.Kill(null);
            victim.die();
        } catch (Throwable t) {
            LOGGER.error("[AtfCasino] kill path failed for {}", username, t);
        }
        if (!victim.isDead()) {
            LOGGER.warn("[AtfCasino] {} survived the guards", username);
            return;
        }
        announce(reason.announcement(username));
    }

    private static void playShot(CasinoNpc guard) {
        PlayWorldSoundPacket packet = new PlayWorldSoundPacket();
        packet.set(SHOT_SOUND, (int) guard.x(), (int) guard.y(), (byte) guard.z(), -1);
        for (UdpConnection c : connections()) {
            if (c == null
                    || !c.isFullyConnected()
                    || !c.RelevantTo(guard.x(), guard.y(), SHOT_SOUND_RADIUS)) {
                continue;
            }
            try {
                ByteBufferWriter b = c.startPacket();
                try {
                    PacketTypes.PacketType.PlayWorldSound.doPacket(b);
                    packet.write(b);
                    PacketTypes.PacketType.PlayWorldSound.send(c);
                } catch (Throwable inner) {
                    c.cancelPacket();
                    throw inner;
                }
            } catch (Throwable t) {
                LOGGER.warn("[AtfCasino] gunshot sound send failed: {}", t.getMessage());
            }
        }
    }

    private static void announce(String message) {
        try {
            if (ChatServer.isInited()) {
                ChatServer.getInstance().sendMessageToServerChat(message);
            }
        } catch (Throwable t) {
            LOGGER.warn("[AtfCasino] chat announce failed: {}", t.toString());
        }
    }

    private static List<UdpConnection> connections() {
        if (GameServer.udpEngine == null) {
            return List.of();
        }
        return new ArrayList<>(GameServer.udpEngine.connections);
    }
}
