package com.sentientsimulations.projectzomboid.survivorlootrespawn.patch;

import net.bytebuddy.asm.Advice;
import zombie.core.raknet.UdpConnection;
import zombie.network.packets.RemoveInventoryItemFromContainerPacket;

public class RemoveInventoryItemFromContainerPacketProcessServerAdvice {

    @Advice.OnMethodExit(suppress = Throwable.class)
    public static void onExit(
            @Advice.This RemoveInventoryItemFromContainerPacket self,
            @Advice.Argument(1) UdpConnection connection) {
        RemoveInventoryItemFromContainerPacketPatch.dispatch(self, connection);
    }
}
