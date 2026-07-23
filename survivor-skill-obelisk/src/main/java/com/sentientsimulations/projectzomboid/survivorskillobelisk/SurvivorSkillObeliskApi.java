package com.sentientsimulations.projectzomboid.survivorskillobelisk;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import se.krka.kahlua.integration.annotations.LuaMethod;
import zombie.characters.Capability;
import zombie.characters.IsoPlayer;
import zombie.characters.Role;
import zombie.core.raknet.UdpConnection;
import zombie.iso.IsoObject;
import zombie.network.GameServer;
import zombie.network.PacketTypes;
import zombie.network.packets.INetworkPacket;

/**
 * Server-Lua-callable half of obelisk indestructibility. In B42 the sledgehammer "Destroy" and
 * furniture pickup/disassemble are synced timed actions: the server reconstructs the Lua action
 * ({@code NetTimedAction}) and runs its {@code complete()} on the main loop, which removes the
 * object through direct Java calls — no removal packet is ever processed, so the packet patches in
 * {@code patch.ObeliskProtection} never see the primary player flow. The overrides in {@code
 * media/lua/server/SurvivorSkillObeliskDestroyGuard.lua} intercept those actions and consult this
 * class, which applies the same role policy as the packet guard.
 *
 * <p>Exposed to the server Lua VM by {@link SurvivorSkillObeliskApiLuaExposerHandler}. All methods
 * run on the main thread (Lua action {@code complete()} executes on the server main loop), so
 * targeted packet sends are safe here.
 */
public final class SurvivorSkillObeliskApi {

    private SurvivorSkillObeliskApi() {}

    /**
     * Mirrors the packet guard's policy: only a role holding {@link Capability#UseBrushToolManager}
     * (the brush-tool admin capability) may remove an obelisk.
     */
    @LuaMethod(name = "isObeliskRemovalAllowed")
    public static boolean isObeliskRemovalAllowed(IsoPlayer character) {
        try {
            if (character == null) {
                return false;
            }
            UdpConnection connection = GameServer.getConnectionFromPlayer(character);
            if (connection == null) {
                return false;
            }
            Role role = connection.getRole();
            return role != null && role.hasCapability(Capability.UseBrushToolManager);
        } catch (Throwable t) {
            LOGGER.error("[SurvivorSkillObelisk] removal-allowed check failed; denying", t);
            return false;
        }
    }

    /**
     * Called when the server-side destroy action was blocked. Resyncs the obelisk to the acting
     * client (its local action already removed the object) and delivers the curse via {@link
     * ObeliskCurseHandler} when enabled.
     */
    @LuaMethod(name = "onBlockedObeliskDestroy")
    public static void onBlockedObeliskDestroy(IsoPlayer character, IsoObject target) {
        UdpConnection connection = resyncBlockedRemoval(character, target, "sledgehammer destroy");
        if (connection == null) {
            return;
        }
        try {
            if (SurvivorSkillObeliskConfig.isCurseOnSledgehammer() && target.getSquare() != null) {
                ObeliskCurseHandler.enqueueCurse(
                        connection,
                        character,
                        target.getSquare().getX(),
                        target.getSquare().getY(),
                        target.getSquare().getZ());
            }
        } catch (Throwable t) {
            LOGGER.error("[SurvivorSkillObelisk] Failed to enqueue curse from action guard", t);
        }
    }

    /**
     * Called when a blocked pickup/disassemble action targeted an obelisk. No curse — bait only
     * applies to the sledgehammer.
     */
    @LuaMethod(name = "onBlockedObeliskPickup")
    public static void onBlockedObeliskPickup(IsoPlayer character, IsoObject target) {
        resyncBlockedRemoval(character, target, "pickup/disassemble");
    }

    private static UdpConnection resyncBlockedRemoval(
            IsoPlayer character, IsoObject target, String action) {
        try {
            if (character == null || target == null) {
                return null;
            }
            UdpConnection connection = GameServer.getConnectionFromPlayer(character);
            LOGGER.warn(
                    "[SurvivorSkillObelisk] Blocked obelisk {} by \"{}\" at ({}, {}, {})",
                    action,
                    character.getUsername(),
                    target.getSquare() != null ? target.getSquare().getX() : -1,
                    target.getSquare() != null ? target.getSquare().getY() : -1,
                    target.getSquare() != null ? target.getSquare().getZ() : -1);
            if (connection != null) {
                // The initiating client already removed the object locally; send it back so
                // the obelisk doesn't linger as a client-side ghost until the chunk reloads.
                INetworkPacket.send(connection, PacketTypes.PacketType.AddItemToMap, target);
            }
            return connection;
        } catch (Throwable t) {
            LOGGER.error("[SurvivorSkillObelisk] Failed to resync blocked obelisk removal", t);
            return null;
        }
    }
}
