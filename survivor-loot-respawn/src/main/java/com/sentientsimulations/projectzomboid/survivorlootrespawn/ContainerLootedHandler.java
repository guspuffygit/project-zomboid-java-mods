package com.sentientsimulations.projectzomboid.survivorlootrespawn;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import com.sentientsimulations.projectzomboid.survivorlootrespawn.state.ContainerLootState;
import com.sentientsimulations.projectzomboid.survivorlootrespawn.state.ContainerLootStateRepository;
import io.pzstorm.storm.event.core.SubscribeEvent;
import io.pzstorm.storm.event.packet.RemoveInventoryItemFromContainerPacketEvent;
import io.pzstorm.storm.event.zomboid.OnContainerLootedEvent;
import zombie.GameTime;
import zombie.SandboxOptions;
import zombie.characters.IsoPlayer;
import zombie.inventory.ItemContainer;
import zombie.iso.IsoGridSquare;
import zombie.iso.IsoObject;
import zombie.iso.objects.IsoDeadBody;
import zombie.iso.objects.IsoThumpable;
import zombie.network.fields.ContainerID;
import zombie.network.packets.RemoveInventoryItemFromContainerPacket;

public final class ContainerLootedHandler {

    private ContainerLootedHandler() {}

    @SubscribeEvent
    public static void onContainerLooted(OnContainerLootedEvent event) {
        // Storm dispatches before src.Remove(item), so the looted item is still in the container.
        // Subtract it so handleLooted always sees the post-removal count, matching the packet path.
        ItemContainer container = event.getContainer();
        handleLooted(event.getPlayer(), container, container.getItems().size() - 1);
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
        // processServer has already removed the items by the time this event dispatches.
        handleLooted(packet.getPlayer(), container, container.getItems().size());
    }

    private static void handleLooted(IsoPlayer player, ItemContainer container, int itemCount) {
        IsoGridSquare sq = container.getSourceGrid();
        if (sq == null) {
            return;
        }
        IsoObject parent = container.getParent();
        if (parent instanceof IsoThumpable || parent instanceof IsoDeadBody) {
            return;
        }

        int maxItems = SandboxOptions.instance.maxItemsForLootRespawn.getValue();
        if (itemCount >= maxItems) {
            return;
        }

        int containerIndex = computeContainerIndex(sq, container);
        if (containerIndex < 0) {
            LOGGER.warn(
                    "(SurvivorLootRespawn) container looted but not found in square objects: type={} at x={} y={} z={}",
                    container.getType(),
                    sq.getX(),
                    sq.getY(),
                    sq.getZ());
            return;
        }

        String username = player != null ? player.getUsername() : null;
        String steamId =
                player != null && player.getSteamID() != 0L
                        ? Long.toString(player.getSteamID())
                        : null;

        double gameHours = GameTime.getInstance().getWorldAgeHours();

        ContainerLootStateRepository.upsert(
                new ContainerLootState(
                        sq.getX(),
                        sq.getY(),
                        sq.getZ(),
                        container.getType(),
                        containerIndex,
                        gameHours,
                        itemCount,
                        null,
                        username,
                        steamId));
    }

    private static int computeContainerIndex(IsoGridSquare sq, ItemContainer target) {
        int idx = 0;
        for (IsoObject obj : sq.getObjects()) {
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
