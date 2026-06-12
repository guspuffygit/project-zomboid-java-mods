package com.sentientsimulations.projectzomboid.survivorlootrespawn;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import com.sentientsimulations.projectzomboid.survivorlootrespawn.config.SurvivorLootRespawnConfig;
import com.sentientsimulations.projectzomboid.survivorlootrespawn.metrics.SurvivorLootRespawnMetrics;
import com.sentientsimulations.projectzomboid.survivorlootrespawn.state.ContainerLootState;
import com.sentientsimulations.projectzomboid.survivorlootrespawn.state.ContainerLootStateRepository;
import com.sentientsimulations.projectzomboid.survivorlootrespawn.state.SurvivorLootRespawnDatabase;
import io.pzstorm.storm.event.core.SubscribeEvent;
import io.pzstorm.storm.event.lua.EveryTenMinutesEvent;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import zombie.iso.IsoChunk;
import zombie.network.GameServer;
import zombie.network.ServerMap;

public final class EveryTenMinutesRespawnHandler {

    private EveryTenMinutesRespawnHandler() {}

    @SubscribeEvent
    public static void onEveryTenMinutes(EveryTenMinutesEvent event) {
        boolean enabled = SurvivorLootRespawnConfig.isModEnabled();
        SurvivorLootRespawnMetrics.setModEnabled(enabled);
        if (!enabled) {
            return;
        }
        if (!GameServer.server) {
            return;
        }
        if (ServerMap.instance == null) {
            return;
        }

        long startNanos = System.nanoTime();
        Map<Long, List<ContainerLootState>> queuedByChunk =
                ContainerLootStateRepository.selectAllQueuedByChunk();
        int chunksScanned = 0;
        int respawned = 0;
        List<ContainerLootState> toDelete = new ArrayList<>();
        List<ContainerLootState> toIncrement = new ArrayList<>();
        if (!queuedByChunk.isEmpty()) {
            for (int i = 0; i < ServerMap.instance.loadedCells.size(); i++) {
                ServerMap.ServerCell cell = ServerMap.instance.loadedCells.get(i);
                if (!cell.isLoaded) {
                    continue;
                }
                for (int y = 0; y < 8; y++) {
                    for (int x = 0; x < 8; x++) {
                        IsoChunk chunk = cell.chunks[x][y];
                        if (chunk == null) {
                            continue;
                        }
                        chunksScanned++;
                        List<ContainerLootState> queued =
                                queuedByChunk.get(
                                        ContainerLootStateRepository.chunkKey(chunk.wx, chunk.wy));
                        if (queued == null) {
                            continue;
                        }
                        respawned +=
                                ChunkLoadedRespawnHandler.processChunkRows(
                                        chunk, queued, toDelete, toIncrement);
                    }
                }
            }
            ContainerLootStateRepository.batchDelete(toDelete);
            ContainerLootStateRepository.batchIncrementFillAddedNothing(toIncrement);
        }
        SurvivorLootRespawnMetrics.observeTenMinSweepSeconds(
                (System.nanoTime() - startNanos) / 1e9);
        LOGGER.debug(
                "[SurvivorLootRespawn] 10-minute sweep fired: chunks={}, respawned={}",
                chunksScanned,
                respawned);
        SurvivorLootRespawnDatabase.submit(
                () -> {
                    SurvivorLootRespawnMetrics.setRowsTracked(
                            ContainerLootStateRepository.countTotal());
                    SurvivorLootRespawnMetrics.setRowsQueued(
                            ContainerLootStateRepository.countQueued());
                });
    }
}
