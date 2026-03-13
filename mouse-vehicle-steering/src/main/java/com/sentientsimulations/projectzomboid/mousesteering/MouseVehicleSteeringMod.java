package com.sentientsimulations.projectzomboid.mousesteering;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import io.pzstorm.storm.core.StormClassTransformer;
import io.pzstorm.storm.event.core.StormEventDispatcher;
import io.pzstorm.storm.mod.ZomboidMod;

import java.util.Collections;
import java.util.List;

public class MouseVehicleSteeringMod implements ZomboidMod {

    @Override
    public void registerEventHandlers() {
        LOGGER.debug("Registering event handler for MouseVehicleSteeringMod");
        StormEventDispatcher.registerEventHandler(this);
    }

    @Override
    public List<Class<?>> getCommandClasses() {
        return Collections.singletonList(MouseSteeringCommand.class);
    }

    @Override
    public List<StormClassTransformer> getClassTransformers() {
        return Collections.singletonList(new CarControllerPatch());
    }
}
