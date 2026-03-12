package com.sentientsimulations.projectzomboid.mapmetasqlite;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import io.pzstorm.storm.core.StormClassTransformer;
import io.pzstorm.storm.mod.ZomboidMod;
import java.util.Collections;
import java.util.List;

public class MapMetaSqliteMod implements ZomboidMod {

    @Override
    public void registerEventHandlers() {
        LOGGER.info("Map Meta SQLite mod loaded");
    }

    @Override
    public List<StormClassTransformer> getClassTransformers() {
        return Collections.emptyList();
    }
}
