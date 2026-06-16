package com.sentientsimulations.projectzomboid.stopzombiesafehousespawns.patch;

import com.sentientsimulations.projectzomboid.stopzombiesafehousespawns.config.StopZombieSafehouseSpawnsConfig;
import io.pzstorm.storm.core.StormClassTransformer;
import net.bytebuddy.asm.Advice;
import net.bytebuddy.dynamic.ClassFileLocator;
import net.bytebuddy.dynamic.DynamicType;
import net.bytebuddy.matcher.ElementMatchers;
import net.bytebuddy.pool.TypePool;
import zombie.iso.IsoGridSquare;
import zombie.iso.areas.SafeHouse;

public class PlayerSpawnsAllowZombieSafehousePatch extends StormClassTransformer {

    public PlayerSpawnsAllowZombieSafehousePatch() {
        super("zombie.popman.PlayerSpawns");
    }

    @Override
    public DynamicType.Builder<Object> dynamicType(
            ClassFileLocator locator, TypePool typePool, DynamicType.Builder<Object> builder) {
        return builder.visit(
                Advice.to(AllowZombieAdvice.class)
                        .on(
                                ElementMatchers.named("allowZombie")
                                        .and(ElementMatchers.takesArguments(1))));
    }

    public static class AllowZombieAdvice {

        @Advice.OnMethodExit(suppress = Throwable.class)
        public static void onExit(
                @Advice.Argument(0) IsoGridSquare sq,
                @Advice.Return(readOnly = false) boolean result) {
            if (!result) {
                return;
            }
            if (!StopZombieSafehouseSpawnsConfig.isEnabled()) {
                return;
            }
            if (sq == null) {
                return;
            }
            if (SafeHouse.getSafeHouse(sq) != null) {
                result = false;
            }
        }
    }
}
