package com.sentientsimulations.projectzomboid.admincore;

import io.pzstorm.storm.core.StormClassTransformer;
import net.bytebuddy.asm.Advice;
import net.bytebuddy.dynamic.ClassFileLocator;
import net.bytebuddy.dynamic.DynamicType;
import net.bytebuddy.matcher.ElementMatchers;
import net.bytebuddy.pool.TypePool;

public final class AdminCoreObservePlayerPatch extends StormClassTransformer {
    public AdminCoreObservePlayerPatch() {
        super("zombie.characters.IsoPlayer");
    }

    @Override
    public DynamicType.Builder<Object> dynamicType(
            ClassFileLocator locator, TypePool pool, DynamicType.Builder<Object> builder) {
        // Keep the UdpConnection overload, used for server invisible-player filtering, untouched.
        return builder.visit(
                Advice.to(
                                pool.describe(
                                                "com.sentientsimulations.projectzomboid.admincore.AdminCoreObservePlayerAdvice")
                                        .resolve(),
                                locator)
                        .on(
                                ElementMatchers.named("checkCanSeeClient")
                                        .and(ElementMatchers.not(ElementMatchers.isStatic()))
                                        .and(
                                                ElementMatchers.takesArgument(
                                                        0,
                                                        ElementMatchers.named(
                                                                "zombie.characters.IsoPlayer")))
                                        .and(ElementMatchers.takesArguments(1))
                                        .and(ElementMatchers.returns(boolean.class))));
    }
}
