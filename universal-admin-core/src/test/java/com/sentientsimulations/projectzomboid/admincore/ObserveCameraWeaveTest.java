package com.sentientsimulations.projectzomboid.admincore;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import net.bytebuddy.ByteBuddy;
import net.bytebuddy.dynamic.ClassFileLocator;
import net.bytebuddy.matcher.ElementMatchers;
import net.bytebuddy.pool.TypePool;
import org.junit.jupiter.api.Test;

class ObserveCameraWeaveTest {
    @Test
    void adviceWeavesIntoInstalledGameWithoutLoadingGameClasses() throws Exception {
        ClassFileLocator locator = ClassFileLocator.ForClassLoader.ofSystemLoader();
        TypePool pool = TypePool.Default.of(locator);
        var type = pool.describe("zombie.iso.IsoCamera").resolve();
        assertEquals(
                1,
                type.getDeclaredMethods()
                        .filter(ElementMatchers.named("setCameraCharacter"))
                        .size());
        var builder = new ByteBuddy().redefine(type, locator);
        byte[] transformed =
                new AdminCoreObservePatch().dynamicType(locator, pool, builder).make().getBytes();
        assertTrue(transformed.length > 0);
    }
}
