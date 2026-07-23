package com.sentientsimulations.projectzomboid.survivorskillobelisk.patch;

import io.pzstorm.storm.core.StormClassTransformer;
import net.bytebuddy.asm.Advice;
import net.bytebuddy.dynamic.ClassFileLocator;
import net.bytebuddy.dynamic.DynamicType;
import net.bytebuddy.matcher.ElementMatchers;
import net.bytebuddy.pool.TypePool;

/**
 * Skips {@code SledgehammerDestroyPacket.processServer} when the target object is an obelisk and
 * the sender is not a brush-tool admin. The admin brush-tool "Destroy tile" option sends this same
 * packet, so the sender's role — not the packet type — is what distinguishes an admin delete from a
 * player sledgehammer. Blocking at this layer (not just the inner remove packet) also suppresses
 * the rebroadcast loop that would otherwise remove the obelisk on every nearby client.
 */
public class SledgehammerDestroyPacketPatch extends StormClassTransformer {

    public SledgehammerDestroyPacketPatch() {
        super("zombie.network.packets.SledgehammerDestroyPacket");
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
            return ObeliskProtection.shouldBlockSledgehammer(packet, connection);
        }
    }
}
