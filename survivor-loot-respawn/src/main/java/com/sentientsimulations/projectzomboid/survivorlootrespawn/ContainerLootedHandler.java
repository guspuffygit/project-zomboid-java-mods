package com.sentientsimulations.projectzomboid.survivorlootrespawn;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import com.sentientsimulations.projectzomboid.survivorlootrespawn.state.ContainerLootState;
import com.sentientsimulations.projectzomboid.survivorlootrespawn.state.ContainerLootStateRepository;
import io.pzstorm.storm.event.core.SubscribeEvent;
import io.pzstorm.storm.event.zomboid.OnContainerLootedEvent;
import zombie.GameTime;
import zombie.SandboxOptions;
import zombie.characters.IsoPlayer;
import zombie.inventory.ItemContainer;
import zombie.iso.IsoGridSquare;
import zombie.iso.IsoObject;
import zombie.iso.objects.IsoThumpable;

public final class ContainerLootedHandler {

    private ContainerLootedHandler() {}

    @SubscribeEvent
    public static void onContainerLooted(OnContainerLootedEvent event) {
        ItemContainer container = event.getContainer();
        IsoGridSquare sq = container.getSourceGrid();
        if (sq == null) {
            return;
        }
        if (container.getParent() instanceof IsoThumpable) {
            return;
        }

        int itemCount = container.getItems().size();
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

        IsoPlayer player = event.getPlayer();
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
