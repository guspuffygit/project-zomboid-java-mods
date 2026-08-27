package com.sentientsimulations.projectzomboid.guspuffyatfpatches.patch;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;

import java.io.InputStream;
import java.lang.reflect.Method;
import org.junit.jupiter.api.Test;

/**
 * Weaves the overload patch against the real {@code VehiclePart} bytes and verifies the added
 * no-arg {@code doInventoryItemStats()} actually exists on the woven class. Compile-green is not
 * weave-safe: the {@code getOnly()} lookups and the {@code MethodCall} assignability checks only
 * fail when the transform runs, e.g. after a game update changes a signature.
 */
class VehiclePartStatsOverloadPatchWeaveTest {

    @Test
    void addsNoArgOverload() throws Exception {
        VehiclePartStatsOverloadPatch patch = new VehiclePartStatsOverloadPatch();
        byte[] woven = patch.transform(rawClass(patch.getClassName()));

        Class<?> wovenClass =
                new ClassLoader(getClass().getClassLoader()) {
                    Class<?> define(String name, byte[] bytes) {
                        return defineClass(name, bytes, 0, bytes.length);
                    }
                }.define(patch.getClassName(), woven);

        Method overload = wovenClass.getDeclaredMethod("doInventoryItemStats");
        assertNotNull(overload);
        assertEquals(void.class, overload.getReturnType());
    }

    private static byte[] rawClass(String className) throws Exception {
        String resource = "/" + className.replace('.', '/') + ".class";
        try (InputStream in =
                VehiclePartStatsOverloadPatchWeaveTest.class.getResourceAsStream(resource)) {
            if (in == null) {
                throw new IllegalStateException(resource + " not on test classpath");
            }
            return in.readAllBytes();
        }
    }
}
