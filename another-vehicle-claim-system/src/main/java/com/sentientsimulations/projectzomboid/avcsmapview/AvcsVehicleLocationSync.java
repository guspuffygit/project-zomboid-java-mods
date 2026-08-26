package com.sentientsimulations.projectzomboid.avcsmapview;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import com.sentientsimulations.projectzomboid.avcsmapview.VehiclesDbLocations.Position;
import com.sentientsimulations.projectzomboid.avcsmapview.VehiclesDbLocations.VerifiedRead;
import io.pzstorm.storm.event.core.SubscribeEvent;
import io.pzstorm.storm.event.lua.OnTickEvent;
import io.pzstorm.storm.event.zomboid.OnPreSaveEvent;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.function.Consumer;
import java.util.function.Function;
import java.util.function.Supplier;
import se.krka.kahlua.vm.KahluaTable;
import se.krka.kahlua.vm.KahluaTableIterator;
import zombie.Lua.LuaManager;
import zombie.iso.IsoCell;
import zombie.iso.IsoWorld;
import zombie.network.GameServer;
import zombie.vehicles.BaseVehicle;
import zombie.world.moddata.GlobalModData;

/**
 * On the first server tick and before every server save, refreshes {@code LastLocationX/Y} of every
 * claim in the {@code AVCSByVehicleSQLID} global mod data table so the Lua DB (and the managers/map
 * reading it) matches where the vehicles actually are.
 *
 * <p>AVCS's own Lua only learns a position when {@code Vehicles.LowerCondition} fires for a loaded
 * vehicle, so claims drift whenever a car moves without that hook (towing, admin teleport, a crash
 * after {@code vehicles.db} was committed but before the next {@code GlobalModData} save). Loaded
 * vehicles contribute their live position; everything else comes from {@code vehicles.db}.
 *
 * <p>Vanilla hands out the lowest free sqlId, so a destroyed car's id comes back on a new one and
 * an orphaned claim can alias a stranger's vehicle. Three guards: when several claims decode to the
 * same sqlId only the newest (largest timestamp prefix) is refreshed; a loaded vehicle whose
 * imprinted claim key (modData, with the mule-part fallback) is not exactly the claim's key leaves
 * the claim untouched; and an unloaded vehicle's {@code vehicles.db} row only counts when its data
 * blob carries the claim key ({@link VehiclesDbLocations#readVerified}).
 */
public final class AvcsVehicleLocationSync {

    private static final AtomicBoolean STARTUP_SYNC_DONE = new AtomicBoolean();

    static final String MOD_DATA_TABLE = "AVCSByVehicleSQLID";
    static final String MODULE = "AVCS";
    static final String BATCH_COMMAND = "updateClientVehicleCoordinates";
    static final int BATCH_SIZE = 100;

    static final String KEY_X = "LastLocationX";
    static final String KEY_Y = "LastLocationY";
    static final String KEY_UPDATED = "LastLocationUpdateDateTime";
    static final String KEY_VEHICLE_ID = "VehicleID";
    static final String MOD_DATA_SQLID = "SQLID";

    record LiveVehicle(Object claimKey, float x, float y) {}

    record Result(
            int claims,
            int undecodable,
            int live,
            int fromDb,
            int stale,
            int unverifiedDb,
            int missing,
            int changed) {}

    private record Claim(Object key, int sqlId, KahluaTable entry) {}

    private AvcsVehicleLocationSync() {}

    @SubscribeEvent
    public static void onPreSave(OnPreSaveEvent event) {
        runSync("pre-save (quit=" + event.isQuit() + ")");
    }

    /**
     * Runs once, on the first server tick, so the db is right from boot and not only from the first
     * save.
     */
    @SubscribeEvent
    public static void onFirstTick(OnTickEvent event) {
        if (!STARTUP_SYNC_DONE.get() && runSync("startup")) {
            STARTUP_SYNC_DONE.set(true);
        }
    }

    /**
     * Returns false when there was nothing to sync against (not a server, or no AVCS table yet).
     */
    private static boolean runSync(String reason) {
        if (!GameServer.server) {
            return false;
        }
        KahluaTable db = GlobalModData.instance.get(MOD_DATA_TABLE);
        if (db == null) {
            return false;
        }
        long start = System.nanoTime();
        try {
            Result result =
                    sync(
                            db,
                            liveVehicles(),
                            VehiclesDbLocations::readVerifiedFromCurrentSave,
                            LuaManager.platform::newTable,
                            AvcsVehicleLocationSync::broadcast,
                            System.currentTimeMillis() / 1000L);
            LOGGER.debug(
                    "AVCS {} location sync: {} in {} ms",
                    reason,
                    result,
                    (System.nanoTime() - start) / 1_000_000L);
        } catch (RuntimeException e) {
            LOGGER.error("AVCS {} location sync failed", reason, e);
        }
        return true;
    }

