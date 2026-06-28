package com.sentientsimulations.projectzomboid.survivorskillobelisk;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import io.pzstorm.storm.event.core.OnClientCommand;
import io.pzstorm.storm.event.core.SubscribeEvent;
import io.pzstorm.storm.event.lua.OnTickEvent;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.ConcurrentLinkedQueue;
import java.util.concurrent.LinkedBlockingQueue;
import zombie.characters.IsoPlayer;
import zombie.characters.skills.PerkFactory;

/**
 * Handles the {@code SurvivorSkillObelisk:setObeliskType} client command. Admin-only: persists a
 * skill-type label for the obelisk at the given world coordinates. {@code "None"} clears the type.
 *
 * <p>The admin check is enforced server-side regardless of UI gating — the Lua menu hides the
 * option for non-admins, but a hand-crafted packet shouldn't be able to mutate state either.
 *
 * <p>Same two-thread split as {@link ListDeathsHandler}: the main thread validates and enqueues, a
 * daemon worker runs the SQLite upsert, and the next tick fires the {@code obeliskUpdated}
 * broadcast (sendServerCommand is not thread-safe).
 */
public final class SetObeliskTypeHandler {

    private static final String NONE = "None";

    private record PendingRequest(
            IsoPlayer player, String username, long steamId, int x, int y, int z, String type) {}

    private record CompletedRequest(int x, int y, int z, String type) {}

    private static final BlockingQueue<PendingRequest> PENDING = new LinkedBlockingQueue<>();
    private static final ConcurrentLinkedQueue<CompletedRequest> COMPLETED =
            new ConcurrentLinkedQueue<>();

    static {
        Thread worker =
                new Thread(
                        SetObeliskTypeHandler::workerLoop,
                        "SurvivorSkillObelisk-SetObeliskType-Worker");
        worker.setDaemon(true);
        worker.start();
    }

    private SetObeliskTypeHandler() {}

    @OnClientCommand
    public static void onSetObeliskType(SetObeliskTypeCommand event) {
        IsoPlayer player = event.getPlayer();
        if (player == null) {
            LOGGER.warn("[SurvivorSkillObelisk] setObeliskType from null player; dropping");
            return;
        }
        String username = player.getUsername();
        long steamId = player.getSteamID();
        String accessLevel = player.getAccessLevel();
        if (accessLevel == null || !"admin".equalsIgnoreCase(accessLevel)) {
            LOGGER.warn(
                    "[SurvivorSkillObelisk] setObeliskType from non-admin {} ({}, role={});"
                            + " dropping",
                    username,
                    steamId,
                    accessLevel);
            return;
        }
        Integer x = event.getX();
        Integer y = event.getY();
        Integer z = event.getZ();
        if (x == null || y == null || z == null) {
            LOGGER.warn(
                    "[SurvivorSkillObelisk] setObeliskType from {} with missing coords"
                            + " (x={}, y={}, z={}); dropping",
                    username,
                    x,
                    y,
                    z);
            return;
        }
        String type = event.getType();
        if (type == null || type.isBlank()) {
            type = NONE;
        }
        if (!NONE.equals(type) && PerkFactory.Perks.FromString(type) == null) {
            LOGGER.warn(
                    "[SurvivorSkillObelisk] setObeliskType from {} with unknown perk '{}';"
                            + " dropping",
                    username,
                    type);
            return;
        }
        PENDING.offer(new PendingRequest(player, username, steamId, x, y, z, type));
    }

    @SubscribeEvent
    public static void onTick(OnTickEvent event) {
        CompletedRequest done;
        while ((done = COMPLETED.poll()) != null) {
            ObeliskBroadcast.obeliskUpdated(done.x(), done.y(), done.z(), done.type());
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
                if (runUpsert(req)) {
                    COMPLETED.offer(new CompletedRequest(req.x(), req.y(), req.z(), req.type()));
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

    private static boolean runUpsert(PendingRequest req) {
        try (SurvivorSkillObeliskDatabase db =
                new SurvivorSkillObeliskDatabase(DeathEventHandler.getDbPath())) {
            SurvivorSkillObeliskRepository repo =
                    new SurvivorSkillObeliskRepository(db.getConnection());
            repo.upsertObeliskType(
                    req.x(),
                    req.y(),
                    req.z(),
                    req.type(),
                    req.username(),
                    req.steamId(),
                    System.currentTimeMillis());
            LOGGER.info(
                    "[SurvivorSkillObelisk] setObeliskType: {} ({}) set obelisk at"
                            + " ({}, {}, {}) -> '{}'",
                    req.username(),
                    req.steamId(),
                    req.x(),
                    req.y(),
                    req.z(),
                    req.type());
            return true;
        } catch (Exception e) {
            LOGGER.error(
                    "[SurvivorSkillObelisk] setObeliskType failed for {} ({}) at ({}, {}, {})"
                            + " -> '{}'",
                    req.username(),
                    req.steamId(),
                    req.x(),
                    req.y(),
                    req.z(),
                    req.type(),
                    e);
            return false;
        }
    }
}
