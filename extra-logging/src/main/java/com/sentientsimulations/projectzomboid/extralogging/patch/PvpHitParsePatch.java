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
 * Server only. Captures each PvP hit's {@code isIgnoreDamage} flag as it came off the wire. Hooks
 * the superclass {@code PlayerHit.parse}, whose exit runs inside {@code
 * PlayerHitPlayerPacket.parse} and so before any mod's exit advice on that method.
 *
 * <p>Re-validate on game updates: assumes {@code PlayerHit.parse} still fills {@code hits}.
 */
public class PvpHitParsePatch extends StormClassTransformer {

    static final String TARGET = "zombie.network.packets.hit.PlayerHit";
    static final String ADVICE = PvpHitParsePatch.class.getName() + "$ParseAdvice";

    public PvpHitParsePatch() {
        super(TARGET);
    }

    @Override
    public DynamicType.Builder<Object> dynamicType(
            ClassFileLocator locator, TypePool typePool, DynamicType.Builder<Object> builder) {
        ElementMatcher.Junction<MethodDescription> parse =
                ElementMatchers.named("parse").and(ElementMatchers.takesArguments(2));
        PatchTargets.require(typePool, TARGET, parse, "parse(ByteBufferReader, IConnection)");
        return builder.visit(Advice.to(typePool.describe(ADVICE).resolve(), locator).on(parse));
    }

    public static class ParseAdvice {

        @Advice.OnMethodExit(suppress = Throwable.class)
        public static void onExit(@Advice.This Object self) {
            PvpHitServerLog.afterParse(self);
        }
    }
}
