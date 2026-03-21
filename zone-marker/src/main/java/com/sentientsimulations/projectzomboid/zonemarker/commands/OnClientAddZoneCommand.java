package com.sentientsimulations.projectzomboid.zonemarker.commands;

import io.pzstorm.storm.event.core.ClientCommand;
import io.pzstorm.storm.event.core.ClientCommandEvent;
import org.jspecify.annotations.Nullable;
import se.krka.kahlua.vm.KahluaTable;
import zombie.characters.IsoPlayer;

@ClientCommand(module = "ZoneMarker", command = "addZone")
public class OnClientAddZoneCommand extends ClientCommandEvent {
    public OnClientAddZoneCommand(IsoPlayer player, @Nullable KahluaTable args) {
        super(player, args);
    }

    public String getCategoryName() {
        return getString("categoryName");
    }

    public Double getXStart() {
        return getDouble("xStart");
    }

    public Double getYStart() {
        return getDouble("yStart");
    }

    public Double getXEnd() {
        return getDouble("xEnd");
    }

    public Double getYEnd() {
        return getDouble("yEnd");
    }

    public String getRegion() {
        return getString("region");
    }
}
