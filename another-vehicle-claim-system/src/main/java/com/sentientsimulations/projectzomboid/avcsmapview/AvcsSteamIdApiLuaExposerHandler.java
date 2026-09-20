package com.sentientsimulations.projectzomboid.avcsmapview;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import io.pzstorm.storm.event.core.SubscribeEvent;
import io.pzstorm.storm.event.zomboid.OnZomboidGlobalsLoadEvent;
import io.pzstorm.storm.util.StormEnv;
import zombie.Lua.LuaManager;

/**
 * Exposes {@link AvcsSteamIdApi} to the server-Lua VM. Skipped on the client JVM because the caller
 * — the parking-fine command handler — only runs server-side.
 *
 * <p>{@link LuaManager.Exposer#exposeLikeJavaRecursively} is a silent no-op for any class that was
 * never passed to {@link LuaManager.Exposer#setExposed(Class)}, so both calls are required.
 */
public final class AvcsSteamIdApiLuaExposerHandler {

    private AvcsSteamIdApiLuaExposerHandler() {}

    @SubscribeEvent
    public static void onZomboidGlobalsLoad(OnZomboidGlobalsLoadEvent event) {
        if (!StormEnv.isStormServer()) {
            return;
        }
        LuaManager.exposer.setExposed(AvcsSteamIdApi.class);
        LuaManager.exposer.exposeLikeJavaRecursively(AvcsSteamIdApi.class, LuaManager.env);
        if (LuaManager.env.rawget("AvcsSteamIdApi") == null) {
            LOGGER.error(
                    "AvcsSteamIdApi did not land in the server Lua env — parking-fine bypass will"
                            + " fall back to admin-only");
        }
    }
}
