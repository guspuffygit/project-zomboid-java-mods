package com.sentientsimulations.projectzomboid.avcsmapview;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import com.sentientsimulations.projectzomboid.avcsmapview.VehiclesDbLocations.Position;
import com.sentientsimulations.projectzomboid.avcsmapview.VehiclesDbLocations.VerifiedRead;
import io.pzstorm.storm.event.core.OnClientCommand;
import io.pzstorm.storm.event.core.SubscribeEvent;
import io.pzstorm.storm.event.lua.OnTickEvent;
import io.pzstorm.storm.event.zomboid.OnZomboidGlobalsLoadEvent;
import io.pzstorm.storm.util.StormEnv;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Set;
import org.jetbrains.annotations.Nullable;
import se.krka.kahlua.vm.KahluaTable;
import zombie.Lua.LuaManager;
import zombie.characters.IsoPlayer;
import zombie.core.logger.LoggerManager;
import zombie.core.physics.Transform;
import zombie.core.physics.WorldSimulation;
import zombie.iso.IsoCell;
import zombie.iso.IsoChunk;
import zombie.iso.IsoGridSquare;
import zombie.iso.IsoWorld;
import zombie.network.GameServer;
import zombie.network.ServerMap;
import zombie.vehicles.BaseVehicle;
import zombie.vehicles.VehiclesDB2;
import zombie.world.moddata.GlobalModData;

/**
 * Server side of the managers' "teleport vehicle to me" button: {@code AVCS:adminTeleportVehicle}
 * from an admin moves the claimed vehicle next to the admin's (server-authoritative) position.
 *
 * <p>Everything runs on the server main thread: the client command is dispatched there, and an
 * unloaded vehicle is brought in by keeping its cell relevant from the {@code OnTick} handler until
 * the vehicle appears in the world (or the load times out). The move itself re-homes the vehicle in
 * memory (physics transform, square, chunk list) and persists through {@link
 * VehiclesDB2#updateVehicle}; the claim's {@code LastLocationX/Y} is refreshed and broadcast the
 * same way the pre-save sync does so managers and map update immediately.
 *
 * <p>Only the {@code admin} role may trigger this; the check is server-side, the UI gating is just
 * convenience.
 *
 * <p>A claim is never resolved by sqlId alone — vanilla recycles the lowest free id, so an orphaned
 * claim's id can point at a stranger's newer vehicle. Every candidate (loaded vehicle or {@code
 * vehicles.db} row) must be imprinted with exactly the requested claim key, else the teleport is
 * refused with {@link Reason#recycledId}.
 */
public final class AvcsAdminVehicleTeleport {

    static final String MODULE = "AVCS";
    static final String COMMAND = "adminTeleportVehicle";
    static final String RESULT_COMMAND = "adminTeleportVehicleResult";
    static final String LUA_ENABLED_FLAG = "AvcsAdminTeleportEnabled";
    static final String ADMIN_ROLE = "admin";
    static final String KEY_OK = "ok";
    static final String KEY_REASON = "reason";
    static final String KEY_X = "X";
    static final String KEY_Y = "Y";

    static final int MAX_OFFSET = 2;
    static final int DEFAULT_OFFSET = 2;
    static final int CHUNK_SIZE = 8;
    static final long LOAD_TIMEOUT_MS = 60_000L;
    static final int MAX_PENDING = 8;
    private static final String LOG_NAME = "AVCS";

    enum Reason {
        moved,
        loading,
        notAdmin,
        badArgs,
        unknownClaim,
        notInDb,
        inProgress,
        tooManyPending,
        recycledId,
        notGround,
        hasOccupants,
        towing,
        targetNotLoaded,
        occupied,
        timeout
    }

    record Target(int x, int y) {
        float centerX() {
            return x + 0.5f;
        }

        float centerY() {
            return y + 0.5f;
        }
    }

    static final class Job {
        final int sqlId;
        final Object claimKey;
        final IsoPlayer admin;
        final String adminName;
        final Target target;
        final int sourceChunkX;
        final int sourceChunkY;
        final long deadlineMs;

        Job(
                int sqlId,
                Object claimKey,
                IsoPlayer admin,
                String adminName,
                Target target,
                int sourceChunkX,
                int sourceChunkY,
                long deadlineMs) {
            this.sqlId = sqlId;
            this.claimKey = claimKey;
            this.admin = admin;
            this.adminName = adminName;
            this.target = target;
            this.sourceChunkX = sourceChunkX;
            this.sourceChunkY = sourceChunkY;
            this.deadlineMs = deadlineMs;
        }

