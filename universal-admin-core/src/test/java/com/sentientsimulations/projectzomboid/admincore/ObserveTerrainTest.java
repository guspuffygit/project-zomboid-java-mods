package com.sentientsimulations.projectzomboid.admincore;

import static org.junit.jupiter.api.Assertions.*;

import java.lang.reflect.InvocationTargetException;
import java.util.HashMap;
import java.util.Map;
import net.bytebuddy.ByteBuddy;
import net.bytebuddy.asm.Advice;
import net.bytebuddy.dynamic.ClassFileLocator;
import net.bytebuddy.dynamic.loading.ByteArrayClassLoader;
import net.bytebuddy.jar.asm.*;
import net.bytebuddy.matcher.ElementMatchers;
import net.bytebuddy.pool.TypePool;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import zombie.core.opengl.Shader;
import zombie.core.textures.ColorInfo;
import zombie.iso.*;
import zombie.iso.fboRenderChunk.FBORenderLevels;

public class ObserveTerrainTest {
    @AfterEach
    void cleanup() {
        AdminCoreObserveRender.clear();
    }

    @SuppressWarnings("unchecked")
    private void scope(int player, int chunkX, int chunkY) throws Exception {
        var field = AdminCoreObserveRender.class.getDeclaredField("RENDER");
        field.setAccessible(true);
        ((ThreadLocal<AdminCoreObserveRender.Region>) field.get(null))
                .set(new AdminCoreObserveRender.Region(player, chunkX, chunkY, 0));
    }

    private IsoChunk chunk(int x, int y) {
        var chunk = new IsoChunk((WorldReuserThread) null);
        chunk.wx = x;
        chunk.wy = y;
        chunk.loaded = true;
        java.util.Arrays.fill(chunk.lightingNeverDone, true);
        return chunk;
    }

    @SuppressWarnings("unchecked")
    private void light(AdminCoreObserveRender.SceneLight light) throws Exception {
        var field = AdminCoreObserveRender.class.getDeclaredField("SCENE_LIGHT");
        field.setAccessible(true);
        ((ThreadLocal<AdminCoreObserveRender.SceneLight>) field.get(null)).set(light);
    }

