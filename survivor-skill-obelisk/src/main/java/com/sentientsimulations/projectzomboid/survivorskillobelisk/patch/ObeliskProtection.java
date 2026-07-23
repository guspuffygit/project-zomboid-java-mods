package com.sentientsimulations.projectzomboid.survivorskillobelisk.patch;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import com.sentientsimulations.projectzomboid.survivorskillobelisk.ObeliskCurseHandler;
import com.sentientsimulations.projectzomboid.survivorskillobelisk.SurvivorSkillObeliskConfig;
import java.lang.reflect.Field;
import zombie.characters.Capability;
import zombie.characters.Role;
import zombie.core.raknet.UdpConnection;
import zombie.iso.IsoGridSquare;
import zombie.iso.IsoObject;
import zombie.iso.IsoWorld;
import zombie.iso.sprite.IsoSprite;
import zombie.network.PacketTypes;
import zombie.network.packets.INetworkPacket;
import zombie.network.packets.RemoveItemFromSquarePacket;
import zombie.network.packets.SledgehammerDestroyPacket;

/**
 * Server-side policy for obelisk indestructibility. Obelisks may only leave the world through an
 * admin holding {@link Capability#UseBrushToolManager} (the brush-tool "Destroy tile" option); the
 * vanilla server removes any object a client asks it to, so the packet patches consult this class
 * before {@code processServer} runs.
 *
 * <p>All members referenced from advice bodies are {@code public} — Byte Buddy inlines advice into
 * the {@code zombie.*} target classes, and the JVM checks field/method visibility at the inlined
 * access site. Parameters arriving from advice are typed {@link Object} and cast explicitly so the
 * patch classes never force an early load of a packet class at registration time.
 */
public final class ObeliskProtection {

    public static final String SPRITE_PREFIX = "atf_obelisks_";

    /** {@code RemoveItemFromSquarePacket.z} is package-private. */
    public static final Field REMOVE_PACKET_Z_FIELD =
            resolveField(RemoveItemFromSquarePacket.class, "z");

    /** {@code SledgehammerDestroyPacket.packet} is package-private. */
    public static final Field SLEDGE_INNER_PACKET_FIELD =
            resolveField(SledgehammerDestroyPacket.class, "packet");

    private ObeliskProtection() {}

    /**
     * Entry check for {@code RemoveItemFromSquarePacket.processServer}. Covers direct removal
     * packets (moveable pickup, scrap/disassemble, modified clients) and — because the sledgehammer
     * packet delegates here — the second half of the sledgehammer flow.
     */
    public static boolean shouldBlockRemoval(Object packetObj, Object connectionObj) {
        return shouldBlockRemoval(packetObj, connectionObj, false);
    }

    private static boolean shouldBlockRemoval(
            Object packetObj, Object connectionObj, boolean sledgehammer) {
        try {
            RemoveItemFromSquarePacket packet = (RemoveItemFromSquarePacket) packetObj;
            if (REMOVE_PACKET_Z_FIELD == null) {
                return false;
            }
            int z = REMOVE_PACKET_Z_FIELD.getByte(packet);
            return shouldBlock(packet.x, packet.y, z, packet.index, connectionObj, sledgehammer);
        } catch (Throwable t) {
            LOGGER.error("[SurvivorSkillObelisk] obelisk removal guard failed; allowing", t);
            return false;
        }
    }

    /**
     * Entry check for {@code SledgehammerDestroyPacket.processServer}. Blocking here (rather than
     * relying only on the inner {@code RemoveItemFromSquarePacket} check) also suppresses the
     * packet's own rebroadcast loop, which would otherwise tell every nearby client to remove the
     * obelisk even though the server kept it.
     */
    public static boolean shouldBlockSledgehammer(Object packetObj, Object connectionObj) {
        try {
            if (SLEDGE_INNER_PACKET_FIELD == null) {
                return false;
            }
            Object inner = SLEDGE_INNER_PACKET_FIELD.get(packetObj);
            return shouldBlockRemoval(inner, connectionObj, true);
        } catch (Throwable t) {
            LOGGER.error("[SurvivorSkillObelisk] obelisk sledgehammer guard failed; allowing", t);
            return false;
        }
    }

    /**
     * Exit check for {@code IsoThumpable.getThumpableFor}: obelisks are never a thump target, so
     * zombies path around them instead of eating them and player weapon hits no-op server-side.
     */
    public static boolean isProtectedObject(Object objectObj) {
        try {
            if (!(objectObj instanceof IsoObject)) {
                return false;
            }
            IsoSprite sprite = ((IsoObject) objectObj).getSprite();
            return sprite != null && isProtectedSpriteName(sprite.getName());
        } catch (Throwable t) {
            LOGGER.error("[SurvivorSkillObelisk] obelisk sprite guard failed; allowing", t);
            return false;
        }
    }

    public static boolean isProtectedSpriteName(String name) {
        return name != null && name.startsWith(SPRITE_PREFIX);
    }

    private static boolean shouldBlock(
            int x, int y, int z, int index, Object connectionObj, boolean sledgehammer) {
        IsoWorld world = IsoWorld.instance;
        if (world == null || world.currentCell == null) {
            return false;
        }
        IsoGridSquare sq = world.currentCell.getGridSquare(x, y, z);
        if (sq == null || index < 0 || index >= sq.getObjects().size()) {
            return false;
        }
        IsoObject target = sq.getObjects().get(index);
        if (!isProtectedObject(target)) {
            return false;
        }
        UdpConnection connection = (UdpConnection) connectionObj;
        if (connection == null) {
            // Server-internal removal (no originating client); trust it.
            return false;
        }
        Role role = connection.getRole();
        if (role != null && role.hasCapability(Capability.UseBrushToolManager)) {
            LOGGER.info(
                    "[SurvivorSkillObelisk] Allowing obelisk removal by brush-tool admin"
                            + " \"{}\" at ({}, {}, {})",
                    connection.getUserName(),
                    x,
                    y,
                    z);
            return false;
        }
        LOGGER.warn(
                "[SurvivorSkillObelisk] Blocked obelisk destruction by \"{}\" at ({}, {}, {})",
                connection.getUserName(),
                x,
                y,
                z);
        // The initiating client already removed the object locally; send it back so the
        // obelisk doesn't linger as a client-side ghost until the chunk reloads.
        INetworkPacket.send(connection, PacketTypes.PacketType.AddItemToMap, target);
        if (sledgehammer && SurvivorSkillObeliskConfig.isCurseOnSledgehammer()) {
            ObeliskCurseHandler.enqueueCurse(connection, x, y, z);
        }
        return true;
    }

    private static Field resolveField(Class<?> owner, String name) {
        try {
            Field field = owner.getDeclaredField(name);
            field.setAccessible(true);
            return field;
        } catch (Throwable t) {
            LOGGER.error(
                    "[SurvivorSkillObelisk] Failed to resolve {}.{}; obelisk destruction"
                            + " guard is DISABLED",
                    owner.getName(),
                    name,
                    t);
            return null;
        }
    }
}
