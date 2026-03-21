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
        return List.of(
                ZoneAddCommand.class,
                ZoneRemoveCommand.class,
                ZoneListCommand.class);
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
        String name = event.getString("name");
        Double r = event.getDouble("r");
        Double g = event.getDouble("g");
        Double b = event.getDouble("b");
        Double a = event.getDouble("a");
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
        String name = event.getString("name");
        if (name == null) {
            LOGGER.warn("Invalid removeCategory args from player {}", event.getPlayer().getUsername());
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
    public void onRequestSync(OnClientRequestSyncCommand event) {
        ZoneMarkerBridge.syncToPlayer(event.getPlayer());
    }
}
