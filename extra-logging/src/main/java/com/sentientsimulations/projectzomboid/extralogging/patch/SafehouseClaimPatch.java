package com.sentientsimulations.projectzomboid.extralogging.patch;

import com.sentientsimulations.projectzomboid.extralogging.events.SafehouseClaimedEvent;
import io.pzstorm.storm.core.StormClassTransformer;
import io.pzstorm.storm.event.core.StormEventDispatcher;
import net.bytebuddy.asm.Advice;
import net.bytebuddy.dynamic.ClassFileLocator;
import net.bytebuddy.dynamic.DynamicType;
import net.bytebuddy.matcher.ElementMatchers;
import net.bytebuddy.pool.TypePool;
import zombie.characters.IsoPlayer;
import zombie.core.raknet.UdpConnection;
import zombie.iso.areas.SafeHouse;

/**
 * Patches {@link zombie.network.packets.safehouse.SafehouseClaimPacket} to dispatch an event when a
 * player claims a safehouse.
 */
public class SafehouseClaimPatch extends StormClassTransformer {

    public SafehouseClaimPatch() {
        super("zombie.network.packets.safehouse.SafehouseClaimPacket");
    }

    @Override
    public DynamicType.Builder<Object> dynamicType(
            ClassFileLocator locator, TypePool typePool, DynamicType.Builder<Object> builder) {
        return builder.visit(
                Advice.to(ProcessServerAdvice.class).on(ElementMatchers.named("processServer")));
    }

    public static class ProcessServerAdvice {

        @Advice.OnMethodExit(suppress = Throwable.class)
        public static void afterProcessServer(
                @Advice.FieldValue("player") IsoPlayer player,
                @Advice.Argument(1) UdpConnection connection) {

            if (player == null) {
                return;
            }

            String username = player.getUsername();
            SafeHouse safehouse = SafeHouse.getSafehouseByOwner(username);
            if (safehouse == null) {
                return;
            }

            StormEventDispatcher.dispatchEvent(
                    new SafehouseClaimedEvent(
                            username,
                            connection.getSteamId(),
                            safehouse.getX(),
                            safehouse.getY(),
                            safehouse.getW(),
                            safehouse.getH(),
                            safehouse.getTitle()));
        }
    }
}
