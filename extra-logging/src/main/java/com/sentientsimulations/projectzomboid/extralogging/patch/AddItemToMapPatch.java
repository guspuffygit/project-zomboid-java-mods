package com.sentientsimulations.projectzomboid.extralogging.patch;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import com.sentientsimulations.projectzomboid.extralogging.events.ItemPlacedOnMapEvent;
import io.pzstorm.storm.core.StormClassTransformer;
import io.pzstorm.storm.event.core.StormEventDispatcher;
import net.bytebuddy.asm.Advice;
import net.bytebuddy.dynamic.ClassFileLocator;
import net.bytebuddy.dynamic.DynamicType;
import net.bytebuddy.matcher.ElementMatchers;
import net.bytebuddy.pool.TypePool;
import zombie.core.raknet.UdpConnection;
import zombie.iso.IsoObject;
import zombie.iso.objects.IsoWorldInventoryObject;

/**
 * Patches {@link zombie.network.packets.AddItemToMapPacket} to dispatch an event when a player
 * places an item or object on the map.
 */
public class AddItemToMapPatch extends StormClassTransformer {

    public AddItemToMapPatch() {
        super("zombie.network.packets.AddItemToMapPacket");
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
                @Advice.FieldValue("obj") IsoObject obj,
                @Advice.Argument(1) UdpConnection connection) {

            LOGGER.info(
                    "[AddItemToMapPatch] advice entered: obj={}, square={}",
                    obj != null ? obj.getClass().getSimpleName() : "null",
                    obj != null ? obj.square : "n/a");

            if (obj == null || obj.square == null) {
                LOGGER.debug("[AddItemToMapPatch] skipped: obj or square is null");
                return;
            }

            String itemType;
            boolean isWorldInventoryItem;
            if (obj instanceof IsoWorldInventoryObject worldInventoryObject) {
                itemType = worldInventoryObject.getItem().getFullType();
                isWorldInventoryItem = true;
            } else {
                itemType = obj.getName() != null ? obj.getName() : obj.getObjectName();
                isWorldInventoryItem = false;
            }

            LOGGER.debug("[AddItemToMapPatch] dispatching event for item={}", itemType);

            StormEventDispatcher.dispatchEvent(
                    new ItemPlacedOnMapEvent(
                            connection.getUserName(),
                            connection.getSteamId(),
                            itemType,
                            obj.getXi(),
                            obj.getYi(),
                            obj.getZi(),
                            isWorldInventoryItem));
        }
    }
}
