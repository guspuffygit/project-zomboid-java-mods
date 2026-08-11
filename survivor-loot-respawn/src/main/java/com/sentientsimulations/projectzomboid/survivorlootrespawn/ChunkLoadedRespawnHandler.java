package com.sentientsimulations.projectzomboid.survivorlootrespawn;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import com.sentientsimulations.projectzomboid.survivorlootrespawn.config.SurvivorLootRespawnConfig;
import com.sentientsimulations.projectzomboid.survivorlootrespawn.metrics.SurvivorLootRespawnMetrics;
import com.sentientsimulations.projectzomboid.survivorlootrespawn.state.ContainerLootState;
import com.sentientsimulations.projectzomboid.survivorlootrespawn.state.ContainerLootStateRepository;
import com.sentientsimulations.projectzomboid.survivorlootrespawn.state.ContainerLootStateRepository.InsertRow;
import com.sentientsimulations.projectzomboid.survivorlootrespawn.state.SurvivorLootRespawnDatabase;
import gnu.trove.map.hash.THashMap;
import io.pzstorm.storm.event.core.SubscribeEvent;
import io.pzstorm.storm.event.lua.OnTickEvent;
import java.lang.reflect.Field;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;
import java.util.concurrent.ConcurrentLinkedQueue;
import zombie.GameTime;
import zombie.SandboxOptions;
import zombie.inventory.InventoryItem;
import zombie.inventory.ItemContainer;
import zombie.inventory.ItemPickerJava;
import zombie.inventory.ItemPickerJava.ItemPickerContainer;
import zombie.inventory.ItemPickerJava.ItemPickerRoom;
import zombie.iso.IsoChunk;
import zombie.iso.IsoGridSquare;
import zombie.iso.IsoObject;
import zombie.iso.areas.IsoRoom;
import zombie.network.GameServer;
import zombie.network.PacketTypes;
import zombie.network.ServerMap;
import zombie.network.packets.INetworkPacket;
import zombie.scripting.objects.ContainerType;
import zombie.scripting.objects.ResourceLocation;
import zombie.util.list.PZArrayList;

/**
 * Respawns loot in a chunk as it streams in. The flow is split across threads to keep SQLite I/O
 * off the server main thread (same pattern as the obelisk mod's ListDeathsHandler):
 *
 * <ol>
 *   <li>{@link #onChunkLoaded} runs on the main thread (LootRespawnPatch advice), walks the chunk's
 *       squares, and hands the discovered rows plus a queued-row select to the mod's DB executor.
 *   <li>The {@code SurvivorLootRespawn-DB} worker runs the batch insert and the select, then pushes
 *       the queued rows onto {@link #COMPLETED}.
 *   <li>{@link #onTick} drains {@link #COMPLETED} on the main thread, re-looks the chunk up by
 *       coordinates, and runs the in-game respawn work; the follow-up deletes/increments go back to
 *       the DB executor. If the chunk unloaded in the meantime the rows stay queued in the DB and
 *       are retried on its next load.
 * </ol>
 */
public final class ChunkLoadedRespawnHandler {

    static final int MAX_FILL_NOTHING_RETRIES = 3;

    private record CompletedChunkSelect(int wx, int wy, List<ContainerLootState> queued) {}

