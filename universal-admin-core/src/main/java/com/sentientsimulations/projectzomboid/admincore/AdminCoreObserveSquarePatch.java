package com.sentientsimulations.projectzomboid.admincore;

import io.pzstorm.storm.core.StormClassTransformer;
import net.bytebuddy.asm.Advice;
import net.bytebuddy.dynamic.ClassFileLocator;
import net.bytebuddy.dynamic.DynamicType;
import net.bytebuddy.matcher.ElementMatchers;
import net.bytebuddy.pool.TypePool;

public final class AdminCoreObserveSquarePatch extends StormClassTransformer {
    public AdminCoreObserveSquarePatch() {
        super("zombie.iso.IsoGridSquare");
    }

    @Override
    public DynamicType.Builder<Object> dynamicType(
            ClassFileLocator locator, TypePool pool, DynamicType.Builder<Object> builder) {
        return builder.visit(
                        Advice.to(
                                        pool.describe(
                                                        "com.sentientsimulations.projectzomboid.admincore.AdminCoreObserveSquareAdvice$Visible")
                                                .resolve(),
                                        locator)
                                .on(
                                        ElementMatchers.namedOneOf(
                                                        "isSeen",
                                                        "getSeen",
                                                        "isCanSee",
                                                        "getCanSee",
                                                        "isCouldSee")
                                                .and(ElementMatchers.takesArguments(int.class))))
                .visit(
                        Advice.to(
                                        pool.describe(
                                                        "com.sentientsimulations.projectzomboid.admincore.AdminCoreObserveSquareAdvice$Color")
                                                .resolve(),
                                        locator)
                                .on(
                                        ElementMatchers.named("getLightInfo")
                                                .and(ElementMatchers.takesArguments(int.class))))
                .visit(
                        Advice.to(
                                        pool.describe(
                                                        "com.sentientsimulations.projectzomboid.admincore.AdminCoreObserveSquareAdvice$Vertex")
                                                .resolve(),
                                        locator)
                                .on(
                                        ElementMatchers.named("getVertLight")
                                                .and(
                                                        ElementMatchers.takesArguments(
                                                                int.class, int.class))))
                .visit(
                        Advice.to(
                                        pool.describe(
                                                        "com.sentientsimulations.projectzomboid.admincore.AdminCoreObserveSquareAdvice$Level")
                                                .resolve(),
                                        locator)
                                .on(
                                        ElementMatchers.namedOneOf(
                                                        "getLightLevel",
                                                        "getDarkMulti",
                                                        "getTargetDarkMulti")
                                                .and(ElementMatchers.takesArguments(int.class))));
    }
}
