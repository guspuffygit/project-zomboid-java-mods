package com.sentientsimulations.projectzomboid.admincore;

import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import se.krka.kahlua.integration.annotations.LuaMethod;
import se.krka.kahlua.vm.KahluaTable;
import zombie.characters.Capability;
import zombie.characters.IsoPlayer;
import zombie.core.raknet.UdpConnection;
import zombie.entity.GameEntity;
import zombie.network.GameServer;
import zombie.network.ServerMap;
import zombie.world.moddata.GlobalModData;

/** Server-issued, expiring read interest. Never changes the physical player's native relevance. */
public final class AdminCoreObserverInterest {
    static final int RADIUS = 3;
    static final int MAX_RADIUS = 9;
    static final long TTL = 6000;
    private static final String FEATURE = "ADMIN_SPECTATOR";
    private static final Map<UdpConnection, Map<IsoPlayer, Lease>> INTEREST =
            new ConcurrentHashMap<>();
    private static volatile boolean patchesReady;

    private AdminCoreObserverInterest() {}

    @LuaMethod
    public static boolean ready() {
        if (patchesReady) return true;
        try {
            for (String name : AdminCoreObserverInterestPatch.TARGETS) {
                var type =
                        Class.forName(
                                name, false, AdminCoreObserverInterest.class.getClassLoader());
                if (type.getDeclaredField(AdminCoreObserverInterestPatch.MARKER).getType()
                        != boolean.class) return false;
            }
            for (String name : AdminCoreObserverReplicationPatch.TARGETS) {
                try {
                    var type =
                            Class.forName(
                                    name, false, AdminCoreObserverInterest.class.getClassLoader());
                    if (type.getDeclaredField(AdminCoreObserverReplicationPatch.MARKER).getType()
                            != boolean.class) return false;
                } catch (ClassNotFoundException olderStorm) {
                    // Older Storm versions do not replace these native broadcast loops.
                }
            }
            patchesReady = true;
            return true;
        } catch (ReflectiveOperationException | LinkageError unavailable) {
            return false;
        }
    }

    record Lease(
            IsoPlayer actor,
            IsoPlayer target,
            UdpConnection connection,
            UdpConnection targetConnection,
            String id,
            String mode,
            double x,
            double y,
            double z,
            int radius,
            long expires,
            long sequence,
            long movedAt) {
        double center(int axis) {
            double offset = axis == 0 ? x : axis == 1 ? y : z;
            if (mode.equals("FREE")) return offset;
            double position = axis == 0 ? target.getX() : axis == 1 ? target.getY() : target.getZ();
            return position + (mode.equals("SOFT") ? offset : 0);
        }
    }

    static boolean policyAllows(IsoPlayer actor, String feature) {
        if (GlobalModData.instance == null) return false;
        KahluaTable policy = GlobalModData.instance.get("UniversalAdminCore.OperationsPolicy.v1");
        if (policy == null) return true;
        Object disabled = policy.rawget("disabled");
        if (disabled instanceof KahluaTable table && Boolean.TRUE.equals(table.rawget(feature)))
            return false;
        Object users = policy.rawget("users");
        if (users instanceof KahluaTable table) {
            Object user = table.rawget(actor.getUsername());
            if (user instanceof KahluaTable own && Boolean.FALSE.equals(own.rawget(feature)))
                return false;
        }
        return true;
    }

    static boolean actorAllowed(IsoPlayer actor) {
        return GameServer.server
                && actor != null
                && !actor.isDead()
                && actor.getVehicle() == null
                && actor.getRole() != null
                && actor.getRole().hasAdminPower()
                && actor.getRole().hasCapability(Capability.TeleportToPlayer)
                && actor.getRole().hasCapability(Capability.SeePlayersConnected)
                && actor.getRole().hasCapability(Capability.UseDebugContextMenu)
                && policyAllows(actor, FEATURE)
                && policyAllows(actor, "ADMIN_RENDER_DEBUG");
    }

