package com.sentientsimulations.projectzomboid.survivorskillobelisk;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import io.pzstorm.storm.event.core.SubscribeEvent;
import io.pzstorm.storm.event.lua.OnDestroyIsoThumpableEvent;
import io.pzstorm.storm.event.lua.OnObjectAboutToBeRemovedEvent;
import io.pzstorm.storm.event.lua.OnObjectAddedEvent;
import io.pzstorm.storm.event.lua.OnTickEvent;
import io.pzstorm.storm.event.lua.OnTileRemovedEvent;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.ConcurrentLinkedQueue;
import java.util.concurrent.LinkedBlockingQueue;
import zombie.iso.IsoGridSquare;
import zombie.iso.IsoObject;
import zombie.iso.sprite.IsoSprite;

/**
 * Keeps the {@code obelisk_types} table in sync with the world: on placement, ensures a {@code
 * type='None'} row exists at the object's square; on any removal path, deletes the matching row so
 * an admin sledgehammer or destruction doesn't leave orphan rows. Subscribed to all four candidate
 * lifecycle events — they overlap (sledgehammer fires both {@code OnDestroyIsoThumpable} and a
 * subsequent {@code OnObjectAboutToBeRemoved}; in-place destruction fires both that and {@code
 * OnTileRemoved}) but the underlying DB ops are idempotent.
 *
 * <p>Same two-thread split as {@link ListDeathsHandler}: the main thread snapshots the obelisk
 * coords and enqueues, a daemon worker runs the SQLite mark/delete, and the next tick fires the
 * {@code obeliskUpdated} / {@code obeliskRemoved} broadcast (sendServerCommand is not thread-safe).
 */
public final class ObeliskLifecycleHandler {

    private static final String SPRITE_PREFIX = "survivor_skill_obelisk_";
    private static final String NONE_TYPE = "None";

    private record PendingOp(int x, int y, int z, boolean placement) {}

    private record CompletedOp(int x, int y, int z, boolean placement) {}

    private static final BlockingQueue<PendingOp> PENDING = new LinkedBlockingQueue<>();
    private static final ConcurrentLinkedQueue<CompletedOp> COMPLETED =
            new ConcurrentLinkedQueue<>();

    static {
        Thread worker =
                new Thread(
                        ObeliskLifecycleHandler::workerLoop,
                        "SurvivorSkillObelisk-ObeliskLifecycle-Worker");
        worker.setDaemon(true);
        worker.start();
    }

    private ObeliskLifecycleHandler() {}

    @SubscribeEvent
    public static void onObjectAdded(OnObjectAddedEvent event) {
        enqueue(event.object, true);
    }

    @SubscribeEvent
    public static void onObjectAboutToBeRemoved(OnObjectAboutToBeRemovedEvent event) {
        enqueue(event.object, false);
    }

    @SubscribeEvent
    public static void onTileRemoved(OnTileRemovedEvent event) {
        enqueue(event.object, false);
    }

    @SubscribeEvent
    public static void onDestroyIsoThumpable(OnDestroyIsoThumpableEvent event) {
        enqueue(event.thumpableObject, false);
    }

    @SubscribeEvent
    public static void onTick(OnTickEvent event) {
        CompletedOp done;
        while ((done = COMPLETED.poll()) != null) {
            if (done.placement()) {
                ObeliskBroadcast.obeliskUpdated(done.x(), done.y(), done.z(), NONE_TYPE);
            } else {
                ObeliskBroadcast.obeliskRemoved(done.x(), done.y(), done.z());
            }
        }
    }

    private static void enqueue(IsoObject obj, boolean placement) {
        if (!isObelisk(obj)) {
            return;
        }
        IsoGridSquare sq = obj.getSquare();
        if (sq == null) {
            LOGGER.warn(
                    "[SurvivorSkillObelisk] Obelisk {} but square is null; skipping DB op",
                    placement ? "placed" : "removed");
            return;
        }
        PENDING.offer(new PendingOp(sq.getX(), sq.getY(), sq.getZ(), placement));
    }

    private static void workerLoop() {
        while (true) {
            PendingOp op;
            try {
                op = PENDING.take();
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                return;
            }
            try {
                if (runOp(op)) {
                    COMPLETED.offer(new CompletedOp(op.x(), op.y(), op.z(), op.placement()));
                }
            } catch (Throwable t) {
                LOGGER.error(
                        "[SurvivorSkillObelisk] worker loop iteration failed at ({}, {}, {}): {}",
                        op.x(),
                        op.y(),
                        op.z(),
                        t.getMessage(),
                        t);
            }
        }
    }

    private static boolean runOp(PendingOp op) {
        try (SurvivorSkillObeliskDatabase db =
                new SurvivorSkillObeliskDatabase(DeathEventHandler.getDbPath())) {
            SurvivorSkillObeliskRepository repo =
                    new SurvivorSkillObeliskRepository(db.getConnection());
            if (op.placement()) {
                repo.markObeliskNone(op.x(), op.y(), op.z(), System.currentTimeMillis());
                LOGGER.info(
                        "[SurvivorSkillObelisk] Obelisk placed at ({}, {}, {});"
                                + " recorded as 'None'",
                        op.x(),
                        op.y(),
                        op.z());
            } else {
                repo.deleteObeliskType(op.x(), op.y(), op.z());
                LOGGER.info(
                        "[SurvivorSkillObelisk] Obelisk removed at ({}, {}, {}); DB row cleared",
                        op.x(),
                        op.y(),
                        op.z());
            }
            return true;
        } catch (Exception e) {
            LOGGER.error(
                    "[SurvivorSkillObelisk] Failed to {} obelisk row at ({}, {}, {})",
                    op.placement() ? "record" : "delete",
                    op.x(),
                    op.y(),
                    op.z(),
                    e);
            return false;
        }
    }

    private static boolean isObelisk(IsoObject obj) {
        if (obj == null) {
            return false;
        }
        IsoSprite sprite = obj.getSprite();
        if (sprite == null) {
            return false;
        }
        String name = sprite.getName();
        return name != null && name.startsWith(SPRITE_PREFIX);
    }
}
