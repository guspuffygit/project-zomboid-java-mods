package com.sentientsimulations.projectzomboid.jumpscareban;

import io.pzstorm.storm.core.StormClassTransformer;
import net.bytebuddy.asm.Advice;
import net.bytebuddy.dynamic.ClassFileLocator;
import net.bytebuddy.dynamic.DynamicType;
import net.bytebuddy.matcher.ElementMatchers;
import net.bytebuddy.pool.TypePool;

/**
 * Pumps {@link JumpscareBanService#drainDueTasks()} from the server main loop.
 *
 * <p>{@code ServerMap.preupdate()} is called from exactly one place — the {@code frameStep} block
 * of {@code GameServer.main}'s server loop — which makes it a once-per-tick main-thread hook. The
 * drain is an {@code isEmpty()} check on all but the handful of ticks that actually have a pending
 * jumpscare kick.
 *
 * <p>Registered only when {@link io.pzstorm.storm.util.StormEnv#isStormServer()}, so it never
 * touches the client JVM's {@code ServerMap} mirror.
 */
public class ServerMainLoopPatch extends StormClassTransformer {

    public ServerMainLoopPatch() {
        super("zombie.network.ServerMap");
    }

    @Override
    public DynamicType.Builder<Object> dynamicType(
            ClassFileLocator locator, TypePool typePool, DynamicType.Builder<Object> builder) {
        return builder.visit(
                Advice.to(PreupdateAdvice.class)
                        .on(
                                ElementMatchers.named("preupdate")
                                        .and(ElementMatchers.takesArguments(0))));
    }

    public static class PreupdateAdvice {

        @Advice.OnMethodEnter
        public static void beforePreupdate() {
            JumpscareBanService.drainDueTasks();
        }
    }
}