    static boolean live(Lease lease, long now) {
        try {
            return now < lease.expires()
                    && actorAllowed(lease.actor())
                    && lease.connection().isFullyConnected()
                    && lease.targetConnection().isFullyConnected()
                    && lease.connection().havePlayer(lease.actor())
                    && lease.targetConnection().havePlayer(lease.target())
                    && !lease.target().isDead()
                    && GameServer.getConnectionFromPlayer(lease.actor()) == lease.connection()
                    && GameServer.getConnectionFromPlayer(lease.target())
                            == lease.targetConnection()
                    && position(lease.target().getX(), lease.target().getY(), lease.target().getZ())
                    && position(lease.center(0), lease.center(1), lease.center(2));
        } catch (RuntimeException | LinkageError unavailable) {
            return false;
        }
    }

    private static Lease current(IsoPlayer actor, String id) {
        UdpConnection connection = actor == null ? null : GameServer.getConnectionFromPlayer(actor);
        Map<IsoPlayer, Lease> leases = connection == null ? null : INTEREST.get(connection);
        Lease lease = leases == null ? null : leases.get(actor);
        if (lease == null || !lease.id().equals(id)) return null;
        if (!live(lease, System.currentTimeMillis())) {
            remove(lease);
            return null;
        }
        return lease;
    }

    private static void remove(Lease lease) {
        Map<IsoPlayer, Lease> leases = INTEREST.get(lease.connection());
        if (leases != null) {
            leases.remove(lease.actor(), lease);
            if (leases.isEmpty()) INTEREST.remove(lease.connection(), leases);
        }
    }

    private static void put(Lease lease) {
        INTEREST.computeIfAbsent(lease.connection(), ignored -> new ConcurrentHashMap<>())
                .put(lease.actor(), lease);
    }

    private static boolean mode(String mode) {
        return "FOLLOW".equals(mode) || "SOFT".equals(mode) || "FREE".equals(mode);
    }

    static boolean position(double x, double y, double z) {
        ServerMap map = ServerMap.instance;
        return Double.isFinite(x)
                && Double.isFinite(y)
                && Double.isFinite(z)
                && z >= -32
                && z < 32
                && map != null
                && map.cellMap != null
                && x >= (double) map.getMinX() * 64
                && y >= (double) map.getMinY() * 64
                && x < (double) (map.getMaxX() + 1) * 64
                && y < (double) (map.getMaxY() + 1) * 64;
    }

    @LuaMethod
    public static boolean start(IsoPlayer actor, IsoPlayer target, String id, String mode) {
        return startWithRadius(actor, target, id, mode, RADIUS);
    }

    private static boolean validRadius(double radius) {
        return Double.isFinite(radius)
                && radius == Math.floor(radius)
                && radius >= RADIUS
                && radius <= MAX_RADIUS;
    }

    @LuaMethod
    public static boolean startWithRadius(
            IsoPlayer actor, IsoPlayer target, String id, String mode, double radius) {
        if (!actorAllowed(actor)
                || !validRadius(radius)
                || target == null
                || target.isDead()
                || id == null
                || id.isEmpty()
                || id.length() > 100
                || !mode(mode)
                || !position(target.getX(), target.getY(), target.getZ())) return false;
        UdpConnection connection = GameServer.getConnectionFromPlayer(actor);
        UdpConnection targetConnection = GameServer.getConnectionFromPlayer(target);
        if (connection == null
                || targetConnection == null
                || !connection.havePlayer(actor)
                || !targetConnection.havePlayer(target)) return false;
        long now = System.currentTimeMillis();
        boolean free = mode.equals("FREE");
        Lease lease =
                new Lease(
                        actor,
                        target,
                        connection,
                        targetConnection,
                        id,
                        mode,
                        free ? target.getX() : 0,
                        free ? target.getY() : 0,
                        free ? target.getZ() : 0,
                        (int) radius,
                        now + TTL,
                        0,
                        now);
        if (!live(lease, now)) return false;
        put(lease);
        return true;
    }

    @LuaMethod
    public static boolean renew(IsoPlayer actor, String id) {
        Lease old = current(actor, id);
        if (old == null) return false;
        put(
                new Lease(
                        old.actor(),
                        old.target(),
                        old.connection(),
                        old.targetConnection(),
                        old.id(),
                        old.mode(),
                        old.x(),
                        old.y(),
                        old.z(),
                        old.radius(),
                        System.currentTimeMillis() + TTL,
                        old.sequence(),
                        old.movedAt()));
        return true;
    }

    static Lease moved(
            Lease old, long sequence, String mode, double x, double y, double z, long now) {
        return moved(old, sequence, mode, x, y, z, old.radius(), now);
    }

