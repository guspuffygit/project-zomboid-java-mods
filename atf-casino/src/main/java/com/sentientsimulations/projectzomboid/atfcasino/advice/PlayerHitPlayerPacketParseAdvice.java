package com.sentientsimulations.projectzomboid.atfcasino.advice;

import com.sentientsimulations.projectzomboid.atfcasino.npc.CasinoAssaultWatch;
import net.bytebuddy.asm.Advice;
import zombie.network.IConnection;
import zombie.network.packets.hit.PlayerHitPlayerPacket;

/**
 * Exit advice on {@code PlayerHitPlayerPacket.parse}: hands every parsed player-hit packet to
 * {@link CasinoAssaultWatch} so hits on the casino NPCs are seen before vanilla drops them at
 * {@code isConsistent} (the NPC target never resolves from {@code IDToPlayerMap}).
 */
public class PlayerHitPlayerPacketParseAdvice {

    @Advice.OnMethodExit(suppress = Throwable.class)
    public static void onExit(
            @Advice.This PlayerHitPlayerPacket self, @Advice.Argument(1) IConnection connection) {
        CasinoAssaultWatch.onHitParsed(self, connection);
    }
}
