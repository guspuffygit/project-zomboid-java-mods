package com.sentientsimulations.projectzomboid.avcsmapview;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import io.pzstorm.storm.event.core.StormEventDispatcher;
import io.pzstorm.storm.event.core.SubscribeEvent;
import io.pzstorm.storm.event.zomboid.OnGetWorldMapFilterOptions;
import io.pzstorm.storm.event.zomboid.OnWorldMapRenderEvent;
import io.pzstorm.storm.event.zomboid.OnZomboidGlobalsLoadEvent;
import io.pzstorm.storm.lua.LuaManagerUtils;
import io.pzstorm.storm.lua.StormKahluaTable;
import io.pzstorm.storm.mod.ZomboidMod;
import io.pzstorm.storm.wrappers.ui.PersistedBooleanConfigOption;
import java.util.*;
import zombie.characters.IsoPlayer;
import zombie.config.BooleanConfigOption;

public class AnotherVehicleClaimSystemMapView implements ZomboidMod {
    private final BooleanConfigOption option =
            new PersistedBooleanConfigOption("Claimed Vehicles", true);
    private Boolean avcsModLoaded = false;

    @Override
    public void registerEventHandlers() {
        LOGGER.debug("Registering event handler for {}", getClass().getName());
        StormEventDispatcher.registerEventHandler(this);
    }

    @SubscribeEvent
    public void onGetWorldMapFilterOptions(OnGetWorldMapFilterOptions event) {
        Optional<StormKahluaTable> avcsTable = LuaManagerUtils.getEnv().getOptionalTable("AVCS");
        if (avcsTable.isPresent()) {
            LOGGER.debug("Adding option {}", event.getName());
            event.addOption(option);
        }
    }

    @SubscribeEvent
    public void onResetLuaEvent(OnZomboidGlobalsLoadEvent event) {
        Optional<StormKahluaTable> avcsTable = LuaManagerUtils.getEnv().getOptionalTable("AVCS");
        avcsModLoaded = avcsTable.isPresent();
    }

    @SubscribeEvent
    public void onGameMapRender(OnWorldMapRenderEvent event) {
        try {
            if (option.getValue() && avcsModLoaded) {
                IsoPlayer player = IsoPlayer.getInstance();
                Optional<StormKahluaTable> avcsTable =
                        LuaManagerUtils.getEnv().getOptionalTable("AVCS");
                if (avcsTable.isEmpty() || player == null) {
                    LOGGER.debug("AVCS mod not loaded.");
                    return;
                }

                StormKahluaTable result =
                        avcsTable.get().pcall("getDetailedVehicleList", StormKahluaTable.class);
                Map<Double, VehicleData> vehicles = new HashMap<>();

                for (int i = 1; i <= result.len(); i++) {
                    VehicleData vehicleData = new VehicleData(result.getTable(i));
                    vehicles.put(vehicleData.getVehicleID(), vehicleData);
                }

                vehicles.values()
                        .forEach(
                                (vehicle) -> {
                                    event.renderPointWithName(
                                            vehicle.getLastLocationX().floatValue(),
                                            vehicle.getLastLocationY().floatValue(),
                                            vehicle.getDisplayName());
                                });
            }
        } catch (Exception e) {
            LOGGER.error("Failed to getDetailedVehicleList", e);
        }
    }
}
