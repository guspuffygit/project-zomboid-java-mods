package com.sentientsimulations.projectzomboid.guspuffyatfpatches.patch;

import io.pzstorm.storm.core.StormClassTransformer;
import net.bytebuddy.asm.Advice;
import net.bytebuddy.dynamic.ClassFileLocator;
import net.bytebuddy.dynamic.DynamicType;
import net.bytebuddy.matcher.ElementMatchers;
import net.bytebuddy.pool.TypePool;

/**
 * Skips {@code FBORenderCutaways$ChunkLevelsData.recreateLevel*} for levels outside {@code [-32,
 * 31]}, where {@code getDataForLevel} returns null and every {@code recreateLevel_*} body NPEs.
 * That NPE propagates through {@code IsoChunk.loadInMainThread} into {@code
 * IngameState.updateInternal}, killing the frame loop and booting the player to the main menu — the
 * fatal second stage of the ATF 2026-08-08 torn-chunk crash.
 *
 * <p>Belt-and-braces to {@link IsoChunkSetMinMaxLevelGuardPatch}, which stops garbage levels at the
 * source; this makes the renderer itself tolerate any chunk that slips through with a corrupt level
 * range. Client-only: the cutaway render path never runs on the dedicated server.
 *
 * <p>Client-patch justification (per Storm CLAUDE.md policy): render-thread crash, unreachable from
 * server-side code or client Lua. Fails soft: an out-of-range level simply gets no cutaway data — a
 * visual no-op instead of a crash.
 *
 * <p>Staged in this mod for live testing; graduates to Storm core once verified.
 */
public class FBORenderCutawaysRecreateLevelGuardPatch extends StormClassTransformer {

    private static final String PKG =
            "com.sentientsimulations.projectzomboid.guspuffyatfpatches.advice.";

    public FBORenderCutawaysRecreateLevelGuardPatch() {
        super("zombie.iso.fboRenderChunk.FBORenderCutaways$ChunkLevelsData");
    }

    @Override
    public DynamicType.Builder<Object> dynamicType(
            ClassFileLocator locator, TypePool typePool, DynamicType.Builder<Object> builder) {
        return builder.visit(
                Advice.to(
                                typePool.describe(PKG + "CutawayRecreateLevelGuardAdvice")
                                        .resolve(),
                                locator)
                        .on(
                                ElementMatchers.nameStartsWith("recreateLevel")
                                        .and(ElementMatchers.takesArguments(int.class))));
    }
}
