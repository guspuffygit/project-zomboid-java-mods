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
        ServerMap serverMap = ServerMap.instance;
        if (serverMap == null) {
            return;
        }

        long startNanos = System.nanoTime();
        Map<Long, List<ContainerLootState>> queuedByChunk =
                ContainerLootStateRepository.selectAllQueuedByChunk();
        long afterSelectNanos = System.nanoTime();
        List<ContainerLootState> toDelete = new ArrayList<>();
        List<ContainerLootState> toIncrement = new ArrayList<>();
        int totalQueued = 0;
        int chunksProcessed = 0;
        int chunksSkippedNotLoaded = 0;
        int respawned = 0;

        for (Map.Entry<Long, List<ContainerLootState>> entry : queuedByChunk.entrySet()) {
            List<ContainerLootState> rows = entry.getValue();
            totalQueued += rows.size();
            long key = entry.getKey();
            int chunkWX = (int) (key >> 32);
            int chunkWY = (int) key;
            IsoChunk chunk = serverMap.getChunk(chunkWX, chunkWY);
            if (chunk == null) {
                chunksSkippedNotLoaded++;
                continue;
            }
            chunksProcessed++;
            respawned +=
                    ChunkLoadedRespawnHandler.processChunkRows(chunk, rows, toDelete, toIncrement);
        }
        long afterProcessNanos = System.nanoTime();

        SurvivorLootRespawnMetrics.observeTenMinSweepSeconds(
                (afterProcessNanos - startNanos) / 1e9);
        LOGGER.debug(
                "[SurvivorLootRespawn] 10-minute sweep: queued={}, chunks_processed={}, chunks_skipped_not_loaded={}, respawned={}",
                totalQueued,
                chunksProcessed,
                chunksSkippedNotLoaded,
                respawned);
        SurvivorLootRespawnDatabase.submit(
                () -> {
                    long submitStartNanos = System.nanoTime();
                    ContainerLootStateRepository.batchDelete(toDelete);
                    long afterDeleteNanos = System.nanoTime();
                    ContainerLootStateRepository.batchIncrementFillAddedNothing(toIncrement);
                    long afterIncrementNanos = System.nanoTime();
                    SurvivorLootRespawnMetrics.setRowsTracked(
                            ContainerLootStateRepository.countTotal());
                    long afterCountTotalNanos = System.nanoTime();
                    SurvivorLootRespawnMetrics.setRowsQueued(
                            ContainerLootStateRepository.countQueued());
                    long afterCountQueuedNanos = System.nanoTime();

                    LOGGER.debug(
                            "[SurvivorLootRespawn] 10-minute sweep timings (ms): select={}, process={}, batchDelete={}, batchIncrement={}, countTotal={}, countQueued={}",
                            String.format("%.2f", (afterSelectNanos - startNanos) / 1e6),
                            String.format("%.2f", (afterProcessNanos - afterSelectNanos) / 1e6),
                            String.format("%.2f", (afterDeleteNanos - submitStartNanos) / 1e6),
                            String.format("%.2f", (afterIncrementNanos - afterDeleteNanos) / 1e6),
                            String.format(
                                    "%.2f", (afterCountTotalNanos - afterIncrementNanos) / 1e6),
                            String.format(
                                    "%.2f",
                                    (afterCountQueuedNanos - afterCountTotalNanos) / 1e6));
                });
    }
}
