package com.sentientsimulations.projectzomboid.atfcasino.advice;

import com.sentientsimulations.projectzomboid.atfcasino.npc.CasinoAssaultWatch;
import net.bytebuddy.asm.Advice;
import zombie.network.packets.hit.PlayerHitPlayerPacket;

/**
 * Exit advice on {@code PlayerHitPlayerPacket.process}: hands every fully accepted player-on-player
 * hit to {@link CasinoAssaultWatch}. By the time {@code process} returns, vanilla has passed the
 * packet through {@code isConsistent} and every anticheat and applied the damage — so this only
 * fires for hits that actually hurt the victim.
 */
public class PlayerHitPlayerPacketProcessAdvice {

    @Advice.OnMethodExit(suppress = Throwable.class)
    public static void onExit(@Advice.This PlayerHitPlayerPacket self) {
        CasinoAssaultWatch.onPlayerHitProcessed(self);
    }
}
