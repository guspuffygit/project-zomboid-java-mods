package com.sentientsimulations.projectzomboid.admincore;

import static org.junit.jupiter.api.Assertions.*;

import java.util.Map;
import net.bytebuddy.ByteBuddy;
import net.bytebuddy.dynamic.ClassFileLocator;
import net.bytebuddy.jar.asm.*;
import net.bytebuddy.pool.TypePool;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import zombie.characters.Capability;
import zombie.characters.IsoPlayer;
import zombie.characters.Role;
import zombie.iso.*;

class ObserveStreamingTest {
    @AfterEach
    void cleanup() {
        AdminCoreObserveStreaming.clear();
        AdminCoreObserveStreaming.grantRadius(3);
    }

    @Test
    void viewportUsesNativeZoomedProjectionAndIsBoundedByAllocatedMap() {
        assertEquals(4, AdminCoreObserveStreaming.viewportRadius(1280, 720, 2, 19));
        assertEquals(4, AdminCoreObserveStreaming.viewportRadius(1920, 1080, 2, 19));
        assertEquals(7, AdminCoreObserveStreaming.viewportRadius(4320, 2430, 2, 19));
        assertEquals(6, AdminCoreObserveStreaming.viewportRadius(4320, 2430, 2, 13));
        assertEquals(
                9,
                AdminCoreObserveStreaming.viewportRadius(
                        Integer.MAX_VALUE, Integer.MAX_VALUE, 1, 19));
        assertEquals(3, AdminCoreObserveStreaming.viewportRadius(0, 720, 2, 19));
    }

    @Test
    void radiusChangesOnlyFromAcceptedGrantAndInterestRetainsExactExpiryBounds() throws Exception {
        assertEquals(3, AdminCoreObserveStreaming.radius());
        assertFalse(AdminCoreObserveStreaming.grantRadius(2));
        assertFalse(AdminCoreObserveStreaming.grantRadius(10));
        assertTrue(AdminCoreObserveStreaming.grantRadius(5));
        assertEquals(
                3, AdminCoreObserveStreaming.radius(), "Pending radius alone grants no terrain");
        var interest = new AdminCoreObserveStreaming.Interest(1000, 2000, 6000, 5);
        int count = 0;
        for (int x = 990; x <= 1010; x++)
            for (int y = 1990; y <= 2010; y++) if (interest.contains(x, y, 5999)) count++;
        assertEquals(121, count);
        assertFalse(interest.contains(1000, 2000, 6000));
        assertFalse(interest.contains(1006, 2000, 5999));
        state("interest", interest);
        assertEquals(5, AdminCoreObserveStreaming.radius());
        AdminCoreObserveStreaming.clear();
        assertEquals(3, AdminCoreObserveStreaming.radius());
    }

    private static void state(String name, Object value) throws Exception {
        var field = AdminCoreObserveStreaming.class.getDeclaredField(name);
        field.setAccessible(true);
        field.set(null, value);
    }

    private static void cameraState(String name, Object value) throws Exception {
        var field = AdminCoreObserveCamera.class.getDeclaredField(name);
        field.setAccessible(true);
        field.set(null, value);
    }

    @SuppressWarnings("unchecked")
    private static Map<Integer, IsoChunk> owners() throws Exception {
        var field = AdminCoreObserveStreaming.class.getDeclaredField("owned");
        field.setAccessible(true);
        return (Map<Integer, IsoChunk>) field.get(null);
    }

    private static <T> T allocate(Class<T> type) throws Exception {
        var field = sun.misc.Unsafe.class.getDeclaredField("theUnsafe");
        field.setAccessible(true);
        return type.cast(((sun.misc.Unsafe) field.get(null)).allocateInstance(type));
    }

    @Test
    void regionIsExactlyFortyNineChunksAndExpiresWithoutWorkerReadingMutablePlayerState() {
        var interest = new AdminCoreObserveStreaming.Interest(1000, 2000, 6000);
        int count = 0;
        for (int x = 990; x <= 1010; x++)
            for (int y = 1990; y <= 2010; y++) if (interest.contains(x, y, 5999)) count++;
        assertEquals(49, count);
        assertFalse(interest.contains(1000, 2000, 6000));
        assertFalse(interest.contains(Integer.MIN_VALUE, Integer.MAX_VALUE, 1));
        assertEquals(8, AdminCoreObserveStreaming.REQUESTS_PER_TICK);
    }

