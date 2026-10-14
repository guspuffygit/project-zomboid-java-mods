package com.sentientsimulations.projectzomboid.guspuffyatfpatches.patch;

import com.sentientsimulations.projectzomboid.guspuffyatfpatches.ATFLifestyleNativeAction;
import io.pzstorm.storm.core.StormClassTransformer;
import net.bytebuddy.asm.Advice;
import net.bytebuddy.dynamic.ClassFileLocator;
import net.bytebuddy.dynamic.DynamicType;
import net.bytebuddy.matcher.ElementMatchers;
import net.bytebuddy.pool.TypePool;

/** Records the real sender before decoded constructor arguments reach Lifestyle reward hooks. */
public final class LifestyleActionProvenancePatch extends StormClassTransformer {
    public LifestyleActionProvenancePatch() {
        super("zombie.core.NetTimedAction");
    }

    @Override
    public DynamicType.Builder<Object> dynamicType(
            ClassFileLocator locator, TypePool pool, DynamicType.Builder<Object> builder) {
        var type = pool.describe("zombie.core.NetTimedAction").resolve();
        var parse =
                ElementMatchers.named("parse")
                        .and(
                                ElementMatchers.hasDescriptor(
                                        "(Lzombie/core/network/ByteBufferReader;Lzombie/network/IConnection;)V"));
        var copyNative =
                ElementMatchers.named("copyFrom")
                        .and(ElementMatchers.hasDescriptor("(Lzombie/core/NetTimedAction;)V"));
        var copyAction =
                ElementMatchers.named("copyFrom")
                        .and(ElementMatchers.hasDescriptor("(Lzombie/core/Action;)V"));
        if (type.getDeclaredMethods().filter(parse).size() != 1
                || type.getDeclaredMethods().filter(copyNative).size() != 1
                || type.getDeclaredMethods().filter(copyAction).size() != 1)
            throw new IllegalStateException(
                    "Unsupported native Lifestyle action provenance layout");
        var owner =
                pool.describe("zombie.core.Action")
                        .resolve()
                        .getDeclaredFields()
                        .filter(ElementMatchers.named("playerId"));
        if (owner.size() != 1
                || !owner.getOnly()
                        .getDescriptor()
                        .equals("Lzombie/network/fields/character/PlayerID;"))
            throw new IllegalStateException("Unsupported native Lifestyle action owner field");
        return builder.visit(Advice.to(Parse.class).on(parse))
                .visit(Advice.to(Copy.class).on(copyNative.or(copyAction)));
    }

    public static final class Parse {
        @Advice.OnMethodEnter(suppress = Throwable.class)
        public static void enter(@Advice.This Object action) {
            ATFLifestyleNativeAction.forget(action);
        }

        @Advice.OnMethodExit(onThrowable = Throwable.class, suppress = Throwable.class)
        public static void exit(
                @Advice.This Object action,
                @Advice.Argument(1) Object connection,
                @Advice.Thrown Throwable failure) {
            if (failure == null) ATFLifestyleNativeAction.capture(action, connection);
        }
    }

    public static final class Copy {
        @Advice.OnMethodExit(onThrowable = Throwable.class, suppress = Throwable.class)
        public static void exit(
                @Advice.This Object destination,
                @Advice.Argument(0) Object source,
                @Advice.Thrown Throwable failure) {
            if (failure == null) ATFLifestyleNativeAction.copy(destination, source);
            else ATFLifestyleNativeAction.forget(destination);
        }
    }
}
