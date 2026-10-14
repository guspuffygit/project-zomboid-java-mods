package com.sentientsimulations.projectzomboid.admincore;

import io.pzstorm.storm.core.StormClassTransformer;
import net.bytebuddy.asm.Advice;
import net.bytebuddy.dynamic.ClassFileLocator;
import net.bytebuddy.dynamic.DynamicType;
import net.bytebuddy.matcher.ElementMatchers;
import net.bytebuddy.pool.TypePool;

public final class AdminCoreObserverWeatherPatch extends StormClassTransformer {
    public AdminCoreObserverWeatherPatch() {
        super("zombie.iso.weather.fx.IsoWeatherFX");
    }

    @Override
    public DynamicType.Builder<Object> dynamicType(
            ClassFileLocator locator, TypePool pool, DynamicType.Builder<Object> builder) {
        return builder.visit(
                Advice.to(
                                pool.describe(
                                                "com.sentientsimulations.projectzomboid.admincore.AdminCoreObserverWeatherAdvice")
                                        .resolve(),
                                locator)
                        .on(
                                ElementMatchers.namedOneOf(
                                        "render",
                                        "renderLayered",
                                        "renderClouds",
                                        "renderFog",
                                        "renderPrecipitation")));
    }
}
