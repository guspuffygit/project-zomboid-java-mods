package com.sentientsimulations.projectzomboid.extralogging;

import io.pzstorm.storm.event.core.SubscribeEvent;
import io.pzstorm.storm.event.packet.*;

public class ItemEventHandler {

    private static final ch.qos.logback.classic.Logger logger =
            ExtraLoggerFactory.createLogger("items");

    @SubscribeEvent
    public static void onAddInventoryItemToContainer(AddInventoryItemToContainerPacketEvent event) {
        try {
            logger.info("{}: steamId={}, user={}, pos=({},{},{}), container={}, items={}", event.getName(), event.steamId, event.username, event.getX(), event.getY(), 0, event.getContainerId(), event.getItems() != null ? event.getItems().size() : 0);
        } catch (Exception e) {
            logger.error("Failed to log onAddInventoryItemToContainer", e);
        }
    }

    @SubscribeEvent
    public static void onAddItemToMap(AddItemToMapPacketEvent event) {
        try {
            logger.info("{}: steamId={}, user={}, object={}", event.getName(), event.steamId, event.username, event.getIsoObject());
        } catch (Exception e) {
            logger.error("Failed to log onAddItemToMap", e);
        }
    }

    @SubscribeEvent
    public static void onBuildAction(BuildActionPacketEvent event) {
        try {
            logger.info("{}: steamId={}, user={}, pos=({},{},{}), sprite={}, type={}, north={}", event.getName(), event.steamId, event.username, event.getX(), event.getY(), event.getZ(), event.getSpriteName(), event.getObjectType(), event.isNorth());
        } catch (Exception e) {
            logger.error("Failed to log onBuildAction", e);
        }
    }

    @SubscribeEvent
    public static void onNetTimedAction(NetTimedActionPacketEvent event) {
        try {
            logger.info("{}: steamId={}, user={}, actionType={}, actionName={}, usingTimeout={}", event.getName(), event.steamId, event.username, event.getActionType(), event.getActionName(), event.getIsUsingTimeout());
        } catch (Exception e) {
            logger.error("Failed to log onNetTimedAction", e);
        }
    }

    @SubscribeEvent
    public static void onPlayerDropHeldItems(PlayerDropHeldItemsPacketEvent event) {
        try {
            logger.info("{}: steamId={}, user={}, pos=({},{},{}), heavy={}, throw={}", event.getName(), event.steamId, event.username, event.getX(), event.getY(), event.getZ(), event.isHeavy(), event.isThrow());
        } catch (Exception e) {
            logger.error("Failed to log onPlayerDropHeldItems", e);
        }
    }

    @SubscribeEvent
    public static void onRemoveItemFromSquare(RemoveItemFromSquarePacketEvent event) {
        try {
            logger.info("{}: steamId={}, user={}, pos=({},{},{}), index={}", event.getName(), event.steamId, event.username, event.getX(), event.getY(), event.getZ(), event.getIndex());
        } catch (Exception e) {
            logger.error("Failed to log onRemoveItemFromSquare", e);
        }
    }

    @SubscribeEvent
    public static void onSledgehammerDestroy(SledgehammerDestroyPacketEvent event) {
        try {
            logger.info("{}: steamId={}, user={}, pos=({},{},{}), index={}", event.getName(), event.steamId, event.username, event.getX(), event.getY(), event.getZ(), event.getIndex());
        } catch (Exception e) {
            logger.error("Failed to log onSledgehammerDestroy", e);
        }
    }
}
