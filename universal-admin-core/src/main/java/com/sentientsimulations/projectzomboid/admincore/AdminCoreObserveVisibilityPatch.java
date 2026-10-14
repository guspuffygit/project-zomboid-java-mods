package com.sentientsimulations.projectzomboid.admincore;

import io.pzstorm.storm.core.StormClassTransformer;
import java.lang.reflect.Modifier;
import net.bytebuddy.asm.Advice;
import net.bytebuddy.dynamic.ClassFileLocator;
import net.bytebuddy.dynamic.DynamicType;
import net.bytebuddy.matcher.ElementMatchers;
import net.bytebuddy.pool.TypePool;

/** The native screen mask uses the stationary avatar's facing and tree cover. */
public final class AdminCoreObserveVisibilityPatch extends StormClassTransformer {
    static final String MARKER = "uacObserverVisibilityReady";

    public AdminCoreObserveVisibilityPatch() {
        super("zombie.vispoly.VisibilityPolygon2");
    }

    @Override
    public DynamicType.Builder<Object> dynamicType(
            ClassFileLocator locator, TypePool pool, DynamicType.Builder<Object> builder) {
        var entry =
                ElementMatchers.named("renderMain")
                        .and(ElementMatchers.takesArguments(int.class))
                        .and(ElementMatchers.returns(void.class));
        if (pool.describe("zombie.vispoly.VisibilityPolygon2")
                        .resolve()
                        .getDeclaredMethods()
                        .filter(entry)
                        .size()
                != 1) throw new IllegalStateException("Observer visibility entry unavailable");
        return builder.defineField(
                        MARKER, boolean.class, Modifier.PUBLIC | Modifier.STATIC | Modifier.FINAL)
                .value(true)
                .visit(
                        Advice.to(
                                        pool.describe(
                                                        "com.sentientsimulations.projectzomboid.admincore.AdminCoreObserveVisibilityAdvice")
                                                .resolve(),
                                        locator)
                                .on(entry));
    }
}
