package com.sentientsimulations.projectzomboid.jumpscareban;

import io.pzstorm.storm.core.StormClassTransformer;
import net.bytebuddy.asm.Advice;
import net.bytebuddy.dynamic.ClassFileLocator;
import net.bytebuddy.dynamic.DynamicType;
import net.bytebuddy.matcher.ElementMatchers;
import net.bytebuddy.pool.TypePool;

/**
 * Intercepts {@code BanSystem.KickUser(username, reason, description)} so that ban-initiated
 * disconnects play the Foxy jumpscare on the target client first, then disconnect ~3 seconds later
 * once the animation has had time to render.
 *
 * <p>{@code BanSystem.BanUser} and {@code BanSystem.BanUserBySteamID} are the two paths that call
 * {@code KickUser} with description {@code "command-banid"}. We match on that string so that
 * unrelated kick callers (none in vanilla, but be defensive) keep their original behavior.
 */
public class BanSystemPatch extends StormClassTransformer {

    public BanSystemPatch() {
        super("zombie.network.BanSystem");
    }

    @Override
    public DynamicType.Builder<Object> dynamicType(
            ClassFileLocator locator, TypePool typePool, DynamicType.Builder<Object> builder) {
        return builder.visit(
                Advice.to(KickUserAdvice.class)
                        .on(
                                ElementMatchers.named("KickUser")
                                        .and(ElementMatchers.takesArguments(3))));
    }

    public static class KickUserAdvice {

        @Advice.OnMethodEnter(skipOn = Advice.OnNonDefaultValue.class)
        public static boolean beforeKickUser(
                @Advice.Argument(0) String username, @Advice.Argument(2) String description) {
            return JumpscareBanService.tryScheduleJumpscareKick(username, description);
        }
    }
}
