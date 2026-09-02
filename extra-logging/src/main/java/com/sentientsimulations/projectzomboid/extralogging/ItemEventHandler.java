package com.sentientsimulations.projectzomboid.extralogging;

import io.pzstorm.storm.event.packet.*;
import io.pzstorm.storm.event.zomboid.OnItemTransferCompletedEvent;
import io.pzstorm.storm.lua.StormKahluaTable;
import java.lang.reflect.Field;
import java.util.List;
import java.util.Set;
import java.util.stream.Collectors;
import se.krka.kahlua.vm.KahluaTableIterator;
import zombie.characters.IsoPlayer;
import zombie.inventory.InventoryItem;
import zombie.inventory.ItemContainer;
import zombie.inventory.types.Food;
import zombie.iso.IsoGridSquare;
import zombie.iso.IsoObject;
import zombie.network.PZNetKahluaNull;
import zombie.network.PZNetKahluaTableImpl;
import zombie.network.fields.ContainerID;
import zombie.network.fields.NetObject;
import zombie.scripting.entity.components.crafting.CraftRecipe;

/**
 * Routes player activity into three files by what an investigation greps for, not by packet type.
 * {@code world.log} holds every change to the map (destroy, scrap, build, smash, barricade...),
 * {@code items.log} holds inventory movement, and {@code actions.log} takes the remaining timed
 * actions (vehicle doors, equip, eat...) that make up ~90% of the volume. Vehicle theft and
 * tampering actions go to {@code vehicles.log} next to PlayerHitVehicle.
 */
public class ItemEventHandler {

    private static final org.slf4j.Logger worldLogger =
            ExtraLoggerFactory.createLogger("world", "log", 5);
    private static final org.slf4j.Logger itemsLogger =
            ExtraLoggerFactory.createLogger("items", "log", 3);
    private static final org.slf4j.Logger actionsLogger =
            ExtraLoggerFactory.createLogger("actions");
    private static final org.slf4j.Logger vehiclesLogger = VehicleEventHandler.logger;

    private static final Set<String> WORLD_ACTIONS =
            Set.of(
                    "ISMoveablesAction",
                    "ISDestroyStuffAction",
                    "ISDismantleAction",
                    "LSIWScrap",
                    "LSIWAction",
                    "LSIWAddItems",
                    "ISLightActions",
                    "ISSmashWindow",
                    "ISRemoveBrokenGlass",
                    "ISRemoveGlass",
                    "ISPickupBrokenGlass",
                    "ISBarricadeAction",
                    "ISUnbarricadeAction",
                    "ISAddSheetRope",
                    "ISRemoveSheetRope",
                    "ISAddSheetAction",
                    "ISRemoveSheetAction",
                    "ISBuildAction",
                    "ISBuildIsoEntity",
                    "ISPaintAction",
                    "ISPlumbItem",
                    "ISPlaceTrap",
                    "ISRemoveTrapAction",
                    "ISTakeTrap",
                    "ISPlaceFishingNetAction",
                    "ISRemoveFishingNetAction",
                    "ISRemoveCampfireAction",
                    "ISPutOutCampfireAction",
                    "ISTakeGenerator",
                    "ISPlaceCarBatteryChargerAction",
                    "ISTakeCarBatteryChargerAction",
                    "ISChopTreeAction",
                    "ISRemoveBush",
                    "ISRemoveGrass",
                    "ISScything",
                    "ISShovelGround",
                    "ISShovelAction",
                    "ISPlowAction",
                    "ISDigGraveAction",
                    "ISFillGrave",
                    "ISBuryCorpse",
                    "ISPickUpGroundCoverItem",
                    "ISPickAxeGroundCoverItem",
                    "ISTakeBricks",
                    "ISLockDoor",
                    "ISLockDoors",
                    "ISPadlockAction",
                    "ISPadlockByCodeAction");

    private static final Set<String> ITEM_ACTIONS =
            Set.of(
                    "ISDropWorldItemAction",
                    "ISDropVehicleItemAction",
                    "ISGrabCorpseAction",
                    "ISGrabCorpseItem",
                    "ISDropCorpseIntoContainer",
                    "ISDropAnimalCorpseAndThen",
                    "ISThrowCorpseOverFence",
                    "ISThrowCorpseThroughWindow",
                    "ISDumpContentsAction",
                    "ISKillAnimalInInventory");

