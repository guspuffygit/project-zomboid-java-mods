package com.sentientsimulations.projectzomboid.guspuffyatfpatches.patch;

import static org.junit.jupiter.api.Assertions.assertEquals;

import java.io.InputStream;
import java.lang.reflect.Method;
import org.junit.jupiter.api.Test;
import zombie.core.raknet.UdpConnection;

/**
 * Weaves the block against the real {@code RemoveCommand} bytes and calls the woven static {@code
 * Remove}. Other subsystems are checked with an unknown name because the real ones write {@code
 * GameServer} statics, which drags in the server's static init.
 */
class RemoveAnimalsCommandBlockPatchWeaveTest {

    @Test
    void blocksAnimalsAndPassesOtherSubsystems() throws Exception {
        RemoveAnimalsCommandBlockPatch patch = new RemoveAnimalsCommandBlockPatch();
        byte[] woven = patch.transform(rawClass(patch.getClassName()));

        Class<?> wovenClass =
                new ClassLoader(getClass().getClassLoader()) {
                    Class<?> define(String name, byte[] bytes) {
                        return defineClass(name, bytes, 0, bytes.length);
                    }
                }.define(patch.getClassName(), woven);
        Method remove = wovenClass.getMethod("Remove", UdpConnection.class, String.class);

        assertEquals(
                "Removing all animals is disabled on this server",
                remove.invoke(null, null, "animals"));
        assertEquals(
                "Removing all animals is disabled on this server",
                remove.invoke(null, null, "ANIMALS"));
        assertEquals("Subsystem error: bogus", remove.invoke(null, null, "bogus"));
    }

    private static byte[] rawClass(String className) throws Exception {
        String resource = "/" + className.replace('.', '/') + ".class";
        try (InputStream in =
                RemoveAnimalsCommandBlockPatchWeaveTest.class.getResourceAsStream(resource)) {
            if (in == null) {
                throw new IllegalStateException(resource + " not on test classpath");
            }
            return in.readAllBytes();
        }
    }
}