        boolean expired(long nowMs) {
            return nowMs >= deadlineMs;
        }
    }

    private static final Map<Integer, Job> PENDING = new LinkedHashMap<>();

    private AvcsAdminVehicleTeleport() {}

    // Lets AVCSServer.lua answer "needs a Storm server" when this handler isn't around
    @SubscribeEvent
    public static void onZomboidGlobalsLoad(OnZomboidGlobalsLoadEvent event) {
        if (StormEnv.isStormServer() && LuaManager.env != null) {
            LuaManager.env.rawset(LUA_ENABLED_FLAG, Boolean.TRUE);
        }
    }

    @OnClientCommand
    public static void onAdminTeleportVehicle(AdminTeleportVehicleCommand event) {
        IsoPlayer admin = event.getPlayer();
        if (admin == null) {
            return;
        }
        Object claimKey = event.getVehicleId();
        if (!isAdminRole(admin.getAccessLevel())) {
            LOGGER.warn(
                    "[AVCS] adminTeleportVehicle from non-admin {} (role={}); dropping",
                    admin.getUsername(),
                    admin.getAccessLevel());
            reply(admin, claimKey, Reason.notAdmin, null);
            return;
        }
        int sqlId = AvcsClaimKey.sqlIdFromClaimKey(claimKey);
        if (sqlId == AvcsClaimKey.INVALID) {
            reply(admin, claimKey, Reason.badArgs, null);
            return;
        }
        if (claimEntry(claimKey) == null) {
            reply(admin, claimKey, Reason.unknownClaim, null);
            return;
        }
        if (Math.floor(admin.getZ()) != 0d) {
            reply(admin, claimKey, Reason.notGround, null);
            return;
        }
        Target target =
                targetFor(admin.getX(), admin.getY(), event.getOffsetX(), event.getOffsetY());
        String adminName = admin.getUsername();

        BaseVehicle loaded = findLoaded(sqlId);
        if (loaded != null) {
            if (!AvcsClaimIdentity.matchesClaim(loaded, claimKey)) {
                logRecycled(adminName, sqlId, claimKey, loaded);
                reply(admin, claimKey, Reason.recycledId, null);
                return;
            }
            finish(new Job(sqlId, claimKey, admin, adminName, target, 0, 0, 0L), loaded);
            return;
        }
        if (PENDING.containsKey(sqlId)) {
            reply(admin, claimKey, Reason.inProgress, null);
            return;
        }
        if (PENDING.size() >= MAX_PENDING) {
            reply(admin, claimKey, Reason.tooManyPending, null);
            return;
        }
        VerifiedRead read =
                VehiclesDbLocations.readVerifiedFromCurrentSave(Map.of(sqlId, (Double) claimKey));
        if (read.unverified().contains(sqlId)) {
            logRecycled(adminName, sqlId, claimKey, null);
            reply(admin, claimKey, Reason.recycledId, null);
            return;
        }
        Position stored = read.positions().get(sqlId);
        if (stored == null) {
            reply(admin, claimKey, Reason.notInDb, null);
            return;
        }
        PENDING.put(
                sqlId,
                new Job(
                        sqlId,
                        claimKey,
                        admin,
                        adminName,
                        target,
                        chunkOf(stored.x()),
                        chunkOf(stored.y()),
                        System.currentTimeMillis() + LOAD_TIMEOUT_MS));
        LOGGER.info(
                "[AVCS] {} asked to teleport sqlId={} (stored at {},{}) to {},{}; loading its cell",
                adminName,
                sqlId,
                stored.x(),
                stored.y(),
                target.x(),
                target.y());
        reply(admin, claimKey, Reason.loading, null);
    }

