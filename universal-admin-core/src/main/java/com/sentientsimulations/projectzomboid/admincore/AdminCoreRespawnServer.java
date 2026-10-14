package com.sentientsimulations.projectzomboid.admincore;

import java.sql.Connection;
import java.util.Arrays;
import java.util.Map;
import java.util.UUID;
import java.util.WeakHashMap;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import se.krka.kahlua.vm.KahluaTable;
import zombie.Lua.LuaManager;
import zombie.characters.IsoPlayer;
import zombie.core.Core;
import zombie.core.network.ByteBufferReader;
import zombie.core.raknet.UdpConnection;
import zombie.core.znet.SteamUtils;
import zombie.iso.areas.SafeHouse;
import zombie.network.GameServer;
import zombie.network.IConnection;
import zombie.network.PacketTypes;
import zombie.network.ServerOptions;
import zombie.network.TableNetworkUtils;
import zombie.network.packets.connection.ConnectedCoopPacket;
import zombie.savefile.ServerPlayerDB;

/** Server-owned, connection-bound tickets for exactly one new character. */
public final class AdminCoreRespawnServer {
    public static final String MODULE = "UniversalAdminRespawn";
    public static final String PREFIX = "UACRespawn:";
    static final String MARKER = "UniversalAdminCore.RespawnAttempt.v1";
    private static final Logger LOG = LoggerFactory.getLogger(AdminCoreRespawnServer.class);
    private static final long TICKET_MILLIS = 30 * 60_000L;
    private static final Map<UdpConnection, Session> SESSIONS = new WeakHashMap<>();
    private static final ThreadLocal<Creation> CREATION = new ThreadLocal<>();
    private static final ThreadLocal<ConnectScope> CONNECT = new ThreadLocal<>();

    private static final class ConnectScope {
        final IConnection connection;
        final ConnectScope previous;
        int slot = -1;

        ConnectScope(IConnection connection, ConnectScope previous) {
            this.connection = connection;
            this.previous = previous;
        }
    }

    private static final class Session {
        final Ticket[] tickets = new Ticket[4];
        final boolean[] negotiated = new boolean[4];
        final SafeHouse[][] pages = new SafeHouse[4][];
        final long[] pagesExpire = new long[4];
        long lastRequest;
    }

    record Ticket(
            String token,
            String request,
            String username,
            SafeHouse house,
            String key,
            long expires) {}

    record Creation(
            UdpConnection connection,
            int slot,
            AdminCoreRespawnStore.Account account,
            Ticket ticket,
            boolean negotiated) {}

    private AdminCoreRespawnServer() {}

    static boolean enabled() {
        return GameServer.server && ServerOptions.instance.safehouseAllowRespawn.getValue();
    }

    static String key(SafeHouse house) {
        return house.getX()
                + ":"
                + house.getY()
                + ":"
                + house.getW()
                + ":"
                + house.getH()
                + ":"
                + house.getDatetimeCreated();
    }

    static boolean member(SafeHouse house, String username) {
        return house != null
                && username != null
                && !username.isBlank()
                && (username.equals(house.getOwner()) || house.getPlayers().contains(username));
    }

    static SafeHouse find(String key, String username) {
        for (SafeHouse house : SafeHouse.getSafehouseList())
            if (key(house).equals(key) && member(house, username)) return house;
        return null;
    }

    static AdminCoreRespawnStore.Account account(UdpConnection connection, int slot) {
        boolean steam = GameServer.coop && SteamUtils.isSteamModeEnabled();
        return new AdminCoreRespawnStore.Account(
                steam ? connection.getIDStr() : connection.getUserName(),
                Core.gameSaveWorld,
                slot,
                steam);
    }

    private static Connection database() {
        ServerPlayerDB database = ServerPlayerDB.getInstance();
        return database == null ? null : database.conn;
    }

    private static String authenticatedName(
            UdpConnection connection, int slot, AdminCoreRespawnStore.Profile profile) {
        if (slot == 0) return connection.getUserName();
        // Never trust a new split-screen username supplied in a request. An existing slot belongs
        // to its authenticated primary account; any currently established slot must also match.
        if (profile == null || profile.splitUsername() == null || profile.splitUsername().isBlank())
            return null;
        String established = connection.getUserName(slot);
        return established == null
                        || established.isBlank()
                        || established.equals(profile.splitUsername())
                ? profile.splitUsername()
                : null;
    }

