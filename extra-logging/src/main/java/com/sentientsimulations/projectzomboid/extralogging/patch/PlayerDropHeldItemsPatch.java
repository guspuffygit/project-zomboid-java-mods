package com.sentientsimulations.projectzomboid.extralogging.patch;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import com.sentientsimulations.projectzomboid.extralogging.events.HeldItemsDroppedEvent;
import io.pzstorm.storm.core.StormClassTransformer;
import io.pzstorm.storm.event.core.StormEventDispatcher;
import net.bytebuddy.asm.Advice;
import net.bytebuddy.dynamic.ClassFileLocator;
import net.bytebuddy.dynamic.DynamicType;
import net.bytebuddy.matcher.ElementMatchers;
import net.bytebuddy.pool.TypePool;
import zombie.characters.IsoPlayer;
import zombie.core.raknet.UdpConnection;
import zombie.inventory.InventoryItem;
import zombie.network.fields.character.PlayerID;

/**
 * Patches {@link zombie.network.packets.character.PlayerDropHeldItemsPacket} to dispatch an event
 * when a player drops held items. Uses {@code @OnMethodEnter} to capture items before they are
 * removed from the player's hands.
 */
public class PlayerDropHeldItemsPatch extends StormClassTransformer {

    public PlayerDropHeldItemsPatch() {
        super("zombie.network.packets.character.PlayerDropHeldItemsPacket");
    }

    @Override
    public DynamicType.Builder<Object> dynamicType(
            ClassFileLocator locator, TypePool typePool, DynamicType.Builder<Object> builder) {
        return builder.visit(
                Advice.to(ProcessServerAdvice.class).on(ElementMatchers.named("processServer")));
    }

    public static class ProcessServerAdvice {

        @Advice.OnMethodEnter(suppress = Throwable.class)
        public static void beforeProcessServer(
                @Advice.This PlayerID self,
                @Advice.FieldValue("x") int x,
                @Advice.FieldValue("y") int y,
                @Advice.FieldValue("z") int z,
                @Advice.FieldValue("isThrow") boolean isThrow,
                @Advice.Argument(1) UdpConnection connection) {

            LOGGER.info("[PlayerDropHeldItemsPatch] advice entered");

            IsoPlayer player = self.getPlayer();
            if (player == null) {
                LOGGER.debug("[PlayerDropHeldItemsPatch] skipped: player is null");
                return;
            }

            InventoryItem primary = player.getPrimaryHandItem();
            InventoryItem secondary = player.getSecondaryHandItem();

            if (primary == null && secondary == null) {
                LOGGER.debug(
                        "[PlayerDropHeldItemsPatch] skipped: no held items for {}",
                        player.getUsername());
                return;
            }

            String primaryType = primary != null ? primary.getFullType() : null;
            String secondaryType = secondary != null ? secondary.getFullType() : null;

            // Avoid duplicate logging when both hands hold the same item
            if (primary == secondary) {
                secondaryType = null;
            }

            LOGGER.debug(
                    "[PlayerDropHeldItemsPatch] dispatching event for {} primary={} secondary={}",
                    player.getUsername(),
                    primaryType,
                    secondaryType);

            StormEventDispatcher.dispatchEvent(
                    new HeldItemsDroppedEvent(
                            player.getUsername(),
                            connection.getSteamId(),
                            primaryType,
                            secondaryType,
                            x,
                            y,
                            z,
                            isThrow));
        }
    }
}