    private static final Set<String> VEHICLE_ACTIONS =
            Set.of(
                    "ISInstallVehiclePart",
                    "ISUninstallVehiclePart",
                    "ISAVCSUninstallVehiclePart",
                    "ISAVCSTakeEngineParts",
                    "ISHotwireVehicle",
                    "ISUnlockVehicleDoor",
                    "ISLockVehicleDoor",
                    "ISTakeGasolineFromVehicle",
                    "ISAddGasolineToVehicle",
                    "ISRefuelFromGasPump",
                    "ISRepairEngine",
                    "ISInflateTire",
                    "ISDeflateTire",
                    "ISStartVehicleEngine",
                    "ISWashVehicle");

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

            itemsLogger.info(
                    "{}: steamId={}, user={}, state={}, consistent={}, extra={}, entries=[{}]",
                    event.getName(),
                    event.steamId,
                    event.username,
                    state,
                    consistent,
                    extra,
                    entryLog);
        } catch (Exception e) {
            itemsLogger.error("Failed to log onItemTransaction", e);
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

    /**
     * Fires after {@code processServer}. {@code state} is the server verdict. {@code action} is
     * null when the server failed to rebuild the action from the client's args (typically the
     * referenced world object no longer exists server-side) — the server rejects those, and the raw
     * {@code actionArgs} are the only description left, so they are dumped instead.
     */
    public static void onNetTimedAction(NetTimedActionPacketEvent event) {
        try {
            String actionType = event.getActionType();
            String extraLog = "";
            try {
                if (event.getPacket().action == null) {
                    extraLog =
                            ", rejected=server-constructor-failed, args={%s}"
                                    .formatted(describeArgs(event.getActionArgs()));
                } else {
                    extraLog = describeAction(actionType, event.getAction());
                }
            } catch (Exception e) {
                loggerFor(actionType)
                        .error("Unable to add extraLog information to {}", actionType, e);
            }

            loggerFor(actionType)
                    .info(
                            "{}: steamId={}, user={}, pos=({},{},{}), state={}, actionType={}{}",
                            event.getName(),
                            event.steamId,
                            event.username,
                            event.getPlayerId().getX(),
                            event.getPlayerId().getY(),
                            event.getPlayerId().getZ(),
                            event.getField("state"),
                            actionType,
                            extraLog);
        } catch (Exception e) {
            actionsLogger.error("Failed to log onNetTimedAction", e);
        }
    }

    private static org.slf4j.Logger loggerFor(String actionType) {
        if (WORLD_ACTIONS.contains(actionType)) {
            return worldLogger;
        }
        if (ITEM_ACTIONS.contains(actionType)) {
            return itemsLogger;
        }
        if (VEHICLE_ACTIONS.contains(actionType)) {
            return vehiclesLogger;
        }
        return actionsLogger;
    }

    private static String describeAction(String actionType, StormKahluaTable action) {
        switch (actionType) {
            case "ISMoveablesAction":
                return ", spriteName=%s, mode=%s"
                                .formatted(
                                        action.getString("origSpriteName"),
                                        action.getString("mode"))
                        + describeWorldObject(action.rawget("object"));
            case "ISDestroyStuffAction":
                return describeWorldObject(action.rawget("item"));
            case "ISDismantleAction":
                return describeWorldObject(action.rawget("thumpable"));
            case "LSIWScrap":
                return describeWorldObject(action.rawget("obj"));
            case "ISLightActions":
                return ", mode=%s".formatted(action.getString("mode"))
                        + describeWorldObject(action.rawget("lightswitch"))
                        + describeItem("item", action.rawget("item"));
            case "ISDropWorldItemAction":
            case "ISEquipWeaponAction":
            case "ISUnequipAction":
            case "ISWearClothing":
                return describeItem(null, action.rawget("item"));
            case "ISEatFoodAction":
                String food = ", percentage=%s".formatted(action.getDouble("percentage"));
                if (action.rawget("item") instanceof Food foodItem) {
                    food += ", foodName=%s".formatted(foodItem.getName());
                }
                return food;
            case "ISHandcraftAction":
                if (action.rawget("craftRecipe") instanceof CraftRecipe craftRecipe) {
                    return ", craftItem=%s".formatted(craftRecipe.getName());
                }
                return "";
            default:
                return "";
        }
    }

    /** With a null label the item's class name is the key, matching the historical format. */
    private static String describeItem(String label, Object value) {
        if (value instanceof InventoryItem item) {
            String key = label != null ? label : item.getClass().getSimpleName();
            return ", %s=%s".formatted(key, item.getFullType());
        }
        return label != null ? ", %s=%s".formatted(label, value) : ", item=%s".formatted(value);
    }

    private static String describeArgs(PZNetKahluaTableImpl args) {
        if (args == null) {
            return "";
        }
        StringBuilder out = new StringBuilder();
        KahluaTableIterator it = args.iterator();
        while (it.advance()) {
            if (out.length() > 0) {
                out.append(", ");
            }
            out.append(it.getKey()).append('=').append(describeArgValue(it.getValue()));
        }
        return out.toString();
    }

    private static String describeArgValue(Object value) {
        if (value == null || value instanceof PZNetKahluaNull) {
            return "nil";
        }
        if (value instanceof InventoryItem item) {
            return item.getFullType();
        }
        if (value instanceof IsoPlayer player) {
            return player.getUsername();
        }
        if (value instanceof IsoGridSquare square) {
            return "square(%d,%d,%d)".formatted(square.getX(), square.getY(), square.getZ());
        }
        if (value instanceof IsoObject object) {
            return describeWorldObject(object).substring(", object=".length());
        }
        return String.valueOf(value);
    }

    /**
     * Scrap/dismantle/destroy actions are the only record of container and furniture destruction;
     * the player position alone can't say what was removed or from which square.
     */
    private static String describeWorldObject(Object target) {
        if (!(target instanceof IsoObject object)) {
            return ", object=%s".formatted(target);
        }
        String description =
                ", object=%s, objectName=%s".formatted(object.getSpriteName(), object.getName());
        IsoGridSquare square = object.getSquare();
        if (square != null) {
            description +=
                    ", objectPos=(%d,%d,%d)".formatted(square.getX(), square.getY(), square.getZ());
        }
        ItemContainer container = object.getContainer();
        if (container != null) {
            description +=
                    ", container=%s, containerItems=%d"
                            .formatted(container.getType(), container.getItems().size());
        }
        return description;
    }

    /**
     * Storm-routed transfers (floor pickups, container moves via StormTransfer.transferItem) never
     * reach the server as an ItemTransactionPacket, so cmd.txt only records the command name.
     */
    public static void onItemTransferCompleted(OnItemTransferCompletedEvent event) {
        try {
            IsoPlayer player = event.getPlayer();
            InventoryItem item = event.getItem();
            itemsLogger.info(
                    "{}: steamId={}, user={}, pos=({},{},{}), item={}, itemId={}, src={}, dest={}",
                    event.getName(),
                    player.getSteamID(),
                    player.getUsername(),
                    (int) player.getX(),
                    (int) player.getY(),
                    (int) player.getZ(),
                    item.getFullType(),
                    item.getID(),
                    event.getSrcRef(),
                    event.getDestRef());
        } catch (Exception e) {
            itemsLogger.error("Failed to log onItemTransferCompleted", e);
        }
    }

    public static void onPlayerDropHeldItems(PlayerDropHeldItemsPacketEvent event) {
        try {
            itemsLogger.info(
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
            itemsLogger.error("Failed to log onPlayerDropHeldItems", e);
        }
    }

    public static void onRemoveItemFromSquare(RemoveItemFromSquarePacketEvent event) {
        try {
            worldLogger.info(
                    "{}: steamId={}, user={}, pos=({},{},{}), index={}",
                    event.getName(),
                    event.steamId,
                    event.username,
                    event.getX(),
                    event.getY(),
                    event.getZ(),
                    event.getIndex());
        } catch (Exception e) {
            worldLogger.error("Failed to log onRemoveItemFromSquare", e);
        }
    }

    public static void onSledgehammerDestroy(SledgehammerDestroyPacketEvent event) {
        try {
            worldLogger.info(
                    "{}: steamId={}, user={}, pos=({},{},{}), index={}",
                    event.getName(),
                    event.steamId,
                    event.username,
                    event.getX(),
                    event.getY(),
                    event.getZ(),
                    event.getIndex());
        } catch (Exception e) {
            worldLogger.error("Failed to log onSledgehammerDestroy", e);
        }
    }

    /** {@code action} is a package-private enum, so it's logged via its name only. */
    public static void onSmashWindow(SmashWindowPacketEvent event) {
        try {
            Object action = event.getField("action");
            Object window = event.getField("window");
            Object target = window instanceof NetObject netObject ? netObject.getObject() : null;
            worldLogger.info(
                    "{}: steamId={}, user={}, action={}{}",
                    event.getName(),
                    event.steamId,
                    event.username,
                    action,
                    describeWorldObject(target));
        } catch (Exception e) {
            worldLogger.error("Failed to log onSmashWindow", e);
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

            worldLogger.info(
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
                    worldLogger.debug("  item key={}, value={}", it.getKey(), it.getValue());
                }
            }
        } catch (Exception e) {
            worldLogger.error("Failed to log onBuildAction", e);
        }
    }
}
