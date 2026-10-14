package com.sentientsimulations.projectzomboid.admincore;

import static org.junit.jupiter.api.Assertions.*;

import java.util.HashMap;
import java.util.Map;
import net.bytebuddy.ByteBuddy;
import net.bytebuddy.asm.Advice;
import net.bytebuddy.dynamic.ClassFileLocator;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy;
import net.bytebuddy.implementation.SuperMethodCall;
import net.bytebuddy.jar.asm.*;
import net.bytebuddy.matcher.ElementMatchers;
import net.bytebuddy.pool.TypePool;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import zombie.characters.Capability;
import zombie.characters.IsoPlayer;
import zombie.characters.Role;
import zombie.iso.*;
import zombie.network.GameClient;
import zombie.vehicles.BaseVehicle;

class ObservePlayerVisibilityTest {
    private IsoPlayer previousInstance, previousSlot;
    private boolean previousClient;
    private NativeVisibilityProbe viewer, remote;

    @BeforeEach
    void setup() throws Exception {
        zombie.core.random.RandStandard.INSTANCE.init();
        previousInstance = IsoPlayer.getInstance();
        previousSlot = IsoPlayer.players[0];
        previousClient = GameClient.client;
        setCameraField("retryAfter", 0L);
        var type =
                new ByteBuddy()
                        .subclass(NativeVisibilityProbe.class)
                        .method(
                                ElementMatchers.named("checkCanSeeClient")
                                        .and(ElementMatchers.takesArguments(IsoPlayer.class)))
                        .intercept(
                                Advice.to(AdminCoreObservePlayerAdvice.class)
                                        .wrap(SuperMethodCall.INSTANCE))
                        .make()
                        .load(getClass().getClassLoader(), ClassLoadingStrategy.Default.WRAPPER)
                        .getLoaded();
        viewer = allocate(type);
        viewer.role = observerRole();
        viewer.local = true;
        viewer.direction = new Vector2(1f, 1f);
        viewer.playerIndex = 0;
        viewer.square(new IsoGridSquare(null, null, 0, 0, 0));
        remote = allocate(NativeVisibilityProbe.class);
        remote.role = new Role("user");
        remote.direction = new Vector2(1f, 1f);
        var square = new IsoGridSquare(null, null, 104, 204, 0);
        square.chunk = new IsoChunk((WorldReuserThread) null);
        remote.square(square);
        IsoPlayer.players[0] = viewer;
        IsoPlayer.setInstance(viewer);
        GameClient.client = true;
    }

    @AfterEach
    void cleanup() throws Exception {
        AdminCoreObserveCamera.stop();
        setCameraField("retryAfter", 0L);
        IsoPlayer.players[0] = previousSlot;
        IsoPlayer.setInstance(previousInstance);
        GameClient.client = previousClient;
    }

    private static Role observerRole() {
        var role = new Role("observer");
        role.addCapability(Capability.TeleportToPlayer);
        role.addCapability(Capability.SeePlayersConnected);
        role.addCapability(Capability.UseDebugContextMenu);
        role.addCapability(Capability.ToggleInvisibleHimself);
        return role;
    }

    private static <T> T allocate(Class<T> type) throws Exception {
        var field = sun.misc.Unsafe.class.getDeclaredField("theUnsafe");
        field.setAccessible(true);
        return type.cast(((sun.misc.Unsafe) field.get(null)).allocateInstance(type));
    }

    private static void setCameraField(String name, Object value) throws Exception {
        var field = AdminCoreObserveCamera.class.getDeclaredField(name);
        field.setAccessible(true);
        field.set(null, value);
    }

    @SuppressWarnings("unchecked")
    private static void renderScope() throws Exception {
        var field = AdminCoreObserveRender.class.getDeclaredField("RENDER");
        field.setAccessible(true);
        ((ThreadLocal<AdminCoreObserveRender.Region>) field.get(null))
                .set(new AdminCoreObserveRender.Region(0, 13, 25, 0));
    }

    private void grant() throws Exception {
        assertTrue(AdminCoreObserveCamera.grant("remote", true));
        renderScope();
    }

