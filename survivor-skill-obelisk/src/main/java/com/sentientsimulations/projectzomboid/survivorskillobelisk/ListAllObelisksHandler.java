package com.sentientsimulations.projectzomboid.survivorskillobelisk;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import io.pzstorm.storm.event.core.OnClientCommand;
import io.pzstorm.storm.event.core.SubscribeEvent;
import io.pzstorm.storm.event.lua.OnTickEvent;
import java.util.List;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.ConcurrentLinkedQueue;
import java.util.concurrent.LinkedBlockingQueue;
import se.krka.kahlua.vm.KahluaTable;
import zombie.Lua.LuaManager;
import zombie.characters.IsoPlayer;
import zombie.network.GameServer;

/**
 * Handles the {@code SurvivorSkillObelisk:listAllObelisks} client command. Replies with every
 * configured obelisk's coordinates and bound perk so the client can render them on the world map.
 *
 * <p>Unconfigured obelisks (no row in {@code obelisk_types}) are intentionally not included — the
 * map shows admin-tagged shrines only.
 *
 * <p>Same two-thread split as {@link ListDeathsHandler}: the main thread enqueues the request, a
 * daemon worker reads the SQLite table, and the next tick builds the Kahlua reply and ships it.
 */
public final class ListAllObelisksHandler {

    private static final String MODULE = "SurvivorSkillObelisk";
    private static final String REPLY_COMMAND = "obeliskList";

    private record PendingRequest(IsoPlayer player, String username) {}

    private record CompletedRequest(
            IsoPlayer player, List<SurvivorSkillObeliskRepository.ObeliskTypeRow> rows) {}

    private static final BlockingQueue<PendingRequest> PENDING = new LinkedBlockingQueue<>();
    private static final ConcurrentLinkedQueue<CompletedRequest> COMPLETED =
            new ConcurrentLinkedQueue<>();

    static {
        Thread worker =
                new Thread(
                        ListAllObelisksHandler::workerLoop,
                        "SurvivorSkillObelisk-ListAllObelisks-Worker");
        worker.setDaemon(true);
        worker.start();
    }

    private ListAllObelisksHandler() {}

    @OnClientCommand
    public static void onListAllObelisks(ListAllObelisksCommand event) {
        IsoPlayer player = event.getPlayer();
        if (player == null) {
            LOGGER.warn("[SurvivorSkillObelisk] listAllObelisks from null player; dropping");
            return;
        }
        PENDING.offer(new PendingRequest(player, player.getUsername()));
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
                List<SurvivorSkillObeliskRepository.ObeliskTypeRow> rows = runQuery(req);
                if (rows != null) {
                    COMPLETED.offer(new CompletedRequest(req.player(), rows));
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

    private static List<SurvivorSkillObeliskRepository.ObeliskTypeRow> runQuery(
            PendingRequest req) {
        try (SurvivorSkillObeliskDatabase db =
                new SurvivorSkillObeliskDatabase(DeathEventHandler.getDbPath())) {
            SurvivorSkillObeliskRepository repo =
                    new SurvivorSkillObeliskRepository(db.getConnection());
            return repo.listAllObeliskTypes();
        } catch (Exception e) {
            LOGGER.error("[SurvivorSkillObelisk] listAllObelisks failed for {}", req.username(), e);
            return null;
        }
    }

    private static void sendReply(CompletedRequest done) {
        try {
            KahluaTable reply = LuaManager.platform.newTable();
            KahluaTable rowsTable = LuaManager.platform.newTable();
            int i = 1;
            for (SurvivorSkillObeliskRepository.ObeliskTypeRow row : done.rows()) {
                KahluaTable rowTable = LuaManager.platform.newTable();
                rowTable.rawset("x", (double) row.x());
                rowTable.rawset("y", (double) row.y());
                rowTable.rawset("z", (double) row.z());
                rowTable.rawset("type", row.type());
                rowsTable.rawset(i++, rowTable);
            }
            reply.rawset("rows", rowsTable);
            reply.rawset("count", (double) done.rows().size());
            // If the player disconnected while the query was in-flight, sendServerCommand is a
            // no-op (it gates on PlayerToAddressMap).
            GameServer.sendServerCommand(done.player(), MODULE, REPLY_COMMAND, reply);
        } catch (Throwable t) {
            LOGGER.error(
                    "[SurvivorSkillObelisk] Failed to send obeliskList reply: {}",
                    t.getMessage(),
                    t);
        }
    }
}
