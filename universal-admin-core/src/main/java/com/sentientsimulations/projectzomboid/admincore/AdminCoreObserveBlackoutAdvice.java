package com.sentientsimulations.projectzomboid.admincore;

import net.bytebuddy.asm.Advice;
import zombie.iso.IsoCamera;
import zombie.iso.IsoGridSquare;

public final class AdminCoreObserveBlackoutAdvice {
    public static final class RoomFade {
        @Advice.OnMethodEnter(skipOn = Advice.OnNonDefaultValue.class)
        public static boolean enter(@Advice.Argument(0) IsoGridSquare square) {
            return AdminCoreObserveRender.visible(square, IsoCamera.frameState.playerIndex);
        }

        @Advice.OnMethodExit
        public static void exit(
                @Advice.Enter boolean override, @Advice.Return(readOnly = false) float value) {
            if (override) value = 1f;
        }
    }

    @Advice.OnMethodEnter(skipOn = Advice.OnNonDefaultValue.class)
    public static boolean enter(@Advice.Argument(0) IsoGridSquare square) {
        return AdminCoreObserveRender.visible(square, IsoCamera.frameState.playerIndex);
    }

    @Advice.OnMethodExit
    public static void exit(
            @Advice.Enter boolean override, @Advice.Return(readOnly = false) boolean value) {
        if (override) value = false;
    }
}
