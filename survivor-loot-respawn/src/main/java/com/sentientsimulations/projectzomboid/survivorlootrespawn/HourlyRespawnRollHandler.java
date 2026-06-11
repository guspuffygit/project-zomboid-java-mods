package com.sentientsimulations.projectzomboid.survivorlootrespawn;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import io.pzstorm.storm.event.core.SubscribeEvent;
import io.pzstorm.storm.event.lua.EveryHoursEvent;

public final class HourlyRespawnRollHandler {

    private HourlyRespawnRollHandler() {}

    @SubscribeEvent
    public static void onEveryHour(EveryHoursEvent event) {
        Thread thread = new Thread(HourlyRespawnRollHandler::rollContainers, "SurvivorLootRespawn-HourlyRoll");
        thread.setDaemon(true);
        thread.start();
    }

    private static void rollContainers() {
        LOGGER.debug("Rolling containers for loot respawn");
        // TODO: iterate containers and roll for refill
    }
}
