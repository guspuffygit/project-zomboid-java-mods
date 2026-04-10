package com.sentientsimulations.projectzomboid.survivorleaderboard.commands;

import io.pzstorm.storm.event.core.ClientCommand;
import io.pzstorm.storm.event.core.ClientCommandEvent;
import org.jspecify.annotations.Nullable;
import se.krka.kahlua.vm.KahluaTable;
import zombie.characters.IsoPlayer;

@ClientCommand(module = "SurvivorLeaderboard", command = "Refresh")
public class OnClientRefreshCommand extends ClientCommandEvent {
    public OnClientRefreshCommand(IsoPlayer player, @Nullable KahluaTable args) {
        super(player, args);
    }
}
