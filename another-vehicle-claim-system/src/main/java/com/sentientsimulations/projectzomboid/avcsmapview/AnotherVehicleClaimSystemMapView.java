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
        if (StormEnv.isStormServer()) {
            StormEventDispatcher.registerEventHandler(AvcsAdminVehicleTeleport.class);
            registerPreSaveLocationSync();
        }
    }

    // OnPreSaveEvent arrived in Storm 2.6.14; an older server must keep the rest of the mod working
    private static void registerPreSaveLocationSync() {
        try {
            Class.forName(
                    "io.pzstorm.storm.event.zomboid.OnPreSaveEvent",
                    false,
                    AnotherVehicleClaimSystemMapView.class.getClassLoader());
        } catch (ClassNotFoundException e) {
            LOGGER.warn(
                    "Storm has no OnPreSaveEvent (needs 2.6.14+); AVCS startup/pre-save vehicle location"
                            + " sync disabled");
            return;
        }
        StormEventDispatcher.registerEventHandler(AvcsVehicleLocationSync.class);
    }

    @Override
    public List<StormClassTransformer> getClassTransformers() {
        if (!StormEnv.isStormServer()) {
            return Collections.emptyList();
        }
        return List.of(new LuaEventManagerVehicleRemovePatch(), new BaseVehicleProcessHitPatch());
    }
}
