package com.sentientsimulations.projectzomboid.admincore;

import static org.junit.jupiter.api.Assertions.*;

import io.pzstorm.storm.core.StormClassTransformer;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;
import net.bytebuddy.ByteBuddy;
import net.bytebuddy.asm.Advice;
import net.bytebuddy.dynamic.ClassFileLocator;
import net.bytebuddy.dynamic.loading.ByteArrayClassLoader;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy;
import net.bytebuddy.jar.asm.*;
import net.bytebuddy.matcher.ElementMatchers;
import net.bytebuddy.pool.TypePool;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import zombie.core.opengl.RenderSettings;
import zombie.core.textures.ColorInfo;
import zombie.iso.*;

class ObserveRenderTest {
    @AfterEach
    void cleanup() {
        AdminCoreObserveRender.clear();
    }

    @Test
    void sceneFallbackMatchesActualNativeSkyBytecodeForDayNightTintAndSaturation()
            throws Exception {
        // Copy the actual native formula, leaving out singleton access, the debug override and
        // JNI invalidation. Production settings remain read-only throughout the comparison.
        String name = "zombie.NativeObserverSkyProbe";
        var writer = new ClassWriter(ClassWriter.COMPUTE_MAXS | ClassWriter.COMPUTE_FRAMES);
        writer.visit(
                Opcodes.V17,
                Opcodes.ACC_PUBLIC,
                name.replace('.', '/'),
                null,
                "java/lang/Object",
                null);
        var output =
                writer.visitMethod(
                        Opcodes.ACC_PUBLIC | Opcodes.ACC_STATIC,
                        "sky",
                        "(Lzombie/core/opengl/RenderSettings$PlayerRenderSettings;)I",
                        null,
                        null);
        output.visitCode();
        output.visitVarInsn(Opcodes.ALOAD, 0);
        output.visitVarInsn(Opcodes.ASTORE, 1);
        boolean[] copied = {false};
        boolean[] finished = {false};
        try (var nativeClass = zombie.GameTime.class.getResourceAsStream("GameTime.class")) {
            new ClassReader(nativeClass)
                    .accept(
                            new ClassVisitor(Opcodes.ASM9) {
                                @Override
                                public MethodVisitor visitMethod(
                                        int access,
                                        String method,
                                        String descriptor,
                                        String signature,
                                        String[] exceptions) {
                                    if (!method.equals("getSkyLightLevel")
                                            || !descriptor.equals("()I")) return null;
                                    return new MethodVisitor(Opcodes.ASM9) {
                                        private boolean active;

                                        @Override
                                        public void visitVarInsn(int opcode, int variable) {
                                            if (!active
                                                    && !copied[0]
                                                    && opcode == Opcodes.ASTORE
                                                    && variable == 1) {
                                                active = copied[0] = true;
                                            } else if (active)
                                                output.visitVarInsn(opcode, variable);
                                        }

                                        @Override
                                        public void visitInsn(int opcode) {
                                            if (active) output.visitInsn(opcode);
                                        }

                                        @Override
                                        public void visitIntInsn(int opcode, int operand) {
                                            if (active) output.visitIntInsn(opcode, operand);
                                        }

                                        @Override
                                        public void visitLdcInsn(Object value) {
                                            if (active) output.visitLdcInsn(value);
                                        }

                                        @Override
                                        public void visitMethodInsn(
                                                int opcode,
                                                String owner,
                                                String called,
                                                String calledDescriptor,
                                                boolean isInterface) {
                                            if (active)
                                                output.visitMethodInsn(
                                                        opcode,
                                                        owner,
                                                        called,
                                                        calledDescriptor,
                                                        isInterface);
                                        }

                                        @Override
                                        public void visitFieldInsn(
                                                int opcode,
                                                String owner,
                                                String field,
                                                String fieldDescriptor) {
                                            if (active) {
                                                assertEquals("zombie/debug/DebugOptions", owner);
                                                assertEquals("instance", field);
                                                output.visitVarInsn(Opcodes.ILOAD, 5);
                                                output.visitInsn(Opcodes.IRETURN);
                                                active = false;
                                                finished[0] = true;
                                            }
                                        }
                                    };
                                }
                            },
                            ClassReader.SKIP_DEBUG | ClassReader.SKIP_FRAMES);
        }
        assertTrue(copied[0]);
        assertTrue(finished[0]);
        output.visitMaxs(0, 0);
        output.visitEnd();
        writer.visitEnd();
        var loader =
                new ByteArrayClassLoader(
                        getClass().getClassLoader(), Map.of(name, writer.toByteArray()));
        var sky =
                Class.forName(name, true, loader)
                        .getMethod("sky", RenderSettings.PlayerRenderSettings.class);
        float[][] conditions = {
            {.5f, 1f, 1f, 1f}, // Ordinary daylight saturates to full skylight.
            {.25f, 1f, 1f, 1f}, // Night / dim sky still uses twice the ambient value.
            {.5f, .5f, .75f, 1f}, // Independent RGB tint, native integer conversion.
            {.1f, 2f, .25f, .9f}, // Clamp after multiplying; do not cap tint beforehand.
            {.75f, 1f, .9f, .25f}, // Per-channel saturation.
            {0f, 1f, 1f, 1f},
            {-.5f, 1f, 1f, 1f},
            {2f, .2f, .4f, 2f}
        };
        String[] fields = {"ambient", "rmod", "gmod", "bmod"};
        for (float[] values : conditions) {
            var settings = new RenderSettings.PlayerRenderSettings();
            for (int index = 0; index < fields.length; index++) {
                var field = settings.getClass().getDeclaredField(fields[index]);
                field.setAccessible(true);
                field.setFloat(settings, values[index]);
            }
            int nativeSky = (int) sky.invoke(null, settings);
            var fallback = AdminCoreObserveRender.SceneLight.from(settings);
            // Lighting64 returns this sky as-is; native JNILighting consumes R low / B high.
            assertEquals((nativeSky & 255) / 255f, fallback.r());
            assertEquals((nativeSky >>> 8 & 255) / 255f, fallback.g());
            assertEquals((nativeSky >>> 16 & 255) / 255f, fallback.b());
            assertEquals(values[0], settings.getAmbient());
            assertEquals(values[1], settings.getRmod());
            assertEquals(values[2], settings.getGmod());
            assertEquals(values[3], settings.getBmod());
        }
    }

