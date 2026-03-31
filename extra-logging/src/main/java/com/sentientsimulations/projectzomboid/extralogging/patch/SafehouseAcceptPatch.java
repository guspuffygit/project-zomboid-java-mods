package com.sentientsimulations.projectzomboid.extralogging.patch;

import com.sentientsimulations.projectzomboid.extralogging.events.SafehouseInviteRespondedEvent;
import io.pzstorm.storm.core.StormClassTransformer;
import io.pzstorm.storm.event.core.StormEventDispatcher;
import net.bytebuddy.asm.Advice;
import net.bytebuddy.dynamic.ClassFileLocator;
import net.bytebuddy.dynamic.DynamicType;
import net.bytebuddy.matcher.ElementMatchers;
import net.bytebuddy.pool.TypePool;
import zombie.core.raknet.UdpConnection;
import zombie.iso.areas.SafeHouse;
import zombie.network.fields.SafehouseID;

/**
 * Patches {@link zombie.network.packets.safehouse.SafehouseAcceptPacket} to dispatch an event when
 * a player responds to a safehouse invite.
 */
public class SafehouseAcceptPatch extends StormClassTransformer {

    public SafehouseAcceptPatch() {
        super("zombie.network.packets.safehouse.SafehouseAcceptPacket");
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
                @Advice.This SafehouseID self,
                @Advice.FieldValue("owner") String owner,
                @Advice.FieldValue("invited") String invited,
                @Advice.FieldValue("isAccepted") boolean isAccepted,
                @Advice.Argument(1) UdpConnection connection) {

            SafeHouse safehouse = self.getSafehouse();
            if (safehouse == null || owner == null || invited == null) {
                return;
            }

            StormEventDispatcher.dispatchEvent(
                    new SafehouseInviteRespondedEvent(
                            invited,
                            owner,
                            isAccepted,
                            connection.getSteamId(),
                            safehouse.getX(),
                            safehouse.getY(),
                            safehouse.getW(),
                            safehouse.getH(),
                            safehouse.getTitle()));
        }
    }
}