    private static AdminCoreRespawnStore.Profile synchronizeDeadProfile(
            Connection db,
            AdminCoreRespawnStore.Account account,
            AdminCoreRespawnStore.Profile profile,
            UdpConnection connection,
            int slot,
            String username,
            IsoPlayer current)
            throws Exception {
        if (!enabled()
                || profile == null
                || profile.dead()
                || username == null
                || current == null
                || connection.getPlayerAt(slot) != current
                || !current.isDead()
                || !username.equals(current.getUsername())) return profile;
        if (profile.data() == null
                || profile.data().length == 0
                || AdminCoreRespawnStore.pending(db, account) != null)
            throw new IllegalStateException("Existing player save needs recovery.");

        // B42.21 normally saves players every three minutes. Construct its native snapshot once:
        // its constructor swallows serialization failures, so validate before writing any data.
        Class<?> type = Class.forName("zombie.savefile.ServerPlayerDB$NetworkCharacterData");
        var constructor =
                type.getDeclaredConstructor(IsoPlayer.class, int.class, UdpConnection.class);
        constructor.setAccessible(true);
        Object snapshot = constructor.newInstance(current, slot, connection);
        var bufferField = type.getDeclaredField("buffer");
        bufferField.setAccessible(true);
        byte[] buffer = (byte[]) bufferField.get(snapshot);
        if (buffer == null || buffer.length == 0)
            throw new IllegalStateException("Dead player could not be saved safely.");
        if (connection.getPlayerAt(slot) != current
                || !current.isDead()
                || !username.equals(current.getUsername())
                || !account.equals(account(connection, slot))
                || AdminCoreRespawnStore.pending(db, account) != null)
            throw new IllegalStateException("Respawning player changed during saving.");
        // Use the native writer directly: no delayed snapshot may outlive this respawn request.
        var writer =
                ServerPlayerDB.class.getDeclaredMethod("serverUpdateNetworkCharacterInt", type);
        writer.setAccessible(true);
        writer.invoke(ServerPlayerDB.getInstance(), snapshot);
        var saved = AdminCoreRespawnStore.read(db, account);
        // The native writer catches SQL failures and rolls back, so successful readback is
        // required.
        if (saved == null
                || saved.id() != profile.id()
                || !saved.dead()
                || !Arrays.equals(buffer, saved.data()))
            throw new IllegalStateException("Dead player save did not complete.");
        return saved;
    }

