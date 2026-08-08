package com.sentientsimulations.projectzomboid.guspuffyatfpatches.patch;

import io.pzstorm.storm.core.StormClassTransformer;
import net.bytebuddy.asm.Advice;
import net.bytebuddy.dynamic.ClassFileLocator;
import net.bytebuddy.dynamic.DynamicType;
import net.bytebuddy.matcher.ElementMatchers;
import net.bytebuddy.pool.TypePool;

/**
 * Surfaces every failed chunk load — {@code IsoChunk.BackupBlam(int, int, Exception)} is the choke
 * point vanilla routes both the torn-streamed-buffer (client) and corrupt-disk-file (server)
 * failure paths through before quarantining the bytes under {@code <save>/blam/} and regenerating
 * the chunk. Vanilla's self-heal is silent; this adds an ERROR log with square coordinates and the
 * {@code pz_chunk_corruption_events_total{event="load_failure"}} counter so admins detect a
 * recurrence of the ATF 2026-08-08 incident without waiting for a player crash report.
 *
 * <p>Registered on both client and server. Observability only — no behavior change.
 *
 * <p>Staged in this mod for live testing; graduates to Storm core once verified.
 */
public class IsoChunkBackupBlamPatch extends StormClassTransformer {

    private static final String PKG =
            "com.sentientsimulations.projectzomboid.guspuffyatfpatches.advice.";

    public IsoChunkBackupBlamPatch() {
        super("zombie.iso.IsoChunk");
    }

    @Override
    public DynamicType.Builder<Object> dynamicType(
            ClassFileLocator locator, TypePool typePool, DynamicType.Builder<Object> builder) {
        return builder.visit(
                Advice.to(typePool.describe(PKG + "IsoChunkBackupBlamAdvice").resolve(), locator)
                        .on(
                                ElementMatchers.named("BackupBlam")
                                        .and(
                                                ElementMatchers.takesArguments(
                                                        int.class, int.class, Exception.class))));
    }
}
