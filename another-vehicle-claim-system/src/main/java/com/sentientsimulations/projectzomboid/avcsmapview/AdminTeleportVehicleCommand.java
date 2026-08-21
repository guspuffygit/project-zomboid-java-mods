package com.sentientsimulations.projectzomboid.avcsmapview;

import io.pzstorm.storm.event.core.ClientCommand;
import io.pzstorm.storm.event.core.ClientCommandEvent;
import org.jetbrains.annotations.Nullable;
import se.krka.kahlua.vm.KahluaTable;
import zombie.characters.IsoPlayer;

/**
 * {@code AVCS:adminTeleportVehicle} — sent by the claimed-vehicle managers when an admin asks for a
 * claimed vehicle to be brought to their position. Carries the AVCS claim key ({@code VehicleID},
 * the {@code timestamp..sqlId} number the Lua DB is keyed by) and the tile offset from the admin.
 */
@ClientCommand(module = AvcsAdminVehicleTeleport.MODULE, command = AvcsAdminVehicleTeleport.COMMAND)
public class AdminTeleportVehicleCommand extends ClientCommandEvent {

    public AdminTeleportVehicleCommand(IsoPlayer player, @Nullable KahluaTable args) {
        super(player, args);
    }

    public @Nullable Object getVehicleId() {
        return rawget(AvcsVehicleLocationSync.KEY_VEHICLE_ID);
    }

    public @Nullable Double getOffsetX() {
        return getDouble("OffsetX");
    }

    public @Nullable Double getOffsetY() {
        return getDouble("OffsetY");
    }
}
