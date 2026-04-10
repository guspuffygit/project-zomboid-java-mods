package com.sentientsimulations.projectzomboid.survivorleaderboard;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import com.sentientsimulations.projectzomboid.survivorleaderboard.commands.*;
import com.sentientsimulations.projectzomboid.zonemarker.commands.*;
import io.pzstorm.storm.event.core.OnClientCommand;
import io.pzstorm.storm.event.core.StormEventDispatcher;
import io.pzstorm.storm.event.core.SubscribeEvent;
import io.pzstorm.storm.event.lua.OnServerStartedEvent;
import io.pzstorm.storm.mod.ZomboidMod;
import java.sql.SQLException;
import java.util.List;

public class SurvivorLeaderboardMod implements ZomboidMod {
    @Override
    public void registerEventHandlers() {
        LOGGER.info(
                "[ZoneMarker] Registering event handlers for {}",
                SurvivorLeaderboardMod.class.getCanonicalName());
        StormEventDispatcher.registerEventHandler(this);
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
                SurvivorLeaderboardBridge.getDbPath());
        try (SurvivorLeaderboardDatabase db = new SurvivorLeaderboardDatabase(SurvivorLeaderboardBridge.getDbPath())) {
            LOGGER.info("[ZoneMarker] Database initialized successfully");
        } catch (SQLException e) {
            LOGGER.error("[ZoneMarker] Failed to initialize database", e);
        }
    }

    @OnClientCommand
    public void onAddCategory(OnClientIncrementCommand event) {
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
        String error = SurvivorLeaderboardBridge.addCategory(name, r, g, b, a);
        if (error != null) {
            LOGGER.warn("[ZoneMarker] addCategory failed: {}", error);
            return;
        }
        LOGGER.info("[ZoneMarker] addCategory succeeded, broadcasting");
        SurvivorLeaderboardBridge.broadcast();
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
        String error = SurvivorLeaderboardBridge.removeCategory(name);
        if (error != null) {
            LOGGER.warn("[ZoneMarker] removeCategory failed: {}", error);
            return;
        }
        LOGGER.info("[ZoneMarker] removeCategory succeeded, broadcasting");
        SurvivorLeaderboardBridge.broadcast();
    }

    @OnClientCommand
    public void onAddZone(OnClientRefreshCommand event) {
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
        String error = SurvivorLeaderboardBridge.addZone(categoryName, xStart, yStart, xEnd, yEnd, region);
        if (error != null) {
            LOGGER.warn("[ZoneMarker] addZone failed: {}", error);
            return;
        }
        LOGGER.info("[ZoneMarker] addZone succeeded, broadcasting");
        SurvivorLeaderboardBridge.broadcast();
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
        String error = SurvivorLeaderboardBridge.removeZone(categoryName, region);
        if (error != null) {
            LOGGER.warn("[ZoneMarker] removeZone failed: {}", error);
            return;
        }
        LOGGER.info("[ZoneMarker] removeZone succeeded, broadcasting");
        SurvivorLeaderboardBridge.broadcast();
    }

    @OnClientCommand
    public void onRequestSync(OnClientAddPlayerCommand event) {
        LOGGER.info(
                "[ZoneMarker] onRequestSync handler called by player {}",
                event.getPlayer().getUsername());
        SurvivorLeaderboardBridge.syncToPlayer(event.getPlayer());
    }
}