    static Lease moved(
            Lease old,
            long sequence,
            String mode,
            double x,
            double y,
            double z,
            double radius,
            long now) {
        if (!mode(mode)
                || !validRadius(radius)
                || sequence <= old.sequence()
                || sequence > 9007199254740991L
                || now - old.movedAt() < 200
                || !position(x, y, z)) return null;
        if (mode.equals("FOLLOW")) {
            x = 0;
            y = 0;
            z = 0;
        } else if (mode.equals("SOFT")) {
            x -= old.target().getX();
            y -= old.target().getY();
            z -= old.target().getZ();
            if (Math.abs(x) > 8 || Math.abs(y) > 8 || z != 0) return null;
        } else {
            double budget = Math.min(Math.max(now - old.movedAt(), 0), 1000) * .03;
            double dx = x - old.center(0), dy = y - old.center(1);
            if (dx * dx + dy * dy > budget * budget || z != old.center(2)) return null;
        }
        return new Lease(
                old.actor(),
                old.target(),
                old.connection(),
                old.targetConnection(),
                old.id(),
                mode,
                x,
                y,
                z,
                (int) radius,
                old.expires(),
                sequence,
                now);
    }

    @LuaMethod
    public static boolean move(
            IsoPlayer actor,
            String id,
            double sequence,
            String mode,
            double x,
            double y,
            double z) {
        Lease old = current(actor, id);
        return old != null && moveWithRadius(actor, id, sequence, mode, x, y, z, old.radius());
    }

    @LuaMethod
    public static boolean moveWithRadius(
            IsoPlayer actor,
            String id,
            double sequence,
            String mode,
            double x,
            double y,
            double z,
            double radius) {
        if (!Double.isFinite(sequence) || sequence != Math.floor(sequence)) return false;
        Lease old = current(actor, id);
        Lease changed =
                old == null
                        ? null
                        : moved(
                                old,
                                (long) sequence,
                                mode,
                                x,
                                y,
                                z,
                                radius,
                                System.currentTimeMillis());
        if (changed == null) return false;
        put(changed);
        return true;
    }

    static Lease movedSoft(
            Lease old, long sequence, double offsetX, double offsetY, double radius, long now) {
        if (!Double.isFinite(offsetX)
                || !Double.isFinite(offsetY)
                || Math.abs(offsetX) > 8
                || Math.abs(offsetY) > 8) return null;
        return moved(
                old,
                sequence,
                "SOFT",
                old.target().getX() + offsetX,
                old.target().getY() + offsetY,
                old.target().getZ(),
                radius,
                now);
    }

    @LuaMethod
    public static boolean moveSoft(
            IsoPlayer actor,
            String id,
            double sequence,
            double offsetX,
            double offsetY,
            double radius) {
        if (!Double.isFinite(sequence) || sequence != Math.floor(sequence)) return false;
        Lease old = current(actor, id);
        Lease changed =
                old == null
                        ? null
                        : movedSoft(
                                old,
                                (long) sequence,
                                offsetX,
                                offsetY,
                                radius,
                                System.currentTimeMillis());
        if (changed == null) return false;
        put(changed);
        return true;
    }

    @LuaMethod
    public static double radius(IsoPlayer actor, String id) {
        Lease lease = current(actor, id);
        return lease == null ? 0 : lease.radius();
    }

    @LuaMethod
    public static double offset(IsoPlayer actor, String id, int axis) {
        Lease lease = current(actor, id);
        if (lease == null || axis < 0 || axis > 1) return Double.NaN;
        return "SOFT".equals(lease.mode()) ? axis == 0 ? lease.x() : lease.y() : 0;
    }

    @LuaMethod
    public static double coordinate(IsoPlayer actor, String id, int axis) {
        Lease lease = current(actor, id);
        return lease == null || axis < 0 || axis > 2 ? Double.NaN : lease.center(axis);
    }

    @LuaMethod
    public static double remaining(IsoPlayer actor, String id) {
        Lease lease = current(actor, id);
        return lease == null ? 0 : Math.max(0, lease.expires() - System.currentTimeMillis());
    }

    @LuaMethod
    public static double sequence(IsoPlayer actor, String id) {
        Lease lease = current(actor, id);
        return lease == null ? -1 : lease.sequence();
    }

