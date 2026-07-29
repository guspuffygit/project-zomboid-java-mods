package com.sentientsimulations.projectzomboid.extralogging;

import io.pzstorm.storm.event.packet.*;
import io.pzstorm.storm.lua.StormKahluaTable;
import java.lang.reflect.Field;
import java.util.List;
import java.util.stream.Collectors;
import se.krka.kahlua.vm.KahluaTableIterator;
import zombie.inventory.InventoryItem;
import zombie.inventory.ItemContainer;
import zombie.inventory.types.Food;
import zombie.network.fields.ContainerID;
import zombie.scripting.entity.components.crafting.CraftRecipe;

public class ItemEventHandler {

    private static final org.slf4j.Logger logger = ExtraLoggerFactory.createLogger("items");

    /**
     * Since PZ 42.20.0 all client-initiated item movement (container-to-container and drops to the
     * floor) reaches the server as an {@code ItemTransactionPacket}; the packets this mod used to
     * log ({@code AddInventoryItemToContainer}, {@code AddItemToMap}) are server-to-client only and
     * never processed by the server anymore.
     *
     * <p>Fires after {@code processServer}, so {@code state} is the server's verdict: {@code
     * Accept} for a validated request, {@code Reject} for a failed one ({@code consistent} carries
     * the validation failure code, 0 = valid) or a client-side cancel.
     */
    public static void onItemTransaction(ItemTransactionPacketEvent event) {
        try {
            byte consistent = event.getPacket().consistent;
            Object state = event.getField("state");
            Object extra = event.getField("extra");
            List<?> entries = (List<?>) event.getField("entries");
            String entryLog =
                    entries == null
                            ? ""
                            : entries.stream()
                                    .map(ItemEventHandler::describeEntry)
                                    .collect(Collectors.joining("; "));

            logger.info(
                    "{}: steamId={}, user={}, state={}, consistent={}, extra={}, entries=[{}]",
                    event.getName(),
                    event.steamId,
                    event.username,
                    state,
                    consistent,
                    extra,
                    entryLog);
        } catch (Exception e) {
            logger.error("Failed to log onItemTransaction", e);
        }
    }

    /** Transaction.TransactionEntry is a protected class, so its fields are read reflectively. */
    private static String describeEntry(Object entry) {
        try {
            Integer itemId = (Integer) readEntryField(entry, "itemId");
            ContainerID source = (ContainerID) readEntryField(entry, "sourceId");
            ContainerID destination = (ContainerID) readEntryField(entry, "destinationId");
            String itemType = resolveItemType(itemId, source, destination);
            return "%s %s -> %s"
                    .formatted(
                            itemType != null ? itemType : "item#" + itemId,
                            describeContainer(source),
                            describeContainer(destination));
        } catch (Exception e) {
            return "unreadable entry: " + e;
        }
    }

    private static Object readEntryField(Object entry, String name)
            throws ReflectiveOperationException {
        Field field = entry.getClass().getDeclaredField(name);
        field.setAccessible(true);
        return field.get(entry);
    }

    private static String resolveItemType(
            Integer itemId, ContainerID source, ContainerID destination) {
        if (itemId == null) {
            return null;
        }
        InventoryItem item = findItem(source, itemId);
        if (item == null) {
            item = findItem(destination, itemId);
        }
        return item != null ? item.getFullType() : null;
    }

    private static InventoryItem findItem(ContainerID containerId, int itemId) {
        ItemContainer container = containerId != null ? containerId.getContainer() : null;
        return container != null ? container.getItemWithID(itemId) : null;
    }

    private static String describeContainer(ContainerID containerId) {
        if (containerId == null) {
            return "null";
        }
        return "%s(%d,%d,%d)"
                .formatted(containerId.containerType, containerId.x, containerId.y, containerId.z);
    }

    public static void onNetTimedAction(NetTimedActionPacketEvent event) {
        try {
            String extraLog = "";
            try {
                if (event.getActionType().equals("ISMoveablesAction")) {
                    String spriteName = event.getAction().getString("origSpriteName");
                    String mode = event.getAction().getString("mode");
                    extraLog += ", spriteName=%s, mode=%s".formatted(spriteName, mode);
                } else if (event.getActionType().equals("ISDropWorldItemAction")) {
                    Object item = event.getAction().rawget("item");
                    if (item instanceof InventoryItem inventoryItem) {
                        extraLog +=
                                ", %s=%s"
                                        .formatted(
                                                inventoryItem.getClass().getSimpleName(),
                                                inventoryItem.getFullType());
                    } else {
                        extraLog += ", item=%s".formatted(item);
                    }
                } else if (event.getActionType().equals("ISEatFoodAction")) {
                    Double percentage = event.getAction().getDouble("percentage");
                    extraLog += ", percentage=%s".formatted(percentage);

                    Object foodObject = event.getAction().rawget("item");
                    if (foodObject instanceof Food food) {
                        extraLog += ", foodName=%s".formatted(food.getName());
                    }
                } else if (event.getActionType().equals("ISHandcraftAction")) {
                    Object craftRecipeObject = event.getAction().rawget("craftRecipe");
                    if (craftRecipeObject instanceof CraftRecipe craftRecipe) {
                        extraLog += ", craftItem=%s".formatted(craftRecipe.getName());
                    }
                } else if (event.getActionType().equals("ISEquipWeaponAction")
                        || event.getActionType().equals("ISUnequipAction")
                        || event.getActionType().equals("ISWearClothing")) {
                    Object itemObject = event.getAction().rawget("item");
                    if (itemObject instanceof InventoryItem inventoryItem) {
                        extraLog +=
                                ", %s=%s"
                                        .formatted(
                                                inventoryItem.getClass().getSimpleName(),
                                                inventoryItem.getFullType());
                    }
                } else if (event.getActionType().equals("ISBuildIsoEntity")) {

                }
            } catch (Exception e) {
                logger.error("Unable to add extraLog information to {}", event.getActionType(), e);
            }

            logger.info(
                    "{}: steamId={}, user={}, pos=({},{},{}), actionType={}{}",
                    event.getName(),
                    event.steamId,
                    event.username,
                    event.getPlayerId().getX(),
                    event.getPlayerId().getY(),
                    event.getPlayerId().getZ(),
                    event.getActionType(),
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
            Object craftRecipeObject = item.rawget("craftRecipe");
            String translationName = "";
            if (craftRecipeObject instanceof CraftRecipe craftRecipe) {
                translationName = craftRecipe.getTranslationName();
            }

            logger.info(
                    "{}: steamId={}, user={}, pos=({},{},{}), type={}, name={}, translationName={}",
                    event.getName(),
                    event.steamId,
                    event.username,
                    event.getX(),
                    event.getY(),
                    event.getZ(),
                    event.getObjectType(),
                    itemName,
                    translationName);

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
