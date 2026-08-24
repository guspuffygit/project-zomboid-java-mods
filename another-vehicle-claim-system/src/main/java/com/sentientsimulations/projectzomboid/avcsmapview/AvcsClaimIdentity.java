package com.sentientsimulations.projectzomboid.avcsmapview;

import org.jetbrains.annotations.Nullable;
import zombie.vehicles.BaseVehicle;
import zombie.vehicles.VehiclePart;

/**
 * Resolves which claim key a loaded vehicle is imprinted with, mirroring Lua's {@code
 * AVCS.getVehicleID}: the vehicle's own {@code modData.SQLID}, falling back to a part's {@code
 * modData.SQLID} (the "mule part" scheme older AVCS versions used before {@code getVehicleID}
 * migrates it onto the vehicle).
 *
 * <p>Vanilla recycles {@code vehicles.db} row ids (lowest free id wins), so a claim key that merely
 * decodes to a vehicle's sqlId proves nothing — the imprinted key is the only trustworthy link
 * between a claim and a physical vehicle.
 */
final class AvcsClaimIdentity {

    private AvcsClaimIdentity() {}

    /** The claim key imprinted on the vehicle, or {@code null} when it carries none. */
    static @Nullable Object effectiveClaimKey(BaseVehicle vehicle) {
        if (vehicle.hasModData()) {
            Object key = vehicle.getModData().rawget(AvcsVehicleLocationSync.MOD_DATA_SQLID);
            if (key instanceof Number) {
                return key;
            }
        }
        for (int i = 0; i < vehicle.getPartCount(); i++) {
            VehiclePart part = vehicle.getPartByIndex(i);
            if (part != null && part.hasModData()) {
                Object key = part.getModData().rawget(AvcsVehicleLocationSync.MOD_DATA_SQLID);
                if (key instanceof Number) {
                    return key;
                }
            }
        }
        return null;
    }

    /** True only when the vehicle is imprinted with exactly {@code claimKey}. */
    static boolean matchesClaim(BaseVehicle vehicle, Object claimKey) {
        Object imprinted = effectiveClaimKey(vehicle);
        return imprinted != null && imprinted.equals(claimKey);
    }
}
