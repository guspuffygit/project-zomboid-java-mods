package com.sentientsimulations.projectzomboid.admincore;

import net.bytebuddy.asm.Advice;

public final class AdminCoreObserveVisibilityAdvice {
    private AdminCoreObserveVisibilityAdvice() {}

    @Advice.OnMethodEnter(skipOn = Advice.OnNonDefaultValue.class)
    public static boolean enter(@Advice.Argument(0) int playerIndex) {
        return AdminCoreObserveRender.suppressVisibilityMask(playerIndex);
    }
}
