package com.sentientsimulations.projectzomboid.admincore;

import static org.junit.jupiter.api.Assertions.*;

import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.file.Path;
import java.sql.Connection;
import java.sql.DriverManager;
import java.util.ArrayList;
import java.util.Map;
import java.util.concurrent.ConcurrentLinkedQueue;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.vm.KahluaTable;
import zombie.Lua.LuaManager;
import zombie.characters.IsoPlayer;
import zombie.characters.SurvivorDesc;
import zombie.core.Core;
import zombie.core.network.ByteBufferReader;
import zombie.core.network.ByteBufferWriter;
import zombie.core.raknet.UdpConnection;
import zombie.iso.IsoCell;
import zombie.iso.areas.SafeHouse;
import zombie.network.GameClient;
import zombie.network.GameServer;
import zombie.network.PacketTypes;
import zombie.network.ServerOptions;
import zombie.network.TableNetworkUtils;
import zombie.savefile.ServerPlayerDB;

/**
 * Real protocol/parser/store/native types; only transport and native world allocation are isolated.
 */
class RespawnProtocolTest {
    @TempDir Path directory;
    Connection db;
    SafeHouse house;
    TestConnection alice;
    Object previousDatabase;
    boolean previousServer;
    boolean previousClient;
    boolean previousCoop;
    boolean previousEnabled;
    String previousWorld;

    @SuppressWarnings("removal")
    private static <T> T allocate(Class<T> type) throws Exception {
        var unsafeField = sun.misc.Unsafe.class.getDeclaredField("theUnsafe");
        unsafeField.setAccessible(true);
        return type.cast(((sun.misc.Unsafe) unsafeField.get(null)).allocateInstance(type));
    }

    private static java.lang.reflect.Field field(Class<?> type, String name) throws Exception {
        var result = type.getDeclaredField(name);
        result.setAccessible(true);
        return result;
    }

    @BeforeEach
    void setup() throws Exception {
        zombie.core.random.RandStandard.INSTANCE.init();
        previousServer = GameServer.server;
        previousClient = GameClient.client;
        previousCoop = GameServer.coop;
        previousWorld = Core.gameSaveWorld;
        previousEnabled = ServerOptions.instance.safehouseAllowRespawn.getValue();
        GameServer.server = true;
        GameClient.client = false;
        GameServer.coop = false;
        Core.gameSaveWorld = "respawn-test";
        ServerOptions.instance.safehouseAllowRespawn.setValue(true);
        if (LuaManager.platform == null) LuaManager.platform = new J2SEPlatform();
        db = DriverManager.getConnection("jdbc:sqlite:" + directory.resolve("players.db"));
        db.setAutoCommit(false);
        try (var q = db.createStatement()) {
            q.executeUpdate(
                    "CREATE TABLE networkPlayers (id INTEGER PRIMARY KEY,world TEXT,username TEXT,steamid TEXT,playerIndex INTEGER,x REAL,y REAL,z REAL,worldversion INTEGER,isDead INTEGER,name TEXT,splitUsername TEXT,data BLOB)");
            q.executeUpdate(
                    "INSERT INTO networkPlayers VALUES(1,'respawn-test','Alice','',0,100,100,0,241,1,'Old Alice','Alice',X'01')");
        }
        db.commit();
        var database = allocate(ServerPlayerDB.class);
        database.conn = db;
        field(ServerPlayerDB.class, "charactersToSave")
                .set(database, new ConcurrentLinkedQueue<>());
        previousDatabase = field(ServerPlayerDB.class, "instance").get(null);
        field(ServerPlayerDB.class, "instance").set(null, database);
        house = new SafeHouse(100, 100, 20, 10, "Alice");
        house.setDatetimeCreated(123);
        SafeHouse.getSafehouseList().add(house);
        alice = connection("Alice");
    }

    @AfterEach
    void cleanup() throws Exception {
        AdminCoreRespawnServer.end();
        SafeHouse.getSafehouseList().remove(house);
        ((Map<?, ?>) field(AdminCoreRespawnServer.class, "SESSIONS").get(null)).clear();
        field(ServerPlayerDB.class, "instance").set(null, previousDatabase);
        GameServer.server = previousServer;
        GameClient.client = previousClient;
        GameServer.coop = previousCoop;
        Core.gameSaveWorld = previousWorld;
        ServerOptions.instance.safehouseAllowRespawn.setValue(previousEnabled);
        if (db != null) db.close();
    }