    @Test
    void actualNativePlayerOverloadWeavesAndServerConnectionOverloadStaysUntouched()
            throws Exception {
        String name = "zombie.characters.IsoPlayer";
        var locator = ClassFileLocator.ForClassLoader.ofSystemLoader();
        var pool = TypePool.Default.of(locator);
        byte[] bytes =
                new AdminCoreObservePlayerPatch()
                        .dynamicType(
                                locator,
                                pool,
                                new ByteBuddy().redefine(pool.describe(name).resolve(), locator))
                        .make()
                        .getBytes();
        Map<String, Integer> calls = new HashMap<>();
        new ClassReader(bytes)
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
                                            String called,
                                            String desc,
                                            boolean isInterface) {
                                        if (owner.endsWith("/AdminCoreObserveCamera")
                                                && called.equals("showsPlayer"))
                                            calls.merge(name + descriptor, 1, Integer::sum);
                                    }
                                };
                            }
                        },
                        0);
        assertEquals(Map.of("checkCanSeeClient(Lzombie/characters/IsoPlayer;)Z", 1), calls);
        // A duplicate full IsoPlayer cannot access its parent's package-protected native fields.
        // Retain the exact woven visibility bodies and fields; omit unrelated native methods
        // before isolated JVM verification. The probe tests execute native fallback in its real
        // loader, where all game classes keep their original runtime package.
        var visibilityOnly = new ClassWriter(0);
        new ClassReader(bytes)
                .accept(
                        new ClassVisitor(Opcodes.ASM9, visibilityOnly) {
                            @Override
                            public MethodVisitor visitMethod(
                                    int access,
                                    String method,
                                    String descriptor,
                                    String signature,
                                    String[] exceptions) {
                                return method.equals("checkCanSeeClient")
                                        ? super.visitMethod(
                                                access, method, descriptor, signature, exceptions)
                                        : null;
                            }
                        },
                        0);
        Class<?> verified = new NativeVerifier().define(name, visibilityOnly.toByteArray());
        assertDoesNotThrow(verified::getDeclaredMethods);
    }

    @Test
    void executesInstalledNativeVisibilityWhenInactiveAndOnlyOverridesDuringScopedRender()
            throws Exception {
        assertFalse(viewer.checkCanSeeClient(remote), "Actual native LOS hides the distant player");
        grant();
        assertTrue(viewer.checkCanSeeClient(remote));
        assertFalse(remote.spottedByPlayer, "Render override does not write native spotted state");
        assertEquals(0, viewer.getCurrentSquare().x, "Observer body remains at its origin");
        assertFalse(remote.getCurrentSquare().lighting[0].bSeen());
        AdminCoreObserveRender.end(true);
        assertFalse(
                viewer.checkCanSeeClient(remote), "Outside render the native method runs again");
        GameClient.client = false;
        assertTrue(viewer.checkCanSeeClient(remote), "Original non-client behavior stays intact");
    }

    @Test
    void unloadedOutsideScopeAndOtherLocalViewersRetainNativeVisibility() throws Exception {
        grant();
        remote.getCurrentSquare().chunk = null;
        assertFalse(viewer.checkCanSeeClient(remote));
        var outside = new IsoGridSquare(null, null, 1000, 2000, 0);
        outside.chunk = new IsoChunk((WorldReuserThread) null);
        remote.square(outside);
        assertFalse(viewer.checkCanSeeClient(remote));
        var upper = new IsoGridSquare(null, null, 104, 204, 1);
        upper.chunk = new IsoChunk((WorldReuserThread) null);
        remote.square(upper);
        assertFalse(viewer.checkCanSeeClient(remote));
        var secondViewer = allocate(NativeVisibilityProbe.class);
        secondViewer.playerIndex = 1;
        secondViewer.role = observerRole();
        secondViewer.local = true;
        assertFalse(AdminCoreObserveCamera.showsPlayer(secondViewer, remote));
        viewer.local = false;
        assertFalse(AdminCoreObserveCamera.showsPlayer(viewer, remote));
    }

    @Test
    void invisiblePermissionExpiredGrantAndRoleRevocationCannotGainObserverVisibility()
            throws Exception {
        grant();
        remote.invisible = true;
        assertFalse(viewer.checkCanSeeClient(remote));
        viewer.role.addCapability(Capability.SeesInvisiblePlayers);
        assertTrue(viewer.checkCanSeeClient(remote));
        remote.invisible = false;
        setCameraField("renderGranted", false);
        assertFalse(viewer.checkCanSeeClient(remote));
        setCameraField("renderGranted", true);
        viewer.role = new Role("user");
        assertFalse(viewer.checkCanSeeClient(remote));
        assertFalse(AdminCoreObserveCamera.active());
        viewer.role = observerRole();
        grant();
        setCameraField("expires", 1L);
        assertFalse(viewer.checkCanSeeClient(remote));
        assertFalse(AdminCoreObserveCamera.active());
    }

    private static final class NativeVerifier extends ClassLoader {
        NativeVerifier() {
            super(ObservePlayerVisibilityTest.class.getClassLoader());
        }

        Class<?> define(String name, byte[] bytes) {
            return defineClass(name, bytes, 0, bytes.length);
        }
    }

    public static class NativeVisibilityProbe extends IsoPlayer {
        Role role;
        Vector2 direction;
        boolean local, invisible, blocked;

        NativeVisibilityProbe() {
            super((IsoCell) null);
        }

        void square(IsoGridSquare value) {
            current = value;
        }

        @Override
        public boolean checkCanSeeClient(IsoPlayer remote) {
            // Execute the installed game's method, rather than a fixture implementation.
            return super.checkCanSeeClient(remote);
        }

        @Override
        public Role getRole() {
            return role;
        }

        @Override
        public Vector2 getForwardDirection() {
            return direction;
        }

        @Override
        public BaseVehicle getVehicle() {
            return null;
        }

        @Override
        public boolean isDead() {
            return false;
        }

        @Override
        public boolean isLocalPlayer() {
            return local;
        }

        @Override
        public boolean isAccessLevel(String level) {
            return "None".equals(level);
        }

        @Override
        public boolean canSeeAll() {
            return false;
        }

        @Override
        public boolean isInvisible() {
            return invisible;
        }

        @Override
        public boolean isBlockMovement() {
            return blocked;
        }

        @Override
        public void setBlockMovement(boolean value) {
            blocked = value;
        }
    }
}