    @Test
    void nativeShadingIsPreservedAndUnlitRemoteFallbackUsesSceneAmbient() throws Exception {
        var square = new IsoGridSquare(null, null, 104, 204, 0);
        square.chunk = chunk(13, 25);
        var original = new ColorInfo(.1f, .2f, .3f, .75f);
        scope(0, 13, 25);
        light(new AdminCoreObserveRender.SceneLight(.25f, .4f, .5f));
        var fallback = AdminCoreObserveRender.color(square, 0, original);
        assertEquals(.25f, fallback.r);
        assertEquals(.4f, fallback.g);
        assertEquals(.5f, fallback.b);
        assertEquals(.75f, fallback.a);
        assertEquals(.5f, AdminCoreObserveRender.level(square, 0, 0f));
        assertEquals(0xFF7F663F, AdminCoreObserveRender.vertex(square, 0, 0, 0xFF000000));
        square.z = -1;
        assertEquals(0xFF6C5636, AdminCoreObserveRender.vertex(square, 0, 0, 0xFF000000));
        assertEquals(0xFF7F663F, AdminCoreObserveRender.vertex(square, 4, 0, 0xFF000000));
        square.z = 0;
        square.chunk.lightingNeverDone[0] = false;
        // Completed chunk lighting can still contain the physical avatar's unseen black tint.
        assertNotSame(original, AdminCoreObserveRender.color(square, 0, original));
        var nativeType =
                new ByteBuddy()
                        .redefine(LightingJNI.JNILighting.class)
                        .name("zombie.iso.AdminObserverNativeSceneProbe")
                        .implement(AdminCoreNativeLighting.class)
                        .intercept(net.bytebuddy.implementation.FieldAccessor.ofField("vis"))
                        .visit(
                                Advice.to(ObserveRenderTest.SkipNativeLightingUpdater.class)
                                        .on(
                                                ElementMatchers.named("update")
                                                        .and(ElementMatchers.takesArguments(0))))
                        .make()
                        .load(
                                getClass().getClassLoader(),
                                net.bytebuddy.dynamic.loading.ClassLoadingStrategy.Default.WRAPPER)
                        .getLoaded();
        var lighting =
                (IsoGridSquare.ILighting)
                        nativeType
                                .getConstructor(int.class, IsoGridSquare.class)
                                .newInstance(0, square);
        square.lighting[0] = lighting;
        var nativeVis = nativeType.getDeclaredField("vis");
        nativeVis.setAccessible(true);
        nativeVis.setByte(lighting, (byte) 1);
        assertNotSame(
                original,
                AdminCoreObserveRender.color(square, 0, original),
                "Remembered-only square must not reuse origin fog shading");
        nativeVis.setByte(lighting, (byte) 3);
        assertSame(original, AdminCoreObserveRender.color(square, 0, original));
        assertEquals(.3f, AdminCoreObserveRender.level(square, 0, .3f));
        assertEquals(0xFF19334C, AdminCoreObserveRender.vertex(square, 0, 0, 0xFF19334C));
        assertEquals(.1f, original.r);
        assertEquals(.2f, original.g);
        assertEquals(.3f, original.b);
        nativeVis.setByte(lighting, (byte) 1);
        light(new AdminCoreObserveRender.SceneLight(.1f, .15f, .2f));
        assertEquals(.1f, AdminCoreObserveRender.color(square, 0, original).r);
        assertEquals(.2f, AdminCoreObserveRender.level(square, 0, 0f));
        assertEquals((byte) 1, ((AdminCoreNativeLighting) lighting).uacObserverVisibilityFlags());
        AdminCoreObserveRender.end(true);
        assertSame(original, AdminCoreObserveRender.color(square, 0, original));
        assertEquals(0f, AdminCoreObserveRender.level(square, 0, 0f));
    }

    @Test
    void sceneFallbackComesFromActualNativeRenderSettingsAndDoesNotMutateThem() throws Exception {
        var settings = new zombie.core.opengl.RenderSettings.PlayerRenderSettings();
        String[] fields = {"ambient", "rmod", "gmod", "bmod"};
        float[] values = {.5f, .5f, .75f, 1f};
        for (int i = 0; i < fields.length; i++) {
            var field = settings.getClass().getDeclaredField(fields[i]);
            field.setAccessible(true);
            field.setFloat(settings, values[i]);
        }
        var scene = AdminCoreObserveRender.SceneLight.from(settings);
        assertEquals(new AdminCoreObserveRender.SceneLight(1f, 191f / 255f, 127f / 255f), scene);
        assertEquals(.5f, settings.getAmbient());
        assertEquals(.5f, settings.getRmod());
        assertEquals(.75f, settings.getGmod());
        assertEquals(1f, settings.getBmod());
        assertFalse(
                scene.differs(
                        new AdminCoreObserveRender.SceneLight(
                                1f, 191f / 255f + .001f, 127f / 255f + .001f)));
        assertTrue(scene.differs(new AdminCoreObserveRender.SceneLight(1f, .75f, .6f)));
    }

