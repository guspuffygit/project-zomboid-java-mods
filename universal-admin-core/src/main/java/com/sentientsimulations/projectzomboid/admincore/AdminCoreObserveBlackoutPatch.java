package com.sentientsimulations.projectzomboid.admincore;

import io.pzstorm.storm.core.StormClassTransformer;
import net.bytebuddy.asm.Advice;
import net.bytebuddy.dynamic.ClassFileLocator;
import net.bytebuddy.dynamic.DynamicType;
import net.bytebuddy.matcher.ElementMatchers;
import net.bytebuddy.pool.TypePool;

public final class AdminCoreObserveBlackoutPatch extends StormClassTransformer {
    public AdminCoreObserveBlackoutPatch() {
        super("zombie.iso.fboRenderChunk.FBORenderCell");
    }

    @Override
    public DynamicType.Builder<Object> dynamicType(
            ClassFileLocator locator, TypePool pool, DynamicType.Builder<Object> builder) {
        return builder.visit(
                        Advice.to(
                                        pool.describe(
                                                        "com.sentientsimulations.projectzomboid.admincore.AdminCoreObserveBlackoutAdvice")
                                                .resolve(),
                                        locator)
                                .on(
                                        ElementMatchers.named("isBlackedOutBuildingSquare")
                                                .and(ElementMatchers.takesArguments(1))))
                .visit(
                        Advice.to(
                                        pool.describe(
                                                        "com.sentientsimulations.projectzomboid.admincore.AdminCoreObserveBlackoutAdvice$RoomFade")
                                                .resolve(),
                                        locator)
                                .on(
                                        ElementMatchers.named("getBlackedOutRoomFadeRatio")
                                                .and(ElementMatchers.takesArguments(1))));
    }
}
