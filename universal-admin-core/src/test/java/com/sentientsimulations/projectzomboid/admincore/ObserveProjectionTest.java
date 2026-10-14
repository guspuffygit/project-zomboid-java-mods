package com.sentientsimulations.projectzomboid.admincore;

import static org.junit.jupiter.api.Assertions.*;

import java.util.HashMap;
import java.util.Map;
import net.bytebuddy.ByteBuddy;
import net.bytebuddy.dynamic.ClassFileLocator;
import net.bytebuddy.jar.asm.*;
import net.bytebuddy.pool.TypePool;
import org.joml.Matrix4f;
import org.junit.jupiter.api.Test;
import zombie.characters.*;
import zombie.iso.*;
import zombie.network.GameClient;

class ObserveProjectionTest {
    public static class Viewer extends ObservePlayerVisibilityTest.NativeVisibilityProbe {
        float px, py, pz;

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
    }

    static void state(String name, Object value) throws Exception {
        var field = AdminCoreObserveCamera.class.getDeclaredField(name);
        field.setAccessible(true);
        field.set(null, value);
    }

    static <T> T allocate(Class<T> type) throws Exception {
        var field = sun.misc.Unsafe.class.getDeclaredField("theUnsafe");
        field.setAccessible(true);
        return type.cast(((sun.misc.Unsafe) field.get(null)).allocateInstance(type));
    }

    private byte[] weave() throws Exception {
        var locator = ClassFileLocator.ForClassLoader.ofSystemLoader();
        var pool = TypePool.Default.of(locator);
        return new AdminCoreObserveProjectionPatch()
                .dynamicType(
                        locator,
                        pool,
                        new ByteBuddy()
                                .redefine(
                                        pool.describe("zombie.iso.PlayerCamera").resolve(),
                                        locator))
                .make()
                .getBytes();
    }

