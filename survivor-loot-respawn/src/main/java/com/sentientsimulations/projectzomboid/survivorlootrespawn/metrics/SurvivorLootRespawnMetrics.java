package com.sentientsimulations.projectzomboid.survivorlootrespawn.metrics;

import io.prometheus.metrics.core.metrics.Counter;
import io.prometheus.metrics.core.metrics.Gauge;
import io.prometheus.metrics.core.metrics.Histogram;
import io.pzstorm.storm.metrics.StormPrometheus;

/**
 * Prometheus instruments for the Survivor Loot Respawn mod.
 *
 * <p>Every recording method is a no-op if PZ was started without {@code -DprometheusPort}; the
 * collectors still register, nothing is exposed. Naming follows the {@code survivor_loot_respawn_*}
 * prefix so the mod's metrics group together at {@code /metrics}.
 */
public final class SurvivorLootRespawnMetrics {

    private static final Counter LOOTED_OBSERVED =
            Counter.builder()
                    .name("survivor_loot_respawn_looted_observed_total")
                    .help(
                            "Container loot events received by the mod, by source path."
                                    + " path=event for OnContainerLootedEvent (Storm UUID"
                                    + " transfer; covers container-to-container and"
                                    + " container-to-floor drops).")
                    .labelNames("path")
                    .register(StormPrometheus.registry());

    private static final Counter LOOTED_TRACKED =
            Counter.builder()
                    .name("survivor_loot_respawn_looted_tracked_total")
                    .help(
                            "Outcome of attempting to track a looted container. inserted = new"
                                    + " row in DB; duplicate = ON CONFLICT no-op (existing row);"
                                    + " skipped_* = filtered before insert.")
                    .labelNames("outcome")
                    .register(StormPrometheus.registry());

    private static final Counter DISCOVERY_INSERTED =
            Counter.builder()
                    .name("survivor_loot_respawn_discovery_inserted_total")
                    .help(
                            "Rows inserted by chunk-load discovery (containers found explored &"
                                    + " looted before the mod started tracking them).")
                    .register(StormPrometheus.registry());

    private static final Counter DISCOVERY_SKIPPED =
            Counter.builder()
                    .name("survivor_loot_respawn_discovery_skipped_total")
                    .help(
                            "Containers seen during chunk discovery that were skipped. reason ="
                                    + " null | unexplored | not_looted | no_items | full |"
                                    + " no_loot_table (room + type resolves to a distribution"
                                    + " with zero items + zero proceduralItems, e.g. counter"
                                    + " in vanilla rooms[\"empty\"]).")
                    .labelNames("reason")
                    .register(StormPrometheus.registry());

    private static final Counter ROLLS =
            Counter.builder()
                    .name("survivor_loot_respawn_rolls_total")
                    .help(
                            "Per-container hourly roll outcomes. won = chance rolled high enough"
                                    + " to queue for respawn; lost = roll fell short, will roll"
                                    + " again next hour.")
                    .labelNames("outcome")
                    .register(StormPrometheus.registry());

    private static final Counter RESPAWN_RESULT =
            Counter.builder()
                    .name("survivor_loot_respawn_result_total")
                    .help(
                            "ChunkLoadedRespawnHandler fill result, one increment per queued row"
                                    + " processed. result mirrors the FillResult enum"
                                    + " (respawned, retry_*, delete_*).")
                    .labelNames("result")
                    .register(StormPrometheus.registry());

    private static final Counter FILL_ADDED_NOTHING =
            Counter.builder()
                    .name("survivor_loot_respawn_fill_added_nothing_total")
                    .help(
                            "Times ItemPickerJava.fillContainer returned with no new items for a"
                                    + " queued container. Repeated hits for the same container_type"
                                    + " mean that type has no loot distribution (or its tables"
                                    + " produced zero rolls). After the per-row retry cap the row"
                                    + " is evicted; see fill_give_up_total.")
                    .labelNames("container_type")
                    .register(StormPrometheus.registry());

    private static final Counter FILL_GIVE_UP =
            Counter.builder()
                    .name("survivor_loot_respawn_fill_give_up_total")
                    .help(
                            "Queued rows evicted after exceeding the fill-added-nothing retry"
                                    + " cap. Indicates a container_type whose distribution never"
                                    + " produces loot in this world.")
                    .labelNames("container_type")
                    .register(StormPrometheus.registry());

    private static final Counter PATCH_INTERCEPT =
            Counter.builder()
                    .name("survivor_loot_respawn_vanilla_interval_intercepted_total")
                    .help(
                            "Times LootRespawnPatch overrode vanilla"
                                    + " zombie.LootRespawn.getRespawnInterval to 0, disabling"
                                    + " vanilla loot respawn for that call.")
                    .register(StormPrometheus.registry());

    private static final Counter ON_CHUNK_LOADED_ERRORS =
            Counter.builder()
                    .name("survivor_loot_respawn_on_chunk_loaded_errors_total")
                    .help(
                            "Unhandled exceptions caught inside"
                                    + " ChunkLoadedRespawnHandler.onChunkLoaded. The Byte Buddy"
                                    + " advice swallows throwables, so without this counter the"
                                    + " failures would be invisible.")
                    .register(StormPrometheus.registry());