    @SuppressWarnings("unchecked")
    private void renderScope(AdminCoreObserveRender.Region region) throws Exception {
        var field = AdminCoreObserveRender.class.getDeclaredField("RENDER");
        field.setAccessible(true);
        ((ThreadLocal<AdminCoreObserveRender.Region>) field.get(null)).set(region);
    }

    private void weave(String name, StormClassTransformer patch, int count, String... methods)
            throws Exception {
        var locator = ClassFileLocator.ForClassLoader.ofSystemLoader();
        var pool = TypePool.Default.of(locator);
        var type = pool.describe(name).resolve();
        assertEquals(
                count,
                type.getDeclaredMethods().filter(ElementMatchers.namedOneOf(methods)).size());
        assertTrue(
                patch.dynamicType(locator, pool, new ByteBuddy().redefine(type, locator))
                                .make()
                                .getBytes()
                                .length
                        > 0);
    }

    @Test
    void adviceWeavesActualB42FrameRenderLightingAndBlackoutSignatures() throws Exception {
        weave("zombie.iso.IsoCamera$FrameState", new AdminCoreObserveFramePatch(), 1, "set");
        weave("zombie.iso.IsoWorld", new AdminCoreObserveRenderPatch(), 1, "render");
        weave(
                "zombie.iso.LightingJNI$JNILighting",
                new AdminCoreObserveLightPatch(),
                6,
                "bSeen",
                "bCanSee",
                "bCouldSee");
        weave(
                "zombie.iso.IsoGridSquare",
                new AdminCoreObserveSquarePatch(),
                10,
                "isSeen",
                "getSeen",
                "isCanSee",
                "getCanSee",
                "isCouldSee",
                "getLightInfo",
                "getVertLight",
                "getLightLevel",
                "getDarkMulti",
                "getTargetDarkMulti");
        weave(
                "zombie.iso.fboRenderChunk.FBORenderCell",
                new AdminCoreObserveBlackoutPatch(),
                1,
                "isBlackedOutBuildingSquare");
    }

    public static class SkipNativeLightingUpdater {
        @Advice.OnMethodEnter(skipOn = Advice.OnNonDefaultValue.class)
        public static boolean enter() {
            return true;
        }
    }

