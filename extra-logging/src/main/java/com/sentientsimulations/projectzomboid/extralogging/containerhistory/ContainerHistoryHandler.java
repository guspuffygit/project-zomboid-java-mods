package com.sentientsimulations.projectzomboid.extralogging.containerhistory;

import io.pzstorm.storm.event.zomboid.OnItemTransferCompletedEvent;
import zombie.characters.IsoPlayer;
import zombie.inventory.InventoryItem;

public final class ContainerHistoryHandler {

    private ContainerHistoryHandler() {}

    public static void onItemTransferCompleted(OnItemTransferCompletedEvent event) {
        String srcRef = event.getSrcRef();
        String destRef = event.getDestRef();

        if (!involvesWorldContainer(srcRef) && !involvesWorldContainer(destRef)) {
            return;
        }

        IsoPlayer player = event.getPlayer();
        InventoryItem item = event.getItem();

        long steamId = player.getSteamID();
        ContainerTransferRecord record =
                new ContainerTransferRecord(
                        0L,
                        System.currentTimeMillis(),
                        player.getUsername(),
                        steamId == 0 ? null : Long.toString(steamId),
                        item.getFullType(),
                        item.getDisplayName(),
                        item.getID(),
                        srcRef,
                        destRef,
                        event.getUuid());

        ContainerHistoryWriter.enqueue(record);
    }

    private static boolean involvesWorldContainer(String ref) {
        return ref != null && (ref.startsWith("object:") || ref.startsWith("worlditem:"));
    }
}
