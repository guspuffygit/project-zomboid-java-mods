package com.sentientsimulations.projectzomboid.sensiblecommonsense;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import io.pzstorm.storm.event.core.StormEventDispatcher;
import io.pzstorm.storm.mod.ZomboidMod;
import java.util.*;

public class SensibleCommonSense implements ZomboidMod {

    @Override
    public void registerEventHandlers() {
        LOGGER.debug("Registering event handler for {}", getClass().getName());
        StormEventDispatcher.registerEventHandler(this);
    }
}
