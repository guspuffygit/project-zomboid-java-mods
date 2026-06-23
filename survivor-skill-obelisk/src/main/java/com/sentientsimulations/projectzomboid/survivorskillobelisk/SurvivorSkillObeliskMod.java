package com.sentientsimulations.projectzomboid.survivorskillobelisk;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import io.pzstorm.storm.event.core.StormEventDispatcher;
import io.pzstorm.storm.event.core.SubscribeEvent;
import io.pzstorm.storm.event.lua.OnCharacterDeathEvent;
import io.pzstorm.storm.mod.ZomboidMod;
import io.pzstorm.storm.util.StormEnv;

public class SurvivorSkillObeliskMod implements ZomboidMod {

    @Override
    public void registerEventHandlers() {
        if (!StormEnv.isStormServer()) {
            return;
        }
        LOGGER.info("[SurvivorSkillObelisk] Registering event handlers");
        StormEventDispatcher.registerEventHandler(this);
    }

    @SubscribeEvent
    public void onCharacterDeath(OnCharacterDeathEvent event) {
        DeathEventHandler.onCharacterDeath(event);
    }
}