    private TestConnection connection(String name) throws Exception {
        TestConnection result = allocate(TestConnection.class);
        result.name = name;
        result.packets = new ArrayList<>();
        result.mockPlayers = new IsoPlayer[4];
        result.connected = true;
        field(zombie.network.PacketsCache.class, "packets").set(result, new java.util.HashMap<>());
        @SuppressWarnings("unchecked")
        var packets =
                (Map<PacketTypes.PacketType, zombie.network.packets.INetworkPacket>)
                        field(zombie.network.PacketsCache.class, "packets").get(result);
        packets.put(
                PacketTypes.PacketType.Kicked,
                PacketTypes.PacketType.Kicked.handler.getDeclaredConstructor().newInstance());
        field(zombie.network.PacketsCache.class, "hashes").set(result, new java.util.HashMap<>());
        field(zombie.network.PacketsCache.class, "limits").set(result, new java.util.HashMap<>());
        return result;
    }

    private KahluaTable request(
            TestConnection connection, String command, String request, String id) throws Exception {
        return request(connection, command, request, id, null);
    }

    private KahluaTable request(
            TestConnection connection, String command, String request, String id, Object offset)
            throws Exception {
        return request(connection, 0, command, request, id, offset);
    }

    private KahluaTable request(
            TestConnection connection,
            int slot,
            String command,
            String request,
            String id,
            Object offset)
            throws Exception {
        Map<?, ?> sessions = (Map<?, ?>) field(AdminCoreRespawnServer.class, "SESSIONS").get(null);
        Object session = sessions.get(connection);
        if (session != null) field(session.getClass(), "lastRequest").setLong(session, 0);
        KahluaTable args = LuaManager.platform.newTable();
        args.rawset("playerIndex", (double) slot);
        args.rawset("requestId", request);
        if (id != null) args.rawset("houseId", id);
        if (offset != null) args.rawset("offset", offset);
        ByteBuffer bytes = ByteBuffer.allocate(8192);
        var writer = new ByteBufferWriter(bytes);
        writer.putByte(-1);
        writer.putUTF(AdminCoreRespawnServer.MODULE);
        writer.putUTF(command);
        writer.putBoolean(true);
        TableNetworkUtils.save(args, writer);
        bytes.flip();
        var reader = new ByteBufferReader(bytes);
        assertTrue(AdminCoreRespawnServer.command(reader, connection));
        assertEquals(0, bytes.position());
        return connection.lastReply();
    }

    private String choose() throws Exception {
        KahluaTable choices = request(alice, "choices", "list", null);
        assertEquals(Boolean.TRUE, choices.rawget("enabled"));
        assertEquals(1, ((KahluaTable) choices.rawget("rows")).len());
        return (String)
                request(alice, "choose", "choose", AdminCoreRespawnServer.key(house))
                        .rawget("regionKey");
    }

    @Test
    void everyEligibleHouseCanBeCollectedInBoundedPagesWithLiveMembershipChecks() throws Exception {
        var extra = new ArrayList<SafeHouse>();
        try {
            for (int i = 0; i < 350; i++) {
                SafeHouse added =
                        new SafeHouse(200 + i * 21, 100, 20, 10, i % 7 == 0 ? "Other" : "Alice");
                added.setDatetimeCreated(1000 + i);
                extra.add(added);
                SafeHouse.getSafehouseList().add(added);
            }
            var expected = new java.util.HashSet<String>();
            expected.add(AdminCoreRespawnServer.key(house));
            for (SafeHouse added : extra)
                if (AdminCoreRespawnServer.member(added, "Alice"))
                    expected.add(AdminCoreRespawnServer.key(added));
            assertEquals(301, expected.size());
            var collected = new java.util.HashSet<String>();
            int offset = 0;
            int pages = 0;
            while (true) {
                KahluaTable page =
                        request(alice, "choices", "page-" + pages++, null, (double) offset);
                assertEquals(Boolean.TRUE, page.rawget("enabled"));
                assertEquals((double) offset, page.rawget("offset"));
                KahluaTable rows = (KahluaTable) page.rawget("rows");
                assertTrue(rows.len() <= 64);
                for (int i = 1; i <= rows.len(); i++)
                    assertTrue(
                            collected.add(
                                    (String) ((KahluaTable) rows.rawget((double) i)).rawget("id")));
                Object next = page.rawget("nextOffset");
                if (next == null) break;
                int nextOffset = ((Double) next).intValue();
                assertTrue(nextOffset > offset);
                offset = nextOffset;
                assertTrue(pages < 10);
            }
            assertEquals(expected, collected);
            assertEquals(5, pages);
            house.setOwner("Other");
            house.getPlayers().remove("Alice");
            KahluaTable refreshed = request(alice, "choices", "revoked-page", null, 0.0);
            KahluaTable rows = (KahluaTable) refreshed.rawget("rows");
            for (int i = 1; i <= rows.len(); i++)
                assertNotEquals(
                        AdminCoreRespawnServer.key(house),
                        ((KahluaTable) rows.rawget((double) i)).rawget("id"));
        } finally {
            SafeHouse.getSafehouseList().removeAll(extra);
        }
    }

