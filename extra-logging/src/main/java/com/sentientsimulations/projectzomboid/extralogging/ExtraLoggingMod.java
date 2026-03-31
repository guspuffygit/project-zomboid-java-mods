package com.sentientsimulations.projectzomboid.extralogging;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import com.sentientsimulations.projectzomboid.extralogging.patch.*;
import io.pzstorm.storm.core.StormClassTransformer;
import io.pzstorm.storm.event.core.StormEventDispatcher;
import io.pzstorm.storm.mod.ZomboidMod;
import io.pzstorm.storm.util.StormEnv;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

public class ExtraLoggingMod implements ZomboidMod {

    @Override
    public void registerEventHandlers() {
        if (StormEnv.isStormServer()) {
            LOGGER.debug("Registering event handler for {}", DeathLogWriter.class.getName());
            StormEventDispatcher.registerEventHandler(DeathLogWriter.class);
            LOGGER.debug("Registering event handler for {}", ItemEventHandler.class.getName());
            StormEventDispatcher.registerEventHandler(ItemEventHandler.class);
            LOGGER.debug("Registering event handler for {}", SafehouseEventHandler.class.getName());
            StormEventDispatcher.registerEventHandler(SafehouseEventHandler.class);
        }
    }

    @Override
    public List<StormClassTransformer> getClassTransformers() {
        if (!StormEnv.isStormServer()) {
            return Collections.emptyList();
        }

        List<StormClassTransformer> transformers = new ArrayList<>();
        transformers.add(new AddItemToMapPatch());
        transformers.add(new ItemTransactionPatch());
        transformers.add(new PlayerDropHeldItemsPatch());
        transformers.add(new SafehouseAcceptPatch());
        transformers.add(new SafehouseChangeMemberPatch());
        transformers.add(new SafehouseChangeOwnerPatch());
        transformers.add(new SafehouseClaimPatch());
        transformers.add(new SafehouseInvitePatch());
        transformers.add(new SafehouseReleasePatch());
        transformers.add(new SafezoneClaimPatch());
        transformers.add(new ServerWorldDatabasePatch());
        transformers.add(new GameServerPatch());

        return transformers;
    }
}
