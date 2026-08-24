package com.sentientsimulations.projectzomboid.avcsmapview;

import io.pzstorm.storm.core.StormClassTransformer;
import net.bytebuddy.asm.Advice;
import net.bytebuddy.dynamic.ClassFileLocator;
import net.bytebuddy.dynamic.DynamicType;
import net.bytebuddy.matcher.ElementMatchers;
import net.bytebuddy.pool.TypePool;

/**
 * Intercepts {@code BaseVehicle.processHit(IsoGameCharacter, HandWeapon, float)} on the dedicated
 * server — the sink {@code PlayerHitVehiclePacket.process()} calls for every gun and melee hit a
 * client lands on a vehicle — and skips it when {@link VehicleDamageSecurity#shouldBlockHit}
 * decides the target is a parked claimed vehicle the attacker may not damage. A skipped call
 * returns {@code false} ("hit not processed"), which the packet path ignores.
 */
public class BaseVehicleProcessHitPatch extends StormClassTransformer {

    public BaseVehicleProcessHitPatch() {
        super("zombie.vehicles.BaseVehicle");
    }

    @Override
    public DynamicType.Builder<Object> dynamicType(
            ClassFileLocator locator, TypePool typePool, DynamicType.Builder<Object> builder) {
        return builder.visit(
                Advice.to(ProcessHitAdvice.class)
                        .on(
                                ElementMatchers.named("processHit")
                                        .and(ElementMatchers.takesArguments(3))));
    }

    public static class ProcessHitAdvice {

        @Advice.OnMethodEnter(skipOn = Advice.OnNonDefaultValue.class)
        public static boolean before(
                @Advice.This Object vehicle, @Advice.Argument(0) Object attacker) {
            return VehicleDamageSecurity.shouldBlockHit(vehicle, attacker);
        }
    }
}
