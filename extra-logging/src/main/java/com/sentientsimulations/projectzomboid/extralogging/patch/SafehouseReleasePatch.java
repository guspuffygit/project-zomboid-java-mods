package com.sentientsimulations.projectzomboid.extralogging.patch;

import com.sentientsimulations.projectzomboid.extralogging.events.SafehouseReleasedEvent;
import io.pzstorm.storm.core.StormClassTransformer;
import io.pzstorm.storm.event.core.StormEventDispatcher;
import java.util.ArrayList;
import java.util.StringJoiner;
import net.bytebuddy.asm.Advice;
import net.bytebuddy.dynamic.ClassFileLocator;
import net.bytebuddy.dynamic.DynamicType;
import net.bytebuddy.matcher.ElementMatchers;
import net.bytebuddy.pool.TypePool;
import zombie.core.raknet.UdpConnection;
import zombie.iso.areas.SafeHouse;
import zombie.network.fields.SafehouseID;

/**
 * Patches {@link zombie.network.packets.safehouse.SafehouseReleasePacket} to dispatch an event when
 * a safehouse is released.
 */
public class SafehouseReleasePatch extends StormClassTransformer {

    public SafehouseReleasePatch() {
        super("zombie.network.packets.safehouse.SafehouseReleasePacket");
    }

    @Override
    public DynamicType.Builder<Object> dynamicType(
            ClassFileLocator locator, TypePool typePool, DynamicType.Builder<Object> builder) {
        return builder.visit(
                Advice.to(ProcessServerAdvice.class).on(ElementMatchers.named("processServer")));
    }

    public static class ProcessServerAdvice {

        @Advice.OnMethodEnter(suppress = Throwable.class)
        public static void beforeProcessServer(
                @Advice.This SafehouseID self, @Advice.Argument(1) UdpConnection connection) {

            SafeHouse safehouse = self.getSafehouse();
            if (safehouse == null) {
                return;
            }

            String owner = safehouse.getOwner();
            ArrayList<String> players = safehouse.getPlayers();
            StringJoiner joiner = new StringJoiner(", ");
            for (String p : players) {
                if (!p.equals(owner)) {
                    joiner.add(p);
                }
            }

            StormEventDispatcher.dispatchEvent(
                    new SafehouseReleasedEvent(
                            owner,
                            connection.getSteamId(),
                            safehouse.getX(),
                            safehouse.getY(),
                            safehouse.getW(),
                            safehouse.getH(),
                            safehouse.getTitle(),
                            joiner.toString()));
        }
    }
}
