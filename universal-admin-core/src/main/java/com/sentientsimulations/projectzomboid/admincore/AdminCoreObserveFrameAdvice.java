package com.sentientsimulations.projectzomboid.admincore;

import net.bytebuddy.asm.Advice;
import zombie.iso.IsoCamera;

public final class AdminCoreObserveFrameAdvice {
    @Advice.OnMethodExit
    public static void exit(@Advice.This IsoCamera.FrameState frame) {
        AdminCoreObserveCamera.frame(frame);
    }
}