    private static final Counter DB_ERRORS =
            Counter.builder()
                    .name("survivor_loot_respawn_db_errors_total")
                    .help("SQL exceptions raised by the repository, labelled by operation.")
                    .labelNames("op")
                    .register(StormPrometheus.registry());

    private static final Histogram CHUNK_PROCESS_DURATION =
            Histogram.builder()
                    .name("survivor_loot_respawn_chunk_process_duration_seconds")
                    .help(
                            "Time to walk one chunk's queued rows and attempt to fill them."
                                    + " Fires on every chunk load and during the 10-minute sweep.")
                    .nativeOnly()
                    .register(StormPrometheus.registry());

    private static final Histogram CHUNK_DISCOVER_DURATION =
            Histogram.builder()
                    .name("survivor_loot_respawn_chunk_discover_duration_seconds")
                    .help(
                            "Time to walk one chunk's squares and batch-insert any explored,"
                                    + " looted containers not yet tracked.")
                    .nativeOnly()
                    .register(StormPrometheus.registry());

    private static final Histogram HOURLY_ROLL_DURATION =
            Histogram.builder()
                    .name("survivor_loot_respawn_hourly_roll_duration_seconds")
                    .help(
                            "Time for the hourly roll cycle: select eligible rows, compute"
                                    + " chance, batch-mark winners as queued.")
                    .nativeOnly()
                    .register(StormPrometheus.registry());

    private static final Histogram TENMIN_SWEEP_DURATION =
            Histogram.builder()
                    .name("survivor_loot_respawn_tenmin_sweep_duration_seconds")
                    .help(
                            "Time for the 10-minute fallback sweep over every loaded chunk."
                                    + " Catches rows that were queued AFTER their chunk was"
                                    + " already loaded.")
                    .nativeOnly()
                    .register(StormPrometheus.registry());

    private static final Histogram WINNING_CHANCE_PERCENT =
            Histogram.builder()
                    .name("survivor_loot_respawn_winning_chance_percent")
                    .help(
                            "Distribution of winning roll chances (percent). Tells you whether"
                                    + " wins are clustered low (curve too generous) or high"
                                    + " (curve too steep).")
                    .classicUpperBounds(1, 5, 10, 25, 50, 75, 90, 99, 100)
                    .register(StormPrometheus.registry());

    private static final Gauge ROWS_TRACKED =
            Gauge.builder()
                    .name("survivor_loot_respawn_rows_tracked")
                    .help("Total rows in container_loot_state.")
                    .register(StormPrometheus.registry());

    private static final Gauge ROWS_QUEUED =
            Gauge.builder()
                    .name("survivor_loot_respawn_rows_queued")
                    .help(
                            "Rows currently queued for respawn (respawn_queued_at_hours IS NOT"
                                    + " NULL).")
                    .register(StormPrometheus.registry());

    private static final Gauge MOD_ENABLED =
            Gauge.builder()
                    .name("survivor_loot_respawn_enabled")
                    .help(
                            "1 when LootRespawnType sandbox option = Exponential, 0 when"
                                    + " Vanilla.")
                    .register(StormPrometheus.registry());

    private SurvivorLootRespawnMetrics() {}

    public static void recordLootedObserved(String path) {
        LOOTED_OBSERVED.labelValues(path).inc();
    }

    public static void recordLootedTracked(String outcome) {
        LOOTED_TRACKED.labelValues(outcome).inc();
    }

    public static void recordDiscoveryInserted(int count) {
        if (count > 0) {
            DISCOVERY_INSERTED.inc(count);
        }
    }

    public static void recordDiscoverySkipped(String reason) {
        DISCOVERY_SKIPPED.labelValues(reason).inc();
    }

    public static void recordRoll(boolean won, double chancePercent) {
        ROLLS.labelValues(won ? "won" : "lost").inc();
        if (won) {
            WINNING_CHANCE_PERCENT.observe(chancePercent);
        }
    }

    public static void recordRespawnResult(String result) {
        RESPAWN_RESULT.labelValues(result).inc();
    }

    public static void recordFillAddedNothing(String containerType) {
        FILL_ADDED_NOTHING.labelValues(containerType).inc();
    }

    public static void recordFillGiveUp(String containerType) {
        FILL_GIVE_UP.labelValues(containerType).inc();
    }

    public static void recordPatchIntercept() {
        PATCH_INTERCEPT.inc();
    }

    public static void recordOnChunkLoadedError() {
        ON_CHUNK_LOADED_ERRORS.inc();
    }

    public static void recordDbError(String op) {
        DB_ERRORS.labelValues(op).inc();
    }

    public static void observeChunkProcessSeconds(double seconds) {
        CHUNK_PROCESS_DURATION.observe(seconds);
    }

    public static void observeChunkDiscoverSeconds(double seconds) {
        CHUNK_DISCOVER_DURATION.observe(seconds);
    }

    public static void observeHourlyRollSeconds(double seconds) {
        HOURLY_ROLL_DURATION.observe(seconds);
    }

    public static void observeTenMinSweepSeconds(double seconds) {
        TENMIN_SWEEP_DURATION.observe(seconds);
    }

    public static void setRowsTracked(long n) {
        ROWS_TRACKED.set(n);
    }

    public static void setRowsQueued(long n) {
        ROWS_QUEUED.set(n);
    }

    public static void setModEnabled(boolean enabled) {
        MOD_ENABLED.set(enabled ? 1 : 0);
    }
}
