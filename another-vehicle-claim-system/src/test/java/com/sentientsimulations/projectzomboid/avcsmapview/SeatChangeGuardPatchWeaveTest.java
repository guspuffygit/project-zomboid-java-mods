package com.sentientsimulations.projectzomboid.avcsmapview;

import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.pzstorm.storm.core.StormClassTransformer;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import org.junit.jupiter.api.Test;

/**
 * Weaves each seat-change guard patch against the real packet class bytes. Compile-green is not
 * weave-safe: {@code Advice.to(...).on(named("processServer"))} only fails when actually applied,
 * e.g. after a game update renames or removes the method.
 */
class SeatChangeGuardPatchWeaveTest {

    @Test
    void vehicleEnterPacketWeaves() throws Exception {
        assertWeaves(new VehicleEnterPacketGuardPatch());
    }

    @Test
    void vehicleSwitchSeatPacketWeaves() throws Exception {
        assertWeaves(new VehicleSwitchSeatPacketGuardPatch());
    }

    private static void assertWeaves(StormClassTransformer patch) throws Exception {
        byte[] raw = rawClass(patch.getClassName());
        byte[] woven = patch.transform(raw);
        assertNotEquals(raw.length, woven.length, "advice was not woven in");
        assertTrue(
                contains(woven, "shouldBlockSeatChange".getBytes(StandardCharsets.UTF_8)),
                "woven class does not call the guard");
    }

    private static byte[] rawClass(String className) throws Exception {
        String resource = "/" + className.replace('.', '/') + ".class";
        try (InputStream in = SeatChangeGuardPatchWeaveTest.class.getResourceAsStream(resource)) {
            if (in == null) {
                throw new IllegalStateException(resource + " not on test classpath");
            }
            return in.readAllBytes();
        }
    }

    private static boolean contains(byte[] haystack, byte[] needle) {
        outer:
        for (int i = 0; i <= haystack.length - needle.length; i++) {
            for (int j = 0; j < needle.length; j++) {
                if (haystack[i + j] != needle[j]) {
                    continue outer;
                }
            }
            return true;
        }
        return false;
    }
}
