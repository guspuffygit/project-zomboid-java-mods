package com.sentientsimulations.projectzomboid.avcsmapview;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import se.krka.kahlua.vm.KahluaTable;
import zombie.Lua.LuaManager;
import zombie.characters.IsoGameCharacter;
import zombie.characters.IsoPlayer;
import zombie.network.GameServer;
import zombie.vehicles.BaseVehicle;
import zombie.vehicles.VehicleManager;
import zombie.vehicles.VehiclePart;

/**
 * Server-side guard that blocks player-inflicted damage to claimed vehicles while no player is
 * inside. Player damage reaches the server through exactly two client channels, both gated here:
 *
 * <ul>
 *   <li>{@code PlayerHitVehiclePacket} &rarr; {@code BaseVehicle.processHit} (guns and melee) —
 *       vetoed by {@link BaseVehicleProcessHitPatch} via {@link #shouldBlockHit}.
 *   <li>the {@code vehicle.damageWindow} client command (window smashes; the vanilla Lua handler
 *       applies the client-sent amount with no validation) — vetoed by {@link
 *       LuaEventManagerVehicleRemovePatch} via {@link #shouldBlockDamageWindowCommand}.
 * </ul>
 *
 * <p>Occupied vehicles are always fair game: shooting at a driver or passenger still damages the
 * car, and zombies thumping a car someone is hiding in are unaffected. The owner, faction/safehouse
 * members (per AllowFaction/AllowSafehouse) and admins may always damage the vehicle. Environmental
 * damage (crashes, run-overs) never passes through these channels and is untouched.
 */
public final class VehicleDamageSecurity {

    private static final long HALO_THROTTLE_NANOS = 2_000_000_000L;
    private static final Map<String, Long> lastHaloByUsername = new ConcurrentHashMap<>();

    private VehicleDamageSecurity() {}

    /**
     * Called from advice on {@code BaseVehicle.processHit}; untyped so the advice stays minimal.
     */
    public static boolean shouldBlockHit(Object vehicleObj, Object attackerObj) {
        try {
            if (!(vehicleObj instanceof BaseVehicle vehicle)
                    || !(attackerObj instanceof IsoPlayer attacker)) {
                return false;
            }
            if (!shouldBlock(vehicle, attacker)) {
                return false;
            }
            // the attacker's client already applied the hit predictively; snap it back
            resyncParts(vehicle);
            logBlocked(attacker, vehicle, "weapon hit");
            return true;
        } catch (Throwable t) {
            // fail open: a broken guard must not take down combat packet processing
            LOGGER.error("[AVCS] vehicle damage guard failed; allowing hit", t);
            return false;
        }
    }

    public static boolean shouldBlockDamageWindowCommand(
            String event, Object module, Object command, Object player, Object args) {
        try {
            if (!"OnClientCommand".equals(event)
                    || !"vehicle".equals(module)
                    || !"damageWindow".equals(command)) {
                return false;
            }
            if (!(player instanceof IsoPlayer p) || !(args instanceof KahluaTable a)) {
                return false;
            }
            Object vehicleIdObj = a.rawget("vehicle");
            if (!(vehicleIdObj instanceof Number n)) {
                return false;
            }
            BaseVehicle vehicle = VehicleManager.instance.getVehicleByID((short) n.intValue());
            if (vehicle == null || !shouldBlock(vehicle, p)) {
                return false;
            }
            logBlocked(p, vehicle, "vehicle.damageWindow");
            return true;
        } catch (Throwable t) {
            LOGGER.error("[AVCS] vehicle damage guard failed; allowing damageWindow", t);
            return false;
        }
    }

    private static boolean shouldBlock(BaseVehicle vehicle, IsoPlayer attacker) {
        if (attacker.getUsername() == null) {
            return false;
        }
        if (!AvcsClaimPermissions.booleanOption("AVCS.ProtectParkedFromDamage")) {
            return false;
        }
        if (hasPlayerInside(vehicle)) {
            return false;
        }
        String owner = AvcsClaimPermissions.claimedOwner(vehicle);
        if (owner == null) {
            return false;
        }
        if (AvcsClaimPermissions.isPermitted(attacker, owner)) {
            return false;
        }
        notifyBlocked(attacker);
        return true;
    }

    private static boolean hasPlayerInside(BaseVehicle vehicle) {
        for (int seat = 0; seat < vehicle.getMaxPassengers(); seat++) {
            IsoGameCharacter chr = vehicle.getCharacter(seat);
            // username check excludes IsoAnimal, which extends IsoPlayer
            if (chr instanceof IsoPlayer p && p.getUsername() != null) {
                return true;
            }
        }
        return false;
    }

    private static void resyncParts(BaseVehicle vehicle) {
        for (int i = 0; i < vehicle.getPartCount(); i++) {
            VehiclePart part = vehicle.getPartByIndex(i);
            if (part != null) {
                vehicle.transmitPartCondition(part);
                vehicle.transmitPartWindow(part);
            }
        }
    }

    private static void notifyBlocked(IsoPlayer attacker) {
        String username = attacker.getUsername();
        long now = System.nanoTime();
        Long last = lastHaloByUsername.get(username);
        if (last != null && now - last < HALO_THROTTLE_NANOS) {
            return;
        }
        lastHaloByUsername.put(username, now);
        GameServer.sendServerCommand(
                attacker, "AVCS", "damageBlocked", LuaManager.platform.newTable());
    }

    private static void logBlocked(IsoPlayer attacker, BaseVehicle vehicle, String channel) {
        LOGGER.warn(
                "[AVCS] BLOCKED {} from {} on parked claimed vehicle id={}",
                channel,
                attacker.getUsername(),
                vehicle.getId());
    }
}