    private static final ConcurrentLinkedQueue<CompletedChunkSelect> COMPLETED =
            new ConcurrentLinkedQueue<>();

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
            List<InsertRow> rows = collectChunk(chunk);
            int wx = chunk.wx;
            int wy = chunk.wy;
            SurvivorLootRespawnDatabase.submit(
                    () -> {
                        int discovered = ContainerLootStateRepository.batchInsertIfMissing(rows);
                        SurvivorLootRespawnMetrics.recordDiscoveryInserted(discovered);
                        if (discovered > 0) {
                            LOGGER.debug(
                                    "[SurvivorLootRespawn] Container discovery in chunk wx={} wy={}: discovered={}",
                                    wx,
                                    wy,
                                    discovered);
                        }
                        List<ContainerLootState> queued =
                                ContainerLootStateRepository.selectQueuedInChunk(wx, wy);
                        if (!queued.isEmpty()) {
                            COMPLETED.offer(new CompletedChunkSelect(wx, wy, queued));
                        }
                    });
        } catch (Throwable t) {
            SurvivorLootRespawnMetrics.recordOnChunkLoadedError();
            LOGGER.error("[SurvivorLootRespawn] onChunkLoaded failed", t);
        }
    }

    @SubscribeEvent
    public static void onTick(OnTickEvent event) {
        CompletedChunkSelect done;
        while ((done = COMPLETED.poll()) != null) {
            try {
                processCompleted(done);
            } catch (Throwable t) {
                SurvivorLootRespawnMetrics.recordOnChunkLoadedError();
                LOGGER.error("[SurvivorLootRespawn] chunk respawn processing failed", t);
            }
        }
    }

    private static void processCompleted(CompletedChunkSelect done) {
        ServerMap serverMap = ServerMap.instance;
        IsoChunk chunk = serverMap == null ? null : serverMap.getChunk(done.wx(), done.wy());
        if (chunk == null) {
            LOGGER.debug(
                    "[SurvivorLootRespawn] Chunk wx={} wy={} unloaded before respawn; {} rows stay queued",
                    done.wx(),
                    done.wy(),
                    done.queued().size());
            return;
        }
        long startNanos = System.nanoTime();
        List<ContainerLootState> toDelete = new ArrayList<>();
        List<ContainerLootState> toIncrement = new ArrayList<>();
        int respawned = processChunkRows(chunk, done.queued(), toDelete, toIncrement);
        SurvivorLootRespawnDatabase.submit(
                () -> {
                    ContainerLootStateRepository.batchDelete(toDelete);
                    ContainerLootStateRepository.batchIncrementFillAddedNothing(toIncrement);
                });
        SurvivorLootRespawnMetrics.observeChunkProcessSeconds(
                (System.nanoTime() - startNanos) / 1e9);
        LOGGER.debug(
                "[SurvivorLootRespawn] Loot respawn for chunk wx={} wy={}: queued={}, respawned={}",
                done.wx(),
                done.wy(),
                done.queued().size(),
                respawned);
    }

    /** Main-thread walk of the chunk's squares; the DB insert happens on the DB executor. */
    private static List<InsertRow> collectChunk(IsoChunk chunk) {
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
        SurvivorLootRespawnMetrics.observeChunkDiscoverSeconds(
                (System.nanoTime() - startNanos) / 1e9);
        return rows;
    }

    private static void collectSquare(
            IsoGridSquare sq, int maxItems, double gameHours, List<InsertRow> rows) {
        if (!VanillaLootRespawnGate.passesSquareGate(sq)) {
            SurvivorLootRespawnMetrics.recordDiscoverySkipped("zone_gate");
            return;
        }
        int idx = 0;
        PZArrayList<IsoObject> objects = sq.getObjects();
        for (int oi = 0; oi < objects.size(); oi++) {
            IsoObject obj = objects.get(oi);
            if (VanillaLootRespawnGate.isExcludedObject(obj)) {
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
                if (wouldFillBeEmpty(sq, container)) {
                    SurvivorLootRespawnMetrics.recordDiscoverySkipped("no_loot_table");
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

    /**
     * True when {@code ItemPickerJava.fillContainer} would deterministically add zero items for
     * this (square, container) — the dispatch lands on an {@link ItemPickerContainer} (or pair of
     * them) whose flat {@code items} and {@code proceduralItems} are both empty. The canonical case
     * is vanilla's {@code rooms["empty"]} which defines only an empty {@code "other"} slot.
     *
     * <p>Returns {@code false} (don't skip) when distribution tables aren't loaded yet or the
     * lookup can't be resolved confidently — the existing retry-and-evict path stays as the
     * backstop.
     */
    static boolean wouldFillBeEmpty(IsoGridSquare sq, ItemContainer container) {
        try {
            THashMap<String, ItemPickerRoom> rooms = ItemPickerJava.rooms;
            if (rooms == null || rooms.isEmpty()) {
                return false;
            }
            String type = container.getType();
            IsoRoom room = sq.getRoom();
            String roomName = room == null ? null : room.getName();
            boolean noGeneric = isNoGenericLoot(type);

            ItemPickerRoom rollRoom = resolveRollRoom(rooms, roomName, type, noGeneric);
            if (rollRoom == null) {
                return false;
            }
            if (hasLoot(rollRoom.containers.get("all"))) {
                return false;
            }
            ItemPickerContainer perType = rollRoom.containers.get(type);
            if (hasLoot(perType)) {
                return false;
            }
            if (perType == null && !noGeneric && hasLoot(rollRoom.containers.get("other"))) {
                return false;
            }
            return true;
        } catch (Throwable t) {
            return false;
        }
    }

    private static ItemPickerRoom resolveRollRoom(
            THashMap<String, ItemPickerRoom> rooms,
            String roomName,
            String type,
            boolean noGeneric) {
        if (roomName != null && rooms.containsKey(roomName)) {
            ItemPickerRoom specific = rooms.get(roomName);
            boolean matches =
                    specific.containers.containsKey(type)
                            || (!noGeneric && specific.containers.containsKey("other"))
                            || specific.containers.containsKey("all");
            if (matches) {
                return specific;
            }
        }
        return rooms.get("all");
    }

    private static boolean hasLoot(ItemPickerContainer cd) {
        if (cd == null) {
            return false;
        }
        if (cd.items != null && cd.items.length > 0) {
            return true;
        }
        return cd.proceduralItems != null && !cd.proceduralItems.isEmpty();
    }

    private static volatile Set<?> noGenericLootSet;
    private static volatile boolean noGenericLootSetResolved;

    private static boolean isNoGenericLoot(String type) {
        Set<?> set = noGenericLootSet;
        if (!noGenericLootSetResolved) {
            try {
                Field f = ItemPickerJava.class.getDeclaredField("NO_GENERIC_LOOT_CONTAINERS");
                f.setAccessible(true);
                set = (Set<?>) f.get(null);
                noGenericLootSet = set;
            } catch (Throwable t) {
                set = null;
            } finally {
                noGenericLootSetResolved = true;
            }
        }
        if (set == null) {
            return false;
        }
        try {
            return set.contains(ContainerType.get(ResourceLocation.of(type)));
        } catch (Throwable t) {
            return false;
        }
    }

    /**
     * Walks a pre-fetched batch of queued rows for one chunk, performing the in-game respawn work
     * and appending DB intent to the two accumulator lists. No DB writes happen here — callers
     * batch-apply {@code toDelete} and {@code toIncrement} once they finish their own outer loop.
     */
    public static int processChunkRows(
            IsoChunk chunk,
            List<ContainerLootState> queued,
            List<ContainerLootState> toDelete,
            List<ContainerLootState> toIncrement) {
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
                            "[SurvivorLootRespawn] fill_added_nothing retry cap reached at x={} y={} z={} type={} idx={}, evicting row",
                            s.squareX(),
                            s.squareY(),
                            s.squareZ(),
                            s.containerType(),
                            s.containerIndex());
                } else {
                    toIncrement.add(s);
                }
            }
            SurvivorLootRespawnMetrics.recordRespawnResult(effective.name().toLowerCase());
            if (effective.shouldDelete) {
                toDelete.add(s);
                if (effective == FillResult.RESPAWNED) {
                    respawned++;
                }
            }
            double hoursLootedToQueued = s.respawnQueuedAtHours() - s.lootedGameHours();
            double chance =
                    HourlyRespawnRollHandler.computeChance(
                            hoursLootedToQueued, hoursTillMax, minChance, maxChance, steepness);
            LOGGER.debug(
                    "[SurvivorLootRespawn] Container x={} y={} z={} type={} idx={} hours_to_win={} rolled={}: {}",
                    s.squareX(),
                    s.squareY(),
                    s.squareZ(),
                    s.containerType(),
                    s.containerIndex(),
                    String.format("%.2f", hoursLootedToQueued),
                    String.format("%.2f%%", chance),
                    effective);
        }
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
        if (!VanillaLootRespawnGate.passesSquareGate(sq)) {
            return FillResult.DELETE_ZONE_BLOCKED;
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
        DELETE_ZONE_BLOCKED(true),
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
