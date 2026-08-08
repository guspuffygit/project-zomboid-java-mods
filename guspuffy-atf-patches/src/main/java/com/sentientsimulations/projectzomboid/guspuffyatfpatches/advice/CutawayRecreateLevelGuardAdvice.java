package com.sentientsimulations.projectzomboid.guspuffyatfpatches.advice;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import com.sentientsimulations.projectzomboid.guspuffyatfpatches.metrics.ChunkCorruptionMetrics;
import net.bytebuddy.asm.Advice;

/**
 * Advice for {@code FBORenderCutaways$ChunkLevelsData.recreateLevel*} that skips the method when
 * the level is outside {@code [-32, 31]} — the range where {@code getDataForLevel} returns
 * non-null. Outside it, every {@code recreateLevel_*} body dereferences the null lookup and the NPE
 * propagates up through {@code IsoChunk.loadInMainThread} into {@code IngameState.updateInternal},
 * killing the frame loop and booting the player to the main menu (observed on ATF 2026-08-08 after
 * a torn streamed chunk left garbage min/max levels on the chunk).
 *
 * <p>Belt-and-braces to {@code IsoChunkSetMinMaxLevelGuardPatch}: with the clamp in place an
 * out-of-range level should never reach here, so any hit is logged (throttled — a garbage level
 * range can drive this per-frame) and counted.
 *
 * <p>No lambdas / streams &mdash; advice bodies are inlined into the target method and must be
 * plain imperative Java. Static fields referenced from the inlined body must be public.
 */
public class CutawayRecreateLevelGuardAdvice {

    public static volatile long lastWarnMillis;

    @Advice.OnMethodEnter(skipOn = Advice.OnNonDefaultValue.class)
    public static boolean onEnter(@Advice.Argument(0) int level) {
        if (level >= -32 && level <= 31) {
            return false;
        }
        ChunkCorruptionMetrics.recordCutawayLevelSkipped();
        long now = System.currentTimeMillis();
        if (now - lastWarnMillis > 1000L) {
            lastWarnMillis = now;
            LOGGER.error(
                    "CutawayRecreateLevelGuardPatch: skipping cutaway recreate for insane level {}"
                            + " (chunk has a corrupt level range)",
                    level);
        }
        return true;
    }
}
