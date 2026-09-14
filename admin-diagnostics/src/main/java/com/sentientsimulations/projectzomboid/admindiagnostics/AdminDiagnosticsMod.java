package com.sentientsimulations.projectzomboid.admindiagnostics;

import io.pzstorm.storm.event.core.StormEventDispatcher;
import io.pzstorm.storm.event.core.SubscribeEvent;
import io.pzstorm.storm.event.zomboid.OnZomboidGlobalsLoadEvent;
import io.pzstorm.storm.mod.ZomboidMod;
import io.pzstorm.storm.util.StormEnv;
import zombie.Lua.LuaManager;

/** Optional read-only client measurements; no transformers or server handlers. */
public final class AdminDiagnosticsMod implements ZomboidMod {
    public void registerEventHandlers() {
        StormEventDispatcher.registerEventHandler(AdminDiagnosticsMod.class);
    }

    @SubscribeEvent
    public static void expose(OnZomboidGlobalsLoadEvent event) {
        if (StormEnv.isStormServer()) return;
        LuaManager.exposer.setExposed(AdminDiagnosticsProbe.class);
        LuaManager.exposer.exposeLikeJavaRecursively(AdminDiagnosticsProbe.class, LuaManager.env);
    }
}