    @Test
    void invalidPageOffsetsAreRejectedWithoutIssuingTickets() throws Exception {
        for (Object offset :
                new Object[] {
                    -1.0, 0.5, Double.NaN, Double.POSITIVE_INFINITY, 2147483648.0, "1", 1.0
                }) {
            KahluaTable reply = request(alice, "choices", "invalid-page", null, offset);
            assertNotNull(reply.rawget("message"));
            assertNull(reply.rawget("rows"));
            assertNull(reply.rawget("regionKey"));
        }
        assertNull(AdminCoreRespawnStore.pending(db, AdminCoreRespawnServer.account(alice, 0)));
    }

    @Test
    void deletingBeforePageCursorCannotSkipNeighborsAndNewHousesAppearOnRefresh() throws Exception {
        var extra = new ArrayList<SafeHouse>();
        try {
            for (int i = 0; i < 128; i++) {
                SafeHouse added = new SafeHouse(200 + i * 21, 100, 20, 10, "Alice");
                added.setDatetimeCreated(1000 + i);
                extra.add(added);
                SafeHouse.getSafehouseList().add(added);
            }
            var expected = new java.util.HashSet<String>();
            expected.add(AdminCoreRespawnServer.key(house));
            for (SafeHouse added : extra) expected.add(AdminCoreRespawnServer.key(added));
            KahluaTable page = request(alice, "choices", "stable-first", null, 0.0);
            assertEquals(64, ((KahluaTable) page.rawget("rows")).len());
            // Removing an earlier native-list entry must not shift the next snapshot cursor.
            SafeHouse.getSafehouseList().remove(house);
            SafeHouse.getSafehouseList().remove(extra.get(100));
            expected.remove(AdminCoreRespawnServer.key(extra.get(100)));
            SafeHouse addedLater = new SafeHouse(10000, 100, 20, 10, "Alice");
            addedLater.setDatetimeCreated(99999);
            extra.add(addedLater);
            SafeHouse.getSafehouseList().add(addedLater);
            var collected = new java.util.HashSet<String>();
            int pages = 0;
            while (true) {
                KahluaTable rows = (KahluaTable) page.rawget("rows");
                for (int i = 1; i <= rows.len(); i++)
                    assertTrue(
                            collected.add(
                                    (String) ((KahluaTable) rows.rawget((double) i)).rawget("id")));
                Object offset = page.rawget("nextOffset");
                if (offset == null) break;
                assertTrue(++pages < 5);
                page = request(alice, "choices", "stable-" + pages, null, offset);
            }
            assertEquals(expected, collected);
            assertFalse(collected.contains(AdminCoreRespawnServer.key(addedLater)));
            page = request(alice, "choices", "refresh-first", null, 0.0);
            collected.clear();
            pages = 0;
            while (true) {
                KahluaTable rows = (KahluaTable) page.rawget("rows");
                for (int i = 1; i <= rows.len(); i++)
                    collected.add((String) ((KahluaTable) rows.rawget((double) i)).rawget("id"));
                Object offset = page.rawget("nextOffset");
                if (offset == null) break;
                assertTrue(++pages < 5);
                page = request(alice, "choices", "refresh-" + pages, null, offset);
            }
            assertTrue(collected.contains(AdminCoreRespawnServer.key(addedLater)));
            assertFalse(collected.contains(AdminCoreRespawnServer.key(house)));
        } finally {
            SafeHouse.getSafehouseList().removeAll(extra);
        }
    }

    @Test
    void ticketIsConnectionBoundConsumedOnceAndCoordinatesAreServerDerived() throws Exception {
        String region = choose();
        assertTrue(AdminCoreRespawnServer.begin(region, 0, connection("Alice")));
        assertFalse(AdminCoreRespawnServer.begin(region, 0, alice));
        assertEquals(110, AdminCoreRespawnServer.coordinate(-999, 0));
        assertEquals(105, AdminCoreRespawnServer.coordinate(-999, 1));
        assertEquals(110.5f, AdminCoreRespawnServer.position(-999, 0));
        AdminCoreRespawnServer.end();
        assertTrue(AdminCoreRespawnServer.begin(region, 0, alice));
        assertTrue(AdminCoreRespawnStore.read(db, AdminCoreRespawnServer.account(alice, 0)).dead());
        assertNull(AdminCoreRespawnStore.pending(db, AdminCoreRespawnServer.account(alice, 0)));
    }

