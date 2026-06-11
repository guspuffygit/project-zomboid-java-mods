package com.sentientsimulations.projectzomboid.survivorlootrespawn;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import com.sentientsimulations.projectzomboid.survivorlootrespawn.config.SurvivorLootRespawnConfig;
import com.sentientsimulations.projectzomboid.survivorlootrespawn.state.ContainerLootState;
import com.sentientsimulations.projectzomboid.survivorlootrespawn.state.ContainerLootStateRepository;
import io.pzstorm.storm.event.core.SubscribeEvent;
import io.pzstorm.storm.event.lua.EveryHoursEvent;
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
        int hoursTillMax = SurvivorLootRespawnConfig.getHoursTillMaxRespawnChance();
        int maxChance = SurvivorLootRespawnConfig.getMaxRespawnChance();
        int minChance = SurvivorLootRespawnConfig.getMinRespawnChance();
        int quietPeriod = SurvivorLootRespawnConfig.getContainerQuietPeriodHours();
        double steepness = SurvivorLootRespawnConfig.getCurveSteepness();

        List<ContainerLootState> rolling =
                ContainerLootStateRepository.selectRolling(worldAgeHours, quietPeriod);
        if (rolling.isEmpty()) {
            return;
        }

        int queued = 0;
        for (ContainerLootState s : rolling) {
            double hoursSinceLooted = worldAgeHours - s.lootedGameHours();
            double chance =
                    computeChance(hoursSinceLooted, hoursTillMax, minChance, maxChance, steepness);
            if (ThreadLocalRandom.current().nextDouble() * 100.0 < chance) {
                ContainerLootStateRepository.markQueued(
                        s.squareX(),
                        s.squareY(),
                        s.squareZ(),
                        s.containerType(),
                        s.containerIndex(),
                        worldAgeHours);
                queued++;
            }
        }
        LOGGER.debug(
                "(SurvivorLootRespawn) Loot respawn roll at worldAgeHours={}: rolled={}, queued={}",
                worldAgeHours,
                rolling.size(),
                queued);
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
