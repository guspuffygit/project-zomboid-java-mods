package com.sentientsimulations.projectzomboid.admincore;

import io.pzstorm.storm.core.StormClassTransformer;
import net.bytebuddy.asm.Advice;
import net.bytebuddy.dynamic.ClassFileLocator;
import net.bytebuddy.dynamic.DynamicType;
import net.bytebuddy.matcher.ElementMatchers;
import net.bytebuddy.pool.TypePool;

public final class AdminCoreObserverPanPatch extends StormClassTransformer {
    public AdminCoreObserverPanPatch() {
        super("zombie.iso.PlayerCamera");
    }

    @Override
    public DynamicType.Builder<Object> dynamicType(
            ClassFileLocator locator, TypePool pool, DynamicType.Builder<Object> builder) {
        return builder.visit(
                Advice.to(
                                pool.describe(
                                                "com.sentientsimulations.projectzomboid.admincore.AdminCoreObserverPanAdvice")
                                        .resolve(),
                                locator)
                        .on(
                                ElementMatchers.namedOneOf("center", "update")
                                        .and(ElementMatchers.takesArguments(0))));
    }
}
