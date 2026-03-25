package com.sentientsimulations.projectzomboid.extralogging;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import io.pzstorm.storm.event.core.StormEventDispatcher;
import io.pzstorm.storm.mod.ZomboidMod;
import io.pzstorm.storm.util.StormEnv;

public class ExtraLoggingMod implements ZomboidMod {

    @Override
    public void registerEventHandlers() {
        LOGGER.debug("Registering event handler for {}", getClass().getName());
        StormEventDispatcher.registerEventHandler(this);
    }
}
