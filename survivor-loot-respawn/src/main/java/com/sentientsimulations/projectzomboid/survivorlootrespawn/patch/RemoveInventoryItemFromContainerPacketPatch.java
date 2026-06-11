package com.sentientsimulations.projectzomboid.survivorlootrespawn.patch;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import com.sentientsimulations.projectzomboid.survivorlootrespawn.ContainerLootedEvent;
import io.pzstorm.storm.core.StormClassTransformer;
import io.pzstorm.storm.event.core.StormEventDispatcher;
import java.lang.reflect.Field;
import net.bytebuddy.asm.Advice;
import net.bytebuddy.dynamic.ClassFileLocator;
import net.bytebuddy.dynamic.DynamicType;
import net.bytebuddy.matcher.ElementMatchers;
import net.bytebuddy.pool.TypePool;
import zombie.characters.IsoPlayer;
import zombie.core.raknet.UdpConnection;
import zombie.inventory.ItemContainer;
import zombie.network.fields.ContainerID;
import zombie.network.packets.RemoveInventoryItemFromContainerPacket;

public class RemoveInventoryItemFromContainerPacketPatch extends StormClassTransformer {

    private static final String ADVICE =
            "com.sentientsimulations.projectzomboid.survivorlootrespawn.patch.RemoveInventoryItemFromContainerPacketProcessServerAdvice";

    public RemoveInventoryItemFromContainerPacketPatch() {
        super("zombie.network.packets.RemoveInventoryItemFromContainerPacket");
    }

    @Override
    public DynamicType.Builder<Object> dynamicType(
            ClassFileLocator locator, TypePool typePool, DynamicType.Builder<Object> builder) {
        return builder.visit(
                Advice.to(typePool.describe(ADVICE).resolve(), locator)
                        .on(ElementMatchers.named("processServer")));
    }

    private static volatile Field containerIdField;

    private static synchronized void initFieldHandles() throws ReflectiveOperationException {
        if (containerIdField != null) {
            return;
        }
        Field f = RemoveInventoryItemFromContainerPacket.class.getDeclaredField("containerId");
        f.setAccessible(true);
        containerIdField = f;
    }

    public static void dispatch(
            RemoveInventoryItemFromContainerPacket packet, UdpConnection connection) {
        try {
            if (containerIdField == null) {
                initFieldHandles();
            }
            ContainerID containerId = (ContainerID) containerIdField.get(packet);
            ItemContainer container = containerId.getContainer();
            if (container == null) {
                return;
            }
            IsoPlayer player = connection.players[0];
            StormEventDispatcher.dispatchEvent(
                    new ContainerLootedEvent(
                            player, container, containerId.x, containerId.y, containerId.z));
        } catch (Throwable t) {
            LOGGER.error("RemoveInventoryItemFromContainerPacketPatch.dispatch threw", t);
        }
    }
}
