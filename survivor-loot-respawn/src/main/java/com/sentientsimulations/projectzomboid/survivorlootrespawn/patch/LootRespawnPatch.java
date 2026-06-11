package com.sentientsimulations.projectzomboid.survivorlootrespawn.patch;

import com.sentientsimulations.projectzomboid.survivorlootrespawn.ChunkLoadedRespawnHandler;
import com.sentientsimulations.projectzomboid.survivorlootrespawn.config.SurvivorLootRespawnConfig;
import com.sentientsimulations.projectzomboid.survivorlootrespawn.metrics.SurvivorLootRespawnMetrics;
import io.pzstorm.storm.core.StormClassTransformer;
import net.bytebuddy.asm.Advice;
import net.bytebuddy.dynamic.ClassFileLocator;
import net.bytebuddy.dynamic.DynamicType;
import net.bytebuddy.matcher.ElementMatchers;
import net.bytebuddy.pool.TypePool;

public class LootRespawnPatch extends StormClassTransformer {

    public LootRespawnPatch() {
        super("zombie.LootRespawn");
    }

    @Override
    public DynamicType.Builder<Object> dynamicType(
            ClassFileLocator locator, TypePool typePool, DynamicType.Builder<Object> builder) {
        return builder.visit(
                        Advice.to(GetRespawnIntervalAdvice.class)
                                .on(ElementMatchers.named("getRespawnInterval")))
                .visit(Advice.to(ChunkLoadedAdvice.class).on(ElementMatchers.named("chunkLoaded")));
    }

    public static class GetRespawnIntervalAdvice {

        @Advice.OnMethodExit(suppress = Throwable.class)
        public static void onExit(@Advice.Return(readOnly = false) int interval) {
            if (interval <= 0) {
                return;
            }
            if (SurvivorLootRespawnConfig.isModEnabled()) {
                interval = 0;
                SurvivorLootRespawnMetrics.recordPatchIntercept();
            }
        }
    }

    public static class ChunkLoadedAdvice {

        @Advice.OnMethodExit(suppress = Throwable.class)
        public static void onExit(@Advice.Argument(0) Object chunk) {
            ChunkLoadedRespawnHandler.onChunkLoaded(chunk);
        }
    }
}
