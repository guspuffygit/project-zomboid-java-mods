package com.sentientsimulations.projectzomboid.survivorskillobelisk;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import io.pzstorm.storm.event.core.SubscribeEvent;
import io.pzstorm.storm.event.zomboid.OnZomboidGlobalsLoadEvent;
import io.pzstorm.storm.util.StormEnv;
import zombie.Lua.LuaManager;

/**
 * Exposes {@link SurvivorSkillObeliskApi} to the server-Lua VM so {@code
 * SurvivorSkillObeliskDestroyGuard.lua} can consult the role policy and trigger the curse.
 *
 * <p>{@code LuaManager.Exposer#exposeLikeJavaRecursively} is a silent no-op for any class never
 * passed to {@code setExposed(Class)} first — both calls are required. The handler verifies the
 * global actually landed: if it didn't, the Lua guard still blocks obelisk removal (protection
 * fails closed) but cannot exempt admins or deliver the curse.
 */
public final class SurvivorSkillObeliskApiLuaExposerHandler {

    private SurvivorSkillObeliskApiLuaExposerHandler() {}

    @SubscribeEvent
    public static void onZomboidGlobalsLoad(OnZomboidGlobalsLoadEvent event) {
        if (!StormEnv.isStormServer()) {
            return;
        }
        LuaManager.exposer.setExposed(SurvivorSkillObeliskApi.class);
        LuaManager.exposer.exposeLikeJavaRecursively(SurvivorSkillObeliskApi.class, LuaManager.env);
        if (LuaManager.env.rawget("SurvivorSkillObeliskApi") == null) {
            LOGGER.error(
                    "[SurvivorSkillObelisk] SurvivorSkillObeliskApi did not land in the server Lua"
                            + " env — obelisk destroy attempts will be blocked but not cursed");
        } else {
            LOGGER.info("[SurvivorSkillObelisk] Exposed SurvivorSkillObeliskApi to server Lua VM");
        }
    }
}
