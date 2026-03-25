package com.sentientsimulations.projectzomboid.extralogging;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import io.pzstorm.storm.event.core.SubscribeEvent;
import io.pzstorm.storm.event.zomboid.HeldItemsDroppedEvent;
import io.pzstorm.storm.event.zomboid.ItemPlacedOnMapEvent;
import io.pzstorm.storm.event.zomboid.ItemTransferredToFloorEvent;
import java.time.Instant;

public class ItemEventHandler {

    @SubscribeEvent
    public static void onItemTransferredToFloor(ItemTransferredToFloorEvent event) {
        try {
            String header = formatHeader("drop item from inventory");
            StringBuilder sb = new StringBuilder();
            field(sb, "Username", event.username);
            field(sb, "Steam ID", String.valueOf(event.steamId));
            field(sb, "Item", event.itemFullType);
            field(sb, "Item Name", event.itemName);
            field(sb, "Location", formatLocation(event.x, event.y, event.z));
            ItemLogWriter.writeEntry(header, sb.toString());
            LOGGER.info("Logged item drop by: {} [{}]", event.username, event.itemFullType);
        } catch (Exception e) {
            LOGGER.error("Failed to log item drop for: {}", event.username, e);
        }
    }

    @SubscribeEvent
    public static void onItemPlacedOnMap(ItemPlacedOnMapEvent event) {
        try {
            String action =
                    event.isWorldInventoryItem ? "place item on ground" : "place object on map";
            String header = formatHeader(action);
            StringBuilder sb = new StringBuilder();
            field(sb, "Username", event.username);
            field(sb, "Steam ID", String.valueOf(event.steamId));
            field(sb, "Item", event.itemType);
            field(sb, "Location", formatLocation(event.x, event.y, event.z));
            ItemLogWriter.writeEntry(header, sb.toString());
            LOGGER.info("Logged item placement by: {} [{}]", event.username, event.itemType);
        } catch (Exception e) {
            LOGGER.error("Failed to log item placement for: {}", event.username, e);
        }
    }

    @SubscribeEvent
    public static void onHeldItemsDropped(HeldItemsDroppedEvent event) {
        try {
            String action = event.isThrow ? "throw held items" : "drop held items";
            String header = formatHeader(action);
            StringBuilder sb = new StringBuilder();
            field(sb, "Username", event.username);
            field(sb, "Steam ID", String.valueOf(event.steamId));
            if (event.primaryItemType != null) {
                field(sb, "Primary", event.primaryItemType);
            }
            if (event.secondaryItemType != null) {
                field(sb, "Secondary", event.secondaryItemType);
            }
            field(sb, "Location", formatLocation(event.x, event.y, event.z));
            ItemLogWriter.writeEntry(header, sb.toString());
            LOGGER.info("Logged held item drop by: {}", event.username);
        } catch (Exception e) {
            LOGGER.error("Failed to log held item drop for: {}", event.username, e);
        }
    }

    private static String formatHeader(String action) {
        return String.format("[%s] %s", Instant.now(), action);
    }

    private static String formatLocation(int x, int y, int z) {
        return String.format("%d,%d,%d", x, y, z);
    }

    private static void field(StringBuilder sb, String label, String value) {
        sb.append(String.format("%-16s%s%n", label + ":", value));
    }
}
