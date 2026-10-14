package com.sentientsimulations.projectzomboid.admincore;

import static org.junit.jupiter.api.Assertions.*;

import io.pzstorm.storm.core.StormClassTransformer;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import net.bytebuddy.ByteBuddy;
import net.bytebuddy.asm.MemberSubstitution;
import net.bytebuddy.description.modifier.Ownership;
import net.bytebuddy.description.modifier.Visibility;
import net.bytebuddy.dynamic.ClassFileLocator;
import net.bytebuddy.implementation.FixedValue;
import net.bytebuddy.implementation.MethodCall;
import net.bytebuddy.jar.asm.ClassReader;
import net.bytebuddy.jar.asm.ClassVisitor;
import net.bytebuddy.jar.asm.MethodVisitor;
import net.bytebuddy.jar.asm.Opcodes;
import net.bytebuddy.matcher.ElementMatchers;
import net.bytebuddy.pool.TypePool;
import org.junit.jupiter.api.Test;
import zombie.characters.IsoPlayer;
import zombie.savefile.ServerPlayerDB;

/** Native B42.21 bytecode with the anti-cheat's exact load substitution, without its dependency. */
class RespawnCompositionTest {
    private static final String SERVER = "zombie.network.GameServer";
    private static final String PROBE =
            "com.sentientsimulations.projectzomboid.securitypatches.patch.PienZInvisibilityProbePatch";
    private static final ClassFileLocator SYSTEM = ClassFileLocator.ForClassLoader.ofSystemLoader();

    @Test
    void everyStormRespawnAndProbeOrderRetainsBothLoadGuardsAndPassesJvmVerification()
            throws Exception {
        byte[] probe = forwardingProbe(PROBE);
        var storm =
                (StormClassTransformer)
                        Class.forName(
                                        "io.pzstorm.storm.patch.networking.GameServerPlayerConnectionEventsPatch")
                                .getDeclaredConstructor()
                                .newInstance();
        for (var order :
                List.of(
                        List.of("storm", "respawn", "probe"),
                        List.of("storm", "probe", "respawn"),
                        List.of("respawn", "storm", "probe"),
                        List.of("respawn", "probe", "storm"),
                        List.of("probe", "storm", "respawn"),
                        List.of("probe", "respawn", "storm"))) {
            byte[] bytes = SYSTEM.locate(SERVER).resolve();
            for (String step : order) {
                bytes =
                        step.equals("probe")
                                ? substitute(bytes, PROBE, probe)
                                : transform(
                                        bytes,
                                        probe,
                                        step.equals("storm")
                                                ? storm
                                                : new AdminCoreRespawnPatch(SERVER));
            }
            Map<String, Integer> calls = connectCalls(bytes);
            String context = order.toString();
            assertEquals(2, calls.get("captureLoad"), context);
            assertEquals(2, calls.get("acceptLoaded"), context);
            assertEquals(2, calls.get("clearConnect"), context);
            assertEquals(2, calls.get("loadAndProbe"), context);
            assertFalse(calls.containsKey("serverLoadNetworkCharacter"), context);
            assertTrue(calls.containsKey("enterConnect"), context);
            assertTrue(calls.containsKey("exitConnect"), context);
            assertTrue(calls.containsKey("snapshotPlayers"), context);
            assertTrue(calls.containsKey("afterPlayerConnect"), context);
            var verifier = new NativeVerifier();
            verifier.define(PROBE, probe);
            Class<?> verified = verifier.define(SERVER, bytes);
            assertDoesNotThrow(verified::getDeclaredMethods, context);
        }
    }

    @Test
    void anUnrecognizedLoadWrapperStillRejectsTheNativeLayout() throws Exception {
        String unknown = PROBE + "Unknown";
        byte[] probe = forwardingProbe(unknown);
        byte[] wrapped = substitute(SYSTEM.locate(SERVER).resolve(), unknown, probe);
        var failure =
                assertThrows(
                        IllegalStateException.class,
                        () -> transform(wrapped, probe, new AdminCoreRespawnPatch(SERVER)));
        assertTrue(failure.getMessage().contains("Unsupported native respawn method layout"));
    }