    @Test
    void pendingLightingViewIsBoundedAndPreservesNativeAndOtherPlayerFlags() throws Exception {
        var chunk = chunk(13, 25);
        boolean[] nativeFlags = {true, true, false, true};
        assertSame(nativeFlags, AdminCoreObserveRender.lightingPending(chunk, nativeFlags));
        scope(0, 13, 25);
        var view = AdminCoreObserveRender.lightingPending(chunk, nativeFlags);
        assertNotSame(nativeFlags, view);
        assertArrayEquals(new boolean[] {false, true, false, true}, view);
        assertArrayEquals(new boolean[] {true, true, false, true}, nativeFlags);
        nativeFlags[1] = false;
        assertSame(view, AdminCoreObserveRender.lightingPending(chunk, nativeFlags));
        assertFalse(view[1], "Copied native flags remain current");
        chunk.loaded = false;
        assertSame(nativeFlags, AdminCoreObserveRender.lightingPending(chunk, nativeFlags));
        chunk.loaded = true;
        chunk.wx = 17;
        assertSame(nativeFlags, AdminCoreObserveRender.lightingPending(chunk, nativeFlags));
        chunk.wx = Integer.MIN_VALUE;
        scope(0, Integer.MAX_VALUE, 25);
        assertSame(nativeFlags, AdminCoreObserveRender.lightingPending(chunk, nativeFlags));
        scope(4, 13, 25);
        assertSame(nativeFlags, AdminCoreObserveRender.lightingPending(chunk, nativeFlags));
        AdminCoreObserveRender.end(true);
        assertSame(nativeFlags, AdminCoreObserveRender.lightingPending(chunk, nativeFlags));
    }

    @Test
    void directNativeColorArrayViewDoesNotOverwriteSavedLighting() throws Exception {
        var square = new IsoGridSquare(null, null, 104, 204, 0);
        square.chunk = chunk(13, 25);
        var black = new ColorInfo(0f, 0f, 0f, .75f);
        var other = new ColorInfo(.3f, .4f, .5f, 1f);
        ColorInfo[] nativeColors = {black, other};
        assertSame(nativeColors, AdminCoreObserveRender.lightInfo(square, nativeColors));
        scope(0, 13, 25);
        var view = AdminCoreObserveRender.lightInfo(square, nativeColors);
        assertNotSame(nativeColors, view);
        assertEquals(1f, view[0].r);
        assertEquals(.75f, view[0].a);
        assertSame(other, view[1]);
        assertSame(black, nativeColors[0]);
        assertEquals(0f, black.r);
        assertSame(view, AdminCoreObserveRender.lightInfo(square, nativeColors));
        square.z = 1;
        assertSame(nativeColors, AdminCoreObserveRender.lightInfo(square, nativeColors));
        square.z = 0;
        AdminCoreObserveRender.end(true);
        assertSame(nativeColors, AdminCoreObserveRender.lightInfo(square, nativeColors));
    }

    private byte[] weave(String name) throws Exception {
        var locator = ClassFileLocator.ForClassLoader.ofSystemLoader();
        var pool = TypePool.Default.of(locator);
        var builder = new ByteBuddy().redefine(pool.describe(name).resolve(), locator);
        return new AdminCoreObserveTerrainPatch(name)
                .dynamicType(locator, pool, builder)
                .make()
                .getBytes();
    }

