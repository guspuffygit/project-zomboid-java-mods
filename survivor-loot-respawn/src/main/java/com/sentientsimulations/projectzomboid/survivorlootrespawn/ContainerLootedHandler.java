package com.sentientsimulations.projectzomboid.survivorlootrespawn;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import com.sentientsimulations.projectzomboid.survivorlootrespawn.metrics.SurvivorLootRespawnMetrics;
import com.sentientsimulations.projectzomboid.survivorlootrespawn.state.ContainerLootStateRepository;
import com.sentientsimulations.projectzomboid.survivorlootrespawn.state.SurvivorLootRespawnDatabase;
import io.pzstorm.storm.event.core.SubscribeEvent;
import io.pzstorm.storm.event.packet.RemoveInventoryItemFromContainerPacketEvent;
import io.pzstorm.storm.event.zomboid.OnContainerLootedEvent;
import zombie.GameTime;
import zombie.SandboxOptions;
import zombie.inventory.ItemContainer;
import zombie.iso.IsoGridSquare;
import zombie.iso.IsoObject;
import zombie.iso.objects.IsoDeadBody;
import zombie.iso.objects.IsoThumpable;
import zombie.network.fields.ContainerID;
import zombie.network.packets.RemoveInventoryItemFromContainerPacket;
import zombie.util.list.PZArrayList;

public final class ContainerLootedHandler {

    private ContainerLootedHandler() {}

    @SubscribeEvent
    public static void onContainerLooted(OnContainerLootedEvent event) {
        SurvivorLootRespawnMetrics.recordLootedObserved("event");
        // Storm dispatches before src.Remove(item), so the looted item is still in the container.
        // Subtract it so handleLooted always sees the post-removal count, matching the packet path.
        ItemContainer container = event.getContainer();
        handleLooted(container, container.getItems().size() - 1);
    }

    /**
     * Floor-drop and dead-body removals bypass {@link OnContainerLootedEvent} because they go
     * through the vanilla {@link RemoveInventoryItemFromContainerPacket} path instead of Storm's
     * UUID transfer handler. Subscribe to the typed packet event so dropping container loot onto
     * the floor still arms the respawn timer.
     */
    @SubscribeEvent
    public static void onItemRemovedFromContainer(
            RemoveInventoryItemFromContainerPacketEvent event) {
        RemoveInventoryItemFromContainerPacket packet = event.getPacket();
        if (packet.isInventory()) {
            return;
        }
        Object raw = event.getField("containerId");
        if (!(raw instanceof ContainerID containerId)) {
            return;
        }
        ItemContainer container = containerId.getContainer();
        if (container == null) {
            return;
        }
        SurvivorLootRespawnMetrics.recordLootedObserved("packet");
        // processServer has already removed the items by the time this event dispatches.
        handleLooted(container, container.getItems().size());
    }

    /**
     * Invoked from {@link
     * com.sentientsimulations.projectzomboid.survivorlootrespawn.patch.GameServerSendRemovePatch}
     * on every server-side {@code GameServer.sendRemoveItemFromContainer} call. Catches the
     * floor-drop path: the server-mirror TimedAction calls {@code DoRemoveItem} then routes through
     * here to broadcast to other clients. The same hook also fires for many non-loot consumers
     * (food eaten, drainables drained, mannequin/animal data, etc.) — the existing filters in
     * {@link #handleLooted} reject them via {@code sq == null} (player inventory) or parent type
     * (thumpable, dead body).
     */
    public static void onServerSendRemove(Object containerObj) {
        if (!(containerObj instanceof ItemContainer container)) {
            return;
        }
        SurvivorLootRespawnMetrics.recordLootedObserved("server_send");
        handleLooted(container, container.getItems().size());
    }

    private static void handleLooted(ItemContainer container, int itemCount) {
        IsoGridSquare sq = container.getSourceGrid();
        if (sq == null) {
            SurvivorLootRespawnMetrics.recordLootedTracked("skipped_no_grid");
            LOGGER.debug(
                    "[SurvivorLootRespawn] Loot skipped: container has no source grid (type={})",
                    container.getType());
            return;
        }
        IsoObject parent = container.getParent();
        if (parent instanceof IsoThumpable || parent instanceof IsoDeadBody) {
            SurvivorLootRespawnMetrics.recordLootedTracked("skipped_thumpable_deadbody");
            LOGGER.debug(
                    "[SurvivorLootRespawn] Loot skipped: parent is {} (type={} at x={} y={} z={})",
                    parent.getClass().getSimpleName(),
                    container.getType(),
                    sq.getX(),
                    sq.getY(),
                    sq.getZ());
            return;
        }

        int maxItems = SandboxOptions.instance.maxItemsForLootRespawn.getValue();
        if (itemCount >= maxItems) {
            SurvivorLootRespawnMetrics.recordLootedTracked("skipped_full");
            LOGGER.debug(
                    "[SurvivorLootRespawn] Loot skipped: container still has {}/{} items (type={} at x={} y={} z={})",
                    itemCount,
                    maxItems,
                    container.getType(),
                    sq.getX(),
                    sq.getY(),
                    sq.getZ());
            return;
        }

        int containerIndex = computeContainerIndex(sq, container);
        if (containerIndex < 0) {
            SurvivorLootRespawnMetrics.recordLootedTracked("skipped_index_not_found");
            LOGGER.warn(
                    "[SurvivorLootRespawn] container looted but not found in square objects: type={} at x={} y={} z={}",
                    container.getType(),
                    sq.getX(),
                    sq.getY(),
                    sq.getZ());
            return;
        }

        int sqX = sq.getX();
        int sqY = sq.getY();
        int sqZ = sq.getZ();
        String type = container.getType();
        int idx = containerIndex;
        double gameHours = GameTime.getInstance().getWorldAgeHours();

        SurvivorLootRespawnDatabase.submit(
                () -> {
                    boolean inserted =
                            ContainerLootStateRepository.insertIfMissing(
                                    sqX, sqY, sqZ, type, idx, gameHours);
                    SurvivorLootRespawnMetrics.recordLootedTracked(
                            inserted ? "inserted" : "duplicate");
                });
    }

    private static int computeContainerIndex(IsoGridSquare sq, ItemContainer target) {
        int idx = 0;
        PZArrayList<IsoObject> objects = sq.getObjects();
        for (int oi = 0; oi < objects.size(); oi++) {
            IsoObject obj = objects.get(oi);
            int count = obj.getContainerCount();
            for (int i = 0; i < count; i++) {
                if (obj.getContainerByIndex(i) == target) {
                    return idx;
                }
                idx++;
            }
        }
        return -1;
    }
}
