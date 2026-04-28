package com.sentientsimulations.projectzomboid.jumpscareban;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import io.pzstorm.storm.core.StormClassTransformer;
import io.pzstorm.storm.mod.ZomboidMod;
import io.pzstorm.storm.util.StormEnv;
import java.util.Collections;
import java.util.List;

public class JumpscareBanMod implements ZomboidMod {

    @Override
    public void registerEventHandlers() {
        if (StormEnv.isStormServer()) {
            LOGGER.info("Jumpscare Ban mod loaded (server)");
        } else {
            LOGGER.info("Jumpscare Ban mod loaded (client)");
        }
    }

    @Override
    public List<StormClassTransformer> getClassTransformers() {
        if (!StormEnv.isStormServer()) {
            return Collections.emptyList();
        }
        return List.of(new BanSystemPatch());
    }
}
