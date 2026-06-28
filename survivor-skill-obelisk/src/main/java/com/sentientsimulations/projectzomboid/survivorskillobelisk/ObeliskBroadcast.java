package com.sentientsimulations.projectzomboid.survivorskillobelisk;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import se.krka.kahlua.vm.KahluaTable;
import zombie.Lua.LuaManager;
import zombie.network.GameServer;

/**
 * Pushes single-obelisk updates to every connected client so their map overlay stays live without a
 * full re-fetch. The reply commands match those the client listens for in {@code
 * SurvivorSkillObeliskMap.lua}.
 */
public final class ObeliskBroadcast {

    private static final String MODULE = "SurvivorSkillObelisk";
    private static final String UPDATED = "obeliskUpdated";
    private static final String REMOVED = "obeliskRemoved";

    private ObeliskBroadcast() {}

    public static void obeliskUpdated(int x, int y, int z, String type) {
        try {
            KahluaTable args = LuaManager.platform.newTable();
            args.rawset("x", (double) x);
            args.rawset("y", (double) y);
            args.rawset("z", (double) z);
            args.rawset("type", type);
            GameServer.sendServerCommand(MODULE, UPDATED, args);
        } catch (Throwable t) {
            LOGGER.error(
                    "[SurvivorSkillObelisk] obeliskUpdated broadcast failed at ({}, {}, {}) -> {}",
                    x,
                    y,
                    z,
                    type,
                    t);
        }
    }

    public static void obeliskRemoved(int x, int y, int z) {
        try {
            KahluaTable args = LuaManager.platform.newTable();
            args.rawset("x", (double) x);
            args.rawset("y", (double) y);
            args.rawset("z", (double) z);
            GameServer.sendServerCommand(MODULE, REMOVED, args);
        } catch (Throwable t) {
            LOGGER.error(
                    "[SurvivorSkillObelisk] obeliskRemoved broadcast failed at ({}, {}, {})",
                    x,
                    y,
                    z,
                    t);
        }
    }
}