    @Test
    void nativeStreamingAndCellLookupMethodsWeaveInInstalledB42() throws Exception {
        var locator = ClassFileLocator.ForClassLoader.ofSystemLoader();
        var pool = TypePool.Default.of(locator);
        for (String name :
                new String[] {
                    "zombie.iso.IsoChunkMap", "zombie.iso.WorldStreamer", "zombie.iso.IsoCell"
                }) {
            byte[] bytes =
                    new AdminCoreObserveStreamingPatch(name)
                            .dynamicType(
                                    locator,
                                    pool,
                                    new ByteBuddy()
                                            .redefine(pool.describe(name).resolve(), locator))
                            .make()
                            .getBytes();
            assertTrue(bytes.length > 0);
            var invoked = new java.util.HashSet<String>();
            var marker = new java.util.concurrent.atomic.AtomicBoolean();
            new ClassReader(bytes)
                    .accept(
                            new ClassVisitor(Opcodes.ASM9) {
                                @Override
                                public FieldVisitor visitField(
                                        int access,
                                        String name,
                                        String descriptor,
                                        String signature,
                                        Object value) {
                                    if (name.equals(AdminCoreObserveStreaming.MARKER)) {
                                        assertEquals("Z", descriptor);
                                        assertEquals(1, value);
                                        assertEquals(
                                                Opcodes.ACC_PUBLIC
                                                        | Opcodes.ACC_STATIC
                                                        | Opcodes.ACC_FINAL,
                                                access
                                                        & (Opcodes.ACC_PUBLIC
                                                                | Opcodes.ACC_STATIC
                                                                | Opcodes.ACC_FINAL));
                                        marker.set(true);
                                    }
                                    return null;
                                }

                                @Override
                                public MethodVisitor visitMethod(
                                        int access,
                                        String name,
                                        String desc,
                                        String sig,
                                        String[] exceptions) {
                                    return new MethodVisitor(Opcodes.ASM9) {
                                        @Override
                                        public void visitMethodInsn(
                                                int opcode,
                                                String owner,
                                                String called,
                                                String descriptor,
                                                boolean itf) {
                                            if (owner.endsWith("/AdminCoreObserveStreaming"))
                                                invoked.add(called);
                                        }
                                    };
                                }
                            },
                            0);
            assertTrue(marker.get(), name + " must include the completed patch marker");
            if (name.endsWith("IsoChunkMap"))
                assertEquals(java.util.Set.of("accept", "physicalCharacter"), invoked);
            if (name.endsWith("WorldStreamer"))
                assertEquals(java.util.Set.of("shouldRequest"), invoked);
            if (name.endsWith("IsoCell"))
                assertEquals(java.util.Set.of("square", "chunk"), invoked);
        }
    }

    @Test
    void lookupsUseNativeChunkSquaresAndNeverInventUnloadedTerrain() throws Exception {
        var cell = allocate(IsoCell.class);
        var chunk = new IsoChunk((WorldReuserThread) null);
        chunk.wx = 1000;
        chunk.wy = 2000;
        var square = new IsoGridSquare(null, null, 8001, 16002, 0);
        chunk.minLevel = chunk.maxLevel = 0;
        var squares = IsoChunk.class.getDeclaredField("squares");
        squares.setAccessible(true);
        var grid = new IsoGridSquare[1][64];
        grid[0][2 * 8 + 1] = square;
        squares.set(chunk, grid);
        state("cell", cell);
        state(
                "interest",
                new AdminCoreObserveStreaming.Interest(
                        1000, 2000, System.currentTimeMillis() + 6000));
        owners().put(AdminCoreObserveStreaming.key(1000, 2000), chunk);
        assertNull(AdminCoreObserveStreaming.square(cell, 8001, 16002, 0));
        chunk.loaded = true;
        assertSame(square, AdminCoreObserveStreaming.square(cell, 8001, 16002, 0));
        assertNull(AdminCoreObserveStreaming.square(cell, 8001, 16002, 32));
        assertNull(AdminCoreObserveStreaming.chunk(allocate(IsoCell.class), 1000, 2000));
        state("interest", new AdminCoreObserveStreaming.Interest(1000, 2000, 0));
        assertNull(AdminCoreObserveStreaming.square(cell, 8001, 16002, 0));
        chunk.loaded = false;
    }