    @Test
    void changedMembershipReleasedHouseBoundaryAndWrongSlotRejectBeforeAnyWrite() throws Exception {
        String region = choose();
        house.setOwner("Other");
        house.getPlayers().remove("Alice");
        assertTrue(AdminCoreRespawnServer.begin(region, 0, alice));
        house.setOwner("Alice");
        region = choose();
        SafeHouse.getSafehouseList().remove(house);
        assertTrue(AdminCoreRespawnServer.begin(region, 0, alice));
        SafeHouse.getSafehouseList().add(house);
        region = choose();
        house.setX(101);
        assertTrue(AdminCoreRespawnServer.begin(region, 0, alice));
        house.setX(100);
        region = choose();
        assertTrue(AdminCoreRespawnServer.begin(region, 1, alice));
        assertArrayEquals(
                new byte[] {1},
                AdminCoreRespawnStore.read(db, AdminCoreRespawnServer.account(alice, 0)).data());
        assertNull(AdminCoreRespawnStore.pending(db, AdminCoreRespawnServer.account(alice, 0)));
    }

    @Test
    void expiredTicketAndAliveProfileAreRejectedButFeatureHandshakeRemainsEnabled()
            throws Exception {
        String region = choose();
        Map<?, ?> sessions = (Map<?, ?>) field(AdminCoreRespawnServer.class, "SESSIONS").get(null);
        Object session = sessions.get(alice);
        var tickets =
                (AdminCoreRespawnServer.Ticket[]) field(session.getClass(), "tickets").get(session);
        var t = tickets[0];
        tickets[0] =
                new AdminCoreRespawnServer.Ticket(
                        t.token(), t.request(), t.username(), t.house(), t.key(), 0);
        assertTrue(AdminCoreRespawnServer.begin(region, 0, alice));
        try (var q = db.createStatement()) {
            q.executeUpdate("UPDATE networkPlayers SET isDead=0");
        }
        db.commit();
        KahluaTable choices = request(alice, "choices", "alive", null);
        assertEquals(Boolean.TRUE, choices.rawget("enabled"));
        assertEquals(0, ((KahluaTable) choices.rawget("rows")).len());
        KahluaTable denied =
                request(alice, "choose", "alive-choice", AdminCoreRespawnServer.key(house));
        assertNotNull(denied.rawget("message"));
        assertNull(denied.rawget("regionKey"));
    }

    @Test
    void revokedAfterCreationRollsBackExactNewProfileBeforeAcceptance() throws Exception {
        String region = choose();
        assertFalse(AdminCoreRespawnServer.begin(region, 0, alice));
        TestPlayer player = allocate(TestPlayer.class);
        player.data = LuaManager.platform.newTable();
        player.x = 110.5f;
        player.y = 105.5f;
        AdminCoreRespawnServer.mark(player);
        try (var q = db.createStatement()) {
            q.executeUpdate("UPDATE networkPlayers SET isDead=0,data=X'0203'");
        }
        db.commit();
        AdminCoreRespawnServer.end();
        house.setOwner("Other");
        house.getPlayers().remove("Alice");
        assertFalse(AdminCoreRespawnServer.accept(player, alice, 0));
        var saved = AdminCoreRespawnStore.read(db, AdminCoreRespawnServer.account(alice, 0));
        assertTrue(saved.dead());
        assertArrayEquals(new byte[] {1}, saved.data());
        assertNull(AdminCoreRespawnStore.pending(db, AdminCoreRespawnServer.account(alice, 0)));
    }

    @Test
    void ordinarySpawnAndForeignPrecharacterCommandsRemainUntouched() throws Exception {
        assertFalse(AdminCoreRespawnServer.begin("ATF Random", 0, alice));
        assertEquals(500, AdminCoreRespawnServer.coordinate(500, 0));
        AdminCoreRespawnServer.end();
        ByteBuffer bytes = ByteBuffer.allocate(128);
        var writer = new ByteBufferWriter(bytes);
        writer.putByte(-1);
        writer.putUTF("OtherMod");
        writer.putUTF("command");
        writer.putBoolean(false);
        bytes.flip();
        assertFalse(AdminCoreRespawnServer.command(new ByteBufferReader(bytes), alice));
        assertEquals(0, bytes.position());
    }

    @Test
    void connectScopeCapturesActualLoadSlotAndAlwaysRestoresNestedContext() {
        assertFalse(AdminCoreRespawnServer.acceptLoaded(null));
        Object outer = AdminCoreRespawnServer.enterConnect(alice);
        try {
            AdminCoreRespawnServer.captureLoad(0, "Alice");
            assertTrue(AdminCoreRespawnServer.acceptLoaded(null));
            Object inner = AdminCoreRespawnServer.enterConnect(alice);
            AdminCoreRespawnServer.captureLoad(-1, "Alice");
            assertFalse(AdminCoreRespawnServer.acceptLoaded(null));
            // Explicit early-return cleanup followed by Advice exit must not clear the outer
            // scope a second time.
            AdminCoreRespawnServer.clearConnect();
            AdminCoreRespawnServer.exitConnect(inner);
            assertTrue(AdminCoreRespawnServer.acceptLoaded(null));
        } finally {
            AdminCoreRespawnServer.exitConnect(outer);
        }
        assertFalse(AdminCoreRespawnServer.acceptLoaded(null));
    }

