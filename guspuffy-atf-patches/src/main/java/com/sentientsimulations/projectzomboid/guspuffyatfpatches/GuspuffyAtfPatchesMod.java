package com.sentientsimulations.projectzomboid.guspuffyatfpatches;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import io.pzstorm.storm.core.StormClassTransformer;
import io.pzstorm.storm.mod.ZomboidMod;
import io.pzstorm.storm.util.StormEnv;
import java.util.Collections;
import java.util.List;

public class GuspuffyAtfPatchesMod implements ZomboidMod {

    @Override
    public void registerEventHandlers() {
        if (!StormEnv.isStormServer()) {
            return;
        }
        LOGGER.debug(
                "[GuspuffyAtfPatches] Registering for {}", GuspuffyAtfPatchesMod.class.getName());
    }

    @Override
    public List<StormClassTransformer> getClassTransformers() {
        return Collections.emptyList();
    }
}