    @Test
    void stopReleasesOnlyObserverRefsAndLatePendingChunksAreRejected() throws Exception {
        var cell = allocate(IsoCell.class);
        var origin = new IsoChunkMap(cell);
        var observer = new IsoChunkMap(cell);
        var shared = new IsoChunk((WorldReuserThread) null);
        shared.wx = 1000;
        shared.wy = 2000;
        shared.refs.add(origin);
        shared.refs.add(observer);
        var pending = new IsoChunk((WorldReuserThread) null);
        pending.wx = 1001;
        pending.wy = 2000;
        pending.refs.add(observer);
        state("cell", cell);
        state("map", observer);
        state(
                "interest",
                new AdminCoreObserveStreaming.Interest(
                        1000, 2000, System.currentTimeMillis() + 6000));
        owners().put(AdminCoreObserveStreaming.key(shared.wx, shared.wy), shared);
        owners().put(AdminCoreObserveStreaming.key(pending.wx, pending.wy), pending);
        IsoChunkMap.SharedChunks.put(
                AdminCoreObserveStreaming.key(pending.wx, pending.wy), pending);
        AdminCoreObserveStreaming.clear();
        assertEquals(java.util.List.of(origin), shared.refs);
        assertTrue(pending.refs.isEmpty());
        assertFalse(
                IsoChunkMap.SharedChunks.containsKey(
                        AdminCoreObserveStreaming.key(pending.wx, pending.wy)));
        assertFalse(AdminCoreObserveStreaming.accept(pending));
        assertFalse(AdminCoreObserveStreaming.shouldRequest(pending));
        assertTrue(owners().isEmpty());
    }

    @Test
    void renderCleanupRestoresExactOriginMapAndKeepsOtherLocalSlots() throws Exception {
        var cell = allocate(IsoCell.class);
        var field = IsoCell.class.getDeclaredField("chunkMap");
        field.setAccessible(true);
        var origin = new IsoChunkMap(cell);
        var observer = new IsoChunkMap(cell);
        var secondLocal = new IsoChunkMap(cell);
        var maps = new IsoChunkMap[] {observer, secondLocal, null, null};
        field.set(cell, maps);
        state("cell", cell);
        state("map", observer);
        state("renderOrigin", origin);
        state("renderSlot", 0);
        var render = AdminCoreObserveRender.class.getDeclaredField("RENDER");
        render.setAccessible(true);
        @SuppressWarnings("unchecked")
        var scope = (ThreadLocal<AdminCoreObserveRender.Region>) render.get(null);
        scope.set(new AdminCoreObserveRender.Region(0, 1000, 2000, 0));
        assertFalse(AdminCoreObserveRender.begin(), "Nested render preserves outer scope");
        AdminCoreObserveRenderAdvice.exit(false);
        assertSame(observer, maps[0]);
        assertNotNull(scope.get());
        AdminCoreObserveRenderAdvice.exit(true);
        assertSame(origin, maps[0]);
        assertSame(secondLocal, maps[1]);
        AdminCoreObserveStreaming.clear();
        assertSame(origin, maps[0]);
    }