    static Map<Integer, LiveVehicle> liveVehicles() {
        IsoCell cell = IsoWorld.instance == null ? null : IsoWorld.instance.currentCell;
        if (cell == null) {
            return Map.of();
        }
        Map<Integer, LiveVehicle> out = new HashMap<>();
        for (BaseVehicle vehicle : cell.getVehicles()) {
            int sqlId = vehicle.getSqlId();
            if (sqlId < 1) {
                continue;
            }
            out.put(
                    sqlId,
                    new LiveVehicle(
                            AvcsClaimIdentity.effectiveClaimKey(vehicle),
                            vehicle.getX(),
                            vehicle.getY()));
        }
        return out;
    }

    private static void broadcast(KahluaTable batch) {
        GameServer.sendServerCommand(MODULE, BATCH_COMMAND, batch);
    }

    static Result sync(
            KahluaTable db,
            Map<Integer, LiveVehicle> live,
            Function<Map<Integer, Double>, VerifiedRead> dbLookup,
            Supplier<KahluaTable> newTable,
            Consumer<KahluaTable> send,
            long nowSeconds) {
        List<Claim> claims = new ArrayList<>();
        int undecodable = 0;
        KahluaTableIterator it = db.iterator();
        while (it.advance()) {
            if (!(it.getValue() instanceof KahluaTable entry)) {
                continue;
            }
            int sqlId = AvcsClaimKey.sqlIdFromClaimKey(it.getKey());
            if (sqlId == AvcsClaimKey.INVALID) {
                undecodable++;
                continue;
            }
            claims.add(new Claim(it.getKey(), sqlId, entry));
        }

        Map<Integer, Claim> newestBySqlId = new HashMap<>();
        for (Claim claim : claims) {
            newestBySqlId.merge(claim.sqlId(), claim, AvcsVehicleLocationSync::newer);
        }

        Map<Claim, Position> resolved = new HashMap<>();
        Map<Integer, Double> needDb = new LinkedHashMap<>();
        int liveCount = 0;
        int stale = 0;
        for (Claim claim : claims) {
            if (newestBySqlId.get(claim.sqlId()) != claim) {
                stale++;
                continue;
            }
            LiveVehicle vehicle = live.get(claim.sqlId());
            if (vehicle == null) {
                needDb.put(claim.sqlId(), (Double) claim.key());
            } else if (!claim.key().equals(vehicle.claimKey())) {
                // recycled sqlId: the loaded vehicle is not (or no longer) this claim's car
                stale++;
            } else {
                resolved.put(claim, new Position(vehicle.x(), vehicle.y()));
                liveCount++;
            }
        }

        VerifiedRead fromDb = needDb.isEmpty() ? VerifiedRead.EMPTY : dbLookup.apply(needDb);
        int dbCount = 0;
        int unverifiedDb = 0;
        int missing = 0;
        for (Claim claim : claims) {
            if (newestBySqlId.get(claim.sqlId()) != claim || !needDb.containsKey(claim.sqlId())) {
                continue;
            }
            Position position = fromDb.positions().get(claim.sqlId());
            if (position != null) {
                resolved.put(claim, position);
                dbCount++;
            } else if (fromDb.unverified().contains(claim.sqlId())) {
                unverifiedDb++;
            } else {
                missing++;
            }
        }

        int changed = 0;
        KahluaTable batch = null;
        int batchSize = 0;
        double updated = (double) nowSeconds;
        for (Claim claim : claims) {
            Position position = resolved.get(claim);
            if (position == null) {
                continue;
            }
            double x = Math.floor(position.x());
            double y = Math.floor(position.y());
            if (isAt(claim.entry(), x, y)) {
                continue;
            }
            claim.entry().rawset(KEY_X, x);
            claim.entry().rawset(KEY_Y, y);
            claim.entry().rawset(KEY_UPDATED, updated);
            changed++;

            KahluaTable delta = newTable.get();
            delta.rawset(KEY_VEHICLE_ID, claim.key());
            delta.rawset(KEY_X, x);
            delta.rawset(KEY_Y, y);
            delta.rawset(KEY_UPDATED, updated);
            if (batch == null) {
                batch = newTable.get();
            }
            batch.rawset(++batchSize, delta);
            if (batchSize == BATCH_SIZE) {
                send.accept(batch);
                batch = null;
                batchSize = 0;
            }
        }
        if (batch != null) {
            send.accept(batch);
        }
        return new Result(
                claims.size(),
                undecodable,
                liveCount,
                dbCount,
                stale,
                unverifiedDb,
                missing,
                changed);
    }

    // the timestamp prefix makes a larger key the later claim
    private static Claim newer(Claim a, Claim b) {
        return ((Double) b.key()) > ((Double) a.key()) ? b : a;
    }

    private static boolean isAt(KahluaTable entry, double x, double y) {
        return entry.rawget(KEY_X) instanceof Double curX
                && curX == x
                && entry.rawget(KEY_Y) instanceof Double curY
                && curY == y;
    }
}
