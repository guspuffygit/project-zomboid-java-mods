package com.sentientsimulations.projectzomboid.avcsmapview;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import java.lang.reflect.Field;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import se.krka.kahlua.vm.KahluaTable;
import zombie.Lua.LuaManager;
import zombie.characters.IsoPlayer;
import zombie.core.logger.LoggerManager;
import zombie.network.GameServer;
import zombie.network.fields.character.PlayerID;
import zombie.network.fields.vehicle.VehicleID;
import zombie.vehicles.BaseVehicle;

/**
 * Server-side AVCS permission gate for taking a seat in a claimed vehicle. AVCS's own enforcement
 * is client-side only ({@code ISEnterVehicle} overrides), so a client that has not yet received the
 * vehicle's {@code modData.SQLID} — or one that skips the Lua check — can enter and drive off a
 * claimed vehicle; the server applied the seat change unquestioned. This is how claimed cars kept
 * "vanishing": another player simply drove them away.
 *
 * <p>{@code VehicleEnterPacket} and {@code VehicleSwitchSeatPacket} are the only two paths through
 * which a client's seat change reaches the server ({@code VehiclePassengers.parse} only mutates
 * state on clients), and both are gated here via {@link VehicleEnterPacketGuardPatch} / {@link
 * VehicleSwitchSeatPacketGuardPatch}. A blocked packet is dropped whole — the vehicle keeps no
 * driver server-side and nothing is relayed to other clients — and the offender is told via the
 * {@code AVCS enterBlocked} client command, whose handler backs their character out of the seat
 * they entered predictively.
 *
 * <p>The check must mirror the client-side {@code ISEnterVehicle}/{@code ISSwitchVehicleSeat}
 * overrides exactly, or the guard blocks seats the client legitimately offered: first the claim's
 * per-vehicle public toggles ({@code AllowPassenger} for any passenger seat, {@code AllowDrive} for
 * seat 0), then the shared {@link AvcsClaimPermissions} ladder (admin, owner, faction/safehouse
 * members per sandbox options). Unclaimed vehicles pass through untouched, and any guard failure
 * fails open: entering vehicles must never break because of a broken guard.
 */
public final class VehicleEnterSecurity {

    private static final long HALO_THROTTLE_NANOS = 2_000_000_000L;
    private static final Map<String, Long> lastNoteByUsername = new ConcurrentHashMap<>();
    private static final String LOG_NAME = "AVCS";

    private VehicleEnterSecurity() {}

    /**
     * Called from advice on the {@code processServer} of both seat packets; untyped so the inlined
     * advice stays minimal. Returns {@code true} when the packet must be dropped.
     */
    public static boolean shouldBlockSeatChange(Object packetObj, String packetName) {
        try {
            BaseVehicle vehicle = vehicleOf(packetObj);
            if (vehicle == null) {
                return false;
            }
            IsoPlayer player = playerOf(packetObj);
            if (player == null || player.getUsername() == null) {
                return false;
            }
            String owner = AvcsClaimPermissions.claimedOwner(vehicle);
            if (owner == null) {
                return false;
            }
            int seatTo = seatToOf(packetObj);
            String publicFlag = seatTo == 0 ? "AllowDrive" : "AllowPassenger";
            if (AvcsClaimPermissions.publicPermission(vehicle, publicFlag)) {
                return false;
            }
            if (AvcsClaimPermissions.isPermitted(player, owner)) {
                return false;
            }
            String line =
                    "["
                            + (System.currentTimeMillis() / 1000L)
                            + "] Warning: Blocked "
                            + packetName
                            + " on claimed vehicle ["
                            + player.getUsername()
                            + "] [owner "
                            + owner
                            + "] ["
                            + vehicle.getScriptName()
                            + "] ["
                            + (int) Math.floor(vehicle.getX())
                            + ","
                            + (int) Math.floor(vehicle.getY())
                            + "]";
            LoggerManager.getLogger(LOG_NAME).write(line);
            LOGGER.warn("[AVCS] {}", line);
            notifyBlocked(player, vehicle);
            return true;
        } catch (Throwable t) {
            // fail open: a broken guard must not take down vehicle packet processing
            LOGGER.error("[AVCS] vehicle enter guard failed; allowing {}", packetName, t);
            return false;
        }
    }

    private static BaseVehicle vehicleOf(Object packet) throws ReflectiveOperationException {
        return ((VehicleID) field(packet, "vehicleId")).getVehicle();
    }

    private static IsoPlayer playerOf(Object packet) throws ReflectiveOperationException {
        return ((PlayerID) field(packet, "playerId")).getPlayer();
    }

    private static int seatToOf(Object packet) throws ReflectiveOperationException {
        return (Integer) field(packet, "seatTo");
    }

    private static Object field(Object o, String name) throws ReflectiveOperationException {
        Field f = o.getClass().getDeclaredField(name);
        f.setAccessible(true);
        return f.get(o);
    }

    private static void notifyBlocked(IsoPlayer player, BaseVehicle vehicle) {
        String username = player.getUsername();
        long now = System.nanoTime();
        Long last = lastNoteByUsername.get(username);
        if (last != null && now - last < HALO_THROTTLE_NANOS) {
            return;
        }
        lastNoteByUsername.put(username, now);
        KahluaTable args = LuaManager.platform.newTable();
        args.rawset("vehicle", (double) vehicle.getId());
        GameServer.sendServerCommand(player, "AVCS", "enterBlocked", args);
    }
}