    /** Called before native ClientCommand's null-character rejection; foreign packets untouched. */
    @SuppressWarnings("PMD.CloseResource") // ServerPlayerDB owns the borrowed connection lifecycle.
    public static boolean command(ByteBufferReader reader, UdpConnection connection) {
        var copy = new ByteBufferReader(reader.bb.duplicate());
        boolean ours = false;
        int slot = -1;
        String request = null;
        try {
            copy.getByte();
            ours = MODULE.equals(copy.getUTF());
            if (!ours) return false;
            if (copy.remaining() > 4096) return true;
            String command = copy.getUTF();
            KahluaTable args = LuaManager.platform.newTable();
            if (copy.getBoolean()) TableNetworkUtils.load(args, copy);
            slot = integer(args.rawget("playerIndex"));
            request = string(args.rawget("requestId"), 80);
            if (slot < 0
                    || slot > 3
                    || connection == null
                    || connection.getUserName() == null
                    || request == null) return true;
            Session session = SESSIONS.computeIfAbsent(connection, ignored -> new Session());
            if (command.equals("cancel")) {
                session.tickets[slot] = null;
                session.pages[slot] = null;
                return true;
            }
            long now = System.currentTimeMillis();
            if (now - session.lastRequest < 150) {
                reject(connection, slot, request, "Please wait a moment and try again.", false);
                return true;
            }
            session.lastRequest = now;
            var db = database();
            if (db == null) {
                reject(
                        connection,
                        slot,
                        request,
                        "Safehouse spawning is temporarily unavailable. Choose a normal location.",
                        false);
                return true;
            }
            ServerPlayerDB.getInstance().process();
            var account = account(connection, slot);
            AdminCoreRespawnStore.recoverUnwritten(db, account);
            var profile = AdminCoreRespawnStore.read(db, account);
            String username = authenticatedName(connection, slot, profile);
            IsoPlayer current = connection.getPlayerAt(slot);
            if (command.equals("choices") || command.equals("choose")) {
                profile =
                        synchronizeDeadProfile(
                                db, account, profile, connection, slot, username, current);
            }
            boolean eligible =
                    enabled()
                            && username != null
                            && (current == null || current.isDead())
                            && (profile == null || profile.dead());
            if (command.equals("choices")) {
                var houses = SafeHouse.getSafehouseList();
                Object requestedOffset = args.rawget("offset");
                int offset =
                        requestedOffset == null
                                ? 0
                                : pageOffset(requestedOffset, Integer.MAX_VALUE);
                if (offset < 0) {
                    reject(
                            connection,
                            slot,
                            request,
                            "Safehouse list changed. Refresh the list.",
                            false);
                    return true;
                }
                if (offset == 0) {
                    session.pages[slot] = houses.toArray(SafeHouse[]::new);
                    session.pagesExpire[slot] = now + 120_000L;
                }
                SafeHouse[] snapshot = session.pages[slot];
                if (snapshot == null
                        || offset > snapshot.length
                        || session.pagesExpire[slot] < now) {
                    session.pages[slot] = null;
                    reject(
                            connection,
                            slot,
                            request,
                            "Safehouse list changed. Refresh the list.",
                            false);
                    return true;
                }
                session.negotiated[slot] = enabled() && username != null;
                KahluaTable reply = reply(slot, request);
                reply.rawset("enabled", enabled() && username != null);
                reply.rawset("offset", (double) offset);
                KahluaTable rows = LuaManager.platform.newTable();
                int index = 0;
                if (eligible) {
                    var present =
                            java.util.Collections.newSetFromMap(
                                    new java.util.IdentityHashMap<SafeHouse, Boolean>());
                    present.addAll(houses);
                    int cursor = offset;
                    while (cursor < snapshot.length && index < 64) {
                        SafeHouse house = snapshot[cursor++];
                        if (!present.contains(house)
                                || !member(house, username)
                                || house.getW() <= 0
                                || house.getH() <= 0) continue;
                        KahluaTable row = LuaManager.platform.newTable();
                        row.rawset("id", key(house));
                        row.rawset("name", house.getTitle());
                        row.rawset("owner", house.getOwner());
                        coordinates(row, house);
                        rows.rawset((double) ++index, row);
                    }
                    if (cursor < snapshot.length) reply.rawset("nextOffset", (double) cursor);
                }
                if (reply.rawget("nextOffset") == null) session.pages[slot] = null;
                reply.rawset("rows", rows);
                send(connection, "choices", reply);
            } else if (command.equals("choose")) {
                session.tickets[slot] = null;
                session.pages[slot] = null;
                String houseId = string(args.rawget("houseId"), 160);
                SafeHouse house = eligible && houseId != null ? find(houseId, username) : null;
                if (house == null) {
                    reject(
                            connection,
                            slot,
                            request,
                            "Safehouse access changed. Choose again.",
                            false);
                    return true;
                }
                String token = UUID.randomUUID().toString();
                session.tickets[slot] =
                        new Ticket(
                                token, request, username, house, key(house), now + TICKET_MILLIS);
                KahluaTable reply = reply(slot, request);
                reply.rawset("token", token);
                reply.rawset("regionKey", PREFIX + token);
                coordinates(reply, house);
                send(connection, "selected", reply);
            }
        } catch (Exception failure) {
            if (ours) LOG.warn("[UAC respawn] Request rejected: {}", failure.toString());
            if (ours && connection != null && slot >= 0 && slot < 4 && request != null) {
                reject(
                        connection,
                        slot,
                        request,
                        "Safehouse spawning is temporarily unavailable. Choose a normal location.",
                        false);
            }
        }
        return ours;
    }

    private static int pageOffset(Object value, int total) {
        if (!(value instanceof Number number)) return -1;
        double numeric = number.doubleValue();
        return Double.isFinite(numeric)
                        && numeric >= 0
                        && numeric <= total
                        && numeric == Math.floor(numeric)
                ? (int) numeric
                : -1;
    }

    private static int integer(Object value) {
        if (!(value instanceof Number number)) return -1;
        double numeric = number.doubleValue();
        return Double.isFinite(numeric)
                        && numeric >= 0
                        && numeric <= 3
                        && numeric == Math.floor(numeric)
                ? (int) numeric
                : -1;
    }

    private static String string(Object value, int limit) {
        return value instanceof String text && !text.isEmpty() && text.length() <= limit
                ? text
                : null;
    }

