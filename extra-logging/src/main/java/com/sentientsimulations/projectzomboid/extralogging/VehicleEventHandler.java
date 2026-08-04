package com.sentientsimulations.projectzomboid.extralogging;

import io.pzstorm.storm.event.packet.*;
import zombie.network.fields.hit.Player;

public class VehicleEventHandler {

    private static final org.slf4j.Logger logger = ExtraLoggerFactory.createLogger("vehicles");

    public static void onPlayerHitVehicle(PlayerHitVehiclePacketEvent event) {
        try {
            Player wielder = (Player) event.getField("wielder");
            logger.info(
                    "{}: steamId={}, user={}, playerPos=({},{},{}), weapon={}, damage={}, vehiclePos=({},{},{}), vehicleId={}, vehicleName={}",
                    event.getName(),
                    event.steamId,
                    event.username,
                    wielder.getX(),
                    wielder.getY(),
                    wielder.getZ(),
                    event.getPacket().getHandWeapon().getName(),
                    event.getDamage(),
                    event.getVehicleId().getX(),
                    event.getVehicleId().getY(),
                    event.getVehicleId().getZ(),
                    event.getVehicleId().getVehicle().vehicleId,
                    event.getVehicleId().getVehicle().getScriptName());
        } catch (Exception e) {
            logger.error("Failed to log PlayerHitVehicle", e);
        }
    }
}
