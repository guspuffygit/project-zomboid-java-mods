package com.sentientsimulations.projectzomboid.guspuffyatfpatches.patch;

import io.pzstorm.storm.core.StormClassTransformer;
import net.bytebuddy.asm.Advice;
import net.bytebuddy.dynamic.ClassFileLocator;
import net.bytebuddy.dynamic.DynamicType;
import net.bytebuddy.matcher.ElementMatchers;
import net.bytebuddy.pool.TypePool;

/**
 * Clamps {@code IsoChunk.setMinMaxLevel(int, int)} arguments to the engine's hard {@code [-32, 31]}
 * level range. The chunk load path reads min/max levels out of the serialized buffer with no
 * validation, and the only other caller can only widen the range — so garbage levels from a torn
 * chunk buffer survive regeneration and NPE the client render thread ({@code
 * FBORenderCutaways$ChunkLevelsData.recreateLevel_ExteriorWalls} via {@code
 * IsoChunk.loadInMainThread} -&gt; {@code IngameState.updateInternal}), booting the player to the
 * main menu. Observed on ATF 2026-08-08 at chunks 918-919,1033.
 *
 * <p>Registered on both client and server: the same unvalidated read runs when the server loads a
 * corrupt {@code map/<wx>/<wy>.bin} from disk (ATF's blam/ history shows this recurring). See
 * {@link
 * com.sentientsimulations.projectzomboid.guspuffyatfpatches.advice.IsoChunkSetMinMaxLevelGuardAdvice}
 * for the failure chain.
 *
 * <p>Client-patch justification (per Storm CLAUDE.md policy): the crash is a render-thread NPE from
 * a torn buffer received over the wire — no server-side change or client Lua can intercept the
 * chunk deserialization path. Fails soft: worst case a corrupt chunk loads with a clamped level
 * range, then takes vanilla's quarantine-and-regenerate path.
 *
 * <p>Staged in this mod for live testing; graduates to Storm core once verified.
 */
public class IsoChunkSetMinMaxLevelGuardPatch extends StormClassTransformer {

    private static final String PKG =
            "com.sentientsimulations.projectzomboid.guspuffyatfpatches.advice.";

    public IsoChunkSetMinMaxLevelGuardPatch() {
        super("zombie.iso.IsoChunk");
    }

    @Override
    public DynamicType.Builder<Object> dynamicType(
            ClassFileLocator locator, TypePool typePool, DynamicType.Builder<Object> builder) {
        return builder.visit(
                Advice.to(
                                typePool.describe(PKG + "IsoChunkSetMinMaxLevelGuardAdvice")
                                        .resolve(),
                                locator)
                        .on(
                                ElementMatchers.named("setMinMaxLevel")
                                        .and(
                                                ElementMatchers.takesArguments(
                                                        int.class, int.class))));
    }
}
