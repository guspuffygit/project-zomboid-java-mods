package com.sentientsimulations.projectzomboid.avcsmapview;

import io.pzstorm.storm.core.StormClassTransformer;
import net.bytebuddy.asm.Advice;
import net.bytebuddy.dynamic.ClassFileLocator;
import net.bytebuddy.dynamic.DynamicType;
import net.bytebuddy.matcher.ElementMatchers;
import net.bytebuddy.pool.TypePool;

/**
 * Gates {@code zombie.network.packets.vehicle.VehicleEnterPacket.processServer} through {@link
 * VehicleEnterSecurity#shouldBlockSeatChange}: a non-permitted player entering a claimed vehicle is
 * dropped before the server seats them, grants driver authorization, or relays to other clients.
 */
public class VehicleEnterPacketGuardPatch extends StormClassTransformer {

    public VehicleEnterPacketGuardPatch() {
        super("zombie.network.packets.vehicle.VehicleEnterPacket");
    }

    @Override
    public DynamicType.Builder<Object> dynamicType(
            ClassFileLocator locator, TypePool typePool, DynamicType.Builder<Object> builder) {
        return builder.visit(
                Advice.to(ProcessServerAdvice.class).on(ElementMatchers.named("processServer")));
    }

    public static class ProcessServerAdvice {

        @Advice.OnMethodEnter(skipOn = Advice.OnNonDefaultValue.class)
        public static boolean before(@Advice.This Object packet) {
            return VehicleEnterSecurity.shouldBlockSeatChange(packet, "VehicleEnterPacket");
        }
    }
}
