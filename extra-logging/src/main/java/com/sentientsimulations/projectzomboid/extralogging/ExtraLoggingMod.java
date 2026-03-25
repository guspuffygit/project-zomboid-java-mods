package com.sentientsimulations.projectzomboid.extralogging;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import io.pzstorm.storm.event.core.StormEventDispatcher;
import io.pzstorm.storm.mod.ZomboidMod;

public class ExtraLoggingMod implements ZomboidMod {

    @Override
    public void registerEventHandlers() {
        LOGGER.info("Registering Extra Logging event handlers");
        StormEventDispatcher.registerEventHandler(DeathEventHandler.class);
        StormEventDispatcher.registerEventHandler(SafehouseEventHandler.class);
    }
}
