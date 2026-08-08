package com.sentientsimulations.projectzomboid.guspuffyatfpatches.advice;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import com.sentientsimulations.projectzomboid.guspuffyatfpatches.metrics.ChunkCorruptionMetrics;
import net.bytebuddy.asm.Advice;

/**
 * Advice for {@code IsoChunk.BackupBlam(int, int, Exception)} — the single choke point vanilla
 * routes every failed chunk load through (torn streamed buffer on the client, corrupt {@code
 * map/<wx>/<wy>.bin} on the server) before quarantining a copy under {@code <save>/blam/} and
 * regenerating the chunk from the base map.
 *
 * <p>Vanilla already self-heals here but does it silently (an ExceptionLogger line lost in the
 * noise). This surfaces every occurrence as an ERROR with square coordinates plus a Prometheus
 * counter, so a recurrence of the ATF 2026-08-08 torn-chunk incident is visible immediately instead
 * of being discovered via a player crash report. ATF's blam/ directory shows 24 such quarantines
 * (Jul 30 - Aug 8), each one a silent reset of that chunk's player constructions.
 *
 * <p>No lambdas / streams &mdash; advice bodies are inlined into the target method and must be
 * plain imperative Java.
 */
public class IsoChunkBackupBlamAdvice {

    @Advice.OnMethodEnter
    public static void onEnter(
            @Advice.Argument(0) int wx,
            @Advice.Argument(1) int wy,
            @Advice.Argument(2) Exception ex) {
        ChunkCorruptionMetrics.recordLoadFailure();
        LOGGER.error(
                "IsoChunkBackupBlamPatch: chunk {},{} (squares {},{} to {},{}) failed to load and"
                        + " will be quarantined to blam/ and regenerated: {}",
                wx,
                wy,
                wx * 8,
                wy * 8,
                wx * 8 + 7,
                wy * 8 + 7,
                ex);
    }
}
