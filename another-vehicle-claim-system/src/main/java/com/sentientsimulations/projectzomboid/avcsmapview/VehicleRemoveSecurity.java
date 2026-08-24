package com.sentientsimulations.projectzomboid.avcsmapview;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import se.krka.kahlua.vm.KahluaTable;
import zombie.characters.IsoPlayer;
import zombie.vehicles.BaseVehicle;
import zombie.vehicles.VehicleManager;

/**
 * Server-side AVCS permission gate for the {@code vehicle.remove} client command. Returns {@code
 * true} when the command should be BLOCKED (so the advice that calls us skips the event dispatch).
 *
 * <p>Unowned or unsupported vehicles pass through (caller not blocked), matching the Lua "ownerless
 * = permitted" semantics; the permission ladder lives in {@link AvcsClaimPermissions}.
 */
public final class VehicleRemoveSecurity {

    private VehicleRemoveSecurity() {}

    public static boolean shouldBlock(
            String event, Object module, Object command, Object player, Object args) {
        if (!"OnClientCommand".equals(event)
                || !"vehicle".equals(module)
                || !"remove".equals(command)) {
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
        if (vehicle == null) {
            return false;
        }

        String owner = AvcsClaimPermissions.claimedOwner(vehicle);
        if (owner == null) {
            return false;
        }
        if (AvcsClaimPermissions.isPermitted(p, owner)) {
            return false;
        }

        LOGGER.warn(
                "[AVCS] BLOCKED vehicle.remove from {} on claimed vehicle (owner={}, id={})",
                p.getUsername(),
                owner,
                vehicle.getId());
        return true;
    }
}
