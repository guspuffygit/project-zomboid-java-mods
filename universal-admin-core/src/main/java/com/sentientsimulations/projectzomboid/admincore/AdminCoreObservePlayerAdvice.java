package com.sentientsimulations.projectzomboid.admincore;

import net.bytebuddy.asm.Advice;
import zombie.characters.IsoPlayer;

public final class AdminCoreObservePlayerAdvice {
    @Advice.OnMethodEnter(skipOn = Advice.OnNonDefaultValue.class)
    public static boolean enter(
            @Advice.This IsoPlayer viewer, @Advice.Argument(0) IsoPlayer remote) {
        return AdminCoreObserveCamera.showsPlayer(viewer, remote);
    }

    @Advice.OnMethodExit
    public static void exit(
            @Advice.Enter boolean override, @Advice.Return(readOnly = false) boolean value) {
        if (override) value = true;
    }
}
