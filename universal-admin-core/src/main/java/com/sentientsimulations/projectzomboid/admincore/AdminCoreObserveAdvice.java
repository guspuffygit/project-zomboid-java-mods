package com.sentientsimulations.projectzomboid.admincore;

import net.bytebuddy.asm.Advice;
import zombie.characters.IsoGameCharacter;

public final class AdminCoreObserveAdvice {
    @Advice.OnMethodEnter
    public static void enter(
            @Advice.Argument(value = 0, readOnly = false) IsoGameCharacter character) {
        character = AdminCoreObserveCamera.select(character);
    }
}
