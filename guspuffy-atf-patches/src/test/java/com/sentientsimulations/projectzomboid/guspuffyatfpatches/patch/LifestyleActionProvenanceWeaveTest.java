package com.sentientsimulations.projectzomboid.guspuffyatfpatches.patch;

import static org.junit.jupiter.api.Assertions.*;

import io.pzstorm.storm.core.StormClassTransformer;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import net.bytebuddy.ByteBuddy;
import net.bytebuddy.dynamic.ClassFileLocator;
import net.bytebuddy.jar.asm.*;
import net.bytebuddy.pool.TypePool;
import org.junit.jupiter.api.Test;

class LifestyleActionProvenanceWeaveTest {
    @Test
    void exactNativeDescriptorsCaptureParseAndBothCopyPaths() throws Exception {
        var locator = ClassFileLocator.ForClassLoader.ofSystemLoader();
        var pool = TypePool.Default.of(locator);
        var type = pool.describe("zombie.core.NetTimedAction").resolve();
        byte[] bytes =
                new LifestyleActionProvenancePatch()
                        .dynamicType(locator, pool, new ByteBuddy().redefine(type, locator))
                        .make()
                        .getBytes();
        Map<String, Integer> calls = provenanceCalls(bytes);
        assertEquals(1, calls.get("parse:capture"));
        assertEquals(1, calls.get("parse:forget"));
        assertEquals(2, calls.get("copyFrom:copy"));
        assertEquals(2, calls.get("copyFrom:forget"));
        assertFalse(calls.containsKey("start:capture"));
    }

    @Test
    void actualStormParseRepairAndNewProvenanceComposeInBothOrders() throws Exception {
        var repair =
                (StormClassTransformer)
                        Class.forName("io.pzstorm.storm.patch.fixes.NetTimedActionParsePatch")
                                .getConstructor()
                                .newInstance();
        for (var patches :
                List.of(
                        List.of(repair, new LifestyleActionProvenancePatch()),
                        List.of(new LifestyleActionProvenancePatch(), repair))) {
            byte[] bytes =
                    ClassFileLocator.ForClassLoader.ofSystemLoader()
                            .locate("zombie.core.NetTimedAction")
                            .resolve();
            for (var patch : patches) {
                var locator =
                        new ClassFileLocator.Compound(
                                ClassFileLocator.Simple.of("zombie.core.NetTimedAction", bytes),
                                ClassFileLocator.ForClassLoader.ofSystemLoader());
                var pool = TypePool.Default.of(locator);
                bytes =
                        patch.dynamicType(
                                        locator,
                                        pool,
                                        new ByteBuddy()
                                                .redefine(
                                                        pool.describe("zombie.core.NetTimedAction")
                                                                .resolve(),
                                                        locator))
                                .make()
                                .getBytes();
            }
            assertEquals(1, provenanceCalls(bytes).get("parse:capture"));
            assertTrue(hasRepair(bytes), "Storm parse-failure repair is preserved");
            byte[] transformed = bytes;
            var defining =
                    new ClassLoader(getClass().getClassLoader()) {
                        @Override
                        protected Class<?> loadClass(String name, boolean resolve)
                                throws ClassNotFoundException {
                            synchronized (getClassLoadingLock(name)) {
                                Class<?> found = findLoadedClass(name);
                                if (found == null && name.startsWith("zombie.")) {
                                    try {
                                        byte[] nativeBytes =
                                                name.equals("zombie.core.NetTimedAction")
                                                        ? transformed
                                                        : ClassFileLocator.ForClassLoader
                                                                .ofSystemLoader()
                                                                .locate(name)
                                                                .resolve();
                                        found =
                                                defineClass(
                                                        name, nativeBytes, 0, nativeBytes.length);
                                    } catch (Exception error) {
                                        throw new ClassNotFoundException(name, error);
                                    }
                                }
                                if (found == null) found = super.loadClass(name, false);
                                if (resolve) resolveClass(found);
                                return found;
                            }
                        }
                    };
            Class<?> verified = Class.forName("zombie.core.NetTimedAction", false, defining);
            assertEquals("zombie.core.NetTimedAction", verified.getName());
            assertTrue(verified.getDeclaredMethods().length > 0);
        }
    }

    private static Map<String, Integer> provenanceCalls(byte[] bytes) {
        Map<String, Integer> calls = new HashMap<>();
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
                                            String name,
                                            String desc,
                                            boolean isInterface) {
                                        if (owner.endsWith("/ATFLifestyleNativeAction"))
                                            calls.merge(method + ":" + name, 1, Integer::sum);
                                    }
                                };
                            }
                        },
                        0);
        return calls;
    }

    private static boolean hasRepair(byte[] bytes) {
        boolean[] found = {false};
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
                                            String name,
                                            String desc,
                                            boolean isInterface) {
                                        if (owner.endsWith("/NetTimedActionParseFix")
                                                && name.equals("onParseFailed")) found[0] = true;
                                    }
                                };
                            }
                        },
                        0);
        return found[0];
    }
}