    @Test
    void livingConnectionCannotChooseEvenWhileSavedProfileIsDead() throws Exception {
        alice.mockPlayers[0] = allocate(TestPlayer.class);
        KahluaTable choices = request(alice, "choices", "alive-current", null);
        assertEquals(Boolean.TRUE, choices.rawget("enabled"));
        assertEquals(0, ((KahluaTable) choices.rawget("rows")).len());
        assertNotNull(
                request(alice, "choose", "alive-current-choice", AdminCoreRespawnServer.key(house))
                        .rawget("message"));
        assertNull(AdminCoreRespawnStore.pending(db, AdminCoreRespawnServer.account(alice, 0)));
    }

    private void markProfileAlive() throws Exception {
        try (var q = db.createStatement()) {
            q.executeUpdate("UPDATE networkPlayers SET isDead=0");
        }
        db.commit();
    }

    private SavingPlayer deadPlayer(String username) throws Exception {
        SavingPlayer player = allocate(SavingPlayer.class);
        player.username = username;
        player.descriptor = allocate(SurvivorDesc.class);
        player.serialized = new byte[] {4, 5, 6};
        player.dead = true;
        return player;
    }

    @Test
    void confirmedDeathSynchronizesLaggedProfileOnceBeforeOfferingSafehouse() throws Exception {
        markProfileAlive();
        SavingPlayer current = deadPlayer("Alice");
        alice.mockPlayers[0] = current;
        KahluaTable choices = request(alice, "choices", "lagged-death", null);
        assertEquals(Boolean.TRUE, choices.rawget("enabled"));
        assertEquals(1, ((KahluaTable) choices.rawget("rows")).len());
        var saved = AdminCoreRespawnStore.read(db, AdminCoreRespawnServer.account(alice, 0));
        assertTrue(saved.dead());
        assertArrayEquals(current.serialized, saved.data());
        assertEquals(1, current.serializations);
        String region =
                (String)
                        request(alice, "choose", "lagged-choice", AdminCoreRespawnServer.key(house))
                                .rawget("regionKey");
        assertNotNull(region);
        assertFalse(AdminCoreRespawnServer.begin(region, 0, alice));
        assertEquals(1, current.serializations);
    }

    @Test
    void confirmedDeathCanSynchronizeAtChooseWithoutPriorListRequest() throws Exception {
        markProfileAlive();
        SavingPlayer current = deadPlayer("Alice");
        alice.mockPlayers[0] = current;
        assertNotNull(
                request(alice, "choose", "direct-choice", AdminCoreRespawnServer.key(house))
                        .rawget("regionKey"));
        assertEquals(1, current.serializations);
        assertTrue(AdminCoreRespawnStore.read(db, AdminCoreRespawnServer.account(alice, 0)).dead());
    }

    @Test
    void deadCurrentWithDifferentUsernameCannotOverwriteAuthenticatedProfile() throws Exception {
        markProfileAlive();
        SavingPlayer current = deadPlayer("Bob");
        alice.mockPlayers[0] = current;
        KahluaTable choices = request(alice, "choices", "wrong-identity", null);
        assertEquals(0, ((KahluaTable) choices.rawget("rows")).len());
        assertEquals(0, current.serializations);
        var saved = AdminCoreRespawnStore.read(db, AdminCoreRespawnServer.account(alice, 0));
        assertFalse(saved.dead());
        assertArrayEquals(new byte[] {1}, saved.data());
    }

    @Test
    void deadPrimaryCannotSynchronizeAnotherRequestedSlot() throws Exception {
        markProfileAlive();
        try (var q = db.createStatement()) {
            q.executeUpdate(
                    "INSERT INTO networkPlayers VALUES(2,'respawn-test','Alice','',1,100,100,0,241,0,'Old Bob','Bob',X'02')");
        }
        db.commit();
        SavingPlayer primary = deadPlayer("Alice");
        alice.mockPlayers[0] = primary;
        KahluaTable choices = request(alice, 1, "choices", "other-slot", null, null);
        assertEquals(0, ((KahluaTable) choices.rawget("rows")).len());
        assertEquals(0, primary.serializations);
        assertFalse(
                AdminCoreRespawnStore.read(db, AdminCoreRespawnServer.account(alice, 0)).dead());
        assertFalse(
                AdminCoreRespawnStore.read(db, AdminCoreRespawnServer.account(alice, 1)).dead());
        alice.mockPlayers[1] = primary;
        choices = request(alice, 1, "choices", "wrong-split-identity", null, null);
        assertEquals(0, ((KahluaTable) choices.rawget("rows")).len());
        assertEquals(0, primary.serializations);
        assertArrayEquals(
                new byte[] {2},
                AdminCoreRespawnStore.read(db, AdminCoreRespawnServer.account(alice, 1)).data());
    }

