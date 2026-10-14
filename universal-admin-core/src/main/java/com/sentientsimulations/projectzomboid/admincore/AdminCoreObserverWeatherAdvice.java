package com.sentientsimulations.projectzomboid.admincore;

import net.bytebuddy.asm.Advice;

public final class AdminCoreObserverWeatherAdvice {
    @Advice.OnMethodEnter(skipOn = Advice.OnNonDefaultValue.class)
    public static boolean enter() {
        return AdminCoreObserveCamera.hideWeather();
    }
}
