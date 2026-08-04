package com.sentientsimulations.projectzomboid.jumpscarebanatfeconomy;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import io.pzstorm.storm.event.core.StormEventDispatcher;
import io.pzstorm.storm.mod.ZomboidMod;
import io.pzstorm.storm.util.StormEnv;

public class JumpscareBanAtfEconomyMod implements ZomboidMod {

    @Override
    public void registerEventHandlers() {
        if (!StormEnv.isStormServer()) {
            return;
        }
        LOGGER.info("[JumpscareBanEconomy] Registering event handlers");
        StormEventDispatcher.registerEventHandler(PurchaseGagHandler.class);
    }
}
