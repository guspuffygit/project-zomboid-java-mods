package com.sentientsimulations.projectzomboid.extralogging.patch;

import com.sentientsimulations.projectzomboid.extralogging.events.SafezoneClaimedEvent;
import io.pzstorm.storm.core.StormClassTransformer;
import io.pzstorm.storm.event.core.StormEventDispatcher;
import net.bytebuddy.asm.Advice;
import net.bytebuddy.dynamic.ClassFileLocator;
import net.bytebuddy.dynamic.DynamicType;
import net.bytebuddy.matcher.ElementMatchers;
import net.bytebuddy.pool.TypePool;
import zombie.characters.IsoPlayer;
import zombie.core.raknet.UdpConnection;

/**
 * Patches {@link zombie.network.packets.safehouse.SafezoneClaimPacket} to dispatch an event when an
 * admin creates a safezone.
 */
public class SafezoneClaimPatch extends StormClassTransformer {

    public SafezoneClaimPatch() {
        super("zombie.network.packets.safehouse.SafezoneClaimPacket");
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
                @Advice.FieldValue("x") int x,
                @Advice.FieldValue("y") int y,
                @Advice.FieldValue("w") int w,
                @Advice.FieldValue("h") int h,
                @Advice.FieldValue("title") String title,
                @Advice.Argument(1) UdpConnection connection) {

            if (player == null) {
                return;
            }

            StormEventDispatcher.dispatchEvent(
                    new SafezoneClaimedEvent(
                            player.getUsername(), connection.getSteamId(), x, y, w, h, title));
        }
    }
}
