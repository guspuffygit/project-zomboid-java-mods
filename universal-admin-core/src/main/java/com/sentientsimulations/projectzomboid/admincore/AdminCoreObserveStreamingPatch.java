package com.sentientsimulations.projectzomboid.admincore;

import io.pzstorm.storm.core.StormClassTransformer;
import net.bytebuddy.asm.Advice;
import net.bytebuddy.description.modifier.FieldManifestation;
import net.bytebuddy.description.modifier.Ownership;
import net.bytebuddy.description.modifier.Visibility;
import net.bytebuddy.dynamic.ClassFileLocator;
import net.bytebuddy.dynamic.DynamicType;
import net.bytebuddy.matcher.ElementMatchers;
import net.bytebuddy.pool.TypePool;

public final class AdminCoreObserveStreamingPatch extends StormClassTransformer {
    private final String name;

    public AdminCoreObserveStreamingPatch(String name) {
        super(name);
        this.name = name;
    }

    @Override
    public DynamicType.Builder<Object> dynamicType(
            ClassFileLocator locator, TypePool pool, DynamicType.Builder<Object> builder) {
        builder =
                builder.defineField(
                                AdminCoreObserveStreaming.MARKER,
                                boolean.class,
                                Visibility.PUBLIC,
                                Ownership.STATIC,
                                FieldManifestation.FINAL)
                        .value(true);
        if (name.equals("zombie.iso.IsoChunkMap"))
            return builder.visit(
                            advice("PhysicalMap", locator, pool)
                                    .on(ElementMatchers.named("ProcessChunkPos")))
                    .visit(
                            advice("Accept", locator, pool)
                                    .on(ElementMatchers.named("setChunkDirect")));
        if (name.equals("zombie.iso.WorldStreamer"))
            return builder.visit(
                    advice("Request", locator, pool).on(ElementMatchers.named("shouldSendChunk")));
        return builder.visit(
                        advice("Square", locator, pool)
                                .on(
                                        ElementMatchers.named("getGridSquare")
                                                .and(
                                                        ElementMatchers.takesArguments(
                                                                int.class, int.class, int.class))))
                .visit(
                        advice("Chunk", locator, pool)
                                .on(
                                        ElementMatchers.named("getChunk")
                                                .and(
                                                        ElementMatchers.takesArguments(
                                                                int.class, int.class))))
                .visit(
                        advice("ChunkSquare", locator, pool)
                                .on(
                                        ElementMatchers.named("getChunkForGridSquare")
                                                .and(
                                                        ElementMatchers.takesArguments(
                                                                int.class, int.class, int.class))));
    }

    private static Advice advice(String nested, ClassFileLocator locator, TypePool pool) {
        return Advice.to(
                pool.describe(
                                "com.sentientsimulations.projectzomboid.admincore.AdminCoreObserveStreamingAdvice$"
                                        + nested)
                        .resolve(),
                locator);
    }
}
