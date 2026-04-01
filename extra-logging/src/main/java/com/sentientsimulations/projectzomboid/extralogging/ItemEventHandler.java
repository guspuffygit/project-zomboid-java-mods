package com.sentientsimulations.projectzomboid.extralogging;

import io.pzstorm.storm.event.packet.*;
import io.pzstorm.storm.lua.StormKahluaTable;
import se.krka.kahlua.vm.KahluaTableIterator;
import zombie.inventory.types.Food;

public class ItemEventHandler {

    private static final ch.qos.logback.classic.Logger logger =
            ExtraLoggerFactory.createLogger("items");

    public static void onAddInventoryItemToContainer(AddInventoryItemToContainerPacketEvent event) {
        try {
            logger.info(
                    "{}: steamId={}, user={}, pos=({},{},{}), container={}, items={}",
                    event.getName(),
                    event.steamId,
                    event.username,
                    event.getX(),
                    event.getY(),
                    0,
                    event.getContainerId(),
                    event.getItems() != null ? event.getItems().size() : 0);
        } catch (Exception e) {
            logger.error("Failed to log onAddInventoryItemToContainer", e);
        }
    }

    public static void onAddItemToMap(AddItemToMapPacketEvent event) {
        try {
            logger.info(
                    "{}: steamId={}, user={}, object={}",
                    event.getName(),
                    event.steamId,
                    event.username,
                    event.getIsoObject());
        } catch (Exception e) {
            logger.error("Failed to log onAddItemToMap", e);
        }
    }

    public static void onNetTimedAction(NetTimedActionPacketEvent event) {
        try {
            String extraLog = "";
            if (event.getActionType().equals("ISMoveablesAction")) {
                String spriteName = event.getAction().getString("origSpriteName");
                String mode = event.getAction().getString("mode");
                extraLog += ", spriteName=%s, mode=%s".formatted(spriteName, mode);
            } else if (event.getActionType().equals("ISDropWorldItemAction")) {
                Object item = event.getAction().rawget("item");
                extraLog += ", item=%s".formatted(item);
            } else if (event.getActionType().equals("ISEatFoodAction")) {
                Double percentage = event.getAction().getDouble("percentage");
                extraLog += ", percentage=%s".formatted(percentage);

                Object foodObject = event.getAction().rawget("item");
                if (foodObject instanceof Food food) {
                    extraLog += ", foodName=%s".formatted(food.getName());
                }
            }

            logger.info(
                    "{}: steamId={}, user={}, pos=({},{},{}), actionType={}, usingTimeout={}{}",
                    event.getName(),
                    event.steamId,
                    event.username,
                    event.getPlayerId().getX(),
                    event.getPlayerId().getY(),
                    event.getPlayerId().getZ(),
                    event.getActionType(),
                    event.getIsUsingTimeout(),
                    extraLog);
        } catch (Exception e) {
            logger.error("Failed to log onNetTimedAction", e);
        }
    }

    public static void onPlayerDropHeldItems(PlayerDropHeldItemsPacketEvent event) {
        try {
            logger.info(
                    "{}: steamId={}, user={}, pos=({},{},{}), heavy={}, throw={}",
                    event.getName(),
                    event.steamId,
                    event.username,
                    event.getX(),
                    event.getY(),
                    event.getZ(),
                    event.isHeavy(),
                    event.isThrow());
        } catch (Exception e) {
            logger.error("Failed to log onPlayerDropHeldItems", e);
        }
    }

    public static void onRemoveItemFromSquare(RemoveItemFromSquarePacketEvent event) {
        try {
            logger.info(
                    "{}: steamId={}, user={}, pos=({},{},{}), index={}",
                    event.getName(),
                    event.steamId,
                    event.username,
                    event.getX(),
                    event.getY(),
                    event.getZ(),
                    event.getIndex());
        } catch (Exception e) {
            logger.error("Failed to log onRemoveItemFromSquare", e);
        }
    }

    public static void onSledgehammerDestroy(SledgehammerDestroyPacketEvent event) {
        try {
            logger.info(
                    "{}: steamId={}, user={}, pos=({},{},{}), index={}",
                    event.getName(),
                    event.steamId,
                    event.username,
                    event.getX(),
                    event.getY(),
                    event.getZ(),
                    event.getIndex());
        } catch (Exception e) {
            logger.error("Failed to log onSledgehammerDestroy", e);
        }
    }

    public static void onBuildAction(BuildActionPacketEvent event) {
        try {
            StormKahluaTable item = event.getItem();
            String itemName = item != null ? item.getString("name") : null;

            logger.info(
                    "{}: steamId={}, user={}, pos=({},{},{}), type={}, name={}",
                    event.getName(),
                    event.steamId,
                    event.username,
                    event.getX(),
                    event.getY(),
                    event.getZ(),
                    event.getObjectType(),
                    itemName);

            if (item != null) {
                KahluaTableIterator it = item.iterator();
                while (it.advance()) {
                    logger.debug("  item key={}, value={}", it.getKey(), it.getValue());
                }
            }
        } catch (Exception e) {
            logger.error("Failed to log onBuildAction", e);
        }
    }
}
