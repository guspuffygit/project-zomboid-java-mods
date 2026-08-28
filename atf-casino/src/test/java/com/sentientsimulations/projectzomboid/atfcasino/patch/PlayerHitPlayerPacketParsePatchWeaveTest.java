package com.sentientsimulations.projectzomboid.atfcasino.patch;

import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import org.junit.jupiter.api.Test;

/**
 * Weaves the assault-watch patch against the real {@code PlayerHitPlayerPacket} bytes and verifies
 * both advice hooks landed. Compile-green is not weave-safe: {@code Advice.to(...).on(named(...))}
 * only fails — or silently matches nothing — when actually applied, e.g. after a game update
 * renames {@code parse} or {@code process}.
 */
class PlayerHitPlayerPacketParsePatchWeaveTest {

    @Test
    void weavesBothAdviceHooks() throws Exception {
        PlayerHitPlayerPacketParsePatch patch = new PlayerHitPlayerPacketParsePatch();
        byte[] raw = rawClass(patch.getClassName());
        byte[] woven = patch.transform(raw);
        assertNotEquals(raw.length, woven.length, "advice was not woven in");
        assertTrue(
                contains(woven, "onHitParsed".getBytes(StandardCharsets.UTF_8)),
                "woven parse() does not call the assault watch");
        assertTrue(
                contains(woven, "onPlayerHitProcessed".getBytes(StandardCharsets.UTF_8)),
                "woven process() does not call the pvp watch");
    }

    private static byte[] rawClass(String className) throws Exception {
        String resource = "/" + className.replace('.', '/') + ".class";
        try (InputStream in =
                PlayerHitPlayerPacketParsePatchWeaveTest.class.getResourceAsStream(resource)) {
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