    @LuaMethod
    public static String mode(IsoPlayer actor, String id) {
        Lease lease = current(actor, id);
        return lease == null ? null : lease.mode();
    }

    @LuaMethod
    public static void stop(IsoPlayer actor, String id) {
        // Cleanup must also work after role revocation/disconnection.
        for (Map<IsoPlayer, Lease> leases : INTEREST.values()) {
            Lease lease = leases.get(actor);
            if (lease != null && (id == null || lease.id().equals(id))) remove(lease);
        }
    }

    static boolean contains(Lease lease, double x, double y) {
        int cx = (int) Math.floor(lease.center(0) / 8), cy = (int) Math.floor(lease.center(1) / 8);
        return Double.isFinite(x)
                && Double.isFinite(y)
                && x >= (cx - lease.radius()) * 8.0
                && x < (cx + lease.radius() + 1) * 8.0
                && y >= (cy - lease.radius()) * 8.0
                && y < (cy + lease.radius() + 1) * 8.0;
    }

    public static boolean observerRelevant(UdpConnection connection, double x, double y) {
        if (connection == null) return false;
        Map<IsoPlayer, Lease> leases = INTEREST.get(connection);
        if (leases == null) return false;
        long now = System.currentTimeMillis();
        for (Lease lease : leases.values()) {
            if (!live(lease, now)) remove(lease);
            else if (contains(lease, x, y)) return true;
        }
        return false;
    }

    public static boolean relevant(UdpConnection connection, float x, float y) {
        return connection.isRelevantTo(x, y) || observerRelevant(connection, x, y);
    }

    public static boolean replicationRelevant(
            UdpConnection connection, float x, float y, Object entity) {
        if (connection == null) return false;
        if (connection.isRelevantTo(x, y)) return true;
        if (!(entity instanceof GameEntity placed)) return false;
        var square = placed.getSquare();
        if (square == null) return false;
        double z = square.getZ();
        Map<IsoPlayer, Lease> leases = INTEREST.get(connection);
        if (leases == null) return false;
        long now = System.currentTimeMillis();
        for (Lease lease : leases.values()) {
            if (!live(lease, now)) remove(lease);
            else if (z == Math.floor(lease.center(2)) && contains(lease, x, y)) return true;
        }
        return false;
    }

    public static boolean relevantWithin(
            UdpConnection connection, float x, float y, float distance) {
        return connection.RelevantTo(x, y, distance) || observerRelevant(connection, x, y);
    }

    public static boolean chunk(UdpConnection connection, int wx, int wy) {
        return observerRelevant(connection, wx * 8.0 + 4, wy * 8.0 + 4);
    }

    public static void retain(ServerMap map) {
        if (!GameServer.server || map.cellMap == null) return;
        long now = System.currentTimeMillis();
        for (Map<IsoPlayer, Lease> leases : INTEREST.values())
            for (Lease lease : leases.values()) {
                if (!live(lease, now)) {
                    remove(lease);
                    continue;
                }
                int cx = (int) Math.floor(lease.center(0) / 8),
                        cy = (int) Math.floor(lease.center(1) / 8);
                // Retain only server cells intersecting this bounded read-only view.
                try {
                    for (int x = Math.floorDiv(cx - lease.radius(), 8);
                            x <= Math.floorDiv(cx + lease.radius(), 8);
                            x++)
                        for (int y = Math.floorDiv(cy - lease.radius(), 8);
                                y <= Math.floorDiv(cy + lease.radius(), 8);
                                y++) map.loadOrKeepRelevent(x - map.getMinX(), y - map.getMinY());
                } catch (RuntimeException unavailable) {
                    remove(lease);
                }
            }
    }

    public static boolean retained(ServerMap.ServerCell cell) {
        long now = System.currentTimeMillis();
        for (Map<IsoPlayer, Lease> leases : INTEREST.values())
            for (Lease lease : leases.values()) {
                if (!live(lease, now)) {
                    remove(lease);
                    continue;
                }
                int cx = (int) Math.floor(lease.center(0) / 8),
                        cy = (int) Math.floor(lease.center(1) / 8);
                if (cell.wx * 8 <= cx + lease.radius()
                        && (cell.wx + 1) * 8 > cx - lease.radius()
                        && cell.wy * 8 <= cy + lease.radius()
                        && (cell.wy + 1) * 8 > cy - lease.radius()) return true;
            }
        return false;
    }
}
