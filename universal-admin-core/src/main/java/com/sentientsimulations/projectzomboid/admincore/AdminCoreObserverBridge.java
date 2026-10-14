package com.sentientsimulations.projectzomboid.admincore;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import se.krka.kahlua.integration.annotations.LuaMethod;
import zombie.characters.Capability;
import zombie.characters.IsoPlayer;
import zombie.network.GameServer;

/** Server-only one-shot movement. Camera observation never calls sendTeleport. */
public final class AdminCoreObserverBridge {
    private static final Logger LOGGER = LoggerFactory.getLogger(AdminCoreObserverBridge.class);

    private AdminCoreObserverBridge() {}

    private static boolean allowed(IsoPlayer actor, Capability capability) {
        return GameServer.server
                && actor != null
                && GameServer.isPlayerConnected(actor)
                && !actor.isDead()
                && actor.getRole() != null
                && actor.getRole().hasAdminPower()
                && actor.getRole().hasCapability(Capability.TeleportToPlayer)
                && actor.getRole().hasCapability(Capability.SeePlayersConnected)
                && actor.getRole().hasCapability(capability);
    }

    @LuaMethod
    public static IsoPlayer target(IsoPlayer actor, String username) {
        if (!allowed(actor, Capability.TeleportToPlayer)
                || username == null
                || username.length() > 128) return null;
        IsoPlayer target = GameServer.getPlayerByUserName(username);
        return target != null && GameServer.isPlayerConnected(target) && !target.isDead()
                ? target
                : null;
    }

    @LuaMethod
    public static boolean teleportTo(IsoPlayer actor, String username) {
        IsoPlayer target = target(actor, username);
        if (target == null || actor == target || actor.getVehicle() != null) return false;
        GameServer.sendTeleport(actor, target.getX(), target.getY(), target.getZ());
        LOGGER.info(
                "[Universal Admin Core] ADMIN_TELEPORT {} -> {}", actor.getUsername(), username);
        return true;
    }

    @LuaMethod
    public static boolean returnTo(IsoPlayer actor, double x, double y, double z) {
        if (!allowed(actor, Capability.TeleportToCoordinates)
                || actor.getVehicle() != null
                || !validPosition(x, y, z)) return false;
        GameServer.sendTeleport(actor, (float) x, (float) y, (float) z);
        LOGGER.info(
                "[Universal Admin Core] ADMIN_TELEPORT {} -> observation origin",
                actor.getUsername());
        return true;
    }

    static boolean validPosition(double x, double y, double z) {
        return Double.isFinite(x)
                && Double.isFinite(y)
                && Double.isFinite(z)
                && Math.abs(x) <= 1000000
                && Math.abs(y) <= 1000000
                && z >= -32
                && z <= 32;
    }
}
