package com.sentientsimulations.projectzomboid.survivorlootrespawn;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import com.sentientsimulations.projectzomboid.survivorlootrespawn.config.SurvivorLootRespawnConfig;
import com.sentientsimulations.projectzomboid.survivorlootrespawn.state.ContainerLootState;
import com.sentientsimulations.projectzomboid.survivorlootrespawn.state.ContainerLootStateRepository;
import java.util.ArrayList;
import java.util.List;
import zombie.SandboxOptions;
import zombie.inventory.InventoryItem;
import zombie.inventory.ItemContainer;
import zombie.inventory.ItemPickerJava;
import zombie.iso.IsoChunk;
import zombie.iso.IsoGridSquare;
import zombie.iso.IsoObject;
import zombie.network.GameServer;
import zombie.network.PacketTypes;
import zombie.network.packets.INetworkPacket;

public final class ChunkLoadedRespawnHandler {

    private ChunkLoadedRespawnHandler() {}

    public static void onChunkLoaded(Object chunkObj) {
        if (!SurvivorLootRespawnConfig.isModEnabled()) {
            return;
        }
        if (!GameServer.server) {
            return;
        }
        if (!(chunkObj instanceof IsoChunk chunk)) {
            return;
        }
        processChunk(chunk);
    }

    public static int processChunk(IsoChunk chunk) {
        if (chunk == null) {
            return 0;
        }
        List<ContainerLootState> queued =
                ContainerLootStateRepository.selectQueuedInChunk(chunk.wx, chunk.wy);
        if (queued.isEmpty()) {
            return 0;
        }

        int respawned = 0;
        for (ContainerLootState s : queued) {
            FillResult result = respawnQueued(chunk, s);
            if (result.shouldDelete) {
                ContainerLootStateRepository.delete(
                        s.squareX(),
                        s.squareY(),
                        s.squareZ(),
                        s.containerType(),
                        s.containerIndex());
                if (result == FillResult.RESPAWNED) {
                    respawned++;
                }
            }
            LOGGER.debug(
                    "(SurvivorLootRespawn) Container x={} y={} z={} type={} idx={}: {}",
                    s.squareX(),
                    s.squareY(),
                    s.squareZ(),
                    s.containerType(),
                    s.containerIndex(),
                    result);
        }
        LOGGER.debug(
                "(SurvivorLootRespawn) Loot respawn for chunk wx={} wy={}: queued={}, respawned={}",
                chunk.wx,
                chunk.wy,
                queued.size(),
                respawned);
        return respawned;
    }

    private static FillResult respawnQueued(IsoChunk chunk, ContainerLootState s) {
        int localX = s.squareX() - chunk.wx * 8;
        int localY = s.squareY() - chunk.wy * 8;
        if (localX < 0 || localX >= 8 || localY < 0 || localY >= 8) {
            return FillResult.RETRY_OUT_OF_BOUNDS;
        }
        IsoGridSquare sq = chunk.getGridSquare(localX, localY, s.squareZ());
        if (sq == null) {
            return FillResult.DELETE_SQUARE_MISSING;
        }

        int idx = 0;
        for (IsoObject obj : sq.getObjects()) {
            int count = obj.getContainerCount();
            for (int i = 0; i < count; i++) {
                if (idx == s.containerIndex()) {
                    ItemContainer container = obj.getContainerByIndex(i);
                    if (container == null) {
                        return FillResult.DELETE_CONTAINER_NULL;
                    }
                    if (!s.containerType().equals(container.getType())) {
                        return FillResult.DELETE_TYPE_CHANGED;
                    }
                    return respawnInContainer(obj, container);
                }
                idx++;
            }
        }
        return FillResult.DELETE_INDEX_NOT_FOUND;
    }

    private static FillResult respawnInContainer(IsoObject obj, ItemContainer container) {
        if (container.getItems() == null) {
            return FillResult.RETRY_NO_ITEMS_LIST;
        }
        int count = container.getItems().size();
        int maxItem = SandboxOptions.instance.maxItemsForLootRespawn.getValue();
        if (count >= maxItem) {
            return FillResult.DELETE_ALREADY_FULL;
        }

        ArrayList<InventoryItem> existing = new ArrayList<>(container.getItems());
        ItemPickerJava.fillContainer(container, null);
        ArrayList<InventoryItem> items = container.getItems();
        if (items == null || items.size() == count) {
            return FillResult.RETRY_FILL_ADDED_NOTHING;
        }

        container.setHasBeenLooted(false);
        ArrayList<InventoryItem> fresh = new ArrayList<>();
        for (int j = 0; j < items.size(); j++) {
            InventoryItem item = items.get(j);
            if (!existing.contains(item)) {
                fresh.add(item);
                item.setAge(0.0F);
            }
        }

        ItemPickerJava.updateOverlaySprite(obj);
        if (GameServer.server && obj.square != null) {
            INetworkPacket.sendToRelative(
                    PacketTypes.PacketType.AddInventoryItemToContainer,
                    obj.square.x,
                    obj.square.y,
                    container,
                    fresh);
        }
        return FillResult.RESPAWNED;
    }

    private enum FillResult {
        RETRY_OUT_OF_BOUNDS(false),
        RETRY_NO_ITEMS_LIST(false),
        RETRY_FILL_ADDED_NOTHING(false),
        DELETE_ALREADY_FULL(true),
        DELETE_SQUARE_MISSING(true),
        DELETE_CONTAINER_NULL(true),
        DELETE_INDEX_NOT_FOUND(true),
        DELETE_TYPE_CHANGED(true),
        RESPAWNED(true);

        final boolean shouldDelete;

        FillResult(boolean shouldDelete) {
            this.shouldDelete = shouldDelete;
        }
    }
}
