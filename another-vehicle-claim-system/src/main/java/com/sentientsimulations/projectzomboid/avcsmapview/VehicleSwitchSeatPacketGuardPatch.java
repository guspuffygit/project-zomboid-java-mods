package com.sentientsimulations.projectzomboid.avcsmapview;

import io.pzstorm.storm.core.StormClassTransformer;
import net.bytebuddy.asm.Advice;
import net.bytebuddy.dynamic.ClassFileLocator;
import net.bytebuddy.dynamic.DynamicType;
import net.bytebuddy.matcher.ElementMatchers;
import net.bytebuddy.pool.TypePool;

/**
 * Gates {@code zombie.network.packets.vehicle.VehicleSwitchSeatPacket.processServer} through {@link
 * VehicleEnterSecurity#shouldBlockSeatChange}: a non-permitted player moving between seats (most
 * importantly into the driver seat) of a claimed vehicle is dropped before the server applies the
 * switch or hands out driver authorization.
 */
public class VehicleSwitchSeatPacketGuardPatch extends StormClassTransformer {

    public VehicleSwitchSeatPacketGuardPatch() {
        super("zombie.network.packets.vehicle.VehicleSwitchSeatPacket");
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
            return VehicleEnterSecurity.shouldBlockSeatChange(packet, "VehicleSwitchSeatPacket");
        }
    }
}
