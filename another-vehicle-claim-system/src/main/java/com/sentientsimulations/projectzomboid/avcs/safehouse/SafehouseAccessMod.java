package com.sentientsimulations.projectzomboid.avcs.safehouse;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import com.sentientsimulations.projectzomboid.avcs.safehouse.commands.*;
import io.pzstorm.storm.event.core.OnClientCommand;
import io.pzstorm.storm.event.core.StormEventDispatcher;
import io.pzstorm.storm.event.core.SubscribeEvent;
import io.pzstorm.storm.event.lua.OnServerStartedEvent;
import io.pzstorm.storm.mod.ZomboidMod;
import java.sql.SQLException;

public class SafehouseAccessMod implements ZomboidMod {

    @Override
    public void registerEventHandlers() {
        LOGGER.info("[AVCSSafehouse] Registering event handlers");
        StormEventDispatcher.registerEventHandler(this);
        LOGGER.info("[AVCSSafehouse] Event handlers registered successfully");
    }

    @SubscribeEvent
    public void onServerStarted(OnServerStartedEvent event) {
        LOGGER.info(
                "[AVCSSafehouse] onServerStarted fired, initializing DB at {}",
                SafehouseAccessBridge.getDbPath());
        try (SafehouseAccessDatabase db =
                new SafehouseAccessDatabase(SafehouseAccessBridge.getDbPath())) {
            LOGGER.info("[AVCSSafehouse] Database initialized successfully");
        } catch (SQLException e) {
            LOGGER.error("[AVCSSafehouse] Failed to initialize database", e);
        }
    }

    @OnClientCommand
    public void onAddAccess(OnClientAddAccessCommand event) {
        String ownerUsername = event.getPlayer().getUsername();
        String allowedUsername = event.getAllowedUsername();
        LOGGER.info(
                "[AVCSSafehouse] onAddAccess: owner={}, allowed={}",
                ownerUsername,
                allowedUsername);
        if (allowedUsername == null) {
            LOGGER.warn("[AVCSSafehouse] Invalid addAccess args - allowedUsername is null");
            return;
        }
        String error = SafehouseAccessBridge.addAccess(ownerUsername, allowedUsername);
        if (error != null) {
            LOGGER.warn("[AVCSSafehouse] addAccess failed: {}", error);
            return;
        }
        SafehouseAccessBridge.broadcast();
    }

    @OnClientCommand
    public void onRemoveAccess(OnClientRemoveAccessCommand event) {
        String ownerUsername = event.getPlayer().getUsername();
        String allowedUsername = event.getAllowedUsername();
        LOGGER.info(
                "[AVCSSafehouse] onRemoveAccess: owner={}, allowed={}",
                ownerUsername,
                allowedUsername);
        if (allowedUsername == null) {
            LOGGER.warn("[AVCSSafehouse] Invalid removeAccess args - allowedUsername is null");
            return;
        }
        String error = SafehouseAccessBridge.removeAccess(ownerUsername, allowedUsername);
        if (error != null) {
            LOGGER.warn("[AVCSSafehouse] removeAccess failed: {}", error);
            return;
        }
        SafehouseAccessBridge.broadcast();
    }

    @OnClientCommand
    public void onRequestSync(OnClientRequestSyncCommand event) {
        LOGGER.info(
                "[AVCSSafehouse] onRequestSync from player {}", event.getPlayer().getUsername());
        SafehouseAccessBridge.syncToPlayer(event.getPlayer());
    }
}
