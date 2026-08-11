package com.sentientsimulations.projectzomboid.zonemarker;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import com.sentientsimulations.projectzomboid.zonemarker.records.ZoneCategoryRecord;
import com.sentientsimulations.projectzomboid.zonemarker.records.ZoneRecord;
import io.pzstorm.storm.event.core.SubscribeEvent;
import io.pzstorm.storm.event.lua.OnTickEvent;
import io.pzstorm.storm.util.StormEnv;
import java.io.File;
import java.sql.SQLException;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.ConcurrentLinkedQueue;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.function.Supplier;
import se.krka.kahlua.vm.KahluaTable;
import zombie.Lua.LuaManager;
import zombie.ZomboidFileSystem;
import zombie.characters.IsoPlayer;
import zombie.network.GameServer;

/**
 * DB and network bridge for zone-marker.
 *
 * <p>Command handling is split across two threads to keep SQLite I/O off the server main thread
 * (same pattern as the obelisk mod's ListDeathsHandler):
 *
 * <ol>
 *   <li>The {@code *Async} entry points run on the main thread and enqueue the op on {@link
 *       #PENDING}.
 *   <li>A single daemon worker thread blocks on {@link #PENDING}, runs the mutation and reloads the
 *       full zone state as plain records, and pushes a {@link Completed} onto {@link #COMPLETED}.
 *   <li>{@link #onTick} runs on the main thread every tick, drains {@link #COMPLETED}, builds the
 *       {@code KahluaTable} sync payload, and ships it via {@link GameServer#sendServerCommand}.
 * </ol>
 *
 * Kahlua tables and {@code sendServerCommand} are not thread-safe, so all Lua construction stays on
 * the main thread; the worker only touches plain Java records. The single FIFO worker also
 * preserves the old sync path's write ordering.
 */
public final class ZoneMarkerBridge {

    static final String MODULE = "ZoneMarker";
    private static final String DB_FILENAME = "zone_marker.db";

    /** Full zone state as plain records, loaded on the worker. */
    private record SyncData(
            List<ZoneCategoryRecord> categories, Map<String, List<ZoneRecord>> zonesByCategory) {}

    /** A sync payload ready to send; {@code replyTo} null means broadcast to all clients. */
    private record Completed(IsoPlayer replyTo, SyncData data) {}

    private static final BlockingQueue<Runnable> PENDING = new LinkedBlockingQueue<>();
    private static final ConcurrentLinkedQueue<Completed> COMPLETED = new ConcurrentLinkedQueue<>();
    private static final AtomicBoolean WORKER_STARTED = new AtomicBoolean();

    private ZoneMarkerBridge() {}

    static String getDbPath() {
        File dbFile = ZomboidFileSystem.instance.getFileInCurrentSave(DB_FILENAME);
        String path = dbFile.getAbsolutePath();
        LOGGER.info("[ZoneMarker] DB path: {}", path);
        return path;
    }

    // ---- Async entry points (validated on the game thread, DB work on the worker) ----

    public static void addCategoryAsync(String name, double r, double g, double b, double a) {
        mutateThenBroadcast("addCategory", () -> addCategory(name, r, g, b, a));
    }

    public static void removeCategoryAsync(String name) {
        mutateThenBroadcast("removeCategory", () -> removeCategory(name));
    }

    public static void addZoneAsync(
            String categoryName,
            double xStart,
            double yStart,
            double xEnd,
            double yEnd,
            String region) {
        mutateThenBroadcast(
                "addZone", () -> addZone(categoryName, xStart, yStart, xEnd, yEnd, region));
    }

    public static void removeZoneAsync(String categoryName, String region) {
        mutateThenBroadcast("removeZone", () -> removeZone(categoryName, region));
    }

    /** Queue a full-state read; the payload goes only to the requesting player. */
    public static void syncToPlayerAsync(IsoPlayer player) {
        submit(
                () -> {
                    SyncData data = loadSyncData();
                    if (data != null) {
                        COMPLETED.offer(new Completed(player, data));
                    }
                });
    }

