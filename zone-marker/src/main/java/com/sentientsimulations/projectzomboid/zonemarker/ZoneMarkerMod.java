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
        LOGGER.info(
                "[ZoneMarker] Registering event handlers for {}",
                ZoneMarkerMod.class.getCanonicalName());
        StormEventDispatcher.registerEventHandler(this);
        StormEventDispatcher.registerEventHandler(ZoneMarkerBridge.class);
        LOGGER.info("[ZoneMarker] Event handlers registered successfully");
    }

    @Override
    public List<Class<?>> getCommandClasses() {
        return List.of();
    }

    @SubscribeEvent
    public void onServerStarted(OnServerStartedEvent event) {
        LOGGER.info(
                "[ZoneMarker] onServerStarted fired, initializing DB at {}",
                ZoneMarkerBridge.getDbPath());
        try (ZoneMarkerDatabase db = new ZoneMarkerDatabase(ZoneMarkerBridge.getDbPath())) {
            LOGGER.info("[ZoneMarker] Database initialized successfully");
        } catch (SQLException e) {
            LOGGER.error("[ZoneMarker] Failed to initialize database", e);
        }
    }

    @OnClientCommand
    public void onAddCategory(OnClientAddCategoryCommand event) {
        LOGGER.info(
                "[ZoneMarker] onAddCategory handler called by player {}",
                event.getPlayer().getUsername());
        String name = event.getName();
        Double r = event.getR();
        Double g = event.getG();
        Double b = event.getB();
        Double a = event.getA();
        LOGGER.info(
                "[ZoneMarker] addCategory args: name={}, r={}, g={}, b={}, a={}", name, r, g, b, a);
        if (name == null || r == null || g == null || b == null || a == null) {
            LOGGER.warn("[ZoneMarker] Invalid addCategory args - one or more nulls");
            return;
        }
        ZoneMarkerBridge.addCategoryAsync(name, r, g, b, a);
    }

    @OnClientCommand
    public void onRemoveCategory(OnClientRemoveCategoryCommand event) {
        LOGGER.info(
                "[ZoneMarker] onRemoveCategory handler called by player {}",
                event.getPlayer().getUsername());
        String name = event.getName();
        LOGGER.info("[ZoneMarker] removeCategory args: name={}", name);
        if (name == null) {
            LOGGER.warn("[ZoneMarker] Invalid removeCategory args - name is null");
            return;
        }
        ZoneMarkerBridge.removeCategoryAsync(name);
    }

    @OnClientCommand
    public void onAddZone(OnClientAddZoneCommand event) {
        LOGGER.info(
                "[ZoneMarker] onAddZone handler called by player {}",
                event.getPlayer().getUsername());
        String categoryName = event.getCategoryName();
        Double xStart = event.getXStart();
        Double yStart = event.getYStart();
        Double xEnd = event.getXEnd();
        Double yEnd = event.getYEnd();
        String region = event.getRegion();
        LOGGER.info(
                "[ZoneMarker] addZone args: cat={}, region={}, x1={}, y1={}, x2={}, y2={}",
                categoryName,
                region,
                xStart,
                yStart,
                xEnd,
                yEnd);
        if (categoryName == null
                || xStart == null
                || yStart == null
                || xEnd == null
                || yEnd == null
                || region == null) {
            LOGGER.warn("[ZoneMarker] Invalid addZone args - one or more nulls");
            return;
        }
        ZoneMarkerBridge.addZoneAsync(categoryName, xStart, yStart, xEnd, yEnd, region);
    }

    @OnClientCommand
    public void onRemoveZone(OnClientRemoveZoneCommand event) {
        LOGGER.info(
                "[ZoneMarker] onRemoveZone handler called by player {}",
                event.getPlayer().getUsername());
        String categoryName = event.getCategoryName();
        String region = event.getRegion();
        LOGGER.info("[ZoneMarker] removeZone args: cat={}, region={}", categoryName, region);
        if (categoryName == null || region == null) {
            LOGGER.warn("[ZoneMarker] Invalid removeZone args - one or more nulls");
            return;
        }
        ZoneMarkerBridge.removeZoneAsync(categoryName, region);
    }

    @OnClientCommand
    public void onRequestSync(OnClientRequestSyncCommand event) {
        LOGGER.info(
                "[ZoneMarker] onRequestSync handler called by player {}",
                event.getPlayer().getUsername());
        ZoneMarkerBridge.syncToPlayerAsync(event.getPlayer());
    }
}