    @Test
    void authorizedPhysicalMapStaysAtActorAndRenderMapIsRestoredOnRevocation() throws Exception {
        var previousInstance = IsoPlayer.getInstance();
        var previousSlot = IsoPlayer.players[0];
        var viewer = allocate(ObservePlayerVisibilityTest.NativeVisibilityProbe.class);
        viewer.playerIndex = 0;
        viewer.role = new Role("observer");
        viewer.role.addCapability(Capability.TeleportToPlayer);
        viewer.role.addCapability(Capability.SeePlayersConnected);
        viewer.role.addCapability(Capability.UseDebugContextMenu);
        viewer.role.addCapability(Capability.ToggleInvisibleHimself);
        var remote = allocate(ObservePlayerVisibilityTest.NativeVisibilityProbe.class);
        IsoPlayer.players[0] = viewer;
        IsoPlayer.setInstance(viewer);
        var retry = AdminCoreObserveCamera.class.getDeclaredField("retryAfter");
        retry.setAccessible(true);
        retry.setLong(null, 0);
        try {
            assertTrue(AdminCoreObserveCamera.grant("remote", true));
            var cell = allocate(IsoCell.class);
            var physical = new IsoChunkMap(cell);
            var observer = new IsoChunkMap(cell);
            var secondLocal = new IsoChunkMap(cell);
            var maps = new IsoChunkMap[] {physical, secondLocal, null, null};
            var field = IsoCell.class.getDeclaredField("chunkMap");
            field.setAccessible(true);
            field.set(cell, maps);
            state("cell", cell);
            state("map", observer);
            state("actor", viewer);
            assertSame(viewer, AdminCoreObserveStreaming.physicalCharacter(physical, remote));
            assertSame(remote, AdminCoreObserveStreaming.physicalCharacter(secondLocal, remote));
            assertTrue(AdminCoreObserveStreaming.beginRender(0));
            assertSame(observer, maps[0]);
            assertSame(secondLocal, maps[1]);
            assertFalse(
                    AdminCoreObserveStreaming.beginRender(0),
                    "Nested frame cannot overwrite origin");
            viewer.role = new Role("user");
            assertFalse(AdminCoreObserveCamera.active());
            assertSame(physical, maps[0]);
            assertSame(secondLocal, maps[1]);
            assertSame(remote, AdminCoreObserveStreaming.physicalCharacter(physical, remote));
        } finally {
            AdminCoreObserveCamera.stop();
            IsoPlayer.players[0] = previousSlot;
            IsoPlayer.setInstance(previousInstance);
            retry.setLong(null, 0);
        }
    }

    @Test
    void inactiveNativeCallsStayNativeAndNoOriginUnloadingOrPlayerSlotGrowthExists()
            throws Exception {
        assertFalse(
                AdminCoreObserveStreaming.capacitySupported(),
                "Unwoven game classes must reject streaming");
        assertNull(AdminCoreObserveStreaming.physicalCharacter(null, null));
        assertFalse(AdminCoreObserveStreaming.accept(null));
        assertFalse(AdminCoreObserveStreaming.shouldRequest(null));
        var forbidden =
                java.util.Set.of(
                        "Unload",
                        "Dispose",
                        "ProcessChunkPos",
                        "sendTeleport",
                        "setX",
                        "setY",
                        "setZ");
        try (var stream =
                AdminCoreObserveStreaming.class.getResourceAsStream(
                        "AdminCoreObserveStreaming.class")) {
            new ClassReader(stream)
                    .accept(
                            new ClassVisitor(Opcodes.ASM9) {
                                @Override
                                public MethodVisitor visitMethod(
                                        int access,
                                        String name,
                                        String desc,
                                        String sig,
                                        String[] exceptions) {
                                    return new MethodVisitor(Opcodes.ASM9) {
                                        @Override
                                        public void visitMethodInsn(
                                                int opcode,
                                                String owner,
                                                String name,
                                                String desc,
                                                boolean itf) {
                                            assertFalse(forbidden.contains(name), name);
                                        }

                                        @Override
                                        public void visitFieldInsn(
                                                int opcode,
                                                String owner,
                                                String name,
                                                String desc) {
                                            if (opcode == Opcodes.PUTSTATIC)
                                                assertFalse(
                                                        name.equals("numPlayers")
                                                                || name.equals("chunkGridWidth"),
                                                        name);
                                        }
                                    };
                                }
                            },
                            0);
        }
    }

