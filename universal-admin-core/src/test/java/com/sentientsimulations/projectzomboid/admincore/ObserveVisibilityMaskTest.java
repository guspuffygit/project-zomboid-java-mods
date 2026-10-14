package com.sentientsimulations.projectzomboid.admincore;

import static com.sentientsimulations.projectzomboid.admincore.ObserveProjectionTest.allocate;
import static com.sentientsimulations.projectzomboid.admincore.ObserveProjectionTest.state;
import static org.junit.jupiter.api.Assertions.*;

import java.util.HashMap;
import java.util.Map;
import net.bytebuddy.ByteBuddy;
import net.bytebuddy.dynamic.ClassFileLocator;
import net.bytebuddy.jar.asm.*;
import net.bytebuddy.pool.TypePool;
import org.junit.jupiter.api.Test;
import zombie.characters.Capability;
import zombie.characters.IsoPlayer;
import zombie.characters.Role;
import zombie.core.Core;
import zombie.debug.DebugOptions;
import zombie.iso.IsoCamera;
import zombie.network.GameClient;

class ObserveVisibilityMaskTest {
    private static final String NATIVE = "zombie.vispoly.VisibilityPolygon2";
    private static final String OWNER = "zombie/vispoly/VisibilityPolygon2";

    private byte[] weave() throws Exception {
        var locator = ClassFileLocator.ForClassLoader.ofSystemLoader();
        var pool = TypePool.Default.of(locator);
        return new AdminCoreObserveVisibilityPatch()
                .dynamicType(
                        locator,
                        pool,
                        new ByteBuddy().redefine(pool.describe(NATIVE).resolve(), locator))
                .make()
                .getBytes();
    }

    @Test
    void weavesOneGuardOnlyIntoInstalledNativeScreenMaskEntry() throws Exception {
        byte[] bytes = weave();
        Map<String, Integer> guards = new HashMap<>();
        new ClassReader(bytes)
                .accept(
                        new ClassVisitor(Opcodes.ASM9) {
                            @Override
                            public MethodVisitor visitMethod(
                                    int access,
                                    String name,
                                    String desc,
                                    String sig,
                                    String[] errors) {
                                return new MethodVisitor(Opcodes.ASM9) {
                                    @Override
                                    public void visitMethodInsn(
                                            int opcode,
                                            String owner,
                                            String method,
                                            String descriptor,
                                            boolean isInterface) {
                                        if (owner.endsWith("/AdminCoreObserveRender")
                                                && method.equals("suppressVisibilityMask"))
                                            guards.merge(name + desc, 1, Integer::sum);
                                    }
                                };
                            }
                        },
                        0);
        assertEquals(Map.of("renderMain(I)V", 1), guards);
        Class<?> type = new NativeLoader().define(bytes);
        assertTrue(type.getField(AdminCoreObserveVisibilityPatch.MARKER).getBoolean(null));
        assertDoesNotThrow(type::getDeclaredMethods);
    }

