package com.sentientsimulations.projectzomboid.survivorskillobelisk;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import io.pzstorm.storm.event.core.OnClientCommand;
import io.pzstorm.storm.event.core.SubscribeEvent;
import io.pzstorm.storm.event.lua.OnTickEvent;
import java.sql.Connection;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.ConcurrentLinkedQueue;
import java.util.concurrent.LinkedBlockingQueue;
import se.krka.kahlua.vm.KahluaTable;
import zombie.Lua.LuaManager;
import zombie.characters.IsoPlayer;
import zombie.network.GameServer;

/**
 * Handles the {@code SurvivorSkillObelisk:listDeaths} client command.
 *
 * <p>The request flow is split across two threads to keep SQLite I/O off the server main thread:
 *
 * <ol>
 *   <li>{@link #onListDeaths} runs on the main thread, validates the request, and enqueues it on
 *       {@link #PENDING}.
 *   <li>A single daemon worker thread blocks on {@link #PENDING}, runs the DB query in one
 *       transaction, and pushes the raw result onto {@link #COMPLETED}.
 *   <li>{@link #onTick} runs on the main thread every tick, drains {@link #COMPLETED}, builds the
 *       {@code KahluaTable} reply, and ships it via {@link GameServer#sendServerCommand}.
 * </ol>
 *
 * Kahlua tables and {@code sendServerCommand} are not thread-safe, so all Lua construction stays on
 * the main thread; the worker only touches plain Java records.
 */
public final class ListDeathsHandler {

    private static final String MODULE = "SurvivorSkillObelisk";
    private static final String REPLY_COMMAND = "deathsList";
    private static final int DEFAULT_LIMIT = 20;
    private static final int MAX_LIMIT = 100;
    private static final String NONE_TYPE = "None";

    private record PendingRequest(
            IsoPlayer player,
            long steamId,
            String username,
            int limit,
            Integer obeliskX,
            Integer obeliskY,
            Integer obeliskZ) {}

    private record DeathWithSkills(
            SurvivorSkillObeliskRepository.DeathSummary summary,
            List<SurvivorSkillObeliskRepository.SkillRow> skills) {}

    private record CompletedRequest(
            IsoPlayer player, List<DeathWithSkills> deaths, String obeliskType) {}

    private static final BlockingQueue<PendingRequest> PENDING = new LinkedBlockingQueue<>();
    private static final ConcurrentLinkedQueue<CompletedRequest> COMPLETED =
            new ConcurrentLinkedQueue<>();

    static {
        Thread worker =
                new Thread(ListDeathsHandler::workerLoop, "SurvivorSkillObelisk-ListDeaths-Worker");
        worker.setDaemon(true);
        worker.start();
    }

    private ListDeathsHandler() {}

