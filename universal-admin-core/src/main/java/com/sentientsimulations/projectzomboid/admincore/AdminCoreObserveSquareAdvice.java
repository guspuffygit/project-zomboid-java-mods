package com.sentientsimulations.projectzomboid.admincore;

import net.bytebuddy.asm.Advice;
import zombie.core.textures.ColorInfo;
import zombie.iso.IsoGridSquare;

public final class AdminCoreObserveSquareAdvice {
    public static final class Visible {
        @Advice.OnMethodEnter(skipOn = Advice.OnNonDefaultValue.class)
        public static boolean enter(
                @Advice.This IsoGridSquare square, @Advice.Argument(0) int playerIndex) {
            return AdminCoreObserveRender.visible(square, playerIndex);
        }

        @Advice.OnMethodExit
        public static void exit(
                @Advice.Enter boolean override, @Advice.Return(readOnly = false) boolean value) {
            if (override) value = true;
        }
    }

    public static final class Color {
        @Advice.OnMethodExit
        public static void exit(
                @Advice.This IsoGridSquare square,
                @Advice.Argument(0) int playerIndex,
                @Advice.Return(readOnly = false) ColorInfo value) {
            value = AdminCoreObserveRender.color(square, playerIndex, value);
        }
    }

    public static final class Vertex {
        @Advice.OnMethodExit
        public static void exit(
                @Advice.This IsoGridSquare square,
                @Advice.Argument(0) int vertex,
                @Advice.Argument(1) int playerIndex,
                @Advice.Return(readOnly = false) int value) {
            value = AdminCoreObserveRender.vertex(square, vertex, playerIndex, value);
        }
    }

    public static final class Level {
        @Advice.OnMethodExit
        public static void exit(
                @Advice.This IsoGridSquare square,
                @Advice.Argument(0) int playerIndex,
                @Advice.Origin("#m") String method,
                @Advice.Return(readOnly = false) float value) {
            if (method.equals("getLightLevel"))
                value = AdminCoreObserveRender.level(square, playerIndex, value);
            else if (AdminCoreObserveRender.visible(square, playerIndex)) value = 1f;
        }
    }
}
