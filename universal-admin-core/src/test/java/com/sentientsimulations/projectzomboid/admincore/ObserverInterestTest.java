package com.sentientsimulations.projectzomboid.admincore;

import static org.junit.jupiter.api.Assertions.*;

import java.util.*;
import net.bytebuddy.ByteBuddy;
import net.bytebuddy.dynamic.ClassFileLocator;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy;
import net.bytebuddy.jar.asm.*;
import net.bytebuddy.pool.TypePool;
import org.junit.jupiter.api.*;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.vm.KahluaTable;
import zombie.Lua.LuaManager;
import zombie.characters.*;
import zombie.core.raknet.*;
import zombie.iso.*;
import zombie.network.*;
import zombie.vehicles.BaseVehicle;
import zombie.world.moddata.GlobalModData;

class ObserverInterestTest {
    Player actor, target;
    Connection connection, targetConnection;
    World world;
    UdpEngine previousEngine;
    ServerMap previousWorld;
    boolean previousServer;
    KahluaTable previousPolicy;

    static final class Player extends IsoPlayer {
        Role role;
        String name;
        float px, py, pz;
        boolean dead;

        private Player() {
            super((IsoCell) null);
        }

        @Override
        public Role getRole() {
            return role;
        }

        @Override
        public String getUsername() {
            return name;
        }

        @Override
        public float getX() {
            return px;
        }

        @Override
        public float getY() {
            return py;
        }

        @Override
        public float getZ() {
            return pz;
        }

        @Override
        public boolean isDead() {
            return dead;
        }

        @Override
        public BaseVehicle getVehicle() {
            return null;
        }
    }

    static final class Connection extends UdpConnection {
        boolean connected = true;

        private Connection() {
            super(null, 0, 0);
        }

        @Override
        public boolean isFullyConnected() {
            return connected;
        }
    }

    static final class World extends ServerMap {
        Set<String> held;

        @Override
        public int getMinX() {
            return -10;
        }

        @Override
        public int getMinY() {
            return -10;
        }

        @Override
        public int getMaxX() {
            return 100;
        }

        @Override
        public int getMaxY() {
            return 100;
        }

        @Override
        public void loadOrKeepRelevent(int x, int y) {
            held.add(x + ":" + y);
        }
    }

    static final class WorldObject extends IsoObject {
        IsoGridSquare square;

        @Override
        public IsoGridSquare getSquare() {
            return square;
        }

        @Override
        public float getX() {
            return square.x;
        }

        @Override
        public float getY() {
            return square.y;
        }
    }

    WorldObject object(int x, int y, int z) throws Exception {
        var value = allocate(WorldObject.class);
        value.square = allocate(IsoGridSquare.class);
        value.square.x = x;
        value.square.y = y;
        value.square.z = z;
        return value;
    }

    @SuppressWarnings("removal")
    static <T> T allocate(Class<T> type) throws Exception {
        var field = sun.misc.Unsafe.class.getDeclaredField("theUnsafe");
        field.setAccessible(true);
        return type.cast(((sun.misc.Unsafe) field.get(null)).allocateInstance(type));
    }

    static java.lang.reflect.Field field(Class<?> type, String name) throws Exception {
        var field = type.getDeclaredField(name);
        field.setAccessible(true);
        return field;
    }

    @SuppressWarnings("unchecked")
    Map<UdpConnection, Map<IsoPlayer, AdminCoreObserverInterest.Lease>> leases() throws Exception {
        return (Map<UdpConnection, Map<IsoPlayer, AdminCoreObserverInterest.Lease>>)
                field(AdminCoreObserverInterest.class, "INTEREST").get(null);
    }