    @SubscribeEvent
    public static void onTick(OnTickEvent event) {
        if (PENDING.isEmpty()) {
            return;
        }
        ServerMap map = ServerMap.instance;
        long now = System.currentTimeMillis();
        Iterator<Job> it = PENDING.values().iterator();
        while (it.hasNext()) {
            Job job = it.next();
            try {
                map.loadOrKeepRelevent(
                        map.worldChunkToServerCellXY(job.sourceChunkX) - map.getMinX(),
                        map.worldChunkToServerCellXY(job.sourceChunkY) - map.getMinY());
                BaseVehicle vehicle = findLoaded(job.sqlId);
                if (vehicle != null) {
                    it.remove();
                    if (AvcsClaimIdentity.matchesClaim(vehicle, job.claimKey)) {
                        finish(job, vehicle);
                    } else {
                        logRecycled(job.adminName, job.sqlId, job.claimKey, vehicle);
                        reply(job.admin, job.claimKey, Reason.recycledId, null);
                    }
                } else if (job.expired(now)) {
                    it.remove();
                    LOGGER.warn(
                            "[AVCS] teleport of sqlId={} for {} timed out waiting for chunk {},{}",
                            job.sqlId,
                            job.adminName,
                            job.sourceChunkX,
                            job.sourceChunkY);
                    reply(job.admin, job.claimKey, Reason.timeout, null);
                }
            } catch (RuntimeException e) {
                it.remove();
                LOGGER.error("[AVCS] teleport of sqlId={} failed", job.sqlId, e);
            }
        }
    }

    private static void finish(Job job, BaseVehicle vehicle) {
        float fromX = vehicle.getX();
        float fromY = vehicle.getY();
        Reason reason;
        try {
            reason = move(vehicle, job.target);
        } catch (RuntimeException e) {
            LOGGER.error("[AVCS] teleport of sqlId={} failed", job.sqlId, e);
            return;
        }
        if (reason == Reason.moved) {
            updateClaimLocation(job.claimKey, job.target);
            String line =
                    "["
                            + (System.currentTimeMillis() / 1000L)
                            + "] Admin teleported vehicle ["
                            + job.adminName
                            + "] ["
                            + vehicle.getScriptName()
                            + "] [sqlId "
                            + job.sqlId
                            + "] from ["
                            + (int) Math.floor(fromX)
                            + ","
                            + (int) Math.floor(fromY)
                            + "] to ["
                            + job.target.x()
                            + ","
                            + job.target.y()
                            + "]";
            LoggerManager.getLogger(LOG_NAME).write(line);
            LOGGER.info("[AVCS] {}", line);
        }
        reply(job.admin, job.claimKey, reason, job.target);
    }

    // Loaded-vehicle move; the server runs no Bullet step so the transform write is the position
    static Reason move(BaseVehicle vehicle, Target target) {
        if (vehicle.chunk == null || !vehicle.chunk.vehicles.contains(vehicle)) {
            return Reason.targetNotLoaded;
        }
        if (hasOccupants(vehicle)) {
            return Reason.hasOccupants;
        }
        if (vehicle.getVehicleTowing() != null || vehicle.getVehicleTowedBy() != null) {
            return Reason.towing;
        }
        IsoCell cell = IsoWorld.instance == null ? null : IsoWorld.instance.currentCell;
        IsoGridSquare square = cell == null ? null : cell.getGridSquare(target.x(), target.y(), 0);
        if (square == null || square.getChunk() == null) {
            return Reason.targetNotLoaded;
        }
        BaseVehicle occupant = square.getVehicleContainer();
        if (occupant != null && occupant != vehicle) {
            return Reason.occupied;
        }

        float nx = target.centerX();
        float ny = target.centerY();
        Transform transform = BaseVehicle.allocTransform();
        try {
            vehicle.getWorldTransform(transform);
            transform.origin.set(
                    nx - WorldSimulation.instance.offsetX,
                    transform.origin.y,
                    ny - WorldSimulation.instance.offsetY);
            vehicle.setWorldTransform(transform);
        } finally {
            BaseVehicle.releaseTransform(transform);
        }
        vehicle.setX(nx);
        vehicle.setY(ny);
        vehicle.setZ(0f);
        vehicle.setSquare(square);
        vehicle.setCurrent(square);

        IsoChunk oldChunk = vehicle.chunk;
        IsoChunk newChunk = square.getChunk();
        if (oldChunk != newChunk) {
            oldChunk.vehicles.remove(vehicle);
            vehicle.chunk = newChunk;
            if (!newChunk.vehicles.contains(vehicle)) {
                newChunk.vehicles.add(vehicle);
            }
        }
        IsoChunk.addFromCheckedVehicles(vehicle);
        vehicle.polyDirty = true;
        vehicle.updateFlags |= BaseVehicle.UpdateFlags.PositionOrientation;
        VehiclesDB2.instance.updateVehicle(vehicle);
        return Reason.moved;
    }

