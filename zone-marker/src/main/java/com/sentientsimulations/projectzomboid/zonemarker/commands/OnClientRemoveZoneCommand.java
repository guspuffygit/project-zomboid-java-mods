package com.sentientsimulations.projectzomboid.zonemarker.commands;

import io.pzstorm.storm.event.core.ClientCommand;
import io.pzstorm.storm.event.core.ClientCommandEvent;
import org.jspecify.annotations.Nullable;
import se.krka.kahlua.vm.KahluaTable;
import zombie.characters.IsoPlayer;

@ClientCommand(module = "ZoneMarker", command = "removeZone")
public class OnClientRemoveZoneCommand extends ClientCommandEvent {
    public OnClientRemoveZoneCommand(IsoPlayer player, @Nullable KahluaTable args) {
        super(player, args);
    }

    public String getCategoryName() {
        return getString("categoryName");
    }

    public String getRegion() {
        return getString("region");
    }
}
