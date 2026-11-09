package com.sentientsimulations.projectzomboid.extralogging.patch;

import com.sentientsimulations.projectzomboid.extralogging.pvphit.PvpShotClientLog;
import io.pzstorm.storm.core.StormClassTransformer;
import net.bytebuddy.asm.Advice;
import net.bytebuddy.description.method.MethodDescription;
import net.bytebuddy.dynamic.ClassFileLocator;
import net.bytebuddy.dynamic.DynamicType;
import net.bytebuddy.matcher.ElementMatcher;
import net.bytebuddy.matcher.ElementMatchers;
import net.bytebuddy.pool.TypePool;

/**
 * Client only. Brackets {@code CombatManager.attackCollisionCheck}, which computes each target's
 * hit chance and, for zombies, rolls it. It also watches {@code addTargetHitCharacter}, which
 * queues each character hit that will be sent with its {@code HitData}. Together they give the
 * chance and the queued outcome per target. Player and animal targets are rolled by the server
 * since 42.22, so for them the client queues every hit and the server log holds the roll.
 *
 * <p>Why a client patch: the chance exists only on the shooter's client and is never sent.
 * Fail-soft: the advice suppresses every throwable, and a missing method fails the weave, which
 * leaves the class vanilla. Re-validate on game updates: assumes the chance stays inline in {@code
 * attackCollisionCheck} and every queued character hit goes through {@code addTargetHitCharacter}.
 */
public class PvpShotCombatManagerPatch extends StormClassTransformer {

    static final String TARGET = "zombie.CombatManager";
    static final String COLLISION_ADVICE =
            PvpShotCombatManagerPatch.class.getName() + "$CollisionAdvice";
    static final String CLIENT_HIT_ADVICE =
            PvpShotCombatManagerPatch.class.getName() + "$ClientHitAdvice";

    public PvpShotCombatManagerPatch() {
        super(TARGET);
    }

    @Override
    public DynamicType.Builder<Object> dynamicType(
            ClassFileLocator locator, TypePool typePool, DynamicType.Builder<Object> builder) {
        ElementMatcher.Junction<MethodDescription> collision =
                ElementMatchers.named("attackCollisionCheck")
                        .and(ElementMatchers.takesArguments(4));
        ElementMatcher.Junction<MethodDescription> clientHit =
                ElementMatchers.named("addTargetHitCharacter")
                        .and(ElementMatchers.takesArguments(5));
        PatchTargets.require(typePool, TARGET, collision, "attackCollisionCheck (4 args)");
        PatchTargets.require(typePool, TARGET, clientHit, "addTargetHitCharacter (5 args)");
        return builder.visit(
                        Advice.to(typePool.describe(COLLISION_ADVICE).resolve(), locator)
                                .on(collision))
                .visit(
                        Advice.to(typePool.describe(CLIENT_HIT_ADVICE).resolve(), locator)
                                .on(clientHit));
    }

    public static class CollisionAdvice {

        @Advice.OnMethodEnter(suppress = Throwable.class)
        public static void onEnter(
                @Advice.Argument(0) Object owner, @Advice.Argument(1) Object weapon) {
            PvpShotClientLog.beforeCollision(owner, weapon);
        }

        @Advice.OnMethodExit(suppress = Throwable.class, onThrowable = Throwable.class)
        public static void onExit(@Advice.Argument(0) Object owner) {
            PvpShotClientLog.afterCollision(owner);
        }
    }

    public static class ClientHitAdvice {

        @Advice.OnMethodEnter(suppress = Throwable.class)
        public static void onEnter(
                @Advice.Argument(1) Object target, @Advice.Argument(2) Object hitData) {
            PvpShotClientLog.onClientHit(target, hitData);
        }
    }
}