    private static boolean hasOccupants(BaseVehicle vehicle) {
        if (vehicle.getDriver() != null) {
            return true;
        }
        for (int seat = 0; seat < vehicle.getMaxPassengers(); seat++) {
            if (vehicle.getCharacter(seat) != null) {
                return true;
            }
        }
        return false;
    }

    private static void logRecycled(
            String adminName, int sqlId, Object claimKey, @Nullable BaseVehicle vehicle) {
        LOGGER.warn(
                "[AVCS] refused teleport for {}: sqlId {} was recycled; claim {} is not the {}",
                adminName,
                sqlId,
                claimKey,
                vehicle == null ? "vehicle in vehicles.db" : "loaded " + vehicle.getScriptName());
    }

    private static @Nullable BaseVehicle findLoaded(int sqlId) {
        IsoCell cell = IsoWorld.instance == null ? null : IsoWorld.instance.currentCell;
        if (cell == null) {
            return null;
        }
        Set<BaseVehicle> vehicles = cell.getVehicles();
        if (vehicles == null) {
            return null;
        }
        for (BaseVehicle vehicle : vehicles) {
            if (vehicle.getSqlId() == sqlId) {
                return vehicle;
            }
        }
        return null;
    }

    private static @Nullable KahluaTable claimEntry(Object claimKey) {
        KahluaTable db = GlobalModData.instance.get(AvcsVehicleLocationSync.MOD_DATA_TABLE);
        if (db == null || claimKey == null) {
            return null;
        }
        return db.rawget(claimKey) instanceof KahluaTable entry ? entry : null;
    }

    private static void updateClaimLocation(Object claimKey, Target target) {
        KahluaTable entry = claimEntry(claimKey);
        if (entry == null) {
            return;
        }
        double updated = (double) (System.currentTimeMillis() / 1000L);
        entry.rawset(AvcsVehicleLocationSync.KEY_X, (double) target.x());
        entry.rawset(AvcsVehicleLocationSync.KEY_Y, (double) target.y());
        entry.rawset(AvcsVehicleLocationSync.KEY_UPDATED, updated);

        KahluaTable delta = LuaManager.platform.newTable();
        delta.rawset(AvcsVehicleLocationSync.KEY_VEHICLE_ID, claimKey);
        delta.rawset(AvcsVehicleLocationSync.KEY_X, (double) target.x());
        delta.rawset(AvcsVehicleLocationSync.KEY_Y, (double) target.y());
        delta.rawset(AvcsVehicleLocationSync.KEY_UPDATED, updated);
        KahluaTable batch = LuaManager.platform.newTable();
        batch.rawset(1.0, delta);
        GameServer.sendServerCommand(MODULE, AvcsVehicleLocationSync.BATCH_COMMAND, batch);
    }

    private static void reply(IsoPlayer admin, Object claimKey, Reason reason, Target target) {
        KahluaTable table = resultTable(LuaManager.platform.newTable(), claimKey, reason, target);
        GameServer.sendServerCommand(admin, MODULE, RESULT_COMMAND, table);
    }

    static KahluaTable resultTable(
            KahluaTable table, Object claimKey, Reason reason, @Nullable Target target) {
        table.rawset(KEY_OK, reason == Reason.moved);
        table.rawset(KEY_REASON, reason.name());
        if (claimKey != null) {
            table.rawset(AvcsVehicleLocationSync.KEY_VEHICLE_ID, claimKey);
        }
        if (target != null) {
            table.rawset(KEY_X, (double) target.x());
            table.rawset(KEY_Y, (double) target.y());
        }
        return table;
    }

    static boolean isAdminRole(@Nullable String roleName) {
        return ADMIN_ROLE.equalsIgnoreCase(roleName);
    }

    static Target targetFor(float adminX, float adminY, @Nullable Double dx, @Nullable Double dy) {
        return new Target(
                (int) Math.floor(adminX) + clampOffset(dx),
                (int) Math.floor(adminY) + clampOffset(dy));
    }

    static int clampOffset(@Nullable Double raw) {
        if (raw == null || raw.isNaN()) {
            return DEFAULT_OFFSET;
        }
        return (int) Math.max(-MAX_OFFSET, Math.min(MAX_OFFSET, Math.rint(raw)));
    }

    static int chunkOf(float worldCoord) {
        return Math.floorDiv((int) Math.floor(worldCoord), CHUNK_SIZE);
    }
}
