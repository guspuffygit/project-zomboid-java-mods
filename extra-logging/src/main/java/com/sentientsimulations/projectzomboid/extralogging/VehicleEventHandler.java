package com.sentientsimulations.projectzomboid.extralogging;

import io.pzstorm.storm.event.packet.*;

public class VehicleEventHandler {

    private static final ch.qos.logback.classic.Logger logger =
            ExtraLoggerFactory.createLogger("vehicles");

    public static void onPlayerHitVehicle(PlayerHitVehiclePacketEvent event) {
        try {
            logger.info(
                    "{}: steamId={}, user={}, playerPos=({},{},{}), weapon={}, damage={}, vehiclePos=({},{},{}), vehicleId={}, vehicleName={}",
                    event.getName(),
                    event.steamId,
                    event.username,
                    event.getPacket().getWielder().getX(),
                    event.getPacket().getWielder().getY(),
                    event.getPacket().getWielder().getZ(),
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
