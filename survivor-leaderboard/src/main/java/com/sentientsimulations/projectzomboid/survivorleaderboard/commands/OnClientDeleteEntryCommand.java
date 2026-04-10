package com.sentientsimulations.projectzomboid.survivorleaderboard.commands;

import io.pzstorm.storm.event.core.ClientCommand;
import io.pzstorm.storm.event.core.ClientCommandEvent;
import io.pzstorm.storm.lua.StormKahluaTable;
import org.jspecify.annotations.Nullable;
import se.krka.kahlua.vm.KahluaTable;
import zombie.characters.IsoPlayer;

@ClientCommand(module = "Lifeboard", command = "DeleteEntry")
public class OnClientDeleteEntryCommand extends ClientCommandEvent {
    public OnClientDeleteEntryCommand(IsoPlayer player, @Nullable KahluaTable args) {
        super(player, args);
    }

    public String getDisplayName() {
        return getTable("player").getString("displayName");
    }

    public Double getDayCount() {
        return getTable("player").getDouble("dayCount");
    }
}