    @Test
    void nativeB42RenderGatesHaveExactReadOnlyWrapperCountsAndMarkers() throws Exception {
        Map<String, Integer> expected =
                Map.of(
                        "zombie.iso.fboRenderChunk.FBORenderCell", 5,
                        "zombie.iso.IsoCell", 1,
                        "zombie.iso.IsoWater", 2,
                        "zombie.iso.IsoGridSquare", 6);
        for (var entry : expected.entrySet()) {
            Map<String, Integer> counts = new HashMap<>();
            boolean[] marker = {false};
            new ClassReader(weave(entry.getKey()))
                    .accept(
                            new ClassVisitor(Opcodes.ASM9) {
                                @Override
                                public FieldVisitor visitField(
                                        int access,
                                        String name,
                                        String descriptor,
                                        String signature,
                                        Object value) {
                                    if (name.equals(AdminCoreObserveTerrainPatch.MARKER)) {
                                        marker[0] =
                                                descriptor.equals("Z")
                                                        && Integer.valueOf(1).equals(value)
                                                        && (access & Opcodes.ACC_STATIC) != 0;
                                    }
                                    return null;
                                }

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
                                                String called,
                                                String desc,
                                                boolean itf) {
                                            if (owner.endsWith("/AdminCoreObserveRender")
                                                    && (called.equals("lightingPending")
                                                            || called.equals("lightInfo"))) {
                                                assertEquals(Opcodes.INVOKESTATIC, opcode);
                                                assertTrue(
                                                        name.startsWith("render")
                                                                || name.equals("invalidateAll")
                                                                || name.equals(
                                                                        "checkNewlyOnScreenChunks")
                                                                || name.equals("performRenderTiles")
                                                                || name.equals("DoCutawayShader")
                                                                || name.equals("performDrawWall"));
                                                counts.merge(name, 1, Integer::sum);
                                            }
                                        }
                                    };
                                }
                            },
                            0);
            assertTrue(marker[0], entry.getKey());
            assertEquals(
                    entry.getValue(),
                    counts.values().stream().mapToInt(Integer::intValue).sum(),
                    entry.getKey());
            assertTrue(counts.values().stream().allMatch(value -> value == 1), entry.getKey());
        }
    }

    public static final class GateReached extends RuntimeException {}

    public static boolean onScreen(IsoChunk chunk, boolean frustum) {
        return true;
    }

    public static FBORenderLevels afterLightingGate(IsoChunk chunk, int player) {
        throw new GateReached();
    }

    public static class AlwaysDarkenRooms {
        @Advice.OnMethodEnter(skipOn = Advice.OnNonDefaultValue.class)
        public static boolean enter() {
            return true;
        }

        @Advice.OnMethodExit
        public static void exit(@Advice.Return(readOnly = false) boolean value) {
            value = true;
        }
    }

    @Test
    void actualNativeFboMethodPassesPendingGateOnlyForLoadedScopedObserverChunk() throws Exception {
        // Keep the actual native gate and branches. Isolate screen geometry, then stop at the
        // first post-gate operation so the test never needs a GPU/native render context.
        String name = "zombie.iso.fboRenderChunk.AdminObserverNativeTerrainProbe";
        var locator = ClassFileLocator.ForClassLoader.ofSystemLoader();
        var pool = TypePool.Default.of(locator);
        var builder =
                new ByteBuddy()
                        .redefine(
                                pool.describe(AdminCoreObserveTerrainPatch.TARGETS.get(0))
                                        .resolve(),
                                locator)
                        .name(name);
        builder =
                new AdminCoreObserveTerrainPatch(AdminCoreObserveTerrainPatch.TARGETS.get(0))
                        .dynamicType(locator, pool, builder);
        byte[] bytes =
                new AdminCoreObserveBlackoutPatch()
                        .dynamicType(locator, pool, builder)
                        .visit(
                                Advice.to(AlwaysDarkenRooms.class)
                                        .on(ElementMatchers.named("shouldDarkenIndividualRooms")))
                        .make()
                        .getBytes();
        var writer = new ClassWriter(0);
        new ClassReader(bytes)
                .accept(
                        new ClassVisitor(Opcodes.ASM9, writer) {
                            @Override
                            public MethodVisitor visitMethod(
                                    int access,
                                    String method,
                                    String descriptor,
                                    String signature,
                                    String[] exceptions) {
                                if (method.equals("<clinit>")) return null;
                                var delegate =
                                        super.visitMethod(
                                                access, method, descriptor, signature, exceptions);
                                if (!method.equals("renderOneChunk")) return delegate;
                                return new MethodVisitor(Opcodes.ASM9, delegate) {
                                    @Override
                                    public void visitMethodInsn(
                                            int opcode,
                                            String owner,
                                            String called,
                                            String desc,
                                            boolean itf) {
                                        if (owner.equals("zombie/iso/IsoChunk")
                                                && called.equals("IsOnScreen")) {
                                            super.visitMethodInsn(
                                                    Opcodes.INVOKESTATIC,
                                                    "com/sentientsimulations/projectzomboid/admincore/ObserveTerrainTest",
                                                    "onScreen",
                                                    "(Lzombie/iso/IsoChunk;Z)Z",
                                                    false);
                                        } else if (owner.equals("zombie/iso/IsoChunk")
                                                && called.equals("getRenderLevels")) {
                                            super.visitMethodInsn(
                                                    Opcodes.INVOKESTATIC,
                                                    "com/sentientsimulations/projectzomboid/admincore/ObserveTerrainTest",
                                                    "afterLightingGate",
                                                    "(Lzombie/iso/IsoChunk;I)Lzombie/iso/fboRenderChunk/FBORenderLevels;",
                                                    false);
                                        } else
                                            super.visitMethodInsn(opcode, owner, called, desc, itf);
                                    }
                                };
                            }
                        },
                        0);
        var loader =
                new ByteArrayClassLoader(
                        getClass().getClassLoader(), Map.of(name, writer.toByteArray()));
        var type = Class.forName(name, true, loader);
        var unsafeField = sun.misc.Unsafe.class.getDeclaredField("theUnsafe");
        unsafeField.setAccessible(true);
        Object probe = ((sun.misc.Unsafe) unsafeField.get(null)).allocateInstance(type);
        var method =
                type.getDeclaredMethod(
                        "renderOneChunk",
                        IsoChunk.class,
                        IsoCell.PerPlayerRender.class,
                        int.class,
                        long.class,
                        Shader.class,
                        Shader.class);
        method.setAccessible(true);
        var chunk = chunk(13, 25);
        chunk.lightingNeverDone[0] = true;
        chunk.lightingNeverDone[1] = true;
        assertDoesNotThrow(() -> method.invoke(probe, chunk, null, 0, 0L, null, null));
        scope(0, 13, 25);
        var reached =
                assertThrows(
                        InvocationTargetException.class,
                        () -> method.invoke(probe, chunk, null, 0, 0L, null, null));
        assertInstanceOf(GateReached.class, reached.getCause());
        assertDoesNotThrow(() -> method.invoke(probe, chunk, null, 1, 0L, null, null));
        chunk.loaded = false;
        assertDoesNotThrow(() -> method.invoke(probe, chunk, null, 0, 0L, null, null));
        chunk.loaded = true;
        chunk.wx = 17;
        assertDoesNotThrow(() -> method.invoke(probe, chunk, null, 0, 0L, null, null));
        AdminCoreObserveRender.end(true);
        chunk.wx = 13;
        assertDoesNotThrow(() -> method.invoke(probe, chunk, null, 0, 0L, null, null));
        assertTrue(chunk.lightingNeverDone[0], "Native pending flag survives remote rendering");
        assertTrue(chunk.lightingNeverDone[1]);
        // Execute the independent native room fade path: default unlit room blackness remains
        // outside observation, while authorized remote squares render without that blackout.
        var fade = type.getDeclaredMethod("getBlackedOutRoomFadeRatio", IsoGridSquare.class);
        var square = new IsoGridSquare(null, null, 104, 204, 0);
        square.chunk = chunk;
        int previousPlayer = IsoCamera.frameState.playerIndex;
        try {
            IsoCamera.frameState.playerIndex = 0;
            assertEquals(0f, fade.invoke(probe, square));
            scope(0, 13, 25);
            assertEquals(1f, fade.invoke(probe, square));
            IsoCamera.frameState.playerIndex = 1;
            assertEquals(0f, fade.invoke(probe, square));
            IsoCamera.frameState.playerIndex = 0;
            square.x += 32;
            assertEquals(0f, fade.invoke(probe, square));
            square.x -= 32;
            AdminCoreObserveRender.end(true);
            assertEquals(0f, fade.invoke(probe, square));
        } finally {
            IsoCamera.frameState.playerIndex = previousPlayer;
        }
    }
}
