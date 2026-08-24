package com.sentientsimulations.projectzomboid.avcsmapview;

import io.pzstorm.storm.core.StormClassTransformer;
import net.bytebuddy.asm.Advice;
import net.bytebuddy.dynamic.ClassFileLocator;
import net.bytebuddy.dynamic.DynamicType;
import net.bytebuddy.matcher.ElementMatchers;
import net.bytebuddy.pool.TypePool;

/**
 * Server-side damage guards on {@code zombie.vehicles.BaseVehicle}:
 *
 * <ul>
 *   <li>{@code processHit(IsoGameCharacter, HandWeapon, float)} — the sink {@code
 *       PlayerHitVehiclePacket.process()} calls for every gun and melee hit a client lands on a
 *       vehicle. Skipped when {@link VehicleDamageSecurity#shouldBlockHit} decides the target is a
 *       parked claimed vehicle the attacker may not damage; a skipped call returns {@code false}
 *       ("hit not processed"), which the packet path ignores.
 *   <li>{@code crash(float, boolean)} — collision damage. On the server every ram lands here, both
 *       when server physics detects it directly and when a client reports it via the {@code
 *       vehicle.crash} command (whose Lua handler calls this same method). Skipped when {@link
 *       VehicleDamageSecurity#shouldBlockCrash} decides the vehicle is a protected parked claim.
 * </ul>
 */
public class BaseVehicleDamageGuardPatch extends StormClassTransformer {

    public BaseVehicleDamageGuardPatch() {
        super("zombie.vehicles.BaseVehicle");
    }

    @Override
    public DynamicType.Builder<Object> dynamicType(
            ClassFileLocator locator, TypePool typePool, DynamicType.Builder<Object> builder) {
        return builder.visit(
                        Advice.to(ProcessHitAdvice.class)
                                .on(
                                        ElementMatchers.named("processHit")
                                                .and(ElementMatchers.takesArguments(3))))
                .visit(
                        Advice.to(CrashAdvice.class)
                                .on(
                                        ElementMatchers.named("crash")
                                                .and(ElementMatchers.takesArguments(2))));
    }

    public static class ProcessHitAdvice {

        @Advice.OnMethodEnter(skipOn = Advice.OnNonDefaultValue.class)
        public static boolean before(
                @Advice.This Object vehicle, @Advice.Argument(0) Object attacker) {
            return VehicleDamageSecurity.shouldBlockHit(vehicle, attacker);
        }
    }

    public static class CrashAdvice {

        @Advice.OnMethodEnter(skipOn = Advice.OnNonDefaultValue.class)
        public static boolean before(@Advice.This Object vehicle) {
            return VehicleDamageSecurity.shouldBlockCrash(vehicle);
        }
    }
}
