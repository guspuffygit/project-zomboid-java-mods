package com.sentientsimulations.projectzomboid.admincore;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.pzstorm.storm.core.StormClassTransformer;
import java.util.HashSet;
import java.util.Set;
import net.bytebuddy.ByteBuddy;
import net.bytebuddy.dynamic.ClassFileLocator;
import net.bytebuddy.jar.asm.ClassReader;
import net.bytebuddy.jar.asm.ClassVisitor;
import net.bytebuddy.jar.asm.MethodVisitor;
import net.bytebuddy.jar.asm.Opcodes;
import net.bytebuddy.matcher.ElementMatchers;
import net.bytebuddy.pool.TypePool;
import org.junit.jupiter.api.Test;

class ObserveCameraWeaveTest {
    @Test
    void adviceWeavesIntoInstalledGameWithoutLoadingGameClasses() throws Exception {
        ClassFileLocator locator = ClassFileLocator.ForClassLoader.ofSystemLoader();
        TypePool pool = TypePool.Default.of(locator);
        var type = pool.describe("zombie.iso.IsoCamera").resolve();
        assertEquals(
                1,
                type.getDeclaredMethods()
                        .filter(ElementMatchers.named("setCameraCharacter"))
                        .size());
        var builder = new ByteBuddy().redefine(type, locator);
        byte[] transformed =
                new AdminCoreObservePatch().dynamicType(locator, pool, builder).make().getBytes();
        assertTrue(transformed.length > 0);
    }

    private void weave(
            String className, StormClassTransformer patch, int expectedMethods, String... methods)
            throws Exception {
        ClassFileLocator locator = ClassFileLocator.ForClassLoader.ofSystemLoader();
        TypePool pool = TypePool.Default.of(locator);
        var type = pool.describe(className).resolve();
        assertEquals(
                expectedMethods,
                type.getDeclaredMethods().filter(ElementMatchers.namedOneOf(methods)).size());
        var builder = new ByteBuddy().redefine(type, locator);
        assertTrue(patch.dynamicType(locator, pool, builder).make().getBytes().length > 0);
    }

    @Test
    void panAndWeatherAdviceWeaveIntoInstalledB42() throws Exception {
        weave("zombie.iso.PlayerCamera", new AdminCoreObserverPanPatch(), 2, "center", "update");
        weave(
                "zombie.iso.weather.fx.IsoWeatherFX",
                new AdminCoreObserverWeatherPatch(),
                5,
                "render",
                "renderLayered",
                "renderClouds",
                "renderFog",
                "renderPrecipitation");
    }

    @Test
    void cameraDoesNotWriteAvatarCoordinatesOrInvokeMovementPackets() throws Exception {
        Set<String> calls = new HashSet<>();
        try (var stream = getClass().getResourceAsStream("AdminCoreObserveCamera.class")) {
            new ClassReader(stream)
                    .accept(
                            new ClassVisitor(Opcodes.ASM9) {
                                @Override
                                public MethodVisitor visitMethod(
                                        int access,
                                        String name,
                                        String descriptor,
                                        String signature,
                                        String[] exceptions) {
                                    return new MethodVisitor(Opcodes.ASM9) {
                                        @Override
                                        public void visitMethodInsn(
                                                int opcode,
                                                String owner,
                                                String name,
                                                String descriptor,
                                                boolean isInterface) {
                                            calls.add(name);
                                        }
                                    };
                                }
                            },
                            0);
        }
        for (String forbidden :
                new String[] {
                    "sendTeleport",
                    "setX",
                    "setY",
                    "setZ",
                    "setLx",
                    "setLy",
                    "setLz",
                    "setSquare",
                    "setCurrentSquare"
                }) {
            assertTrue(!calls.contains(forbidden), "Camera must not call " + forbidden);
        }
        assertTrue(calls.contains("isBlockMovement"), "Capture pre-existing input state");
        assertTrue(calls.contains("setBlockMovement"), "Restore input state on cleanup");
    }

    @Test
    void observerReturnRejectsNonFiniteAndImpossibleCoordinates() {
        assertTrue(AdminCoreObserverBridge.validPosition(1234.5, 6789.5, 0));
        assertTrue(!AdminCoreObserverBridge.validPosition(Double.NaN, 0, 0));
        assertTrue(!AdminCoreObserverBridge.validPosition(0, Double.POSITIVE_INFINITY, 0));
        assertTrue(!AdminCoreObserverBridge.validPosition(0, 0, 400));
        assertTrue(!AdminCoreObserverBridge.validPosition(2000000, 0, 0));
    }

    @Test
    void panLimitsAnchorOnObservedAreaAndDoNotClaimOtherPlayersCameras() {
        assertTrue(AdminCoreObserveCamera.insidePanRange(101, 201, 100, 200, 8));
        assertTrue(!AdminCoreObserveCamera.insidePanRange(130, 201, 100, 200, 24));
        assertTrue(!AdminCoreObserveCamera.insidePanRange(Float.NaN, 201, 100, 200, 24));
        Object actor = new Object(), target = new Object(), secondLocalPlayer = new Object();
        assertTrue(AdminCoreObserveCamera.ownsCamera(actor, actor, target));
        assertTrue(AdminCoreObserveCamera.ownsCamera(target, actor, target));
        assertTrue(!AdminCoreObserveCamera.ownsCamera(secondLocalPlayer, actor, target));
    }
}
