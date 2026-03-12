package com.sentientsimulations.projectzomboid.mapmetasqlite;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import io.pzstorm.storm.core.StormClassTransformer;
import io.pzstorm.storm.mod.ZomboidMod;
import io.pzstorm.storm.util.StormEnv;
import java.util.Collections;
import java.util.List;

public class MapMetaSqliteMod implements ZomboidMod {

    @Override
    public void registerEventHandlers() {
        if (StormEnv.isStormServer()) {
            LOGGER.info("Map Meta SQLite mod loaded");
        } else {
            LOGGER.info("Map Meta SQLite mod skipped (client mode)");
        }
    }

    @Override
    public List<StormClassTransformer> getClassTransformers() {
        if (!StormEnv.isStormServer()) {
            return Collections.emptyList();
        }
        return List.of(new IsoMetaGridPatch());
    }
}