    @Test
    void softPanAndRestoredPredictionStayRelativeToTargetAndDoNotMoveStreamRegion()
            throws Exception {
        var previousInstance = IsoPlayer.getInstance();
        var previousSlot = IsoPlayer.players[0];
        var previousWorld = IsoWorld.instance;
        var viewer = allocate(ObservePlayerVisibilityTest.NativeVisibilityProbe.class);
        viewer.playerIndex = 0;
        viewer.role = new Role("observer");
        for (var cap :
                java.util.List.of(
                        Capability.TeleportToPlayer,
                        Capability.SeePlayersConnected,
                        Capability.UseDebugContextMenu,
                        Capability.ToggleInvisibleHimself)) viewer.role.addCapability(cap);
        var remote = allocate(ObservePlayerVisibilityTest.NativeVisibilityProbe.class);
        remote.setX(1000);
        remote.setY(1000);
        remote.square(new IsoGridSquare(null, null, 1000, 1000, 0));
        IsoPlayer.players[0] = viewer;
        IsoPlayer.setInstance(viewer);
        IsoWorld.instance = allocate(IsoWorld.class);
        IsoWorld.instance.currentCell = allocate(IsoCell.class);
        cameraState("retryAfter", 0L);
        try {
            assertTrue(AdminCoreObserveCamera.grant("remote", true));
            cameraState("target", remote);
            cameraState("resolveAfter", System.currentTimeMillis() + 60000);
            cameraState("streamGranted", true);
            cameraState("hasPosition", true);
            cameraState("grantedX", 1007f);
            cameraState("grantedY", 1000f);
            cameraState("grantedZ", 0f);
            cameraState("mode", "SOFT");
            assertFalse(
                    AdminCoreObserveCamera.pan(2, 0),
                    "ACK offset cannot become the SOFT bounds anchor");
            assertEquals(1007f, AdminCoreObserveCamera.getViewX());
            assertTrue(AdminCoreObserveCamera.pan(1, 0));
            assertEquals(1008f, AdminCoreObserveCamera.getViewX());
            cameraState("panX", 0f);
            assertTrue(AdminCoreObserveCamera.restorePrediction(1, 0));
            assertEquals(1008f, AdminCoreObserveCamera.getViewX());
            assertFalse(AdminCoreObserveCamera.restorePrediction(.1, 0));
            assertEquals(1008f, AdminCoreObserveCamera.getViewX());
            assertFalse(AdminCoreObserveCamera.restorePrediction(Double.NaN, 0));
            assertFalse(AdminCoreObserveCamera.restorePrediction(0, Double.POSITIVE_INFINITY));
            assertFalse(AdminCoreObserveCamera.restorePrediction(Double.MAX_VALUE, 0));
            cameraState("mode", "FOLLOW");
            assertFalse(AdminCoreObserveCamera.restorePrediction(1, 0));
            cameraState("mode", "FREE");
            cameraState("freeX", 1000f);
            cameraState("freeY", 1000f);
            cameraState("freeAnchorX", 1000f);
            cameraState("freeAnchorY", 1000f);
            var interest =
                    new AdminCoreObserveStreaming.Interest(
                            125, 125, System.currentTimeMillis() + 6000);
            state("interest", interest);
            assertTrue(AdminCoreObserveCamera.restorePrediction(24, 0));
            assertEquals(1024f, AdminCoreObserveCamera.getViewX());
            assertFalse(AdminCoreObserveCamera.restorePrediction(1, 0));
            assertEquals(1024f, AdminCoreObserveCamera.getViewX());
            var field = AdminCoreObserveStreaming.class.getDeclaredField("interest");
            field.setAccessible(true);
            assertSame(
                    interest,
                    field.get(null),
                    "Prediction never changes authorized terrain interest");
            assertTrue(owners().isEmpty(), "Prediction requests no terrain");
            cameraState("streamGranted", false);
            assertFalse(AdminCoreObserveCamera.restorePrediction(-1, 0));
            viewer.role = new Role("user");
            assertFalse(AdminCoreObserveCamera.restorePrediction(-1, 0));
        } finally {
            AdminCoreObserveCamera.stop();
            IsoWorld.instance = previousWorld;
            IsoPlayer.players[0] = previousSlot;
            IsoPlayer.setInstance(previousInstance);
            cameraState("retryAfter", 0L);
        }
    }
}
