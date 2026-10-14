package com.sentientsimulations.projectzomboid.admincore;

import net.bytebuddy.asm.Advice;

public final class AdminCoreObserveRenderAdvice {
    @Advice.OnMethodEnter
    public static boolean enter() {
        return AdminCoreObserveRender.begin();
    }

    @Advice.OnMethodExit(onThrowable = Throwable.class)
    public static void exit(@Advice.Enter boolean entered) {
        AdminCoreObserveRender.end(entered);
    }
}
