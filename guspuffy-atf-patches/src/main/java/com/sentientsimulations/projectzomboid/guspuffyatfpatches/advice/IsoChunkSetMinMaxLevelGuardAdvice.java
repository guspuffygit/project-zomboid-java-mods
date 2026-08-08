package com.sentientsimulations.projectzomboid.guspuffyatfpatches.advice;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import com.sentientsimulations.projectzomboid.guspuffyatfpatches.metrics.ChunkCorruptionMetrics;
import net.bytebuddy.asm.Advice;
import zombie.iso.IsoChunk;

/**
 * Advice for {@code IsoChunk.setMinMaxLevel(int, int)} that clamps the level range to the engine's
 * hard {@code [-32, 31]} limit (the range {@code FBORenderCutaways$ChunkLevelsData.getDataForLevel}
 * supports and the {@code z < 64} loops assume).
 *
 * <p>{@code LoadFromDiskOrBufferInternal} reads {@code maxLevel}/{@code minLevel} straight out of
 * the chunk buffer with no validation, and the only other caller ({@code checkLevelRange}) can only
 * ever <em>widen</em> the range — so a garbage level header from a torn chunk buffer survives even
 * the {@code Blam} + {@code LoadBrandNew} regeneration and later NPEs the render thread in {@code
 * ChunkLevelsData.recreateLevel_ExteriorWalls} (via {@code loadInMainThread}), which kills the
 * frame loop and boots the player to the main menu. Clamping here keeps the chunk structurally
 * sane; a torn buffer still fails its per-square parse and takes vanilla's designed corrupt-chunk
 * path (quarantine + regenerate) instead of crashing the client.
 *
 * <p>No lambdas / streams &mdash; advice bodies are inlined into the target method and must be
 * plain imperative Java.
 */
public class IsoChunkSetMinMaxLevelGuardAdvice {

    @Advice.OnMethodEnter
    public static void onEnter(
            @Advice.This IsoChunk self,
            @Advice.Argument(value = 0, readOnly = false) int minLevel,
            @Advice.Argument(value = 1, readOnly = false) int maxLevel) {
        if (minLevel >= -32 && maxLevel <= 31 && minLevel <= maxLevel) {
            return;
        }
        LOGGER.error(
                "IsoChunkSetMinMaxLevelGuardPatch: insane level range [{}, {}] on chunk {},{};"
                        + " clamping (torn or corrupt chunk buffer)",
                minLevel,
                maxLevel,
                self.wx,
                self.wy);
        ChunkCorruptionMetrics.recordLevelHeaderClamped();
        if (minLevel < -32) {
            minLevel = -32;
        } else if (minLevel > 31) {
            minLevel = 31;
        }
        if (maxLevel > 31) {
            maxLevel = 31;
        }
        if (maxLevel < minLevel) {
            minLevel = 0;
            maxLevel = 7;
        }
    }
}