    @Test
    void livingCurrentCannotSynchronizeLaggedProfile() throws Exception {
        markProfileAlive();
        SavingPlayer current = deadPlayer("Alice");
        current.dead = false;
        alice.mockPlayers[0] = current;
        KahluaTable choices = request(alice, "choices", "still-alive", null);
        assertEquals(0, ((KahluaTable) choices.rawget("rows")).len());
        assertEquals(0, current.serializations);
        assertFalse(
                AdminCoreRespawnStore.read(db, AdminCoreRespawnServer.account(alice, 0)).dead());
    }

    @Test
    void synchronizedDeathDoesNotBypassRevokedMembership() throws Exception {
        markProfileAlive();
        SavingPlayer current = deadPlayer("Alice");
        alice.mockPlayers[0] = current;
        house.setOwner("Other");
        house.getPlayers().remove("Alice");
        KahluaTable choices = request(alice, "choices", "revoked-death", null);
        assertEquals(0, ((KahluaTable) choices.rawget("rows")).len());
        assertEquals(1, current.serializations);
        assertNull(
                request(alice, "choose", "revoked-choice", AdminCoreRespawnServer.key(house))
                        .rawget("regionKey"));
        assertNull(AdminCoreRespawnStore.pending(db, AdminCoreRespawnServer.account(alice, 0)));
    }

    @Test
    void nativeSerializationFailureNeverWritesNullDataOrOverwritesPriorProfile() throws Exception {
        markProfileAlive();
        SavingPlayer current = deadPlayer("Alice");
        current.serializationFailure = true;
        alice.mockPlayers[0] = current;
        KahluaTable failure = request(alice, "choices", "save-failed", null);
        assertNotNull(failure.rawget("message"));
        assertNull(failure.rawget("rows"));
        assertEquals(1, current.serializations);
        var saved = AdminCoreRespawnStore.read(db, AdminCoreRespawnServer.account(alice, 0));
        assertFalse(saved.dead());
        assertArrayEquals(new byte[] {1}, saved.data());
        assertTrue(
                ((java.util.Queue<?>)
                                field(ServerPlayerDB.class, "charactersToSave")
                                        .get(ServerPlayerDB.getInstance()))
                        .isEmpty());
    }

    @Test
    void emptyNativeSnapshotIsRejectedBeforePriorProfileChanges() throws Exception {
        markProfileAlive();
        SavingPlayer current = deadPlayer("Alice");
        current.serialized = new byte[0];
        alice.mockPlayers[0] = current;
        assertNotNull(request(alice, "choices", "empty-save", null).rawget("message"));
        var saved = AdminCoreRespawnStore.read(db, AdminCoreRespawnServer.account(alice, 0));
        assertFalse(saved.dead());
        assertArrayEquals(new byte[] {1}, saved.data());
    }

    @Test
    void failedNativeDatabaseWriteRejectsChoiceAndPreservesPriorProfile() throws Exception {
        markProfileAlive();
        try (var q = db.createStatement()) {
            q.executeUpdate(
                    "CREATE TRIGGER fail_dead_save BEFORE UPDATE ON networkPlayers WHEN NEW.isDead=1 BEGIN SELECT RAISE(ABORT,'save blocked'); END");
        }
        db.commit();
        SavingPlayer current = deadPlayer("Alice");
        alice.mockPlayers[0] = current;
        KahluaTable failure = request(alice, "choices", "database-save-failed", null);
        assertNotNull(failure.rawget("message"));
        assertNull(failure.rawget("rows"));
        var saved = AdminCoreRespawnStore.read(db, AdminCoreRespawnServer.account(alice, 0));
        assertFalse(saved.dead());
        assertArrayEquals(new byte[] {1}, saved.data());
        assertEquals(1, current.serializations);
        Map<?, ?> sessions = (Map<?, ?>) field(AdminCoreRespawnServer.class, "SESSIONS").get(null);
        Object session = sessions.get(alice);
        assertFalse(((boolean[]) field(session.getClass(), "negotiated").get(session))[0]);
        assertTrue(
                ((java.util.Queue<?>)
                                field(ServerPlayerDB.class, "charactersToSave")
                                        .get(ServerPlayerDB.getInstance()))
                        .isEmpty());
        assertFalse(AdminCoreRespawnServer.begin("normal", 0, alice));
        assertEquals(1, current.serializations);
    }