    @Test
    void aChangedProbeSignatureStillRejectsTheNativeLayout() throws Exception {
        byte[] probe =
                new ByteBuddy()
                        .subclass(Object.class)
                        .name(PROBE)
                        .defineMethod(
                                "loadAndProbe",
                                IsoPlayer.class,
                                Visibility.PUBLIC,
                                Ownership.STATIC)
                        .withParameters(Object.class, int.class, String.class)
                        .intercept(FixedValue.nullValue())
                        .make()
                        .getBytes();
        byte[] wrapped = substitute(SYSTEM.locate(SERVER).resolve(), PROBE, probe);
        var failure =
                assertThrows(
                        IllegalStateException.class,
                        () -> transform(wrapped, probe, new AdminCoreRespawnPatch(SERVER)));
        assertTrue(failure.getMessage().contains("Unsupported native respawn method layout"));
    }

    private static byte[] forwardingProbe(String name) throws Exception {
        // Same receiver/int/String signature and native call as loadAndProbe. The real anti-cheat
        // adds its detection after this call. No anti-cheat code is copied or shipped with UAC.
        return new ByteBuddy()
                .subclass(Object.class)
                .name(name)
                .defineMethod("loadAndProbe", IsoPlayer.class, Visibility.PUBLIC, Ownership.STATIC)
                .withParameters(ServerPlayerDB.class, int.class, String.class)
                .intercept(
                        MethodCall.invoke(
                                        ServerPlayerDB.class.getMethod(
                                                "serverLoadNetworkCharacter",
                                                int.class,
                                                String.class))
                                .onArgument(0)
                                .withArgument(1, 2))
                .make()
                .getBytes();
    }

    private static ClassFileLocator locator(byte[] server, String probeName, byte[] probe) {
        return new ClassFileLocator.Compound(
                new ClassFileLocator.Simple(Map.of(SERVER, server, probeName, probe)), SYSTEM);
    }

    private static byte[] substitute(byte[] server, String probeName, byte[] probe) {
        var locator = locator(server, probeName, probe);
        var pool = TypePool.Default.of(locator);
        var load =
                pool.describe(probeName)
                        .resolve()
                        .getDeclaredMethods()
                        .filter(ElementMatchers.named("loadAndProbe"))
                        .getOnly();
        return new ByteBuddy()
                .redefine(pool.describe(SERVER).resolve(), locator)
                .visit(
                        MemberSubstitution.relaxed()
                                .method(
                                        ElementMatchers.named("serverLoadNetworkCharacter")
                                                .and(
                                                        ElementMatchers.isDeclaredBy(
                                                                ElementMatchers.named(
                                                                        "zombie.savefile.ServerPlayerDB"))))
                                .replaceWith(load)
                                .on(ElementMatchers.named("receivePlayerConnect")))
                .make()
                .getBytes();
    }

    private static byte[] transform(byte[] server, byte[] probe, StormClassTransformer patch) {
        var locator =
                locator(server, new ClassReader(probe).getClassName().replace('/', '.'), probe);
        var pool = TypePool.Default.of(locator);
        return patch.dynamicType(
                        locator,
                        pool,
                        new ByteBuddy().redefine(pool.describe(SERVER).resolve(), locator))
                .make()
                .getBytes();
    }

    private static Map<String, Integer> connectCalls(byte[] bytes) {
        Map<String, Integer> result = new HashMap<>();
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
                                if (!name.equals("receivePlayerConnect")) return null;
                                return new MethodVisitor(Opcodes.ASM9) {
                                    @Override
                                    public void visitMethodInsn(
                                            int opcode,
                                            String owner,
                                            String name,
                                            String descriptor,
                                            boolean itf) {
                                        if (owner.contains("AdminCoreRespawn")
                                                || owner.endsWith("PlayerConnectionEvents")
                                                || owner.equals(PROBE.replace('.', '/'))
                                                || owner.equals("zombie/savefile/ServerPlayerDB"))
                                            result.merge(name, 1, Integer::sum);
                                    }
                                };
                            }
                        },
                        0);
        return result;
    }

    private static final class NativeVerifier extends ClassLoader {
        NativeVerifier() {
            super(RespawnCompositionTest.class.getClassLoader());
        }

        Class<?> define(String name, byte[] bytes) {
            return defineClass(name, bytes, 0, bytes.length);
        }
    }
}
