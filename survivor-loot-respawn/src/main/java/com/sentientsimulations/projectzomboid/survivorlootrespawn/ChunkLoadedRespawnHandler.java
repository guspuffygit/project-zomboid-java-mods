package com.sentientsimulations.projectzomboid.survivorlootrespawn;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import com.sentientsimulations.projectzomboid.survivorlootrespawn.config.SurvivorLootRespawnConfig;
import com.sentientsimulations.projectzomboid.survivorlootrespawn.metrics.SurvivorLootRespawnMetrics;
import com.sentientsimulations.projectzomboid.survivorlootrespawn.state.ContainerLootState;
import com.sentientsimulations.projectzomboid.survivorlootrespawn.state.ContainerLootStateRepository;
import com.sentientsimulations.projectzomboid.survivorlootrespawn.state.ContainerLootStateRepository.InsertRow;
import java.util.ArrayList;
import java.util.List;
import zombie.GameTime;
import zombie.SandboxOptions;
import zombie.inventory.InventoryItem;
import zombie.inventory.ItemContainer;
import zombie.inventory.ItemPickerJava;
import zombie.iso.IsoChunk;
import zombie.iso.IsoGridSquare;
import zombie.iso.IsoObject;
import zombie.iso.objects.IsoDeadBody;
import zombie.iso.objects.IsoThumpable;
import zombie.network.GameServer;
import zombie.network.PacketTypes;
import zombie.network.packets.INetworkPacket;
import zombie.util.list.PZArrayList;

public final class ChunkLoadedRespawnHandler {

    static final int MAX_FILL_NOTHING_RETRIES = 3;

    private ChunkLoadedRespawnHandler() {}

    public static void onChunkLoaded(Object chunkObj) {
        try {
            if (!SurvivorLootRespawnConfig.isModEnabled()) {
                return;
            }
            if (!GameServer.server) {
                return;
            }
            if (!(chunkObj instanceof IsoChunk chunk)) {
                return;
            }
            discoverChunk(chunk);
            processChunk(chunk);
        } catch (Throwable t) {
            SurvivorLootRespawnMetrics.recordOnChunkLoadedError();
            LOGGER.error("(SurvivorLootRespawn) onChunkLoaded failed", t);
        }
    }

    public static int discoverChunk(IsoChunk chunk) {
        if (chunk == null) {
            return 0;
        }
        long startNanos = System.nanoTime();
        int maxItems = SandboxOptions.instance.maxItemsForLootRespawn.getValue();
        double gameHours = GameTime.getInstance().getWorldAgeHours();
        List<InsertRow> rows = new ArrayList<>();
        for (int z = chunk.minLevel; z <= chunk.maxLevel; z++) {
            for (int y = 0; y < 8; y++) {
                for (int x = 0; x < 8; x++) {
                    IsoGridSquare sq = chunk.getGridSquare(x, y, z);
                    if (sq == null) {
                        continue;
                    }
                    collectSquare(sq, maxItems, gameHours, rows);
                }
            }
        }
        int discovered = ContainerLootStateRepository.batchInsertIfMissing(rows);
        SurvivorLootRespawnMetrics.recordDiscoveryInserted(discovered);
        SurvivorLootRespawnMetrics.observeChunkDiscoverSeconds(
                (System.nanoTime() - startNanos) / 1e9);
        if (discovered > 0) {
            LOGGER.debug(
                    "(SurvivorLootRespawn) Container discovery in chunk wx={} wy={}: discovered={}",
                    chunk.wx,
                    chunk.wy,
                    discovered);
        }
        return discovered;
    }

    private static void collectSquare(
            IsoGridSquare sq, int maxItems, double gameHours, List<InsertRow> rows) {
        int idx = 0;
        PZArrayList<IsoObject> objects = sq.getObjects();
        for (int oi = 0; oi < objects.size(); oi++) {
            IsoObject obj = objects.get(oi);
            if (obj instanceof IsoThumpable || obj instanceof IsoDeadBody) {
                idx += obj.getContainerCount();
                continue;
            }
            int count = obj.getContainerCount();
            for (int i = 0; i < count; i++) {
                ItemContainer container = obj.getContainerByIndex(i);
                if (container == null) {
                    SurvivorLootRespawnMetrics.recordDiscoverySkipped("null");
                    idx++;
                    continue;
                }
                if (!container.isExplored()) {
                    SurvivorLootRespawnMetrics.recordDiscoverySkipped("unexplored");
                    idx++;
                    continue;
                }
                if (!container.isHasBeenLooted()) {
                    SurvivorLootRespawnMetrics.recordDiscoverySkipped("not_looted");
                    idx++;
                    continue;
                }
                if (container.getItems() == null) {
                    SurvivorLootRespawnMetrics.recordDiscoverySkipped("no_items");
                    idx++;
                    continue;
                }
                if (container.getItems().size() >= maxItems) {
                    SurvivorLootRespawnMetrics.recordDiscoverySkipped("full");
                    idx++;
                    continue;
                }
                rows.add(
                        new InsertRow(
                                sq.getX(),
                                sq.getY(),
                                sq.getZ(),
                                container.getType(),
                                idx,
                                gameHours));
                idx++;
            }
        }
    }

