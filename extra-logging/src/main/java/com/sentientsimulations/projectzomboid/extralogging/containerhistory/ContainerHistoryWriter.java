package com.sentientsimulations.projectzomboid.extralogging.containerhistory;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ConcurrentLinkedQueue;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;

public final class ContainerHistoryWriter {

    private static final long FLUSH_INTERVAL_MS = 1000L;

    private static final ConcurrentLinkedQueue<ContainerTransferRecord> QUEUE =
            new ConcurrentLinkedQueue<>();

    private static ScheduledExecutorService executor;

    private ContainerHistoryWriter() {}

    public static void enqueue(ContainerTransferRecord record) {
        QUEUE.add(record);
        ensureStarted();
    }

    public static void flush() {
        drainAndInsert();
    }

    private static synchronized void ensureStarted() {
        if (executor != null) {
            return;
        }
        executor =
                Executors.newSingleThreadScheduledExecutor(
                        r -> {
                            Thread t = new Thread(r, "ContainerHistory-DB");
                            t.setDaemon(true);
                            return t;
                        });
        executor.scheduleWithFixedDelay(
                () -> {
                    try {
                        drainAndInsert();
                    } catch (Throwable e) {
                        LOGGER.error("[ContainerHistory] Writer flush failed", e);
                    }
                },
                FLUSH_INTERVAL_MS,
                FLUSH_INTERVAL_MS,
                TimeUnit.MILLISECONDS);
        Runtime.getRuntime()
                .addShutdownHook(
                        new Thread(
                                ContainerHistoryWriter::drainAndInsert,
                                "ContainerHistory-DB-Shutdown"));
    }

    private static void drainAndInsert() {
        List<ContainerTransferRecord> batch = new ArrayList<>();
        ContainerTransferRecord r;
        while ((r = QUEUE.poll()) != null) {
            batch.add(r);
        }
        ContainerHistoryRepository.batchInsert(batch);
    }
}