    @Test
    void substitutesOnlyNativeViewerReadsAndVerifiesInstalledCameraBytecode() throws Exception {
        byte[] bytes = weave();
        Map<String, Integer> calls = new HashMap<>();
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
                                        if (owner.endsWith("/AdminCoreObserveCamera")
                                                && method.equals("projectionCoordinate"))
                                            calls.merge(n, 1, Integer::sum);
                                    }
                                };
                            }
                        },
                        0);
        assertEquals(
                Map.of("calculateModelViewProjection", 3, "calculateFixForJigglyModels", 1), calls);
        Class<?> nativeCamera = new NativeLoader().define(bytes);
        assertDoesNotThrow(nativeCamera::getDeclaredMethods);
    }

    @Test
    void nativeProjectionMatchesObserverPositionWhileAvatarAndOtherViewersStayPut()
            throws Exception {
        IsoPlayer previous = IsoPlayer.getInstance(), slot = IsoPlayer.players[0];
        IsoGameCharacter cameraCharacter = IsoCamera.getCameraCharacter();
        boolean client = GameClient.client;
        Viewer actor = allocate(Viewer.class), reference = allocate(Viewer.class);
        actor.px = 10;
        actor.py = 20;
        reference.px = 104;
        reference.py = 205;
        reference.pz = 1;
        actor.role = new Role("observer");
        for (var cap :
                new Capability[] {
                    Capability.TeleportToPlayer, Capability.SeePlayersConnected,
                    Capability.UseDebugContextMenu, Capability.ToggleInvisibleHimself
                }) actor.role.addCapability(cap);
        actor.playerIndex = 0;
        IsoPlayer.players[0] = actor;
        IsoPlayer.setInstance(actor);
        GameClient.client = true;
        try {
            AdminCoreObserveCamera.stop();
            state("retryAfter", 0L);
            Class<?> type = new NativeLoader().define(weave());
            Object camera = type.getConstructor(int.class).newInstance(0);
            float offX = IsoUtils.XToScreen(104, 205, 1, 0) - IsoCamera.getOffscreenWidth(0) / 2f;
            float offY = IsoUtils.YToScreen(104, 205, 1, 0) - IsoCamera.getOffscreenHeight(0) / 2f;
            for (String name : new String[] {"offX", "tOffX"}) {
                var f = type.getDeclaredField(name);
                f.setAccessible(true);
                f.setFloat(camera, offX);
            }
            for (String name : new String[] {"offY", "tOffY"}) {
                var f = type.getDeclaredField(name);
                f.setAccessible(true);
                f.setFloat(camera, offY);
            }
            var calculate =
                    type.getMethod(
                            "calculateModelViewProjection", float.class, float.class, float.class);
            IsoCamera.setCameraCharacter(reference);
            calculate.invoke(camera, 0f, 0f, 0f);
            Matrix4f expected = new Matrix4f((Matrix4f) type.getField("modelview").get(camera));
            IsoCamera.setCameraCharacter(actor);
            calculate.invoke(camera, 0f, 0f, 0f);
            assertFalse(
                    expected.equals((Matrix4f) type.getField("modelview").get(camera), .00001f),
                    "Native projection reproduces the avatar-centered bug before the grant");
            assertTrue(AdminCoreObserveCamera.grant("observer", true));
            state("target", actor);
            state("resolveAfter", System.currentTimeMillis() + 6000);
            state("mode", "FREE");
            state("freeX", 104f);
            state("freeY", 205f);
            state("freeZ", 1f);
            calculate.invoke(camera, 0f, 0f, 0f);
            assertTrue(
                    expected.equals((Matrix4f) type.getField("modelview").get(camera), .00001f),
                    "Actual B42 matrix calculation uses the observer coordinates");
            assertEquals(10, actor.getX());
            assertEquals(20, actor.getY());
            assertEquals(0, actor.getZ());
            assertEquals(
                    42f,
                    AdminCoreObserveCamera.projectionCoordinate(42, 1, 0),
                    "Other local camera is unchanged");
            assertEquals(42f, AdminCoreObserveCamera.projectionCoordinate(42, 0, -1));
            AdminCoreObserveCamera.stop();
            assertEquals(42f, AdminCoreObserveCamera.projectionCoordinate(42, 0, 0));
        } finally {
            AdminCoreObserveCamera.stop();
            state("retryAfter", 0L);
            IsoPlayer.players[0] = slot;
            IsoPlayer.setInstance(previous);
            IsoCamera.setCameraCharacter(cameraCharacter);
            GameClient.client = client;
        }
    }

    @Test
    void followsInterpolatedPlayerBetweenGrantsWithoutReplayingTargetMotionAsPan()
            throws Exception {
        IsoPlayer previous = IsoPlayer.getInstance(), slot = IsoPlayer.players[0];
        boolean client = GameClient.client;
        Viewer actor = allocate(Viewer.class), remote = allocate(Viewer.class);
        remote.square(new IsoGridSquare(null, null, 1000, 2000, 0));
        actor.px = 10;
        actor.py = 20;
        actor.playerIndex = 0;
        actor.role = new Role("observer");
        actor.role.addCapability(Capability.TeleportToPlayer);
        actor.role.addCapability(Capability.SeePlayersConnected);
        actor.role.addCapability(Capability.ToggleInvisibleHimself);
        IsoPlayer.players[0] = actor;
        IsoPlayer.setInstance(actor);
        GameClient.client = true;
        try {
            AdminCoreObserveCamera.stop();
            state("retryAfter", 0L);
            assertTrue(AdminCoreObserveCamera.grant("remote", true));
            state("target", remote);
            state("resolveAfter", System.currentTimeMillis() + 6000);
            state("streamGranted", true);
            state("hasPosition", true);
            state("grantedX", 1000f);
            state("grantedY", 2000f);
            state("grantedZ", 0f);
            remote.px = 1000.25f;
            remote.py = 2000.5f;
            assertEquals(1000.25f, AdminCoreObserveCamera.getViewX());
            remote.px = 1000.75f;
            assertEquals(
                    1000.75f,
                    AdminCoreObserveCamera.getViewX(),
                    "Native movement is visible before the next grant");
            state("grantedX", 1000.5f);
            assertEquals(
                    1000.75f,
                    AdminCoreObserveCamera.getViewX(),
                    "An older server snapshot cannot pull the camera back");
            assertTrue(AdminCoreObserveCamera.setMode("SOFT"));
            assertTrue(AdminCoreObserveCamera.setFollowOffset(2, -1));
            assertTrue(AdminCoreObserveCamera.restorePrediction(.5, .25));
            remote.px += 3;
            remote.py += 2;
            assertEquals(remote.px + 2.5f, AdminCoreObserveCamera.getViewX());
            assertEquals(remote.py - .75f, AdminCoreObserveCamera.getViewY());
            assertEquals(2.5f, AdminCoreObserveCamera.getFollowOffsetX());
            assertEquals(-.75f, AdminCoreObserveCamera.getFollowOffsetY());
            assertFalse(AdminCoreObserveCamera.restorePrediction(6, 0));
            assertFalse(AdminCoreObserveCamera.setFollowOffset(Double.NaN, 0));
            assertTrue(AdminCoreObserveCamera.setMode("FOLLOW"));
            remote.pz = 1;
            assertEquals(
                    1000.5f,
                    AdminCoreObserveCamera.getViewX(),
                    "A new floor awaits server authorization");
            assertEquals(0f, AdminCoreObserveCamera.getViewZ());
            remote.pz = 0;
            remote.px = 5000;
            assertEquals(
                    1000.5f,
                    AdminCoreObserveCamera.getViewX(),
                    "Outside the granted region uses the authorized center");
            state("target", null);
            assertEquals(2000f, AdminCoreObserveCamera.getViewY());
            assertEquals(10, actor.px);
            assertEquals(20, actor.py);
        } finally {
            AdminCoreObserveCamera.stop();
            state("retryAfter", 0L);
            IsoPlayer.players[0] = slot;
            IsoPlayer.setInstance(previous);
            GameClient.client = client;
        }
    }

    private static final class NativeLoader extends ClassLoader {
        NativeLoader() {
            super(ObserveProjectionTest.class.getClassLoader());
        }

        Class<?> define(byte[] bytes) {
            return defineClass("zombie.iso.PlayerCamera", bytes, 0, bytes.length);
        }
    }
}
