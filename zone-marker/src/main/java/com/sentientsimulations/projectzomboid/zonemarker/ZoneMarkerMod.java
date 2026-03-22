package com.sentientsimulations.projectzomboid.zonemarker;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import com.sentientsimulations.projectzomboid.zonemarker.commands.*;
import io.pzstorm.storm.event.core.OnClientCommand;
import io.pzstorm.storm.event.core.StormEventDispatcher;
import io.pzstorm.storm.event.core.SubscribeEvent;
import io.pzstorm.storm.event.lua.OnServerStartedEvent;
import io.pzstorm.storm.mod.ZomboidMod;
import java.sql.SQLException;
import java.util.List;

public class ZoneMarkerMod implements ZomboidMod {
    @Override
    public void registerEventHandlers() {
        LOGGER.debug("Registering event handler for {}", ZoneMarkerMod.class.getCanonicalName());
        StormEventDispatcher.registerEventHandler(this);
    }

    @Override
    public List<Class<?>> getCommandClasses() {
        return List.of();
    }

    @SubscribeEvent
    public void onServerStarted(OnServerStartedEvent event) {
        try (ZoneMarkerDatabase db = new ZoneMarkerDatabase(ZoneMarkerBridge.getDbPath())) {
            LOGGER.info("ZoneMarker database initialized");
        } catch (SQLException e) {
            LOGGER.error("Failed to initialize ZoneMarker database", e);
        }
    }

    @OnClientCommand
    public void onAddCategory(OnClientAddCategoryCommand event) {
        String name = event.getName();
        Double r = event.getR();
        Double g = event.getG();
        Double b = event.getB();
        Double a = event.getA();
        if (name == null || r == null || g == null || b == null || a == null) {
            LOGGER.warn("Invalid addCategory args from player {}", event.getPlayer().getUsername());
            return;
        }
        String error = ZoneMarkerBridge.addCategory(name, r, g, b, a);
        if (error != null) {
            LOGGER.warn("addCategory failed: {}", error);
            return;
        }
        ZoneMarkerBridge.broadcast();
    }

    @OnClientCommand
    public void onRemoveCategory(OnClientRemoveCategoryCommand event) {
        String name = event.getName();
        if (name == null) {
            LOGGER.warn(
                    "Invalid removeCategory args from player {}", event.getPlayer().getUsername());
            return;
        }
        String error = ZoneMarkerBridge.removeCategory(name);
        if (error != null) {
            LOGGER.warn("removeCategory failed: {}", error);
            return;
        }
        ZoneMarkerBridge.broadcast();
    }

    @OnClientCommand
    public void onAddZone(OnClientAddZoneCommand event) {
        String categoryName = event.getCategoryName();
        Double xStart = event.getXStart();
        Double yStart = event.getYStart();
        Double xEnd = event.getXEnd();
        Double yEnd = event.getYEnd();
        String region = event.getRegion();
        if (categoryName == null
                || xStart == null
                || yStart == null
                || xEnd == null
                || yEnd == null
                || region == null) {
            LOGGER.warn("Invalid addZone args from player {}", event.getPlayer().getUsername());
            return;
        }
        String error = ZoneMarkerBridge.addZone(categoryName, xStart, yStart, xEnd, yEnd, region);
        if (error != null) {
            LOGGER.warn("addZone failed: {}", error);
            return;
        }
        ZoneMarkerBridge.broadcast();
    }

    @OnClientCommand
    public void onRemoveZone(OnClientRemoveZoneCommand event) {
        String categoryName = event.getCategoryName();
        String region = event.getRegion();
        if (categoryName == null || region == null) {
            LOGGER.warn("Invalid removeZone args from player {}", event.getPlayer().getUsername());
            return;
        }
        String error = ZoneMarkerBridge.removeZone(categoryName, region);
        if (error != null) {
            LOGGER.warn("removeZone failed: {}", error);
            return;
        }
        ZoneMarkerBridge.broadcast();
    }

    @OnClientCommand
    public void onRequestSync(OnClientRequestSyncCommand event) {
        ZoneMarkerBridge.syncToPlayer(event.getPlayer());
    }
}
