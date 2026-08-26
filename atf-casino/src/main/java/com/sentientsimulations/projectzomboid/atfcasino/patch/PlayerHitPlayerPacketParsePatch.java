package com.sentientsimulations.projectzomboid.atfcasino.patch;

import io.pzstorm.storm.core.StormClassTransformer;
import net.bytebuddy.asm.Advice;
import net.bytebuddy.dynamic.ClassFileLocator;
import net.bytebuddy.dynamic.DynamicType;
import net.bytebuddy.matcher.ElementMatchers;
import net.bytebuddy.pool.TypePool;
import zombie.core.network.ByteBufferReader;
import zombie.network.IConnection;

/**
 * Observes {@code PlayerHitPlayerPacket.parse} on the server so attacks on the casino NPCs reach
 * {@link com.sentientsimulations.projectzomboid.atfcasino.npc.CasinoAssaultWatch}. A hook this
 * early is required because the NPC targets are not in {@code IDToPlayerMap}: vanilla drops the
 * packet at {@code isConsistent} and neither {@code processServer} nor Storm's packet events ever
 * fire for them. Behaviour is unchanged — the packet is still dropped, the hit still does nothing.
 *
 * <p>The security mod also patches this class (wielder-ownership gate on {@code isConsistent});
 * Storm chains transformers per class, and the two touch different methods.
 */
public class PlayerHitPlayerPacketParsePatch extends StormClassTransformer {

    private static final String ADVICE =
            "com.sentientsimulations.projectzomboid.atfcasino.advice.PlayerHitPlayerPacketParseAdvice";

    public PlayerHitPlayerPacketParsePatch() {
        super("zombie.network.packets.hit.PlayerHitPlayerPacket");
    }

    @Override
    public DynamicType.Builder<Object> dynamicType(
            ClassFileLocator locator, TypePool typePool, DynamicType.Builder<Object> builder) {
        return builder.visit(
                Advice.to(typePool.describe(ADVICE).resolve(), locator)
                        .on(
                                ElementMatchers.named("parse")
                                        .and(
                                                ElementMatchers.takesArguments(
                                                        ByteBufferReader.class,
                                                        IConnection.class))));
    }
}
