package com.sentientsimulations.projectzomboid.admincore;

import io.pzstorm.storm.event.core.StormEventDispatcher;
import io.pzstorm.storm.event.core.SubscribeEvent;
import io.pzstorm.storm.event.zomboid.OnZomboidGlobalsLoadEvent;
import io.pzstorm.storm.mod.ZomboidMod;
import io.pzstorm.storm.util.StormEnv;
import zombie.Lua.LuaManager;

public final class AdminCoreMod implements ZomboidMod {
    public void registerEventHandlers() {
        StormEventDispatcher.registerEventHandler(AdminCoreMod.class);
    }

    public java.util.List<io.pzstorm.storm.core.StormClassTransformer> getClassTransformers() {
        return StormEnv.isStormServer()
                ? java.util.List.of()
                : java.util.List.of(new AdminCoreObservePatch());
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
        System.out.println("[Universal Admin Core] Server bridge exposed.");
    }
}
