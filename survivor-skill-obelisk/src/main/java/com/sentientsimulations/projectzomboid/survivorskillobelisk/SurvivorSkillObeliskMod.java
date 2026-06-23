package com.sentientsimulations.projectzomboid.survivorskillobelisk;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import io.pzstorm.storm.event.core.StormEventDispatcher;
import io.pzstorm.storm.mod.ZomboidMod;

public class SurvivorSkillObeliskMod implements ZomboidMod {

    @Override
    public void registerEventHandlers() {
        LOGGER.info("[SurvivorSkillObelisk] Registering event handlers");
        StormEventDispatcher.registerEventHandler(this);
    }
}
