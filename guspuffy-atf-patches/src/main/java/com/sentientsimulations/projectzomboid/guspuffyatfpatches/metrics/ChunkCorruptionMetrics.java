package com.sentientsimulations.projectzomboid.guspuffyatfpatches.metrics;

import io.prometheus.metrics.core.datapoints.CounterDataPoint;
import io.prometheus.metrics.core.metrics.Counter;
import io.pzstorm.storm.metrics.StormPrometheus;

/**
 * Counters for chunk-corruption defenses. Each event is a chunk that would previously have been a
 * silent regeneration ({@code load_failure}), a crash-inducing garbage level header ({@code
 * level_header_clamped}), or a render-thread NPE ({@code cutaway_level_skipped}). Any nonzero rate
 * on a server means clients received (or disk contained) a torn chunk buffer and the incident
 * should be investigated via the {@code blam/} quarantine directory in the save.
 *
 * <p>Named {@code pz_*} (not {@code guspuffyatfpatches_*}) deliberately: these patches are staged
 * here for live testing before graduating into Storm core, and the metric name should survive the
 * move. When they graduate, remove this mod's copy first — registering the same metric twice throws
 * at class-init.
 */
public final class ChunkCorruptionMetrics {

    private static final Counter EVENTS =
            Counter.builder()
                    .name("pz_chunk_corruption_events_total")
                    .help("Chunk corruption defenses triggered, by event.")
                    .labelNames("event")
                    .register(StormPrometheus.registry());

    private static final CounterDataPoint LOAD_FAILURE = EVENTS.labelValues("load_failure");
    private static final CounterDataPoint LEVEL_HEADER_CLAMPED =
            EVENTS.labelValues("level_header_clamped");
    private static final CounterDataPoint CUTAWAY_LEVEL_SKIPPED =
            EVENTS.labelValues("cutaway_level_skipped");

    private ChunkCorruptionMetrics() {}

    public static void recordLoadFailure() {
        LOAD_FAILURE.inc();
    }

    public static void recordLevelHeaderClamped() {
        LEVEL_HEADER_CLAMPED.inc();
    }

    public static void recordCutawayLevelSkipped() {
        CUTAWAY_LEVEL_SKIPPED.inc();
    }
}
