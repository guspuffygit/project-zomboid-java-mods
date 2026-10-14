package com.sentientsimulations.projectzomboid.admincore;

import net.bytebuddy.asm.Advice;
import zombie.iso.IsoGridSquare;

public final class AdminCoreObserveLightAdvice {
    @Advice.OnMethodEnter(skipOn = Advice.OnNonDefaultValue.class)
    public static boolean enter(
            @Advice.FieldValue("square") IsoGridSquare square,
            @Advice.FieldValue("playerIndex") int playerIndex) {
        return AdminCoreObserveRender.visible(square, playerIndex);
    }

    @Advice.OnMethodExit
    public static void exit(
            @Advice.Enter boolean override, @Advice.Return(readOnly = false) boolean value) {
        if (override) value = true;
    }
}
