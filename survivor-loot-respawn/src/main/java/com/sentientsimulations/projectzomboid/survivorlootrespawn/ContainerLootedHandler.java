package com.sentientsimulations.projectzomboid.survivorlootrespawn;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import io.pzstorm.storm.event.core.SubscribeEvent;
import io.pzstorm.storm.event.zomboid.OnContainerLootedEvent;
import zombie.characters.IsoPlayer;
import zombie.inventory.ItemContainer;
import zombie.iso.IsoGridSquare;
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

        IsoPlayer player = event.getPlayer();
        String username = player != null ? player.getUsername() : "<null>";
        String steamId = player != null ? String.valueOf(player.getSteamID()) : "<null>";

        LOGGER.info(
                "container looted: player={} steamId={} type={} at x={} y={} z={}",
                username,
                steamId,
                container.getType(),
                sq.getX(),
                sq.getY(),
                sq.getZ());
    }
}
