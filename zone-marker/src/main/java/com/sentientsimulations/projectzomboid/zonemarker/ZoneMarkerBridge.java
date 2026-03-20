package com.sentientsimulations.projectzomboid.zonemarker;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import java.io.File;
import java.sql.SQLException;
import java.util.List;

import com.sentientsimulations.projectzomboid.zonemarker.records.ZoneCategoryRecord;
import com.sentientsimulations.projectzomboid.zonemarker.records.ZoneRecord;
import se.krka.kahlua.vm.KahluaTable;
import zombie.Lua.LuaManager;
import zombie.ZomboidFileSystem;
import zombie.characters.IsoPlayer;
import zombie.network.GameServer;

public final class ZoneMarkerBridge {

    static final String MODULE = "ZoneMarker";
    private static final String DB_FILENAME = "zone_marker.db";

    private ZoneMarkerBridge() {}

    static String getDbPath() {
        File dbFile = ZomboidFileSystem.instance.getFileInCurrentSave(DB_FILENAME);
        return dbFile.getAbsolutePath();
    }

    // ---- Category operations ----

    /**
     * @return null on success, or an error message
     */
    public static String addCategory(String name, double r, double g, double b, double a) {
        try (ZoneMarkerDatabase db = new ZoneMarkerDatabase(getDbPath())) {
            ZoneMarkerRepository repo = new ZoneMarkerRepository(db.getConnection());
            if (repo.categoryExists(name)) {
                return "Category '" + name + "' already exists.";
            }
            repo.insertCategory(name, r, g, b, a);
            return null;
        } catch (SQLException e) {
            LOGGER.error("Failed to add category '{}'", name, e);
            return "Database error adding category.";
        }
    }

    /**
     * @return null on success, or an error message
     */
    public static String removeCategory(String name) {
        try (ZoneMarkerDatabase db = new ZoneMarkerDatabase(getDbPath())) {
            ZoneMarkerRepository repo = new ZoneMarkerRepository(db.getConnection());
            if (!repo.deleteCategoryByName(name)) {
                return "Category '" + name + "' not found.";
            }
            return null;
        } catch (SQLException e) {
            LOGGER.error("Failed to remove category '{}'", name, e);
            return "Database error removing category.";
        }
    }

    // ---- Zone operations ----

    /**
     * @return null on success, or an error message
     */
    public static String addZone(
            String categoryName,
            double xStart,
            double yStart,
            double xEnd,
            double yEnd,
            String region) {
        try (ZoneMarkerDatabase db = new ZoneMarkerDatabase(getDbPath())) {
            ZoneMarkerRepository repo = new ZoneMarkerRepository(db.getConnection());
            repo.insertZone(categoryName, xStart, yStart, xEnd, yEnd, region);
            return null;
        } catch (SQLException e) {
            LOGGER.error("Failed to add zone '{}' to '{}'", region, categoryName, e);
            return "Database error adding zone.";
        }
    }

    /**
     * @return null on success, or an error message
     */
    public static String removeZone(String categoryName, String region) {
        try (ZoneMarkerDatabase db = new ZoneMarkerDatabase(getDbPath())) {
            ZoneMarkerRepository repo = new ZoneMarkerRepository(db.getConnection());
            int removed = repo.deleteZonesByRegion(categoryName, region);
            if (removed == 0) {
                return "Zone '" + region + "' not found in " + categoryName + ".";
            }
            return null;
        } catch (SQLException e) {
            LOGGER.error("Failed to remove zone '{}' from '{}'", region, categoryName, e);
            return "Database error removing zone.";
        }
    }

    // ---- Query operations ----

    public static boolean categoryExists(String name) {
        try (ZoneMarkerDatabase db = new ZoneMarkerDatabase(getDbPath())) {
            ZoneMarkerRepository repo = new ZoneMarkerRepository(db.getConnection());
            return repo.categoryExists(name);
        } catch (SQLException e) {
            LOGGER.error("Failed to check category '{}'", name, e);
            return false;
        }
    }

    public static List<ZoneCategoryRecord> listCategories() {
        try (ZoneMarkerDatabase db = new ZoneMarkerDatabase(getDbPath())) {
            ZoneMarkerRepository repo = new ZoneMarkerRepository(db.getConnection());
            return repo.loadAllCategories();
        } catch (SQLException e) {
            LOGGER.error("Failed to list categories", e);
            return List.of();
        }
    }

    public static List<ZoneRecord> listZonesInCategory(String categoryName) {
        try (ZoneMarkerDatabase db = new ZoneMarkerDatabase(getDbPath())) {
            ZoneMarkerRepository repo = new ZoneMarkerRepository(db.getConnection());
            return repo.loadZonesByCategoryName(categoryName);
        } catch (SQLException e) {
            LOGGER.error("Failed to list zones in '{}'", categoryName, e);
            return List.of();
        }
    }

    // ---- Network ----

    /** Broadcast full zone data to all connected clients. */
    public static void broadcast() {
        try {
            KahluaTable args = buildSyncTable();
            GameServer.sendServerCommand(MODULE, "sync", args);
        } catch (SQLException e) {
            LOGGER.error("Failed to broadcast zone data", e);
        }
    }

    /** Send full zone data to a single player (for requestSync). */
    static void syncToPlayer(IsoPlayer player) {
        try {
            KahluaTable args = buildSyncTable();
            GameServer.sendServerCommand(player, MODULE, "sync", args);
        } catch (SQLException e) {
            LOGGER.error("Failed to sync zone data to player", e);
        }
    }

    /**
     * Build a KahluaTable matching the existing client wire format:
     *
     * <pre>{ categories = [{name, r, g, b, a}, ...],
     *   zones = { [catName] = [{xStart, yStart, xEnd, yEnd, region}, ...] } }</pre>
     */
    private static KahluaTable buildSyncTable() throws SQLException {
        try (ZoneMarkerDatabase db = new ZoneMarkerDatabase(getDbPath())) {
            ZoneMarkerRepository repo = new ZoneMarkerRepository(db.getConnection());
            List<ZoneCategoryRecord> categories = repo.loadAllCategories();

            KahluaTable args = LuaManager.platform.newTable();
            KahluaTable catsTable = LuaManager.platform.newTable();
            KahluaTable zonesTable = LuaManager.platform.newTable();

            int idx = 1;
            for (ZoneCategoryRecord cat : categories) {
                KahluaTable catEntry = LuaManager.platform.newTable();
                catEntry.rawset("name", cat.name());
                catEntry.rawset("r", cat.r());
                catEntry.rawset("g", cat.g());
                catEntry.rawset("b", cat.b());
                catEntry.rawset("a", cat.a());
                catsTable.rawset(idx++, catEntry);

                List<ZoneRecord> zones = repo.loadZonesByCategoryName(cat.name());
                KahluaTable zoneArray = LuaManager.platform.newTable();
                int zIdx = 1;
                for (ZoneRecord z : zones) {
                    KahluaTable zoneEntry = LuaManager.platform.newTable();
                    zoneEntry.rawset("xStart", z.xStart());
                    zoneEntry.rawset("yStart", z.yStart());
                    zoneEntry.rawset("xEnd", z.xEnd());
                    zoneEntry.rawset("yEnd", z.yEnd());
                    zoneEntry.rawset("region", z.region());
                    zoneArray.rawset(zIdx++, zoneEntry);
                }
                zonesTable.rawset(cat.name(), zoneArray);
            }

            args.rawset("categories", catsTable);
            args.rawset("zones", zonesTable);
            return args;
        }
    }

    // ---- Utilities (moved from ZoneModDataHelper) ----

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
