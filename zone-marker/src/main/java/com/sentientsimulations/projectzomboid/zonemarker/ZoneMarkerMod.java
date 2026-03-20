package com.sentientsimulations.projectzomboid.zonemarker;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import com.sentientsimulations.projectzomboid.zonemarker.commands.*;
import io.pzstorm.storm.event.core.StormEventDispatcher;
import io.pzstorm.storm.event.core.SubscribeEvent;
import io.pzstorm.storm.event.lua.OnClientCommandEvent;
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
                ZoneCategoryAddCommand.class,
                ZoneCategoryRemoveCommand.class,
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

    @SubscribeEvent
    public void onClientCommand(OnClientCommandEvent event) {
        if (!ZoneMarkerBridge.MODULE.equals(event.var1)) return;
        if ("requestSync".equals(event.var2)) {
            ZoneMarkerBridge.syncToPlayer(event.player);
        }
    }
}
