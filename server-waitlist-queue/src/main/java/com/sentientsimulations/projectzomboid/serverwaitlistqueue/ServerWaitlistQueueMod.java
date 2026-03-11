package com.sentientsimulations.projectzomboid.serverwaitlistqueue;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import io.pzstorm.storm.core.StormClassTransformer;
import io.pzstorm.storm.mod.ZomboidMod;
import io.pzstorm.storm.util.StormEnv;
import java.util.Collections;
import java.util.List;

public class ServerWaitlistQueueMod implements ZomboidMod {

    @Override
    public void registerEventHandlers() {
        if (StormEnv.isStormServer()) {
            LOGGER.info("Server Waitlist Queue mod loaded");
        } else {
            LOGGER.info("Server Waitlist Queue mod skipped (client mode)");
        }
    }

    @Override
    public List<StormClassTransformer> getClassTransformers() {
        if (!StormEnv.isStormServer()) {
            return Collections.emptyList();
        }
        return List.of(new GameServerPatch());
    }
}
