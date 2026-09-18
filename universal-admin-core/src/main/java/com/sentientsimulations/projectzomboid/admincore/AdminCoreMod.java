package com.sentientsimulations.projectzomboid.admincore;

import io.pzstorm.storm.core.StormClassTransformer;
import io.pzstorm.storm.event.core.StormEventDispatcher;
import io.pzstorm.storm.event.core.SubscribeEvent;
import io.pzstorm.storm.event.zomboid.OnZomboidGlobalsLoadEvent;
import io.pzstorm.storm.mod.ZomboidMod;
import io.pzstorm.storm.util.StormEnv;
import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import zombie.Lua.LuaManager;

public final class AdminCoreMod implements ZomboidMod {
    private static final Logger LOGGER = LoggerFactory.getLogger(AdminCoreMod.class);

    @Override
    public void registerEventHandlers() {
        StormEventDispatcher.registerEventHandler(AdminCoreMod.class);
    }

    @Override
    public List<StormClassTransformer> getClassTransformers() {
        return StormEnv.isStormServer() ? List.of() : List.of(new AdminCoreObservePatch());
    }

    @SubscribeEvent
    public static void expose(OnZomboidGlobalsLoadEvent event) {
        if (!StormEnv.isStormServer()) {
            LuaManager.exposer.setExposed(AdminCoreObserveCamera.class);
            LuaManager.exposer.exposeLikeJavaRecursively(
                    AdminCoreObserveCamera.class, LuaManager.env);
            return;
        }
        LuaManager.exposer.setExposed(AdminCoreBridge.class);
        LuaManager.exposer.exposeLikeJavaRecursively(AdminCoreBridge.class, LuaManager.env);
        LOGGER.info("[Universal Admin Core] Server bridge exposed.");
    }
}
