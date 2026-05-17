package com.sentientsimulations.projectzomboid.avcsmapview;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import java.util.ArrayList;
import se.krka.kahlua.vm.KahluaTable;
import zombie.SandboxOptions;
import zombie.characters.Faction;
import zombie.characters.IsoPlayer;
import zombie.config.BooleanConfigOption;
import zombie.iso.areas.SafeHouse;
import zombie.vehicles.BaseVehicle;
import zombie.vehicles.VehicleManager;
import zombie.world.moddata.ModData;

/**
 * Server-side AVCS permission gate for the {@code vehicle.remove} client command. Returns {@code
 * true} when the command should be BLOCKED (so the advice that calls us skips the event dispatch).
 *
 * <p>Mirrors the Lua {@code AVCS.checkPermission} logic: admin bypass, owner match, faction
 * members, safehouse members. Unowned or unsupported vehicles pass through (caller not blocked),
 * matching the Lua "ownerless = permitted" semantics.
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

        if (p.isAccessLevel("admin")) {
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

        Object sqlidObj = vehicle.getModData().rawget("SQLID");
        if (!(sqlidObj instanceof Number)) {
            return false;
        }

        KahluaTable byVehicleSqlid = ModData.get("AVCSByVehicleSQLID");
        if (byVehicleSqlid == null) {
            return false;
        }
        Object claimObj = byVehicleSqlid.rawget(sqlidObj);
        if (!(claimObj instanceof KahluaTable claim)) {
            return false;
        }
        Object ownerObj = claim.rawget("OwnerPlayerID");
        if (!(ownerObj instanceof String owner)) {
            return false;
        }

        String username = p.getUsername();
        if (owner.equals(username)) {
            return false;
        }

        if (booleanOption("AVCS.AllowFaction")) {
            Faction faction = Faction.getPlayerFaction(owner);
            if (faction != null) {
                if (username.equals(faction.getOwner())) {
                    return false;
                }
                ArrayList<String> members = faction.getPlayers();
                if (members != null && members.contains(username)) {
                    return false;
                }
            }
        }

        if (booleanOption("AVCS.AllowSafehouse")) {
            SafeHouse safehouse = SafeHouse.hasSafehouse(owner);
            if (safehouse != null) {
                ArrayList<String> members = safehouse.getPlayers();
                if (members != null && members.contains(username)) {
                    return false;
                }
            }
        }

        LOGGER.warn(
                "[AVCS] BLOCKED vehicle.remove from {} on claimed vehicle (owner={}, sqlid={})",
                username,
                owner,
                sqlidObj);
        return true;
    }

    private static boolean booleanOption(String name) {
        SandboxOptions.SandboxOption opt = SandboxOptions.instance.getOptionByName(name);
        if (opt == null) {
            return false;
        }
        if (opt.asConfigOption() instanceof BooleanConfigOption bo) {
            return bo.getValue();
        }
        return false;
    }
}