    @BeforeEach
    void setup() throws Exception {
        zombie.core.random.RandStandard.INSTANCE.init();
        previousEngine = GameServer.udpEngine;
        previousWorld = ServerMap.instance;
        previousServer = GameServer.server;
        if (LuaManager.platform == null) LuaManager.platform = new J2SEPlatform();
        previousPolicy = GlobalModData.instance.get("UniversalAdminCore.OperationsPolicy.v1");
        GlobalModData.instance.add(
                "UniversalAdminCore.OperationsPolicy.v1", LuaManager.platform.newTable());
        GameServer.server = true;
        var engine = allocate(UdpEngine.class);
        var connections = new HashMap<Long, UdpConnection>();
        field(UdpEngine.class, "connectionMap").set(engine, connections);
        GameServer.udpEngine = engine;
        world = allocate(World.class);
        world.cellMap = new ServerMap.ServerCell[1];
        world.held = new HashSet<>();
        ServerMap.instance = world;
        actor = allocate(Player.class);
        actor.name = "observer";
        actor.px = 10;
        actor.py = 10;
        actor.role = new Role("observer");
        for (var cap :
                List.of(
                        Capability.ToggleInvisibleHimself,
                        Capability.TeleportToPlayer,
                        Capability.SeePlayersConnected,
                        Capability.UseDebugContextMenu)) actor.role.addCapability(cap);
        target = allocate(Player.class);
        target.name = "target";
        target.px = 1000;
        target.py = 1000;
        connection = connection(actor);
        targetConnection = connection(target);
        connections.put(81L, connection);
        connections.put(82L, targetConnection);
        GameServer.PlayerToAddressMap.put(actor, 81L);
        GameServer.PlayerToAddressMap.put(target, 82L);
    }

    Connection connection(Player player) throws Exception {
        var value = allocate(Connection.class);
        value.connected = true;
        value.players = new IsoPlayer[] {player, null, null, null};
        value.releventPos = new Vector3[] {new Vector3(player.px, player.py, 0), null, null, null};
        value.connectArea = new Vector3[4];
        field(UdpConnection.class, "relevantRange").set(value, (byte) 7);
        return value;
    }

    @AfterEach
    void cleanup() throws Exception {
        leases().clear();
        GameServer.PlayerToAddressMap.remove(actor);
        GameServer.PlayerToAddressMap.remove(target);
        GameServer.udpEngine = previousEngine;
        GameServer.server = previousServer;
        ServerMap.instance = previousWorld;
        GlobalModData.instance.remove("UniversalAdminCore.OperationsPolicy.v1");
        if (previousPolicy != null)
            GlobalModData.instance.add("UniversalAdminCore.OperationsPolicy.v1", previousPolicy);
    }

    @Test
    void stormObjectInterestKeepsOriginAndRequiresCurrentFloorAndAuthorization() throws Exception {
        var remote = object(1000, 1000, 0);
        assertFalse(AdminCoreObserverInterest.replicationRelevant(connection, 1000, 1000, remote));
        assertTrue(AdminCoreObserverInterest.start(actor, target, "objects", "FOLLOW"));
        assertTrue(AdminCoreObserverInterest.replicationRelevant(connection, 1000, 1000, remote));
        assertFalse(
                AdminCoreObserverInterest.replicationRelevant(
                        connection, 1000, 1000, object(1000, 1000, 1)));
        assertFalse(
                AdminCoreObserverInterest.replicationRelevant(
                        connection, 1080, 1000, object(1080, 1000, 0)));
        assertFalse(AdminCoreObserverInterest.replicationRelevant(connection, 1000, 1000, null));
        assertTrue(
                AdminCoreObserverInterest.replicationRelevant(
                        connection, 10, 10, object(10, 10, 1)),
                "Physical origin relevance remains native, including other floors");
        assertFalse(
                AdminCoreObserverInterest.replicationRelevant(
                        targetConnection, 10, 10, object(10, 10, 0)));
        target.pz = 1;
        assertTrue(
                AdminCoreObserverInterest.replicationRelevant(
                        connection, 1000, 1000, object(1000, 1000, 1)));
        assertFalse(AdminCoreObserverInterest.replicationRelevant(connection, 1000, 1000, remote));
        target.pz = 0;
        GameServer.server = false;
        assertFalse(AdminCoreObserverInterest.replicationRelevant(connection, 1000, 1000, remote));
        GameServer.server = true;
        assertTrue(AdminCoreObserverInterest.start(actor, target, "objects", "FOLLOW"));
        connection.connected = false;
        assertFalse(AdminCoreObserverInterest.replicationRelevant(connection, 1000, 1000, remote));
        connection.connected = true;
        assertTrue(AdminCoreObserverInterest.start(actor, target, "objects", "FOLLOW"));
        actor.role = new Role("ordinary");
        assertFalse(AdminCoreObserverInterest.replicationRelevant(connection, 1000, 1000, remote));
        assertFalse(AdminCoreObserverInterest.start(actor, target, "forged", "FOLLOW"));
    }

