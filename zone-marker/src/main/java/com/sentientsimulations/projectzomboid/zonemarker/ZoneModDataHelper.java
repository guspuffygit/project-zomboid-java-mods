package com.sentientsimulations.projectzomboid.zonemarker;

import se.krka.kahlua.vm.KahluaTable;
import zombie.Lua.LuaManager;
import zombie.network.GameServer;
import zombie.world.moddata.ModData;

/** Shared helpers for zone ModData manipulation across all zone commands. */
public final class ZoneModDataHelper {

    public static final String MODDATA_KEY = "ZoneMarker";

    private ZoneModDataHelper() {}

    /** Get or initialize the zone data table with categories and zones sub-tables. */
    public static KahluaTable getZoneData() {
        KahluaTable data = ModData.getOrCreate(MODDATA_KEY);
        if (data.rawget("categories") == null) {
            data.rawset("categories", LuaManager.platform.newTable());
        }
        if (data.rawget("zones") == null) {
            data.rawset("zones", LuaManager.platform.newTable());
        }
        return data;
    }

    public static final String MODULE = "ZoneMarker";

    /** Broadcast zone data to all connected clients via sendServerCommand. */
    public static void broadcast() {
        KahluaTable data = getZoneData();
        KahluaTable args = LuaManager.platform.newTable();
        args.rawset("categories", data.rawget("categories"));
        args.rawset("zones", data.rawget("zones"));
        GameServer.sendServerCommand(MODULE, "sync", args);
    }

    /**
     * Find a category by name in the categories array.
     *
     * @return 1-based index, or -1 if not found
     */
    public static int findCategoryIndex(KahluaTable categories, String name) {
        for (int i = 1; i <= categories.len(); i++) {
            KahluaTable cat = (KahluaTable) categories.rawget(i);
            if (cat != null && name.equals(cat.rawget("name"))) {
                return i;
            }
        }
        return -1;
    }

    /**
     * Remove element at 1-based index from a KahluaTable array, shifting subsequent elements down.
     */
    public static void removeArrayElement(KahluaTable array, int index) {
        int len = array.len();
        for (int i = index; i < len; i++) {
            array.rawset(i, array.rawget(i + 1));
        }
        array.rawset(len, null);
    }

    /** Parse a string as a Double, returning null on failure. */
    public static Double parseDouble(String s) {
        if (s == null) return null;
        try {
            return Double.parseDouble(s);
        } catch (NumberFormatException e) {
            return null;
        }
    }

    /** Join command args from startIdx (inclusive) to endIdx (exclusive). */
    public static String joinArgs(
            java.util.function.IntFunction<String> argGetter, int startIdx, int endIdx) {
        StringBuilder sb = new StringBuilder();
        for (int i = startIdx; i < endIdx; i++) {
            if (!sb.isEmpty()) {
                sb.append(" ");
            }
            sb.append(argGetter.apply(i));
        }
        return sb.toString();
    }
}
