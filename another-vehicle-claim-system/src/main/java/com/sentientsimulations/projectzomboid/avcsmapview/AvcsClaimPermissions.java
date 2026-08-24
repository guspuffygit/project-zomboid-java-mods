package com.sentientsimulations.projectzomboid.avcsmapview;

import java.util.ArrayList;
import se.krka.kahlua.vm.KahluaTable;
import zombie.SandboxOptions;
import zombie.characters.Faction;
import zombie.characters.IsoPlayer;
import zombie.config.BooleanConfigOption;
import zombie.iso.areas.SafeHouse;
import zombie.vehicles.BaseVehicle;
import zombie.world.moddata.ModData;

/**
 * Shared AVCS claim lookup and permission ladder, mirroring the Lua {@code AVCS.checkPermission}
 * logic: admin bypass, owner match, faction members, safehouse members.
 */
final class AvcsClaimPermissions {

    private AvcsClaimPermissions() {}

    /** Claim owner username, or {@code null} when the vehicle is not claimed. */
    static String claimedOwner(BaseVehicle vehicle) {
        Object claimKey = AvcsClaimIdentity.effectiveClaimKey(vehicle);
        if (claimKey == null) {
            return null;
        }
        KahluaTable byVehicleSqlid = ModData.get("AVCSByVehicleSQLID");
        if (byVehicleSqlid == null) {
            return null;
        }
        Object claimObj = byVehicleSqlid.rawget(claimKey);
        if (!(claimObj instanceof KahluaTable claim)) {
            return null;
        }
        Object ownerObj = claim.rawget("OwnerPlayerID");
        return ownerObj instanceof String owner ? owner : null;
    }

    static boolean isPermitted(IsoPlayer p, String owner) {
        if (p.isAccessLevel("admin")) {
            return true;
        }
        String username = p.getUsername();
        if (owner.equals(username)) {
            return true;
        }
        if (booleanOption("AVCS.AllowFaction")) {
            Faction faction = Faction.getPlayerFaction(owner);
            if (faction != null) {
                if (username.equals(faction.getOwner())) {
                    return true;
                }
                ArrayList<String> members = faction.getPlayers();
                if (members != null && members.contains(username)) {
                    return true;
                }
            }
        }
        if (booleanOption("AVCS.AllowSafehouse")) {
            SafeHouse safehouse = SafeHouse.hasSafehouse(owner);
            if (safehouse != null) {
                ArrayList<String> members = safehouse.getPlayers();
                if (members != null && members.contains(username)) {
                    return true;
                }
            }
        }
        return false;
    }

    static boolean booleanOption(String name) {
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