    @Test
    void stormHelperWeavesAndRunsRealObjectGateWithAnExpiringLease() throws Exception {
        var name = AdminCoreObserverReplicationPatch.TARGETS.get(1);
        var locator = ClassFileLocator.ForClassLoader.ofSystemLoader();
        var pool = TypePool.Default.of(locator);
        var transformed =
                new AdminCoreObserverReplicationPatch(name)
                        .dynamicType(
                                locator,
                                pool,
                                new ByteBuddy().redefine(pool.describe(name).resolve(), locator))
                        .make()
                        .load(getClass().getClassLoader(), ClassLoadingStrategy.Default.CHILD_FIRST)
                        .getLoaded();
        var method =
                transformed.getDeclaredMethod("isRelevant", UdpConnection.class, IsoObject.class);
        method.setAccessible(true);
        var remote = object(1000, 1000, 0);
        assertEquals(false, method.invoke(null, connection, remote));
        assertTrue(AdminCoreObserverInterest.start(actor, target, "objects", "FOLLOW"));
        assertEquals(true, method.invoke(null, connection, remote));
        assertEquals(false, method.invoke(null, connection, object(1000, 1000, 1)));
        var old = leases().get(connection).get(actor);
        leases().get(connection)
                .put(
                        actor,
                        new AdminCoreObserverInterest.Lease(
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
                                System.currentTimeMillis() - 1,
                                old.sequence(),
                                old.movedAt()));
        assertEquals(false, method.invoke(null, connection, remote));
        assertEquals(true, method.invoke(null, connection, object(10, 10, 0)));
        assertTrue(
                leases().isEmpty(),
                "Expired interest is removed rather than extending object access");
    }

    @Test
    void realStormHelperCallSitesOnlyRedirectOutgoingRelevance() throws Exception {
        var locator = ClassFileLocator.ForClassLoader.ofSystemLoader();
        var pool = TypePool.Default.of(locator);
        for (String name : AdminCoreObserverReplicationPatch.TARGETS) {
            byte[] bytes =
                    new AdminCoreObserverReplicationPatch(name)
                            .dynamicType(
                                    locator,
                                    pool,
                                    new ByteBuddy()
                                            .redefine(pool.describe(name).resolve(), locator))
                            .make()
                            .load(
                                    getClass().getClassLoader(),
                                    ClassLoadingStrategy.Default.CHILD_FIRST)
                            .getBytes();
            int[] replaced = {0};
            new ClassReader(bytes)
                    .accept(
                            new ClassVisitor(Opcodes.ASM9) {
                                @Override
                                public MethodVisitor visitMethod(
                                        int access,
                                        String method,
                                        String descriptor,
                                        String signature,
                                        String[] exceptions) {
                                    return new MethodVisitor(Opcodes.ASM9) {
                                        @Override
                                        public void visitMethodInsn(
                                                int opcode,
                                                String owner,
                                                String called,
                                                String desc,
                                                boolean itf) {
                                            if (owner.endsWith("/AdminCoreObserverInterest")) {
                                                assertEquals("replicationRelevant", called);
                                                assertTrue(
                                                        Set.of(
                                                                        "run",
                                                                        "isRelevant",
                                                                        "runLightSwitch")
                                                                .contains(method));
                                                replaced[0]++;
                                            }
                                        }
                                    };
                                }
                            },
                            0);
            assertEquals(name.endsWith("BroadcastGate") ? 1 : 2, replaced[0], name);
        }
    }

    @Test
    void keepsPhysicalRelevanceAndBoundsObserverToFortyNineChunks() {
        assertTrue(AdminCoreObserverInterest.start(actor, target, "1", "FOLLOW"));
        assertTrue(connection.isRelevantTo(10, 10));
        assertFalse(
                connection.isRelevantTo(1000, 1000), "native authorization method stays physical");
        assertTrue(AdminCoreObserverInterest.relevant(connection, 1000, 1000));
        assertTrue(AdminCoreObserverInterest.relevant(connection, 10, 10));
        int included = 0;
        for (int x = 120; x <= 130; x++)
            for (int y = 120; y <= 130; y++)
                if (AdminCoreObserverInterest.chunk(connection, x, y)) included++;
        assertEquals(49, included);
        assertFalse(AdminCoreObserverInterest.observerRelevant(targetConnection, 1000, 1000));
        assertEquals(10, connection.releventPos[0].x);
        target.px += 80;
        assertTrue(AdminCoreObserverInterest.observerRelevant(connection, 1080, 1000));
        assertFalse(AdminCoreObserverInterest.observerRelevant(connection, 1000, 1000));
        AdminCoreObserverInterest.retain(world);
        assertTrue(world.held.size() <= 4);
        AdminCoreObserverInterest.stop(actor, "1");
        assertFalse(AdminCoreObserverInterest.observerRelevant(connection, 1080, 1000));
        assertTrue(connection.isRelevantTo(10, 10));
    }

