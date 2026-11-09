package com.sentientsimulations.projectzomboid.extralogging.patch;

import com.sentientsimulations.projectzomboid.extralogging.pvphit.PvpHitServerLog;
import io.pzstorm.storm.core.StormClassTransformer;
import net.bytebuddy.asm.Advice;
import net.bytebuddy.description.method.MethodDescription;
import net.bytebuddy.dynamic.ClassFileLocator;
import net.bytebuddy.dynamic.DynamicType;
import net.bytebuddy.matcher.ElementMatcher;
import net.bytebuddy.matcher.ElementMatchers;
import net.bytebuddy.pool.TypePool;

/**
 * Server only. Brackets {@code PlayerHitPlayerPacket.process()} so {@link PvpHitServerLog} can log
 * the flags the hits carried and whether the target's body took damage.
 *
 * <p>Re-validate on game updates: assumes {@code process()} applies the hits synchronously through
 * {@code Hit.process} and {@code IsoGameCharacter.Hit}.
 */
public class PvpHitProcessPatch extends StormClassTransformer {

    static final String TARGET = "zombie.network.packets.hit.PlayerHitPlayerPacket";
    static final String ADVICE = PvpHitProcessPatch.class.getName() + "$ProcessAdvice";

    public PvpHitProcessPatch() {
        super(TARGET);
    }

    @Override
    public DynamicType.Builder<Object> dynamicType(
            ClassFileLocator locator, TypePool typePool, DynamicType.Builder<Object> builder) {
        ElementMatcher.Junction<MethodDescription> process =
                ElementMatchers.named("process").and(ElementMatchers.takesArguments(0));
        PatchTargets.require(typePool, TARGET, process, "process()");
        return builder.visit(Advice.to(typePool.describe(ADVICE).resolve(), locator).on(process));
    }

    public static class ProcessAdvice {

        @Advice.OnMethodEnter(suppress = Throwable.class)
        public static Object onEnter(@Advice.This Object self) {
            return PvpHitServerLog.beforeProcess(self);
        }

        @Advice.OnMethodExit(suppress = Throwable.class, onThrowable = Throwable.class)
        public static void onExit(@Advice.This Object self, @Advice.Enter Object before) {
            PvpHitServerLog.afterProcess(self, before);
        }
    }
}