    public static int processChunk(IsoChunk chunk) {
        if (chunk == null) {
            return 0;
        }
        long startNanos = System.nanoTime();
        List<ContainerLootState> queued =
                ContainerLootStateRepository.selectQueuedInChunk(chunk.wx, chunk.wy);
        if (queued.isEmpty()) {
            SurvivorLootRespawnMetrics.observeChunkProcessSeconds(
                    (System.nanoTime() - startNanos) / 1e9);
            return 0;
        }

        int hoursTillMax = SurvivorLootRespawnConfig.getHoursTillMaxRespawnChance();
        int maxChance = SurvivorLootRespawnConfig.getMaxRespawnChance();
        int minChance = SurvivorLootRespawnConfig.getMinRespawnChance();
        double steepness = SurvivorLootRespawnConfig.getCurveSteepness();

        int respawned = 0;
        for (ContainerLootState s : queued) {
            FillResult result = respawnQueued(chunk, s);
            FillResult effective = result;
            if (result == FillResult.RETRY_FILL_ADDED_NOTHING) {
                SurvivorLootRespawnMetrics.recordFillAddedNothing(s.containerType());
                int newCount = s.fillAddedNothingCount() + 1;
                if (newCount >= MAX_FILL_NOTHING_RETRIES) {
                    effective = FillResult.DELETE_FILL_GIVE_UP;
                    SurvivorLootRespawnMetrics.recordFillGiveUp(s.containerType());
                    LOGGER.debug(
                            "(SurvivorLootRespawn) fill_added_nothing retry cap reached at x={} y={} z={} type={} idx={}, evicting row",
                            s.squareX(),
                            s.squareY(),
                            s.squareZ(),
                            s.containerType(),
                            s.containerIndex());
                } else {
                    ContainerLootStateRepository.incrementFillAddedNothing(
                            s.squareX(),
                            s.squareY(),
                            s.squareZ(),
                            s.containerType(),
                            s.containerIndex());
                }
            }
            SurvivorLootRespawnMetrics.recordRespawnResult(effective.name().toLowerCase());
            if (effective.shouldDelete) {
                ContainerLootStateRepository.delete(
                        s.squareX(),
                        s.squareY(),
                        s.squareZ(),
                        s.containerType(),
                        s.containerIndex());
                if (effective == FillResult.RESPAWNED) {
                    respawned++;
                }
            }
            double hoursLootedToQueued = s.respawnQueuedAtHours() - s.lootedGameHours();
            double chance =
                    HourlyRespawnRollHandler.computeChance(
                            hoursLootedToQueued, hoursTillMax, minChance, maxChance, steepness);
            LOGGER.debug(
                    "(SurvivorLootRespawn) Container x={} y={} z={} type={} idx={} queued={} rolled={}: {}",
                    s.squareX(),
                    s.squareY(),
                    s.squareZ(),
                    s.containerType(),
                    s.containerIndex(),
                    String.format("%.2f", hoursLootedToQueued),
                    String.format("%.2f%%", chance),
                    effective);
        }
        SurvivorLootRespawnMetrics.observeChunkProcessSeconds(
                (System.nanoTime() - startNanos) / 1e9);
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
        PZArrayList<IsoObject> objects = sq.getObjects();
        for (int oi = 0; oi < objects.size(); oi++) {
            IsoObject obj = objects.get(oi);
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

    enum FillResult {
        RETRY_OUT_OF_BOUNDS(false),
        RETRY_NO_ITEMS_LIST(false),
        RETRY_FILL_ADDED_NOTHING(false),
        DELETE_ALREADY_FULL(true),
        DELETE_SQUARE_MISSING(true),
        DELETE_CONTAINER_NULL(true),
        DELETE_INDEX_NOT_FOUND(true),
        DELETE_TYPE_CHANGED(true),
        DELETE_FILL_GIVE_UP(true),
        RESPAWNED(true);

        final boolean shouldDelete;

        FillResult(boolean shouldDelete) {
            this.shouldDelete = shouldDelete;
        }
    }
}