    @OnClientCommand
    public static void onListDeaths(ListDeathsCommand event) {
        IsoPlayer player = event.getPlayer();
        if (player == null) {
            LOGGER.warn("[SurvivorSkillObelisk] listDeaths from null player; dropping");
            return;
        }
        long steamId = player.getSteamID();
        String username = player.getUsername();
        if (username == null || username.isBlank()) {
            LOGGER.warn(
                    "[SurvivorSkillObelisk] listDeaths from {} with no username; dropping",
                    steamId);
            return;
        }
        Integer requested = event.getLimit();
        int limit = requested == null ? DEFAULT_LIMIT : Math.min(Math.max(requested, 1), MAX_LIMIT);
        PENDING.offer(
                new PendingRequest(
                        player,
                        steamId,
                        username,
                        limit,
                        event.getX(),
                        event.getY(),
                        event.getZ()));
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
                QueryResult result = runQuery(req);
                if (result != null) {
                    COMPLETED.offer(
                            new CompletedRequest(req.player(), result.deaths, result.obeliskType));
                }
            } catch (Throwable t) {
                LOGGER.error(
                        "[SurvivorSkillObelisk] worker loop iteration failed for {} ({}): {}",
                        req.username(),
                        req.steamId(),
                        t.getMessage(),
                        t);
            }
        }
    }

    private record QueryResult(List<DeathWithSkills> deaths, String obeliskType) {}

    private static QueryResult runQuery(PendingRequest req) {
        List<DeathWithSkills> result = new ArrayList<>();
        String obeliskType = NONE_TYPE;
        try (SurvivorSkillObeliskDatabase db =
                new SurvivorSkillObeliskDatabase(DeathEventHandler.getDbPath())) {
            Connection conn = db.getConnection();
            // Bracket the 1 + N reads in one transaction so SQLite skips the implicit
            // BEGIN/COMMIT (and SHARED-lock acquire/release) it would otherwise run per statement.
            conn.setAutoCommit(false);
            SurvivorSkillObeliskRepository repo = new SurvivorSkillObeliskRepository(conn);
            List<SurvivorSkillObeliskRepository.DeathSummary> rows =
                    repo.listDeathsByOwner(req.steamId(), req.username(), req.limit());
            for (SurvivorSkillObeliskRepository.DeathSummary r : rows) {
                List<SurvivorSkillObeliskRepository.SkillRow> skills =
                        repo.listSkillsByDeath(r.id());
                result.add(new DeathWithSkills(r, skills));
            }
            if (req.obeliskX() != null && req.obeliskY() != null && req.obeliskZ() != null) {
                String stored =
                        repo.findObeliskType(req.obeliskX(), req.obeliskY(), req.obeliskZ());
                if (stored != null && !stored.isBlank()) {
                    obeliskType = stored;
                }
            }
            conn.commit();
        } catch (Exception e) {
            LOGGER.error(
                    "[SurvivorSkillObelisk] listDeaths query failed for {} ({}): {}",
                    req.username(),
                    req.steamId(),
                    e.getMessage(),
                    e);
            return null;
        }
        return new QueryResult(result, obeliskType);
    }

    private static void sendReply(CompletedRequest done) {
        try {
            KahluaTable reply = LuaManager.platform.newTable();
            KahluaTable rowsTable = LuaManager.platform.newTable();
            int i = 1;
            for (DeathWithSkills d : done.deaths()) {
                SurvivorSkillObeliskRepository.DeathSummary r = d.summary();
                KahluaTable rowTable = LuaManager.platform.newTable();
                rowTable.rawset("id", (double) r.id());
                rowTable.rawset("ts", (double) r.ts());
                rowTable.rawset("username", r.username());
                rowTable.rawset("forename", r.forename());
                rowTable.rawset("surname", r.surname());
                rowTable.rawset("hoursSurvived", r.hoursSurvived());
                rowTable.rawset("zombieKills", (double) r.zombieKills());

                KahluaTable skillsTable = LuaManager.platform.newTable();
                int s = 1;
                for (SurvivorSkillObeliskRepository.SkillRow skill : d.skills()) {
                    KahluaTable skillTable = LuaManager.platform.newTable();
                    skillTable.rawset("perk", skill.perk());
                    skillTable.rawset("level", (double) skill.level());
                    skillTable.rawset("xp", (double) skill.xp());
                    skillsTable.rawset(s++, skillTable);
                }
                rowTable.rawset("skills", skillsTable);

                rowsTable.rawset(i++, rowTable);
            }
            reply.rawset("rows", rowsTable);
            reply.rawset("count", (double) done.deaths().size());
            reply.rawset("type", done.obeliskType());
            // If the player disconnected while the query was in-flight, sendServerCommand is a
            // no-op (it gates on PlayerToAddressMap).
            GameServer.sendServerCommand(done.player(), MODULE, REPLY_COMMAND, reply);
        } catch (Throwable t) {
            LOGGER.error(
                    "[SurvivorSkillObelisk] Failed to send listDeaths reply: {}",
                    t.getMessage(),
                    t);
        }
    }
}
