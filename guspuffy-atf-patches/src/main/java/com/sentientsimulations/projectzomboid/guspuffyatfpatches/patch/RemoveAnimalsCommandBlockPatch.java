package com.sentientsimulations.projectzomboid.guspuffyatfpatches.patch;

import io.pzstorm.storm.core.StormClassTransformer;
import net.bytebuddy.asm.Advice;
import net.bytebuddy.dynamic.ClassFileLocator;
import net.bytebuddy.dynamic.DynamicType;
import net.bytebuddy.matcher.ElementMatchers;
import net.bytebuddy.pool.TypePool;

/**
 * Blocks {@code /remove animals}. Vanilla queues {@code AnimalInstanceManager.removeAnimals}, which
 * deletes every animal on the server, not just the ones near the admin. The debug context menu's
 * Animals &gt; Remove All sends this same command, so one misclick wipes every player's livestock.
 * The other {@code /remove} subsystems are untouched.
 */
public class RemoveAnimalsCommandBlockPatch extends StormClassTransformer {

    private static final String PKG =
            "com.sentientsimulations.projectzomboid.guspuffyatfpatches.advice.";

    public RemoveAnimalsCommandBlockPatch() {
        super("zombie.commands.serverCommands.RemoveCommand");
    }

    @Override
    public DynamicType.Builder<Object> dynamicType(
            ClassFileLocator locator, TypePool typePool, DynamicType.Builder<Object> builder) {
        return builder.visit(
                Advice.to(
                                typePool.describe(PKG + "RemoveAnimalsCommandBlockAdvice")
                                        .resolve(),
                                locator)
                        .on(ElementMatchers.named("Remove").and(ElementMatchers.isStatic())));
    }
}