    @Test
    void nativeMaskIsSkippedOnlyDuringAuthorizedObserverRenderAndReturnsAfterRevocation()
            throws Exception {
        zombie.core.random.RandStandard.INSTANCE.init();
        var previousInstance = IsoPlayer.getInstance();
        var previousSlot = IsoPlayer.players[0];
        var previousCamera = IsoCamera.getCameraCharacter();
        boolean previousClient = GameClient.client;
        boolean previousDebug = Core.debug;
        var option = DebugOptions.instance.fboRenderChunk.renderVisionPolygon;
        // This native debug-only option returns its default unless debug mode is enabled.
        Core.debug = true;
        boolean previousOption = option.getValue();
        ThreadLocal<AdminCoreObserveRender.Region> scope = scope();
        var previousRegion = scope.get();
        var viewer = allocate(ObservePlayerVisibilityTest.NativeVisibilityProbe.class);
        viewer.playerIndex = 0;
        viewer.role = new Role("observer");
        for (var capability :
                new Capability[] {
                    Capability.TeleportToPlayer, Capability.SeePlayersConnected,
                    Capability.UseDebugContextMenu, Capability.ToggleInvisibleHimself
                }) viewer.role.addCapability(capability);
        IsoPlayer.players[0] = viewer;
        IsoPlayer.setInstance(viewer);
        GameClient.client = true;
        // The real native body returns at its first debug gate, before accessing GL or drawers.
        // Count entry immediately after observer advice, not in a replacement implementation.
        option.setValue(false);
        try {
            AdminCoreObserveCamera.stop();
            state("retryAfter", 0L);
            Class<?> type = new NativeLoader().define(withNativeEntryCounter(weave()));
            Object mask = allocate(type);
            var render = type.getMethod("renderMain", int.class);
            var count = type.getField("nativeEntries");

            render.invoke(mask, 0);
            assertEquals(1, count.getInt(null), "Inactive native screen-mask path remains intact");
            assertTrue(AdminCoreObserveCamera.grant("remote", true));
            render.invoke(mask, 0);
            assertEquals(
                    2, count.getInt(null), "A grant alone cannot suppress rendering outside scope");
            scope.set(new AdminCoreObserveRender.Region(0, 125, 250, 0, 7));
            render.invoke(mask, 0);
            assertEquals(
                    2,
                    count.getInt(null),
                    "Authorized observer skips the actual native screen mask");
            render.invoke(mask, 1);
            assertEquals(3, count.getInt(null), "Another local player's native view is untouched");

            viewer.role.removeCapability(Capability.UseDebugContextMenu);
            render.invoke(mask, 0);
            assertEquals(
                    4,
                    count.getInt(null),
                    "Render permission is checked again inside the render scope");
            viewer.role.addCapability(Capability.UseDebugContextMenu);
            render.invoke(mask, 0);
            assertEquals(4, count.getInt(null));
            assertTrue(AdminCoreObserveCamera.grant("remote", false));
            render.invoke(mask, 0);
            assertEquals(5, count.getInt(null), "Server-denied render grant keeps native masking");

            assertTrue(AdminCoreObserveCamera.grant("remote", true));
            state("expires", 0L);
            render.invoke(mask, 0);
            assertEquals(6, count.getInt(null), "Expiry restores native masking in the same frame");
            assertFalse(AdminCoreObserveCamera.active());
            assertFalse(viewer.isBlockMovement(), "Expiry restores the physical player's movement");
            assertNull(
                    scope.get(),
                    "Expired authorization clears the temporary observer render scope");
            assertFalse(option.getValue(), "Observer never toggles global vision debug options");
        } finally {
            AdminCoreObserveCamera.stop();
            state("retryAfter", 0L);
            option.setValue(previousOption);
            Core.debug = previousDebug;
            IsoPlayer.players[0] = previousSlot;
            IsoPlayer.setInstance(previousInstance);
            IsoCamera.setCameraCharacter(previousCamera);
            GameClient.client = previousClient;
            if (previousRegion == null) scope.remove();
            else scope.set(previousRegion);
        }
    }

    private static byte[] withNativeEntryCounter(byte[] bytes) {
        ClassWriter writer = new ClassWriter(ClassWriter.COMPUTE_MAXS);
        int[] entries = {0};
        new ClassReader(bytes)
                .accept(
                        new ClassVisitor(Opcodes.ASM9, writer) {
                            @Override
                            public MethodVisitor visitMethod(
                                    int access,
                                    String name,
                                    String descriptor,
                                    String signature,
                                    String[] exceptions) {
                                MethodVisitor delegate =
                                        super.visitMethod(
                                                access, name, descriptor, signature, exceptions);
                                if (!name.equals("renderMain") || !descriptor.equals("(I)V"))
                                    return delegate;
                                return new MethodVisitor(Opcodes.ASM9, delegate) {
                                    private boolean counted;

                                    @Override
                                    public void visitFieldInsn(
                                            int opcode, String owner, String field, String desc) {
                                        if (!counted
                                                && opcode == Opcodes.GETSTATIC
                                                && owner.equals("zombie/debug/DebugOptions")
                                                && field.equals("instance")) {
                                            counted = true;
                                            entries[0]++;
                                            super.visitFieldInsn(
                                                    Opcodes.GETSTATIC, OWNER, "nativeEntries", "I");
                                            super.visitInsn(Opcodes.ICONST_1);
                                            super.visitInsn(Opcodes.IADD);
                                            super.visitFieldInsn(
                                                    Opcodes.PUTSTATIC, OWNER, "nativeEntries", "I");
                                        }
                                        super.visitFieldInsn(opcode, owner, field, desc);
                                    }
                                };
                            }

                            @Override
                            public void visitEnd() {
                                super.visitField(
                                                Opcodes.ACC_PUBLIC | Opcodes.ACC_STATIC,
                                                "nativeEntries",
                                                "I",
                                                null,
                                                null)
                                        .visitEnd();
                                super.visitEnd();
                            }
                        },
                        0);
        assertEquals(
                1, entries[0], "The counter must sit at the actual installed native body entry");
        return writer.toByteArray();
    }

    @SuppressWarnings("unchecked")
    private static ThreadLocal<AdminCoreObserveRender.Region> scope() throws Exception {
        var field = AdminCoreObserveRender.class.getDeclaredField("RENDER");
        field.setAccessible(true);
        return (ThreadLocal<AdminCoreObserveRender.Region>) field.get(null);
    }

    private static final class NativeLoader extends ClassLoader {
        NativeLoader() {
            super(ObserveVisibilityMaskTest.class.getClassLoader());
        }

        Class<?> define(byte[] bytes) {
            return defineClass(NATIVE, bytes, 0, bytes.length);
        }
    }
}