    @Test
    void confirmedDeathWritesSynchronouslyWithoutQueuingAnOutstandingSnapshot() throws Exception {
        markProfileAlive();
        SavingPlayer current = deadPlayer("Alice");
        alice.mockPlayers[0] = current;
        var queue = new RefusingSaveQueue();
        field(ServerPlayerDB.class, "charactersToSave").set(ServerPlayerDB.getInstance(), queue);
        var choices = request(alice, "choices", "synchronous-save", null);
        assertEquals(1, ((KahluaTable) choices.rawget("rows")).len());
        assertEquals(1, current.serializations);
        assertTrue(queue.isEmpty());
        assertArrayEquals(
                current.serialized,
                AdminCoreRespawnStore.read(db, AdminCoreRespawnServer.account(alice, 0)).data());
    }

    @Test
    void accountChangeDuringSerializationCannotWriteTheCapturedSnapshot() throws Exception {
        markProfileAlive();
        var account = AdminCoreRespawnServer.account(alice, 0);
        SavingPlayer current = deadPlayer("Alice");
        current.duringSerialization = () -> alice.name = "Other";
        alice.mockPlayers[0] = current;
        assertNotNull(request(alice, "choices", "account-changed", null).rawget("message"));
        assertEquals(1, current.serializations);
        var saved = AdminCoreRespawnStore.read(db, account);
        assertFalse(saved.dead());
        assertArrayEquals(new byte[] {1}, saved.data());
        assertNull(AdminCoreRespawnStore.read(db, AdminCoreRespawnServer.account(alice, 0)));
    }

    @Test
    void creationJournalAppearingDuringSerializationPreventsSnapshotWrite() throws Exception {
        var account = AdminCoreRespawnServer.account(alice, 0);
        var previous = AdminCoreRespawnStore.read(db, account);
        markProfileAlive();
        SavingPlayer current = deadPlayer("Alice");
        current.duringSerialization =
                () -> {
                    try {
                        AdminCoreRespawnStore.begin(
                                db,
                                account,
                                new AdminCoreRespawnStore.Pending(
                                        "pending", "house", "Alice", Long.MAX_VALUE, previous));
                    } catch (Exception failure) {
                        throw new AssertionError(failure);
                    }
                };
        alice.mockPlayers[0] = current;
        assertNotNull(request(alice, "choices", "journal-changed", null).rawget("message"));
        assertEquals(1, current.serializations);
        var saved = AdminCoreRespawnStore.read(db, account);
        assertFalse(saved.dead());
        assertArrayEquals(new byte[] {1}, saved.data());
        assertNotNull(AdminCoreRespawnStore.pending(db, account));
    }

    @Test
    void pendingCreationJournalPreventsDeathSynchronizationOverNewProfile() throws Exception {
        var account = AdminCoreRespawnServer.account(alice, 0);
        var previous = AdminCoreRespawnStore.read(db, account);
        AdminCoreRespawnStore.begin(
                db,
                account,
                new AdminCoreRespawnStore.Pending(
                        "pending", "house", "Alice", Long.MAX_VALUE, previous));
        try (var q = db.createStatement()) {
            q.executeUpdate("UPDATE networkPlayers SET isDead=0,data=X'02'");
        }
        db.commit();
        SavingPlayer current = deadPlayer("Alice");
        alice.mockPlayers[0] = current;
        assertNotNull(request(alice, "choices", "pending-save", null).rawget("message"));
        assertEquals(0, current.serializations);
        var saved = AdminCoreRespawnStore.read(db, account);
        assertFalse(saved.dead());
        assertArrayEquals(new byte[] {2}, saved.data());
        assertNotNull(AdminCoreRespawnStore.pending(db, account));
    }

    @Test
    void unavailableDatabaseRepliesWithActionableFailureInsteadOfLeavingChooserWaiting()
            throws Exception {
        ServerPlayerDB.getInstance().conn = null;
        var reply = request(alice, "choices", "unavailable", null);
        assertEquals(
                "Safehouse spawning is temporarily unavailable. Choose a normal location.",
                reply.rawget("message"));
        assertNull(reply.rawget("rows"));
    }

    @Test
    void initialJoinRejectionSendsReadableKickAndTerminatesNativeLoadingWait() throws Exception {
        alice.connected = false;
        assertTrue(
                AdminCoreRespawnServer.begin(AdminCoreRespawnServer.PREFIX + "invalid", 0, alice));
        assertEquals("uac-respawn-choice-invalid", alice.disconnected);
        assertTrue(
                alice.packets.stream()
                        .anyMatch(
                                packet ->
                                        ByteBuffer.wrap(packet).getShort(1)
                                                == PacketTypes.PacketType.Kicked.getId()));
        assertNotNull(alice.lastReply().rawget("message"));
        assertTrue(AdminCoreRespawnStore.read(db, AdminCoreRespawnServer.account(alice, 0)).dead());
    }

