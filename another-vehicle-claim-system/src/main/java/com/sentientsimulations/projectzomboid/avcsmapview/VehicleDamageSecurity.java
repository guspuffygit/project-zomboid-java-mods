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
 * inside. Player damage reaches the server through three channels, all gated here:
 *
 * <ul>
 *   <li>{@code PlayerHitVehiclePacket} &rarr; {@code BaseVehicle.processHit} (guns and melee) —
 *       vetoed by {@link BaseVehicleDamageGuardPatch} via {@link #shouldBlockHit}.
 *   <li>the {@code vehicle.damageWindow} client command (window smashes; the vanilla Lua handler
 *       applies the client-sent amount with no validation) — vetoed by {@link
 *       LuaEventManagerVehicleRemovePatch} via {@link #shouldBlockDamageWindowCommand}.
 *   <li>{@code BaseVehicle.crash} (ramming with another vehicle) — vetoed by {@link
 *       BaseVehicleDamageGuardPatch} via {@link #shouldBlockCrash}. Both the server-physics path
 *       and the {@code vehicle.crash} client command funnel into this one method. Crash carries no
 *       attacker identity, so the block is unconditional for a protected parked claim: even the
 *       owner ramming their own parked car does no damage while the option is on.
 * </ul>
 *
 * <p>Occupied vehicles are always fair game: shooting at or ramming a car with a driver or
 * passenger inside works as vanilla, and zombies thumping a car someone is hiding in are
 * unaffected. For the two attacker-attributed channels the owner, faction/safehouse members (per
 * AllowFaction/AllowSafehouse) and admins may always damage the vehicle. Run-over ped damage
 * ({@code damageFromHitChr}) only ever applies to a driven vehicle and is untouched.
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

    /** Called from advice on {@code BaseVehicle.crash}; untyped so the advice stays minimal. */
    public static boolean shouldBlockCrash(Object vehicleObj) {
        try {
            if (!(vehicleObj instanceof BaseVehicle vehicle)) {
                return false;
            }
            if (!isProtectedParked(vehicle)) {
                return false;
            }
            LOGGER.debug(
                    "[AVCS] BLOCKED crash damage on parked claimed vehicle id={}", vehicle.getId());
            return true;
        } catch (Throwable t) {
            LOGGER.error("[AVCS] vehicle damage guard failed; allowing crash", t);
            return false;
        }
    }

    private static boolean shouldBlock(BaseVehicle vehicle, IsoPlayer attacker) {
        if (attacker.getUsername() == null) {
            return false;
        }
        if (!isProtectedParked(vehicle)) {
            return false;
        }
        String owner = AvcsClaimPermissions.claimedOwner(vehicle);
        if (AvcsClaimPermissions.isPermitted(attacker, owner)) {
            return false;
        }
        notifyBlocked(attacker);
        return true;
    }

    private static boolean isProtectedParked(BaseVehicle vehicle) {
        return AvcsClaimPermissions.booleanOption("AVCS.ProtectParkedFromDamage")
                && !hasPlayerInside(vehicle)
                && AvcsClaimPermissions.claimedOwner(vehicle) != null;
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
