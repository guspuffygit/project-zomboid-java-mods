package com.sentientsimulations.projectzomboid.serverwaitlistqueue;

import io.pzstorm.storm.core.StormClassTransformer;
import net.bytebuddy.asm.Advice;
import net.bytebuddy.dynamic.ClassFileLocator;
import net.bytebuddy.dynamic.DynamicType;
import net.bytebuddy.matcher.ElementMatchers;
import net.bytebuddy.pool.TypePool;
import zombie.network.ServerOptions;

/**
 * Patches {@code GameServer.getPlayerCount()} so that the premature "ServerFull" rejection in
 * {@code LoginPacket.processServer()} is bypassed. This allows players to flow into the existing
 * {@code LoginQueue}, which enforces the real capacity limit via its own {@code getCountPlayers()}
 * method.
 *
 * <p>Requires {@code LoginQueueEnabled=true} in the server options.
 *
 * <p>This is a server-only change that is fully backwards compatible with vanilla (unmodified)
 * clients because it reuses the existing {@code LoadingQueueState} UI and {@code QueuePacket}
 * protocol.
 */
public class GameServerPatch extends StormClassTransformer {

    public GameServerPatch() {
        super("zombie.network.GameServer");
    }

    @Override
    public DynamicType.Builder<Object> dynamicType(
            ClassFileLocator locator, TypePool typePool, DynamicType.Builder<Object> builder) {
        return builder.visit(
                Advice.to(GetPlayerCountAdvice.class)
                        .on(
                                ElementMatchers.named("getPlayerCount")
                                        .and(ElementMatchers.takesNoArguments())
                                        .and(ElementMatchers.returns(int.class))));
    }

    public static class GetPlayerCountAdvice {

        @Advice.OnMethodExit
        public static void afterGetPlayerCount(@Advice.Return(readOnly = false) int returned) {
            if (!Boolean.getBoolean("storm.server")) {
                return;
            }
            if (ServerOptions.getInstance().loginQueueEnabled.getValue()) {
                int max = ServerOptions.getInstance().getMaxPlayers();
                if (returned >= max) {
                    returned = max - 1;
                }
            }
        }
    }
}