    @Test
    void revocationPolicyExpiryDisconnectAndCharacterReplacementImmediatelyDeny() throws Exception {
        assertTrue(AdminCoreObserverInterest.start(actor, target, "1", "FOLLOW"));
        actor.role.removeCapability(Capability.UseDebugContextMenu);
        assertFalse(AdminCoreObserverInterest.observerRelevant(connection, 1000, 1000));
        assertFalse(AdminCoreObserverInterest.renew(actor, "1"));
        actor.role.addCapability(Capability.UseDebugContextMenu);
        assertTrue(AdminCoreObserverInterest.start(actor, target, "2", "FOLLOW"));
        var policy = GlobalModData.instance.get("UniversalAdminCore.OperationsPolicy.v1");
        var disabled = LuaManager.platform.newTable();
        disabled.rawset("ADMIN_RENDER_DEBUG", true);
        policy.rawset("disabled", disabled);
        assertFalse(AdminCoreObserverInterest.observerRelevant(connection, 1000, 1000));
        policy.rawset("disabled", null);
        assertTrue(AdminCoreObserverInterest.start(actor, target, "3", "FOLLOW"));
        var lease = leases().get(connection).get(actor);
        leases().get(connection)
                .put(
                        actor,
                        new AdminCoreObserverInterest.Lease(
                                actor,
                                target,
                                connection,
                                targetConnection,
                                lease.id(),
                                lease.mode(),
                                0,
                                0,
                                0,
                                lease.radius(),
                                System.currentTimeMillis() - 1,
                                0,
                                0));
        assertFalse(AdminCoreObserverInterest.renew(actor, "3"));
        assertFalse(AdminCoreObserverInterest.chunk(connection, 125, 125));
        assertTrue(AdminCoreObserverInterest.start(actor, target, "4", "FOLLOW"));
        targetConnection.connected = false;
        assertFalse(AdminCoreObserverInterest.observerRelevant(connection, 1000, 1000));
        targetConnection.connected = true;
        assertTrue(AdminCoreObserverInterest.start(actor, target, "5", "FOLLOW"));
        targetConnection.players[0] = actor;
        assertFalse(AdminCoreObserverInterest.observerRelevant(connection, 1000, 1000));
        assertEquals(0, leases().size());
    }

    @Test
    void rejectsForgedReplayNonfiniteTeleportAndFloorInterestsWithoutRenewingLease()
            throws Exception {
        assertTrue(AdminCoreObserverInterest.start(actor, target, "1", "FREE"));
        var old = leases().get(connection).get(actor);
        long time = old.movedAt() + 1000;
        var moved = AdminCoreObserverInterest.moved(old, 1, "FREE", 1030, 1000, 0, time);
        assertNotNull(moved);
        assertEquals(old.expires(), moved.expires());
        assertNull(AdminCoreObserverInterest.moved(old, 1, "FREE", 1030.1, 1000, 0, time));
        assertNull(AdminCoreObserverInterest.moved(old, 1, "FREE", 1000, 1000, 1, time));
        assertNull(AdminCoreObserverInterest.moved(old, 1, "FREE", Double.NaN, 1000, 0, time));
        assertNull(AdminCoreObserverInterest.moved(old, 1, "FREE", 1000000, 1000, 0, time));
        assertNull(
                AdminCoreObserverInterest.moved(
                        old, 1, "FREE", 1000, 1000, 0, old.movedAt() + 199));
        assertNull(AdminCoreObserverInterest.moved(moved, 1, "FREE", 1030, 1000, 0, time + 1000));
        assertNull(AdminCoreObserverInterest.moved(old, 1, "SOFT", 1009, 1000, 0, time));
        assertNotNull(AdminCoreObserverInterest.moved(old, 1, "SOFT", 1008, 1008, 0, time));
        assertFalse(AdminCoreObserverInterest.move(actor, "forged", 1, "FREE", 1000, 1000, 0));
        assertFalse(
                AdminCoreObserverInterest.move(
                        actor, "1", Double.POSITIVE_INFINITY, "FREE", 1000, 1000, 0));
        assertFalse(AdminCoreObserverInterest.move(actor, "1", 1.5, "FREE", 1000, 1000, 0));
        AdminCoreObserverInterest.stop(actor, "forged");
        assertTrue(AdminCoreObserverInterest.observerRelevant(connection, 1000, 1000));
        target.px = Float.NaN;
        assertFalse(
                AdminCoreObserverInterest.observerRelevant(connection, 1000, 1000),
                "Invalid live target state revokes even an independently positioned free camera");
        AdminCoreObserverInterest.stop(actor, "1");
        assertFalse(AdminCoreObserverInterest.start(actor, target, "2", "FOLLOW"));
    }

