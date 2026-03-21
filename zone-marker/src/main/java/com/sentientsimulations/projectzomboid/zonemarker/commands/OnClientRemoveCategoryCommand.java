package com.sentientsimulations.projectzomboid.zonemarker.commands;

import io.pzstorm.storm.event.core.ClientCommand;
import io.pzstorm.storm.event.core.ClientCommandEvent;
import org.jspecify.annotations.Nullable;
import se.krka.kahlua.vm.KahluaTable;
import zombie.characters.IsoPlayer;

@ClientCommand(module = "ZoneMarker", command = "removeCategory")
public class OnClientRemoveCategoryCommand extends ClientCommandEvent {
    public OnClientRemoveCategoryCommand(IsoPlayer player, @Nullable KahluaTable args) {
        super(player, args);
    }

    public String getName() {
        return getString("name");
    }
}
