package com.sentientsimulations.projectzomboid.survivorskillobelisk.patch;

import io.pzstorm.storm.core.StormClassTransformer;
import net.bytebuddy.asm.Advice;
import net.bytebuddy.dynamic.ClassFileLocator;
import net.bytebuddy.dynamic.DynamicType;
import net.bytebuddy.matcher.ElementMatchers;
import net.bytebuddy.pool.TypePool;

/**
 * Skips {@code RemoveItemFromSquarePacket.processServer} when the target object is an obelisk and
 * the sender is not a brush-tool admin. This is the generic object-removal packet — moveable
 * pickup, scrap/disassemble, and the delegated half of the sledgehammer flow all land here.
 */
public class RemoveItemFromSquarePacketPatch extends StormClassTransformer {

    public RemoveItemFromSquarePacketPatch() {
        super("zombie.network.packets.RemoveItemFromSquarePacket");
    }

    @Override
    public DynamicType.Builder<Object> dynamicType(
            ClassFileLocator locator, TypePool typePool, DynamicType.Builder<Object> builder) {
        return builder.visit(
                Advice.to(ProcessServerAdvice.class).on(ElementMatchers.named("processServer")));
    }

    public static class ProcessServerAdvice {

        @Advice.OnMethodEnter(skipOn = Advice.OnNonDefaultValue.class, suppress = Throwable.class)
        public static boolean onEnter(
                @Advice.This Object packet, @Advice.Argument(1) Object connection) {
            return ObeliskProtection.shouldBlockRemoval(packet, connection);
        }
    }
}
