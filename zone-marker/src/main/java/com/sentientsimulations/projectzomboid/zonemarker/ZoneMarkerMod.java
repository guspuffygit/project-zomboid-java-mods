package com.sentientsimulations.projectzomboid.zonemarker;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import io.pzstorm.storm.event.core.StormEventDispatcher;
import io.pzstorm.storm.mod.ZomboidMod;
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
                ZoneAddCategoryCommand.class,
                ZoneRemoveCategoryCommand.class,
                ZoneAddCommand.class,
                ZoneRemoveCommand.class,
                ZoneListCommand.class);
    }
}
