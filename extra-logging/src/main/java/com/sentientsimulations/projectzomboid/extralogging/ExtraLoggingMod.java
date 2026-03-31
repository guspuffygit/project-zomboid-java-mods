package com.sentientsimulations.projectzomboid.extralogging;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import com.sentientsimulations.projectzomboid.extralogging.patch.*;
import io.pzstorm.storm.core.StormClassTransformer;
import io.pzstorm.storm.event.core.StormEventDispatcher;
import io.pzstorm.storm.event.core.SubscribeEvent;
import io.pzstorm.storm.event.lua.OnCharacterDeathEvent;
import io.pzstorm.storm.event.packet.*;
import io.pzstorm.storm.mod.ZomboidMod;
import io.pzstorm.storm.util.StormEnv;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

public class ExtraLoggingMod implements ZomboidMod {

    @Override
    public void registerEventHandlers() {
        if (StormEnv.isStormServer()) {
            LOGGER.debug("Registering event handler for {}", ExtraLoggingMod.class.getName());
            StormEventDispatcher.registerEventHandler(this);
        }
    }

    @Override
    public List<StormClassTransformer> getClassTransformers() {
        if (!StormEnv.isStormServer()) {
            return Collections.emptyList();
        }

        List<StormClassTransformer> transformers = new ArrayList<>();
        //        transformers.add(new AddItemToMapPatch());
        //        transformers.add(new ItemTransactionPatch());
        //        transformers.add(new PlayerDropHeldItemsPatch());
        transformers.add(new ServerWorldDatabasePatch());
        transformers.add(new GameServerPatch());

        return transformers;
    }

    // Death events

    @SubscribeEvent
    public void onCharacterDeath(OnCharacterDeathEvent event) {
        DeathEventHandler.onCharacterDeath(event);
    }

    // Item events

    @SubscribeEvent
    public void onAddInventoryItemToContainer(AddInventoryItemToContainerPacketEvent event) {
        ItemEventHandler.onAddInventoryItemToContainer(event);
    }

    @SubscribeEvent
    public void onAddItemToMap(AddItemToMapPacketEvent event) {
        ItemEventHandler.onAddItemToMap(event);
    }

    @SubscribeEvent
    public void onBuildAction(BuildActionPacketEvent event) {
        ItemEventHandler.onBuildAction(event);
    }

    @SubscribeEvent
    public void onNetTimedAction(NetTimedActionPacketEvent event) {
        ItemEventHandler.onNetTimedAction(event);
    }

    @SubscribeEvent
    public void onPlayerDropHeldItems(PlayerDropHeldItemsPacketEvent event) {
        ItemEventHandler.onPlayerDropHeldItems(event);
    }

    @SubscribeEvent
    public void onRemoveItemFromSquare(RemoveItemFromSquarePacketEvent event) {
        ItemEventHandler.onRemoveItemFromSquare(event);
    }

    @SubscribeEvent
    public void onSledgehammerDestroy(SledgehammerDestroyPacketEvent event) {
        ItemEventHandler.onSledgehammerDestroy(event);
    }

    // Safehouse events

    @SubscribeEvent
    public void onSafehouseClaim(SafehouseClaimPacketEvent event) {
        SafehouseEventHandler.onSafehouseClaim(event);
    }

    @SubscribeEvent
    public void onSafehouseRelease(SafehouseReleasePacketEvent event) {
        SafehouseEventHandler.onSafehouseRelease(event);
    }

    @SubscribeEvent
    public void onSafehouseChangeOwner(SafehouseChangeOwnerPacketEvent event) {
        SafehouseEventHandler.onSafehouseChangeOwner(event);
    }

    @SubscribeEvent
    public void onSafehouseChangeMember(SafehouseChangeMemberPacketEvent event) {
        SafehouseEventHandler.onSafehouseChangeMember(event);
    }

    @SubscribeEvent
    public void onSafehouseInvite(SafehouseInvitePacketEvent event) {
        SafehouseEventHandler.onSafehouseInvite(event);
    }

    @SubscribeEvent
    public void onSafehouseAccept(SafehouseAcceptPacketEvent event) {
        SafehouseEventHandler.onSafehouseAccept(event);
    }

    @SubscribeEvent
    public void onSafehouseChangeRespawn(SafehouseChangeRespawnPacketEvent event) {
        SafehouseEventHandler.onSafehouseChangeRespawn(event);
    }

    @SubscribeEvent
    public void onSafehouseChangeTitle(SafehouseChangeTitlePacketEvent event) {
        SafehouseEventHandler.onSafehouseChangeTitle(event);
    }

    @SubscribeEvent
    public void onSafezoneClaim(SafezoneClaimPacketEvent event) {
        SafehouseEventHandler.onSafezoneClaim(event);
    }
}