    /** True skips creation. Recognized-but-invalid tickets never fall back to another spawn. */
    @SuppressWarnings("PMD.CloseResource") // ServerPlayerDB owns the borrowed connection lifecycle.
    public static boolean begin(String region, int slot, UdpConnection connection) {
        CREATION.remove();
        boolean selected = region != null && region.startsWith(PREFIX);
        Session session = SESSIONS.get(connection);
        if (!selected) {
            if (session != null && slot >= 0 && slot < 4) {
                session.tickets[slot] = null;
                session.pages[slot] = null;
            }
            CREATION.set(
                    new Creation(
                            connection,
                            slot,
                            null,
                            null,
                            session != null && slot >= 0 && slot < 4 && session.negotiated[slot]));
            return false;
        }
        String request = "";
        try {
            if (slot < 0 || slot > 3 || session == null)
                throw new IllegalStateException("Choose a safehouse again.");
            Ticket ticket = session.tickets[slot];
            session.tickets[slot] = null;
            session.pages[slot] = null;
            if (ticket == null)
                throw new IllegalStateException("Safehouse choice expired. Choose again.");
            request = ticket.request();
            var account = account(connection, slot);
            var db = database();
            ServerPlayerDB.getInstance().process();
            var profile = AdminCoreRespawnStore.read(db, account);
            IsoPlayer current = connection.getPlayerAt(slot);
            if (!enabled()
                    || !region.equals(PREFIX + ticket.token())
                    || ticket.expires() < System.currentTimeMillis()
                    || !ticket.username().equals(authenticatedName(connection, slot, profile))
                    || (current != null && !current.isDead())
                    || (profile != null && !profile.dead())
                    || !SafeHouse.getSafehouseList().contains(ticket.house())
                    || !ticket.key().equals(key(ticket.house()))
                    || !member(ticket.house(), ticket.username()))
                throw new IllegalStateException("Safehouse access changed. Choose again.");
            AdminCoreRespawnStore.begin(
                    db,
                    account,
                    new AdminCoreRespawnStore.Pending(
                            ticket.token(),
                            ticket.key(),
                            ticket.username(),
                            System.currentTimeMillis() + 10 * 60_000L,
                            profile));
            CREATION.set(new Creation(connection, slot, account, ticket, true));
            return false;
        } catch (Exception failure) {
            LOG.warn("[UAC respawn] Creation rejected: {}", failure.toString());
            reject(
                    connection,
                    slot,
                    request,
                    "Safehouse choice is no longer valid. Choose again.",
                    true);
            return true;
        }
    }

    public static void end() {
        Creation creation = CREATION.get();
        CREATION.remove();
        if (creation != null && creation.ticket() != null)
            try {
                AdminCoreRespawnStore.recoverUnwritten(database(), creation.account());
            } catch (Exception failure) {
                LOG.warn("[UAC respawn] Deferred journal recovery: {}", failure.toString());
            }
    }

    public static int coordinate(int original, int axis) {
        Creation creation = CREATION.get();
        if (creation == null || creation.ticket() == null) return original;
        SafeHouse house = creation.ticket().house();
        return axis == 0
                ? house.getX() + house.getW() / 2
                : axis == 1 ? house.getY() + house.getH() / 2 : 0;
    }

    public static float position(float original, int axis) {
        Creation creation = CREATION.get();
        return creation == null || creation.ticket() == null
                ? original
                : coordinate(0, axis) + (axis < 2 ? .5f : 0f);
    }

    public static boolean legacyPreference(boolean original) {
        Creation creation = CREATION.get();
        return creation != null && creation.negotiated() ? false : original;
    }

    public static void mark(IsoPlayer player) {
        Creation creation = CREATION.get();
        if (creation != null && creation.ticket() != null) {
            player.getModData().rawset(MARKER, creation.ticket().token());
            player.setUsername(creation.ticket().username());
        }
    }

    public static Object enterConnect(IConnection connection) {
        ConnectScope scope = new ConnectScope(connection, CONNECT.get());
        CONNECT.set(scope);
        return scope;
    }

    public static void captureLoad(int slot, String account) {
        ConnectScope scope = CONNECT.get();
        if (scope != null) scope.slot = account == null ? -1 : slot;
    }

    public static boolean acceptLoaded(IsoPlayer player) {
        ConnectScope scope = CONNECT.get();
        return scope != null
                && scope.slot >= 0
                && scope.slot < 4
                && accept(player, scope.connection, scope.slot);
    }

