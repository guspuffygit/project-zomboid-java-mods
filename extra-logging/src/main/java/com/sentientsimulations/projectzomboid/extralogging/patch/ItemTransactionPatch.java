package com.sentientsimulations.projectzomboid.extralogging.patch;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import io.pzstorm.storm.core.StormClassTransformer;
import io.pzstorm.storm.patch.networking.PacketReceivedPatch;
import net.bytebuddy.asm.Advice;
import net.bytebuddy.dynamic.ClassFileLocator;
import net.bytebuddy.dynamic.DynamicType;
import net.bytebuddy.matcher.ElementMatchers;
import net.bytebuddy.pool.TypePool;
import zombie.core.Transaction;
import zombie.core.raknet.UdpConnection;
import zombie.inventory.InventoryItem;
import zombie.inventory.ItemContainer;
import zombie.iso.IsoDirections;
import zombie.network.fields.ContainerID;
import zombie.network.fields.character.PlayerID;

/**
 * Patches {@link zombie.network.packets.ItemTransactionPacket} to log all packet fields for
 * debugging item movements. Event dispatching is handled by {@link PacketReceivedPatch}.
 */
public class ItemTransactionPatch extends StormClassTransformer {

    public ItemTransactionPatch() {
        super("zombie.network.packets.ItemTransactionPacket");
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
                @Advice.FieldValue("id") byte txId,
                @Advice.FieldValue("state") Transaction.TransactionState state,
                @Advice.FieldValue("itemId") int itemId,
                @Advice.FieldValue("playerId") PlayerID playerId,
                @Advice.FieldValue("sourceId") ContainerID sourceId,
                @Advice.FieldValue("destinationId") ContainerID destinationId,
                @Advice.FieldValue("extra") String extra,
                @Advice.FieldValue("direction") IsoDirections direction,
                @Advice.FieldValue("xoff") float xoff,
                @Advice.FieldValue("yoff") float yoff,
                @Advice.FieldValue("zoff") float zoff,
                @Advice.FieldValue("consistent") byte consistent,
                @Advice.Argument(1) UdpConnection connection) {

            // Log all packet fields for every transaction
            LOGGER.info(
                    "[ItemTransactionPatch] === PACKET DUMP === user={}, steamId={}",
                    connection.getUserName(),
                    connection.getSteamId());
            LOGGER.info(
                    "[ItemTransactionPatch]   txId={}, state={}, itemId={}, consistent={}",
                    txId,
                    state,
                    itemId,
                    consistent);
            LOGGER.info(
                    "[ItemTransactionPatch]   playerId={}", playerId != null ? playerId : "null");
            LOGGER.info(
                    "[ItemTransactionPatch]   extra={}, direction={}, offsets=({}, {}, {})",
                    extra,
                    direction,
                    xoff,
                    yoff,
                    zoff);

            // Log source container details
            if (sourceId != null) {
                LOGGER.info(
                        "[ItemTransactionPatch]   source: type={}, pos=({},{},{}), worldItemId={}",
                        sourceId.containerType,
                        sourceId.x,
                        sourceId.y,
                        sourceId.z,
                        sourceId.worldItemId);
            } else {
                LOGGER.info("[ItemTransactionPatch]   source: null");
            }

            // Log destination container details
            if (destinationId != null) {
                LOGGER.info(
                        "[ItemTransactionPatch]   dest: type={}, pos=({},{},{}), worldItemId={}",
                        destinationId.containerType,
                        destinationId.x,
                        destinationId.y,
                        destinationId.z,
                        destinationId.worldItemId);
            } else {
                LOGGER.info("[ItemTransactionPatch]   dest: null");
            }

            // Try to resolve item details from source container
            if (sourceId != null) {
                ItemContainer sourceContainer = sourceId.getContainer();
                if (sourceContainer != null) {
                    InventoryItem item = sourceContainer.getItemWithID(itemId);
                    if (item != null) {
                        LOGGER.info(
                                "[ItemTransactionPatch]   resolvedItem: fullType={}, name={}, displayName={}",
                                item.getFullType(),
                                item.getName(),
                                item.getDisplayName());
                    } else {
                        LOGGER.info(
                                "[ItemTransactionPatch]   resolvedItem: not found in source container for id={}",
                                itemId);
                    }
                } else {
                    LOGGER.info("[ItemTransactionPatch]   resolvedItem: source container is null");
                }
            }

            // Try to resolve item details from destination container
            if (destinationId != null) {
                ItemContainer destContainer = destinationId.getContainer();
                if (destContainer != null) {
                    InventoryItem item = destContainer.getItemWithID(itemId);
                    if (item != null) {
                        LOGGER.info(
                                "[ItemTransactionPatch]   destResolvedItem: fullType={}, name={}, displayName={}",
                                item.getFullType(),
                                item.getName(),
                                item.getDisplayName());
                    } else {
                        LOGGER.info(
                                "[ItemTransactionPatch]   destResolvedItem: not found in dest container for id={}",
                                itemId);
                    }
                } else {
                    LOGGER.info(
                            "[ItemTransactionPatch]   destResolvedItem: dest container is null");
                }
            }

            LOGGER.info("[ItemTransactionPatch] === END PACKET DUMP ===");
        }
    }
}
