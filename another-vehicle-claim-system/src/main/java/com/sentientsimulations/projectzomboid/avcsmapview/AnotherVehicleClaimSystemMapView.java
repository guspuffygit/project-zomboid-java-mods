package com.sentientsimulations.projectzomboid.avcsmapview;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import io.pzstorm.storm.core.StormClassTransformer;
import io.pzstorm.storm.event.core.StormEventDispatcher;
import io.pzstorm.storm.mod.ZomboidMod;
import io.pzstorm.storm.util.StormEnv;
import java.util.Collections;
import java.util.List;

public class AnotherVehicleClaimSystemMapView implements ZomboidMod {

    @Override
    public void registerEventHandlers() {
        LOGGER.debug("Registering event handler for {}", getClass().getName());
        StormEventDispatcher.registerEventHandler(this);
        StormEventDispatcher.registerEventHandler(AvcsSteamIdApiLuaExposerHandler.class);
    }

    @Override
    public List<StormClassTransformer> getClassTransformers() {
        if (!StormEnv.isStormServer()) {
            return Collections.emptyList();
        }
        return List.of(new LuaEventManagerVehicleRemovePatch());
    }
}
