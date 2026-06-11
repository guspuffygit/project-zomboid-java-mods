package com.sentientsimulations.projectzomboid.survivorlootrespawn;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import com.sentientsimulations.projectzomboid.survivorlootrespawn.config.SurvivorLootRespawnConfig;
import io.pzstorm.storm.event.core.SubscribeEvent;
import io.pzstorm.storm.event.lua.OnServerStartedEvent;

public final class StartupConfigLogger {

    private StartupConfigLogger() {}

    @SubscribeEvent
    public static void onServerStarted(OnServerStartedEvent event) {
        LOGGER.info(
                "(SurvivorLootRespawn) Active config: lootRespawnType={}, hoursTillMax={}, maxChance={}, minChance={}, quietPeriodHours={}, curveSteepness={}",
                SurvivorLootRespawnConfig.getLootRespawnType(),
                SurvivorLootRespawnConfig.getHoursTillMaxRespawnChance(),
                SurvivorLootRespawnConfig.getMaxRespawnChance(),
                SurvivorLootRespawnConfig.getMinRespawnChance(),
                SurvivorLootRespawnConfig.getContainerQuietPeriodHours(),
                SurvivorLootRespawnConfig.getCurveSteepness());
    }
}
