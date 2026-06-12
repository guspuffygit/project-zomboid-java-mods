package com.sentientsimulations.projectzomboid.survivorlootrespawn;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import com.sentientsimulations.projectzomboid.survivorlootrespawn.metrics.SurvivorLootRespawnMetrics;
import com.sentientsimulations.projectzomboid.survivorlootrespawn.state.ContainerLootStateRepository;
import com.sentientsimulations.projectzomboid.survivorlootrespawn.state.SurvivorLootRespawnDatabase;
import io.pzstorm.storm.event.core.SubscribeEvent;
import io.pzstorm.storm.event.zomboid.OnContainerLootedEvent;
import zombie.GameTime;
import zombie.SandboxOptions;
import zombie.inventory.ItemContainer;
import zombie.iso.IsoGridSquare;
import zombie.iso.IsoObject;
import zombie.util.list.PZArrayList;

public final class ContainerLootedHandler {

    private ContainerLootedHandler() {}

    @SubscribeEvent
    public static void onContainerLooted(OnContainerLootedEvent event) {
        SurvivorLootRespawnMetrics.recordLootedObserved("event");
        // Storm dispatches before src.Remove(item), so the looted item is still in the container.
        // Subtract it so handleLooted sees the post-removal count.
        ItemContainer container = event.getContainer();
        handleLooted(container, container.getItems().size() - 1);
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
        if (!VanillaLootRespawnGate.passesSquareGate(sq)) {
            SurvivorLootRespawnMetrics.recordLootedTracked("skipped_zone_gate");
            LOGGER.debug(
                    "[SurvivorLootRespawn] Loot skipped: square failed vanilla gate (type={} at x={} y={} z={})",
                    container.getType(),
                    sq.getX(),
                    sq.getY(),
                    sq.getZ());
            return;
        }
        IsoObject parent = container.getParent();
        if (VanillaLootRespawnGate.isExcludedObject(parent)) {
            SurvivorLootRespawnMetrics.recordLootedTracked("skipped_excluded_object");
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
