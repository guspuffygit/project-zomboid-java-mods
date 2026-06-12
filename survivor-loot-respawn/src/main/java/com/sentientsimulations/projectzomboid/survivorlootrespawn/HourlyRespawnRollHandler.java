package com.sentientsimulations.projectzomboid.survivorlootrespawn;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import com.sentientsimulations.projectzomboid.survivorlootrespawn.config.SurvivorLootRespawnConfig;
import com.sentientsimulations.projectzomboid.survivorlootrespawn.metrics.SurvivorLootRespawnMetrics;
import com.sentientsimulations.projectzomboid.survivorlootrespawn.state.ContainerLootState;
import com.sentientsimulations.projectzomboid.survivorlootrespawn.state.ContainerLootStateRepository;
import io.pzstorm.storm.event.core.SubscribeEvent;
import io.pzstorm.storm.event.lua.EveryHoursEvent;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ThreadLocalRandom;
import zombie.GameTime;

public final class HourlyRespawnRollHandler {

    private HourlyRespawnRollHandler() {}

    @SubscribeEvent
    public static void onEveryHour(EveryHoursEvent event) {
        if (!SurvivorLootRespawnConfig.isModEnabled()) {
            return;
        }
        double worldAgeHours = GameTime.getInstance().getWorldAgeHours();
        Thread thread =
                new Thread(() -> rollContainers(worldAgeHours), "SurvivorLootRespawn-HourlyRoll");
        thread.setDaemon(true);
        thread.start();
    }

    private static void rollContainers(double worldAgeHours) {
        long startNanos = System.nanoTime();
        int hoursTillMax = SurvivorLootRespawnConfig.getHoursTillMaxRespawnChance();
        int maxChance = SurvivorLootRespawnConfig.getMaxRespawnChance();
        int minChance = SurvivorLootRespawnConfig.getMinRespawnChance();
        int quietPeriod = SurvivorLootRespawnConfig.getContainerQuietPeriodHours();
        double steepness = SurvivorLootRespawnConfig.getCurveSteepness();

        List<ContainerLootState> rolling =
                ContainerLootStateRepository.selectRolling(worldAgeHours, quietPeriod);

        List<ContainerLootState> winners = new ArrayList<>();
        for (ContainerLootState s : rolling) {
            double hoursSinceLooted = worldAgeHours - s.lootedGameHours();
            double chance =
                    computeChance(hoursSinceLooted, hoursTillMax, minChance, maxChance, steepness);
            boolean won = ThreadLocalRandom.current().nextDouble() * 100.0 < chance;
            SurvivorLootRespawnMetrics.recordRoll(won, chance);
            if (won) {
                winners.add(s);
            }
        }
        if (!winners.isEmpty()) {
            ContainerLootStateRepository.batchMarkQueued(winners, worldAgeHours);
        }
        SurvivorLootRespawnMetrics.observeHourlyRollSeconds((System.nanoTime() - startNanos) / 1e9);
        LOGGER.debug(
                "[SurvivorLootRespawn] Hourly roll fired at worldAgeHours={}: eligible={}, queued={} (hoursTillMax={}, max={}%, min={}%, quiet={}h, steepness={})",
                worldAgeHours,
                rolling.size(),
                winners.size(),
                hoursTillMax,
                maxChance,
                minChance,
                quietPeriod,
                steepness);
    }

    static double computeChance(
            double hoursSinceLooted,
            int hoursTillMax,
            int minChance,
            int maxChance,
            double steepness) {
        if (hoursTillMax <= 0) {
            return maxChance;
        }
        double t = hoursSinceLooted / hoursTillMax;
        if (t > 1.0) {
            t = 1.0;
        }
        if (t < 0.0) {
            t = 0.0;
        }
        double curve;
        if (steepness <= 1.0) {
            curve = t;
        } else {
            curve = (Math.pow(steepness, t) - 1.0) / (steepness - 1.0);
        }
        return minChance + (maxChance - minChance) * curve;
    }
}
