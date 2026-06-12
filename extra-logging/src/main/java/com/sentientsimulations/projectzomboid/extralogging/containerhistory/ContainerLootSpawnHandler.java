package com.sentientsimulations.projectzomboid.extralogging.containerhistory;

import java.util.ArrayList;
import java.util.UUID;
import zombie.inventory.InventoryItem;
import zombie.inventory.ItemContainer;
import zombie.iso.IsoGridSquare;
import zombie.iso.IsoObject;
import zombie.iso.objects.IsoWorldInventoryObject;
import zombie.network.GameServer;
import zombie.util.list.PZArrayList;

/**
 * Captures items spawned into a world container by {@code ItemPickerJava.fillContainer} (initial
 * room fill, packet-driven first-open fill, and survivor-loot-respawn refills) and writes one
 * {@link ContainerTransferRecord} per fresh item into the container-history database, so the
 * History window for that container shows the loot generation alongside player take/put events.
 */
public final class ContainerLootSpawnHandler {

    public static final String LOOT_SRC_REF = "loot:fill";
    public static final String LOOT_PLAYER_NAME = "[loot]";

    private ContainerLootSpawnHandler() {}

    public static ArrayList<InventoryItem> snapshot(ItemContainer container) {
        if (!GameServer.server || container == null) {
            return null;
        }
        ArrayList<InventoryItem> items = container.getItems();
        if (items == null) {
            return null;
        }
        return new ArrayList<>(items);
    }

    public static void onFillComplete(ItemContainer container, ArrayList<InventoryItem> snapshot) {
        if (!GameServer.server || container == null || snapshot == null) {
            return;
        }
        ArrayList<InventoryItem> items = container.getItems();
        if (items == null || items.size() == snapshot.size()) {
            return;
        }

        String destRef = buildContainerRef(container);
        if (destRef == null) {
            return;
        }

        long now = System.currentTimeMillis();
        String uuid = UUID.randomUUID().toString();
        for (int i = 0; i < items.size(); i++) {
            InventoryItem item = items.get(i);
            if (item == null || snapshot.contains(item)) {
                continue;
            }
            ContainerTransferRecord record =
                    new ContainerTransferRecord(
                            0L,
                            now,
                            LOOT_PLAYER_NAME,
                            null,
                            item.getFullType(),
                            item.getDisplayName(),
                            item.getID(),
                            LOOT_SRC_REF,
                            destRef,
                            uuid);
            ContainerHistoryRepository.insert(record);
        }
    }

    /**
     * Mirrors the ref format produced by {@code StormTransferFix.lua}'s {@code getContainerRef} and
     * consumed by {@code StormTransferHandler.resolveContainer}, so loot rows key off the same
     * {@code object:...} / {@code worlditem:...} string as player transfer rows. Returns {@code
     * null} for containers without a world location (player inventory, vehicle parts, transient
     * fill-targets) — those rows are silently skipped.
     */
    private static String buildContainerRef(ItemContainer container) {
        IsoGridSquare sq = container.getSourceGrid();
        if (sq == null) {
            return null;
        }

        IsoObject parent = container.getParent();
        if (parent != null) {
            PZArrayList<IsoObject> objects = sq.getObjects();
            for (int i = 0; i < objects.size(); i++) {
                if (objects.get(i) == parent) {
                    int containerIdx = parent.getContainerIndex(container);
                    return "object:"
                            + sq.getX()
                            + ":"
                            + sq.getY()
                            + ":"
                            + sq.getZ()
                            + ":"
                            + i
                            + ":"
                            + containerIdx;
                }
            }
        }

        InventoryItem containingItem = container.getContainingItem();
        if (containingItem != null) {
            IsoWorldInventoryObject worldItem = containingItem.getWorldItem();
            if (worldItem != null) {
                PZArrayList<IsoObject> objects = sq.getObjects();
                for (int i = 0; i < objects.size(); i++) {
                    if (objects.get(i) == worldItem) {
                        return "worlditem:"
                                + sq.getX()
                                + ":"
                                + sq.getY()
                                + ":"
                                + sq.getZ()
                                + ":"
                                + i;
                    }
                }
            }
        }

        return null;
    }
}