    @SuppressWarnings("PMD.CompareObjectsWithEquals") // Only the exact active scope may be unwound.
    public static void exitConnect(Object expected) {
        if (expected instanceof ConnectScope scope && CONNECT.get() == scope) {
            if (scope.previous == null) CONNECT.remove();
            else CONNECT.set(scope.previous);
        }
    }

    public static void clearConnect() {
        exitConnect(CONNECT.get());
    }

    /** Runs on the native loaded character before world/connection assignment. */
    @SuppressWarnings("PMD.CloseResource") // ServerPlayerDB owns the borrowed connection lifecycle.
    public static boolean accept(IsoPlayer player, IConnection connection, int slot) {
        if (player == null || !(connection instanceof UdpConnection udp)) return true;
        Object marker = player.getModData().rawget(MARKER);
        try {
            var db = database();
            var account = account(udp, slot);
            var pending = AdminCoreRespawnStore.pending(db, account);
            if (marker == null && pending == null) return true;
            // A journal with unchanged old data means native creation never committed. It cannot
            // authorize that dead/null profile as a successful new spawn.
            if (pending == null || !pending.token().equals(marker))
                throw new IllegalStateException("Missing attempt journal.");
            var current = AdminCoreRespawnStore.read(db, account);
            SafeHouse house = find(pending.house(), pending.username());
            boolean allowed =
                    enabled()
                            && pending.expires() >= System.currentTimeMillis()
                            && pending.username().equals(authenticatedName(udp, slot, current))
                            && house != null
                            && house.containsLocation(player.getX(), player.getY())
                            && player.getZi() == 0
                            && !player.isDead();
            if (!allowed) {
                if (!AdminCoreRespawnStore.rollback(db, account, pending, current))
                    throw new IllegalStateException("Character rollback was not safe.");
                reject(
                        udp,
                        slot,
                        "",
                        "Safehouse access changed while loading. Choose another spawn.",
                        true);
                return false;
            }
            player.getModData().rawset(MARKER, null);
            if (!AdminCoreRespawnStore.commit(db, account, current, serialize(player)))
                throw new IllegalStateException("Character commit failed.");
            return true;
        } catch (Exception failure) {
            LOG.error("[UAC respawn] Final authorization failed closed", failure);
            reject(udp, slot, "", "Couldn't finish spawning. Rejoin or contact an admin.", true);
            return false;
        }
    }

    private static byte[] serialize(IsoPlayer player) throws java.io.IOException {
        // Same native serializer and bounded growth used by ServerPlayerDB.NetworkCharacterData.
        for (int size = 32768; size <= 1048576; size += 32768) {
            java.nio.ByteBuffer buffer = java.nio.ByteBuffer.allocate(size);
            try {
                player.save(buffer);
                return java.util.Arrays.copyOf(buffer.array(), buffer.position());
            } catch (java.nio.BufferOverflowException overflow) {
                if (size == 1048576) throw overflow;
            }
        }
        throw new java.io.IOException("Character exceeds native save size.");
    }

    static void coordinates(KahluaTable table, SafeHouse house) {
        table.rawset("x", (double) (house.getX() + house.getW() / 2));
        table.rawset("y", (double) (house.getY() + house.getH() / 2));
        table.rawset("z", 0.0);
    }

    private static KahluaTable reply(int slot, String request) {
        KahluaTable reply = LuaManager.platform.newTable();
        reply.rawset("playerIndex", (double) slot);
        reply.rawset("requestId", request);
        return reply;
    }

    private static void send(UdpConnection connection, String command, KahluaTable args) {
        GameServer.sendServerCommand(MODULE, command, args, connection);
    }

    private static void reject(
            UdpConnection connection, int slot, String request, String message, boolean creation) {
        KahluaTable reply = reply(slot, request);
        reply.rawset("message", message);
        reply.rawset("creation", creation);
        send(connection, "rejected", reply);
        if (creation && !connection.isFullyConnected()) {
            // Initial game loading has no AddCoopPlayer state to return to. Native disconnect
            // terminates its wait; reconnect loads the restored dead/missing profile normally.
            GameServer.kick(connection, message, null);
            connection.forceDisconnect("uac-respawn-choice-invalid");
            return;
        }
        if (creation && slot >= 0 && slot < 4) {
            var packet = new ConnectedCoopPacket();
            packet.setAccessDenied(message, (byte) slot);
            var writer = connection.startPacket();
            PacketTypes.PacketType.ConnectedCoop.doPacket(writer);
            packet.write(writer);
            PacketTypes.PacketType.ConnectedCoop.send(connection);
        }
    }
}