    @Test
    void viewportRadiusIsBoundedAndSurvivesHeartbeatWithoutChangingPhysicalRelevance()
            throws Exception {
        for (double radius : new double[] {2, 10, 3.5, Double.NaN, Double.POSITIVE_INFINITY})
            assertFalse(
                    AdminCoreObserverInterest.startWithRadius(
                            actor, target, "bad", "FOLLOW", radius));
        assertEquals(0, leases().size());
        assertTrue(AdminCoreObserverInterest.startWithRadius(actor, target, "wide", "FOLLOW", 9));
        assertEquals(9, AdminCoreObserverInterest.radius(actor, "wide"));
        int included = 0;
        for (int x = 115; x <= 135; x++)
            for (int y = 115; y <= 135; y++)
                if (AdminCoreObserverInterest.chunk(connection, x, y)) included++;
        assertEquals(361, included);
        assertFalse(connection.isRelevantTo(1000, 1000));
        assertEquals(10, actor.px);
        assertEquals(10, connection.releventPos[0].x);
        AdminCoreObserverInterest.retain(world);
        assertEquals(9, world.held.size());
        var inside = allocate(ServerMap.ServerCell.class);
        inside.wx = 14;
        inside.wy = 14;
        var outside = allocate(ServerMap.ServerCell.class);
        outside.wx = 13;
        outside.wy = 14;
        assertTrue(AdminCoreObserverInterest.retained(inside));
        assertFalse(AdminCoreObserverInterest.retained(outside));
        target.px = 1024;
        target.py = 1024;
        world.held.clear();
        AdminCoreObserverInterest.retain(world);
        assertEquals(
                16, world.held.size(), "Maximum radius intersects at most four cells per axis");
        target.px = 1000;
        target.py = 1000;
        assertTrue(AdminCoreObserverInterest.renew(actor, "wide"));
        assertEquals(9, AdminCoreObserverInterest.radius(actor, "wide"));
        var old = leases().get(connection).get(actor);
        var smaller =
                AdminCoreObserverInterest.moved(
                        old, 1, "FOLLOW", 1000, 1000, 0, 3, old.movedAt() + 250);
        assertNotNull(smaller);
        assertEquals(3, smaller.radius());
        assertEquals(old.expires(), smaller.expires());
        assertFalse(AdminCoreObserverInterest.contains(smaller, 1056, 1000));
        assertEquals(
                9,
                AdminCoreObserverInterest.moved(
                                old, 1, "FOLLOW", 1000, 1000, 0, old.movedAt() + 250)
                        .radius());
        for (double radius : new double[] {2, 10, 3.5, Double.NaN, Double.POSITIVE_INFINITY})
            assertNull(
                    AdminCoreObserverInterest.moved(
                            old, 1, "FOLLOW", 1000, 1000, 0, radius, old.movedAt() + 250));
        actor.role.removeCapability(Capability.UseDebugContextMenu);
        assertEquals(0, AdminCoreObserverInterest.radius(actor, "wide"));
        assertFalse(
                AdminCoreObserverInterest.moveWithRadius(
                        actor, "wide", 2, "FOLLOW", 1000, 1000, 0, 9));
        assertFalse(AdminCoreObserverInterest.chunk(connection, 125, 125));
    }

