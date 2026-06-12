package com.sentientsimulations.projectzomboid.extralogging.patch;

import com.sentientsimulations.projectzomboid.extralogging.containerhistory.ContainerLootSpawnHandler;
import io.pzstorm.storm.core.StormClassTransformer;
import java.util.ArrayList;
import net.bytebuddy.asm.Advice;
import net.bytebuddy.dynamic.ClassFileLocator;
import net.bytebuddy.dynamic.DynamicType;
import net.bytebuddy.matcher.ElementMatchers;
import net.bytebuddy.pool.TypePool;
import zombie.inventory.InventoryItem;
import zombie.inventory.ItemContainer;

/**
 * Instruments {@code ItemPickerJava.fillContainer(ItemContainer, IsoPlayer)} so the container
 * history database records every item spawned by loot generation. The enter advice snapshots the
 * container's current items; the exit advice forwards the snapshot + post-fill state to {@link
 * ContainerLootSpawnHandler} which computes the diff and inserts one row per fresh item.
 */
public class ItemPickerJavaPatch extends StormClassTransformer {

    public ItemPickerJavaPatch() {
        super("zombie.inventory.ItemPickerJava");
    }

    @Override
    public DynamicType.Builder<Object> dynamicType(
            ClassFileLocator locator, TypePool typePool, DynamicType.Builder<Object> builder) {
        return builder.visit(
                Advice.to(FillContainerAdvice.class).on(ElementMatchers.named("fillContainer")));
    }

    public static class FillContainerAdvice {

        @Advice.OnMethodEnter(suppress = Throwable.class)
        public static void onEnter(
                @Advice.Argument(0) ItemContainer container,
                @Advice.Local("stormSnapshot") ArrayList<InventoryItem> stormSnapshot) {
            stormSnapshot = ContainerLootSpawnHandler.snapshot(container);
        }

        @Advice.OnMethodExit(suppress = Throwable.class)
        public static void onExit(
                @Advice.Argument(0) ItemContainer container,
                @Advice.Local("stormSnapshot") ArrayList<InventoryItem> stormSnapshot) {
            ContainerLootSpawnHandler.onFillComplete(container, stormSnapshot);
        }
    }
}
