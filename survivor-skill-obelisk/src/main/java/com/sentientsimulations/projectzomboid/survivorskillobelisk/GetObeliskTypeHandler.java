package com.sentientsimulations.projectzomboid.survivorskillobelisk;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import io.pzstorm.storm.event.core.OnClientCommand;
import io.pzstorm.storm.event.core.SubscribeEvent;
import io.pzstorm.storm.event.lua.OnTickEvent;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.ConcurrentLinkedQueue;
import java.util.concurrent.LinkedBlockingQueue;
import se.krka.kahlua.vm.KahluaTable;
import zombie.Lua.LuaManager;
import zombie.characters.IsoPlayer;
import zombie.network.GameServer;

/**
 * Handles the {@code SurvivorSkillObelisk:getObeliskType} client command. Returns the obelisk's
 * configured perk id (or {@code "None"}) for the given coords. Used by the Configure Obelisk window
 * to pre-select its skill combo so reopening doesn't silently reset to None on save.
 *
 * <p>Same two-thread split as {@link ListDeathsHandler}: the main thread enqueues the request, a
 * daemon worker runs the SQLite read, and the next tick builds the Kahlua reply and ships it.
 */
public final class GetObeliskTypeHandler {

    private static final String MODULE = "SurvivorSkillObelisk";
    private static final String REPLY_COMMAND = "obeliskType";
    private static final String NONE = "None";

    private record PendingRequest(IsoPlayer player, String username, int x, int y, int z) {}

    private record CompletedRequest(IsoPlayer player, int x, int y, int z, String type) {}

    private static final BlockingQueue<PendingRequest> PENDING = new LinkedBlockingQueue<>();
    private static final ConcurrentLinkedQueue<CompletedRequest> COMPLETED =
            new ConcurrentLinkedQueue<>();

    static {
        Thread worker =
                new Thread(
                        GetObeliskTypeHandler::workerLoop,
                        "SurvivorSkillObelisk-GetObeliskType-Worker");
        worker.setDaemon(true);
        worker.start();
    }

    private GetObeliskTypeHandler() {}

    @OnClientCommand
    public static void onGetObeliskType(GetObeliskTypeCommand event) {
        IsoPlayer player = event.getPlayer();
        if (player == null) {
            LOGGER.warn("[SurvivorSkillObelisk] getObeliskType from null player; dropping");
            return;
        }
        Integer x = event.getX();
        Integer y = event.getY();
        Integer z = event.getZ();
        if (x == null || y == null || z == null) {
            LOGGER.warn(
                    "[SurvivorSkillObelisk] getObeliskType from {} with missing coords"
                            + " (x={}, y={}, z={}); dropping",
                    player.getUsername(),
                    x,
                    y,
                    z);
            return;
        }
        PENDING.offer(new PendingRequest(player, player.getUsername(), x, y, z));
    }

    @SubscribeEvent
    public static void onTick(OnTickEvent event) {
        CompletedRequest done;
        while ((done = COMPLETED.poll()) != null) {
            sendReply(done);
        }
    }

    private static void workerLoop() {
        while (true) {
            PendingRequest req;
            try {
                req = PENDING.take();
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                return;
            }
            try {
                String type = runQuery(req);
                if (type != null) {
                    COMPLETED.offer(
                            new CompletedRequest(req.player(), req.x(), req.y(), req.z(), type));
                }
            } catch (Throwable t) {
                LOGGER.error(
                        "[SurvivorSkillObelisk] worker loop iteration failed for {}: {}",
                        req.username(),
                        t.getMessage(),
                        t);
            }
        }
    }

    private static String runQuery(PendingRequest req) {
        try (SurvivorSkillObeliskDatabase db =
                new SurvivorSkillObeliskDatabase(DeathEventHandler.getDbPath())) {
            SurvivorSkillObeliskRepository repo =
                    new SurvivorSkillObeliskRepository(db.getConnection());
            String stored = repo.findObeliskType(req.x(), req.y(), req.z());
            if (stored != null && !stored.isBlank()) {
                return stored;
            }
            return NONE;
        } catch (Exception e) {
            LOGGER.error(
                    "[SurvivorSkillObelisk] getObeliskType failed for {} at ({}, {}, {})",
                    req.username(),
                    req.x(),
                    req.y(),
                    req.z(),
                    e);
            return null;
        }
    }

    private static void sendReply(CompletedRequest done) {
        try {
            KahluaTable reply = LuaManager.platform.newTable();
            reply.rawset("x", (double) done.x());
            reply.rawset("y", (double) done.y());
            reply.rawset("z", (double) done.z());
            reply.rawset("type", done.type());
            // If the player disconnected while the query was in-flight, sendServerCommand is a
            // no-op (it gates on PlayerToAddressMap).
            GameServer.sendServerCommand(done.player(), MODULE, REPLY_COMMAND, reply);
        } catch (Throwable t) {
            LOGGER.error(
                    "[SurvivorSkillObelisk] Failed to send obeliskType reply: {}",
                    t.getMessage(),
                    t);
        }
    }
}