    @Test
    void softOffsetsFollowMovingTargetWithoutReplayingMotionAsUserPan() throws Exception {
        assertTrue(AdminCoreObserverInterest.startWithRadius(actor, target, "soft", "SOFT", 5));
        var old = leases().get(connection).get(actor);
        target.px += 12;
        target.py += 4;
        var moved = AdminCoreObserverInterest.movedSoft(old, 1, 2, -3, 7, old.movedAt() + 250);
        assertNotNull(moved);
        assertEquals(1014, moved.center(0));
        assertEquals(1001, moved.center(1));
        assertEquals(old.expires(), moved.expires());
        assertEquals(7, moved.radius());
        leases().get(connection).put(actor, moved);
        assertEquals(2, AdminCoreObserverInterest.offset(actor, "soft", 0));
        assertEquals(-3, AdminCoreObserverInterest.offset(actor, "soft", 1));
        target.px += 5;
        assertEquals(1019, AdminCoreObserverInterest.coordinate(actor, "soft", 0));
        assertEquals(2, AdminCoreObserverInterest.offset(actor, "soft", 0));
        assertTrue(AdminCoreObserverInterest.renew(actor, "soft"));
        assertEquals(2, AdminCoreObserverInterest.offset(actor, "soft", 0));
        assertEquals(7, AdminCoreObserverInterest.radius(actor, "soft"));
        for (double offset : new double[] {-8.1, 8.1, Double.NaN, Double.POSITIVE_INFINITY}) {
            assertNull(
                    AdminCoreObserverInterest.movedSoft(old, 1, offset, 0, 5, old.movedAt() + 250));
            assertNull(
                    AdminCoreObserverInterest.movedSoft(old, 1, 0, offset, 5, old.movedAt() + 250));
        }
        assertNotNull(AdminCoreObserverInterest.movedSoft(old, 1, -8, 8, 9, old.movedAt() + 250));
        assertNull(AdminCoreObserverInterest.movedSoft(old, 1, 0, 0, 10, old.movedAt() + 250));
        assertNull(AdminCoreObserverInterest.movedSoft(old, 1, 0, 0, 5, old.movedAt() + 199));
        assertNull(AdminCoreObserverInterest.movedSoft(moved, 1, 0, 0, 5, moved.movedAt() + 250));
        assertFalse(AdminCoreObserverInterest.moveSoft(actor, "forged", 2, 0, 0, 5));
        assertFalse(AdminCoreObserverInterest.moveSoft(actor, "soft", 2.5, 0, 0, 5));
        assertFalse(AdminCoreObserverInterest.moveSoft(actor, "soft", Double.NaN, 0, 0, 5));
        actor.role.removeCapability(Capability.UseDebugContextMenu);
        assertFalse(AdminCoreObserverInterest.moveSoft(actor, "soft", 2, 0, 0, 5));
        assertTrue(Double.isNaN(AdminCoreObserverInterest.offset(actor, "soft", 0)));
    }

    @Test
    void weavesOnlyVettedNativeReplicationAndChunkPaths() throws Exception {
        var locator = ClassFileLocator.ForClassLoader.ofSystemLoader();
        var pool = TypePool.Default.of(locator);
        Map<String, Integer> expected =
                Map.of(
                        "zombie.network.PlayerDownloadServer",
                        1,
                        "zombie.network.ServerMap",
                        2,
                        "zombie.network.packets.character.PlayerPacket",
                        1,
                        "zombie.network.packets.INetworkPacket",
                        2,
                        "zombie.vehicles.VehicleManager",
                        1,
                        "zombie.popman.NetworkZombiePacker",
                        1,
                        "zombie.popman.animal.AnimalSynchronizationManager",
                        1);
        for (String name : AdminCoreObserverInterestPatch.TARGETS) {
            var bytes =
                    new AdminCoreObserverInterestPatch(name)
                            .dynamicType(
                                    locator,
                                    pool,
                                    new ByteBuddy()
                                            .redefine(pool.describe(name).resolve(), locator))
                            .make()
                            .getBytes();
            int[] calls = {0};
            new ClassReader(bytes)
                    .accept(
                            new ClassVisitor(Opcodes.ASM9) {
                                @Override
                                public MethodVisitor visitMethod(
                                        int a, String n, String d, String s, String[] e) {
                                    return new MethodVisitor(Opcodes.ASM9) {
                                        @Override
                                        public void visitMethodInsn(
                                                int op,
                                                String owner,
                                                String method,
                                                String desc,
                                                boolean itf) {
                                            if (owner.endsWith("/AdminCoreObserverInterest"))
                                                calls[0]++;
                                        }
                                    };
                                }
                            },
                            0);
            assertEquals(expected.get(name), calls[0], name);
        }
        assertFalse(
                AdminCoreObserverInterest.ready(),
                "Unpatched runtime must not advertise remote streaming");
    }
}
