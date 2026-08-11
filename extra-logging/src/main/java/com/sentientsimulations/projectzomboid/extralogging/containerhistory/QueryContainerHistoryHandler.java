package com.sentientsimulations.projectzomboid.extralogging.containerhistory;

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
 * Handles the {@code ExtraLogging:queryContainerHistory} client command.
 *
 * <p>The request flow is split across two threads to keep SQLite I/O off the server main thread
 * (same pattern as the obelisk mod's ListDeathsHandler):
 *
 * <ol>
 *   <li>{@link #onQuery} runs on the main thread, validates the request, and enqueues it on {@link
 *       #PENDING}.
 *   <li>A single daemon worker thread blocks on {@link #PENDING}, flushes pending history writes so
 *       the query sees them, runs the query, and pushes the raw rows onto {@link #COMPLETED}.
 *   <li>{@link #onTick} runs on the main thread every tick, drains {@link #COMPLETED}, builds the
 *       {@code KahluaTable} reply, and ships it via {@link
 *       zombie.network.GameServer#sendServerCommand}.
 * </ol>
 *
 * Kahlua tables and {@code sendServerCommand} are not thread-safe, so all Lua construction stays on
 * the main thread; the worker only touches plain Java records.
 */
public final class QueryContainerHistoryHandler {

    private static final String MODULE = "ExtraLogging";
    private static final String REPLY_COMMAND = "containerHistory";
    private static final int DEFAULT_LIMIT = 200;
    private static final int MAX_LIMIT = 1000;

    private record PendingQuery(IsoPlayer player, String ref, int limit) {}

    private record CompletedQuery(
            IsoPlayer player, String ref, List<ContainerTransferRecord> rows) {}

    private static final BlockingQueue<PendingQuery> PENDING = new LinkedBlockingQueue<>();
    private static final ConcurrentLinkedQueue<CompletedQuery> COMPLETED =
            new ConcurrentLinkedQueue<>();

    static {
        Thread worker =
                new Thread(
                        QueryContainerHistoryHandler::workerLoop,
                        "ExtraLogging-ContainerHistoryQuery-Worker");
        worker.setDaemon(true);
        worker.start();
    }

    private QueryContainerHistoryHandler() {}

    @OnClientCommand
    public static void onQuery(QueryContainerHistoryCommand event) {
        IsoPlayer player = event.getPlayer();
        if (player == null || !player.isAccessLevel("admin")) {
            String username = player == null ? "<null>" : player.getUsername();
            String steamId = player == null ? "?" : Long.toString(player.getSteamID());
            String role = "?";
            if (player != null) {
                role = player.getRole() == null ? "none" : player.getRole().getName();
            }
            LOGGER.warn(
                    "[StormAntiCheat] connection {}/{} sent queryContainerHistory while role={};"
                            + " the History button is gated to admins on the client, so a non-admin"
                            + " reaching this handler is running a hacked client or crafting"
                            + " client commands directly; dropping query for ref={}",
                    username,
                    steamId,
                    role,
                    event.getContainerRef());
            return;
        }

        String ref = event.getContainerRef();
        if (ref == null || ref.isBlank()) {
            LOGGER.warn("queryContainerHistory: missing ref from {}", player.getUsername());
            return;
        }

        Integer requested = event.getLimit();
        int limit = requested == null ? DEFAULT_LIMIT : Math.min(Math.max(requested, 1), MAX_LIMIT);

        PENDING.offer(new PendingQuery(player, ref, limit));
    }

    @SubscribeEvent
    public static void onTick(OnTickEvent event) {
        CompletedQuery done;
        while ((done = COMPLETED.poll()) != null) {
            sendReply(done);
        }
    }

    private static void workerLoop() {
        while (true) {
            PendingQuery req;
            try {
                req = PENDING.take();
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                return;
            }
            try {
                // Flush so transfers recorded just before the query are visible to it.
                ContainerHistoryWriter.flush();
                List<ContainerTransferRecord> rows =
                        ContainerHistoryRepository.queryByContainerRef(req.ref(), req.limit());
                COMPLETED.offer(new CompletedQuery(req.player(), req.ref(), rows));
            } catch (Throwable t) {
                LOGGER.error(
                        "[ContainerHistory] query worker iteration failed for ref={}: {}",
                        req.ref(),
                        t.getMessage(),
                        t);
            }
        }
    }

    private static void sendReply(CompletedQuery done) {
        try {
            KahluaTable reply = LuaManager.platform.newTable();
            reply.rawset("ref", done.ref());

            KahluaTable rowsTable = LuaManager.platform.newTable();
            int i = 1;
            for (ContainerTransferRecord r : done.rows()) {
                KahluaTable rowTable = LuaManager.platform.newTable();
                rowTable.rawset("id", (double) r.id());
                rowTable.rawset("ts", (double) r.ts());
                rowTable.rawset("player", r.playerUsername());
                if (r.playerSteamId() != null) {
                    rowTable.rawset("steamId", r.playerSteamId());
                }
                rowTable.rawset("itemType", r.itemType());
                rowTable.rawset("itemName", r.itemName());
                rowTable.rawset("itemId", (double) r.itemId());
                rowTable.rawset("srcRef", r.srcRef());
                rowTable.rawset("destRef", r.destRef());
                rowTable.rawset("uuid", r.uuid());
                rowsTable.rawset(i++, rowTable);
            }
            reply.rawset("rows", rowsTable);
            reply.rawset("count", (double) done.rows().size());

            // If the player disconnected while the query was in-flight, sendServerCommand is a
            // no-op (it gates on PlayerToAddressMap).
            GameServer.sendServerCommand(done.player(), MODULE, REPLY_COMMAND, reply);
        } catch (Throwable t) {
            LOGGER.error(
                    "[ContainerHistory] Failed to send containerHistory reply: {}",
                    t.getMessage(),
                    t);
        }
    }
}
