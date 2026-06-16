package com.sentientsimulations.projectzomboid.stopzombiesafehousespawns;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import com.sentientsimulations.projectzomboid.stopzombiesafehousespawns.patch.PlayerSpawnsAllowZombieSafehousePatch;
import io.pzstorm.storm.core.StormClassTransformer;
import io.pzstorm.storm.mod.ZomboidMod;
import io.pzstorm.storm.util.StormEnv;
import java.util.Collections;
import java.util.List;

public class StopZombieSafehouseSpawnsMod implements ZomboidMod {

    @Override
    public void registerEventHandlers() {
        if (!StormEnv.isStormServer()) {
            return;
        }
        LOGGER.debug(
                "[StopZombieSafehouseSpawns] Registering for {}",
                StopZombieSafehouseSpawnsMod.class.getName());
    }

    @Override
    public List<StormClassTransformer> getClassTransformers() {
        if (!StormEnv.isStormServer()) {
            return Collections.emptyList();
        }
        return List.of(new PlayerSpawnsAllowZombieSafehousePatch());
    }
}