    /**
     * Worker-side wrapper for the four mutations: on success reload the zone state and queue a
     * broadcast; on failure just log (the old sync path gave the client no error feedback either).
     */
    private static void mutateThenBroadcast(String opName, Supplier<String> mutation) {
        submit(
                () -> {
                    String error = mutation.get();
                    if (error != null) {
                        LOGGER.warn("[ZoneMarker] {} failed: {}", opName, error);
                        return;
                    }
                    LOGGER.info("[ZoneMarker] {} succeeded, queueing broadcast", opName);
                    SyncData data = loadSyncData();
                    if (data != null) {
                        COMPLETED.offer(new Completed(null, data));
                    }
                });
    }

    private static void submit(Runnable dbOp) {
        if (WORKER_STARTED.compareAndSet(false, true)) {
            Thread worker = new Thread(ZoneMarkerBridge::workerLoop, "ZoneMarker-DbWorker");
            worker.setDaemon(true);
            worker.start();
        }
        PENDING.offer(dbOp);
    }

    private static void workerLoop() {
        while (true) {
            Runnable op;
            try {
                op = PENDING.take();
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                return;
            }
            try {
                op.run();
            } catch (Throwable t) {
                LOGGER.error("[ZoneMarker] DB worker op failed", t);
            }
        }
    }

    /** Game-thread drain: builds the Kahlua sync payload and sends it. */
    @SubscribeEvent
    public static void onTick(OnTickEvent event) {
        if (!StormEnv.isStormServer()) {
            return;
        }
        Completed done;
        while ((done = COMPLETED.poll()) != null) {
            try {
                KahluaTable args = buildSyncTable(done.data());
                if (done.replyTo() == null) {
                    LOGGER.info("[ZoneMarker] Broadcasting sync table to all clients");
                    GameServer.sendServerCommand(MODULE, "sync", args);
                } else {
                    // If the player disconnected while the read was in-flight, sendServerCommand
                    // is a no-op (it gates on PlayerToAddressMap).
                    LOGGER.info(
                            "[ZoneMarker] Sending sync table to player {}",
                            done.replyTo().getUsername());
                    GameServer.sendServerCommand(done.replyTo(), MODULE, "sync", args);
                }
            } catch (Throwable t) {
                LOGGER.error("[ZoneMarker] Failed to send sync payload", t);
            }
        }
    }

    // ---- Worker-side DB ops ----

    /**
     * @return null on success, or an error message
     */
    static String addCategory(String name, double r, double g, double b, double a) {
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
    static String removeCategory(String name) {
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

    /**
     * @return null on success, or an error message
     */
    static String addZone(
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
    static String removeZone(String categoryName, String region) {
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

    private static SyncData loadSyncData() {
        try (ZoneMarkerDatabase db = new ZoneMarkerDatabase(getDbPath())) {
            ZoneMarkerRepository repo = new ZoneMarkerRepository(db.getConnection());
            List<ZoneCategoryRecord> categories = repo.loadAllCategories();
            Map<String, List<ZoneRecord>> zonesByCategory = new LinkedHashMap<>();
            for (ZoneCategoryRecord cat : categories) {
                zonesByCategory.put(cat.name(), repo.loadZonesByCategoryName(cat.name()));
            }
            LOGGER.info("[ZoneMarker] loadSyncData: loaded {} categories", categories.size());
            return new SyncData(categories, zonesByCategory);
        } catch (SQLException e) {
            LOGGER.error("[ZoneMarker] Failed to load zone data for sync", e);
            return null;
        }
    }

    /**
     * Build a KahluaTable matching the existing client wire format:
     *
     * <pre>{ categories = [{name, r, g, b, a}, ...],
     *   zones = { [catName] = [{xStart, yStart, xEnd, yEnd, region}, ...] } }</pre>
     */
    private static KahluaTable buildSyncTable(SyncData data) {
        KahluaTable args = LuaManager.platform.newTable();
        KahluaTable catsTable = LuaManager.platform.newTable();
        KahluaTable zonesTable = LuaManager.platform.newTable();

        int idx = 1;
        for (ZoneCategoryRecord cat : data.categories()) {
            KahluaTable catEntry = LuaManager.platform.newTable();
            catEntry.rawset("name", cat.name());
            catEntry.rawset("r", cat.r());
            catEntry.rawset("g", cat.g());
            catEntry.rawset("b", cat.b());
            catEntry.rawset("a", cat.a());
            catsTable.rawset(idx++, catEntry);

            List<ZoneRecord> zones = data.zonesByCategory().getOrDefault(cat.name(), List.of());
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
