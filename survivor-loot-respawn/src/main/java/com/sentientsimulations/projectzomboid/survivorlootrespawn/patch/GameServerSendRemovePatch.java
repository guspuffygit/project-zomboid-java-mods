package com.sentientsimulations.projectzomboid.survivorlootrespawn.patch;

import com.sentientsimulations.projectzomboid.survivorlootrespawn.ContainerLootedHandler;
import io.pzstorm.storm.core.StormClassTransformer;
import net.bytebuddy.asm.Advice;
import net.bytebuddy.dynamic.ClassFileLocator;
import net.bytebuddy.dynamic.DynamicType;
import net.bytebuddy.matcher.ElementMatchers;
import net.bytebuddy.pool.TypePool;

/**
 * Hooks {@code GameServer.sendRemoveItemFromContainer(ItemContainer, InventoryItem)} on the server.
 * This is the only signal the server emits when items leave a container via the vanilla TimedAction
 * server-mirror path — the floor-drop case that bypasses both {@code OnContainerLootedEvent} (Storm
 * UUID transfer only) and {@code RemoveInventoryItemFromContainerPacketEvent} (inbound packets
 * only; floor drops broadcast outbound from the server).
 */
public class GameServerSendRemovePatch extends StormClassTransformer {

    public GameServerSendRemovePatch() {
        super("zombie.network.GameServer");
    }

    @Override
    public DynamicType.Builder<Object> dynamicType(
            ClassFileLocator locator, TypePool typePool, DynamicType.Builder<Object> builder) {
        return builder.visit(
                Advice.to(SendRemoveAdvice.class)
                        .on(
                                ElementMatchers.named("sendRemoveItemFromContainer")
                                        .and(ElementMatchers.takesArguments(2))));
    }

    public static class SendRemoveAdvice {

        @Advice.OnMethodExit(suppress = Throwable.class)
        public static void onExit(@Advice.Argument(0) Object container) {
            ContainerLootedHandler.onServerSendRemove(container);
        }
    }
}
