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
        StormEventDispatcher.registerEventHandler(SurvivorSkillObeliskSandboxApplier.class);
        StormEventDispatcher.registerEventHandler(ListDeathsHandler.class);
        StormEventDispatcher.registerEventHandler(RecoverSkillsHandler.class);
        StormEventDispatcher.registerEventHandler(SetObeliskTypeHandler.class);
        StormEventDispatcher.registerEventHandler(GetObeliskTypeHandler.class);
        StormEventDispatcher.registerEventHandler(ObeliskLifecycleHandler.class);
        StormEventDispatcher.registerEventHandler(ListAllObelisksHandler.class);
        StormEventDispatcher.registerEventHandler(SyncLearnedSongsHandler.class);
        StormEventDispatcher.registerEventHandler(SyncHiddenSkillsHandler.class);
        StormEventDispatcher.registerEventHandler(SyncAmbitionsHandler.class);
        StormEventDispatcher.registerEventHandler(CharacterBaselineHandler.class);
    }

    @SubscribeEvent
    public void onCharacterDeath(OnCharacterDeathEvent event) {
        DeathEventHandler.onCharacterDeath(event);
    }
}
