package com.sentientsimulations.projectzomboid.admincore;

import net.bytebuddy.asm.Advice;
import zombie.iso.PlayerCamera;

public final class AdminCoreObserverPanAdvice {
    @Advice.OnMethodExit
    public static void exit(
            @Advice.This PlayerCamera camera,
            @Advice.FieldValue(value = "tOffX", readOnly = false) float targetX,
            @Advice.FieldValue(value = "tOffY", readOnly = false) float targetY) {
        if (AdminCoreObserveCamera.active()) {
            AdminCoreObserveCamera.center(camera);
            targetX = camera.offX;
            targetY = camera.offY;
        }
    }
}