    @Test
    void delayedSelectedRepliesCannotReactivateCancelledOrSupersededClientChoice()
            throws Exception {
        UdpConnection previous = GameClient.connection;
        try {
            GameClient.client = true;
            GameServer.server = false;
            GameClient.connection = alice;
            assertTrue(AdminCoreRespawnBridge.requestChoices(0, "current"));
            Object[] choices = (Object[]) field(AdminCoreRespawnBridge.class, "CHOICES").get(null);
            assertTrue(AdminCoreRespawnBridge.response(selectedReply("old"), false));
            assertNull(choices[0]);
            assertTrue(AdminCoreRespawnBridge.response(selectedReply("current"), false));
            assertNotNull(choices[0]);
            assertTrue(AdminCoreRespawnBridge.cancel(0));
            assertNull(choices[0]);
            assertTrue(AdminCoreRespawnBridge.response(selectedReply("current"), false));
            assertNull(choices[0]);
        } finally {
            GameClient.connection = previous;
        }
    }

    private ByteBufferReader selectedReply(String request) throws Exception {
        KahluaTable args = LuaManager.platform.newTable();
        args.rawset("playerIndex", 0.0);
        args.rawset("requestId", request);
        args.rawset("regionKey", AdminCoreRespawnServer.PREFIX + "test");
        args.rawset("x", 110.0);
        args.rawset("y", 105.0);
        args.rawset("z", 0.0);
        ByteBuffer bytes = ByteBuffer.allocate(4096);
        var writer = new ByteBufferWriter(bytes);
        writer.putUTF(AdminCoreRespawnServer.MODULE);
        writer.putUTF("selected");
        writer.putBoolean(true);
        TableNetworkUtils.save(args, writer);
        bytes.flip();
        return new ByteBufferReader(bytes);
    }

    public static class TestConnection extends UdpConnection {
        String name;
        ArrayList<byte[]> packets;
        ByteBuffer active;
        IsoPlayer[] mockPlayers;
        boolean connected;
        String disconnected;

        TestConnection() {
            super(null, 0, 0);
        }

        @Override
        public String getUserName() {
            return name;
        }

        @Override
        public String getUserName(int slot) {
            return slot == 0 ? name : null;
        }

        @Override
        public IsoPlayer getPlayerAt(int slot) {
            return mockPlayers[slot];
        }

        @Override
        public boolean isFullyConnected() {
            return connected;
        }

        @Override
        public void forceDisconnect(String reason) {
            disconnected = reason;
        }

        @Override
        public String getDescription() {
            return name;
        }

        @Override
        public ByteBufferWriter startPacket() {
            active = ByteBuffer.allocate(65536);
            return new ByteBufferWriter(active);
        }

        @Override
        public void endPacket(int priority, int reliability, byte channel) {
            packets.add(java.util.Arrays.copyOf(active.array(), active.position()));
        }

        KahluaTable lastReply() throws Exception {
            for (int i = packets.size() - 1; i >= 0; i--) {
                var reader = new ByteBufferReader(ByteBuffer.wrap(packets.get(i)));
                reader.getByte();
                if (reader.getShort() != PacketTypes.PacketType.ClientCommand.getId()) continue;
                assertEquals(AdminCoreRespawnServer.MODULE, reader.getUTF());
                reader.getUTF();
                KahluaTable result = LuaManager.platform.newTable();
                if (reader.getBoolean()) TableNetworkUtils.load(result, reader);
                return result;
            }
            throw new AssertionError("No server response");
        }
    }

    public static class TestPlayer extends IsoPlayer {
        KahluaTable data;
        float x;
        float y;

        TestPlayer() {
            super((IsoCell) null);
        }

        @Override
        public KahluaTable getModData() {
            return data;
        }

        @Override
        public float getX() {
            return x;
        }

        @Override
        public float getY() {
            return y;
        }

        @Override
        public boolean isDead() {
            return false;
        }

        @Override
        public void setUsername(String username) {}
    }

    public static class SavingPlayer extends TestPlayer {
        SurvivorDesc descriptor;
        byte[] serialized;
        int serializations;
        boolean serializationFailure;
        boolean dead;
        Runnable duringSerialization;

        @Override
        public SurvivorDesc getDescriptor() {
            return descriptor;
        }

        @Override
        public boolean isDead() {
            return dead;
        }

        @Override
        public void save(ByteBuffer bytes, boolean net) throws IOException {
            serializations++;
            if (serializationFailure)
                throw new IOException("Simulated player serialization failure");
            bytes.put(serialized);
            if (duringSerialization != null) duringSerialization.run();
        }
    }

    private static class RefusingSaveQueue extends ConcurrentLinkedQueue<Object> {
        @Override
        public boolean add(Object snapshot) {
            throw new AssertionError(
                    "Death synchronization must not enqueue a delayed player save.");
        }
    }
}