    @Test
    void actualNativeLightingGettersAreTemporaryAndDoNotRevealSavedSeenState() throws Exception {
        // Execute actual B42 getter bytecode with only its native-DLL updater suppressed.
        // Renaming keeps this test-local class isolated from the JVM's installed game class.
        var observedType =
                new ByteBuddy()
                        .redefine(LightingJNI.JNILighting.class)
                        .name("zombie.iso.AdminObserverNativeLightingProbe")
                        .visit(
                                Advice.to(AdminCoreObserveLightAdvice.class)
                                        .on(
                                                ElementMatchers.namedOneOf(
                                                                "bSeen", "bCanSee", "bCouldSee")
                                                        .and(ElementMatchers.takesArguments(0))))
                        .visit(
                                Advice.to(SkipNativeLightingUpdater.class)
                                        .on(
                                                ElementMatchers.named("update")
                                                        .and(ElementMatchers.takesArguments(0))))
                        .make()
                        .load(getClass().getClassLoader(), ClassLoadingStrategy.Default.WRAPPER)
                        .getLoaded();
        var square = new IsoGridSquare(null, null, 104, 204, 0);
        square.chunk = new IsoChunk((WorldReuserThread) null);
        square.chunk.lightingNeverDone[0] = true;
        var lighting =
                (IsoGridSquare.ILighting)
                        observedType
                                .getConstructor(int.class, IsoGridSquare.class)
                                .newInstance(0, square);
        var otherLighting =
                (IsoGridSquare.ILighting)
                        observedType
                                .getConstructor(int.class, IsoGridSquare.class)
                                .newInstance(1, square);
        var nativeVis = observedType.getDeclaredField("vis");
        nativeVis.setAccessible(true);
        var nativeColor = new ColorInfo(0f, 0f, 0f, 1f);
        square.setLightInfoServerGUIOnly(nativeColor);
        assertFalse(lighting.bSeen());
        assertFalse(lighting.bCanSee());
        assertSame(nativeColor, square.getLightInfo(0));
        renderScope(new AdminCoreObserveRender.Region(0, 13, 25, 0));
        assertTrue(lighting.bSeen());
        assertTrue(lighting.bCanSee());
        assertTrue(lighting.bCouldSee());
        assertEquals(1f, AdminCoreObserveRender.color(square, 0, nativeColor).r);
        assertNotSame(nativeColor, AdminCoreObserveRender.color(square, 0, nativeColor));
        assertEquals((byte) 0, nativeVis.getByte(lighting));
        assertFalse(square.lighting[0].bSeen(), "Native stored exploration bit stays false");
        assertFalse(square.lighting[0].bCanSee(), "Native stored LOS stays false");
        assertEquals(0f, nativeColor.r, "Native light color is not overwritten");
        assertFalse(otherLighting.bSeen(), "Another split-screen slot retains its visibility");
        AdminCoreObserveRender.end(true);
        assertFalse(lighting.bSeen());
        assertFalse(lighting.bCanSee());
        assertSame(nativeColor, AdminCoreObserveRender.color(square, 0, nativeColor));
        assertEquals(104, square.x);
        assertEquals(204, square.y);
        assertEquals(0, square.z);
    }

    @Test
    void scopeRejectsUnloadedFarAwayUpperFloorAndOtherPlayerSquares() throws Exception {
        var square = new IsoGridSquare(null, null, 104, 204, 0);
        renderScope(new AdminCoreObserveRender.Region(0, 13, 25, 0));
        assertFalse(AdminCoreObserveRender.visible(square, 0));
        square.chunk = new IsoChunk((WorldReuserThread) null);
        assertTrue(AdminCoreObserveRender.visible(square, 0));
        assertFalse(AdminCoreObserveRender.visible(square, 1));
        assertFalse(new AdminCoreObserveRender.Region(0, 13, 25, 0).contains(0, 1000, 2000, 0));
        assertFalse(new AdminCoreObserveRender.Region(0, 13, 25, 0).contains(0, 104, 204, 1));
        assertFalse(new AdminCoreObserveRender.Region(0, 13, 25, 0).contains(0, 104, 204, -3));
        AdminCoreObserveRender.clear();
        assertFalse(AdminCoreObserveRender.visible(square, 0));
    }

    @Test
    void exceptionsAndStopRemoveTemporaryRenderPrivilege() throws Exception {
        var square = new IsoGridSquare(null, null, 104, 204, 0);
        square.chunk = new IsoChunk((WorldReuserThread) null);
        renderScope(new AdminCoreObserveRender.Region(0, 13, 25, 0));
        assertTrue(AdminCoreObserveRender.visible(square, 0));
        AdminCoreObserveRenderAdvice.exit(true);
        assertFalse(AdminCoreObserveRender.visible(square, 0));
        renderScope(new AdminCoreObserveRender.Region(0, 13, 25, 0));
        AdminCoreObserveCamera.stop();
        assertFalse(AdminCoreObserveRender.visible(square, 0));
        assertFalse(AdminCoreObserveRender.begin(), "No grant creates no render scope");
    }

    @Test
    void observerCodeNeverCallsNativeExplorationLightingOrMovementSetters() throws Exception {
        Set<String> calls = new HashSet<>();
        for (var type :
                new Class<?>[] {
                    AdminCoreObserveCamera.class,
                    AdminCoreObserveRender.class,
                    AdminCoreObserveLightAdvice.class,
                    AdminCoreObserveSquareAdvice.class,
                    AdminCoreObserveBlackoutAdvice.class
                }) {
            try (var stream = type.getResourceAsStream(type.getSimpleName() + ".class")) {
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
                                                calls.add(name + descriptor);
                                            }
                                        };
                                    }
                                },
                                0);
            }
        }
        for (String call : calls)
            assertFalse(
                    call.matches(
                            "(setIsSeen|setCanSee|setCouldSee|setDarkMulti|setTargetDarkMulti|setCurrentSquare|setSquare|sendTeleport|setX|setY|setZ|bSeen|bCanSee|bCouldSee).*"),
                    call);
    }
}
