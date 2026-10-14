package com.sentientsimulations.projectzomboid.admincore;

import io.pzstorm.storm.core.StormClassTransformer;
import net.bytebuddy.asm.Advice;
import net.bytebuddy.dynamic.ClassFileLocator;
import net.bytebuddy.dynamic.DynamicType;
import net.bytebuddy.implementation.FieldAccessor;
import net.bytebuddy.matcher.ElementMatchers;
import net.bytebuddy.pool.TypePool;

public final class AdminCoreObserveLightPatch extends StormClassTransformer {
    public AdminCoreObserveLightPatch() {
        super("zombie.iso.LightingJNI$JNILighting");
    }

    @Override
    public DynamicType.Builder<Object> dynamicType(
            ClassFileLocator locator, TypePool pool, DynamicType.Builder<Object> builder) {
        return builder.implement(pool.describe(AdminCoreNativeLighting.class.getName()).resolve())
                .intercept(FieldAccessor.ofField("vis"))
                .visit(
                        Advice.to(
                                        pool.describe(
                                                        "com.sentientsimulations.projectzomboid.admincore.AdminCoreObserveLightAdvice")
                                                .resolve(),
                                        locator)
                                .on(
                                        ElementMatchers.namedOneOf("bSeen", "bCanSee", "bCouldSee")
                                                .and(ElementMatchers.takesArguments(0))));
    }
}
