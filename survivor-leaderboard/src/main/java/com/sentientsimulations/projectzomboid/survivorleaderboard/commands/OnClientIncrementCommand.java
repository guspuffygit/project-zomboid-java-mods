package com.sentientsimulations.projectzomboid.survivorleaderboard.commands;

import io.pzstorm.storm.event.core.ClientCommand;
import io.pzstorm.storm.event.core.ClientCommandEvent;
import org.jspecify.annotations.Nullable;
import se.krka.kahlua.vm.KahluaTable;
import zombie.characters.IsoPlayer;

@ClientCommand(module = "SurvivorLeaderboard", command = "Increment")
public class OnClientIncrementCommand extends ClientCommandEvent {
    public OnClientIncrementCommand(IsoPlayer player, @Nullable KahluaTable args) {
        super(player, args);
    }

    public String getName() {
        return getString("name");
    }

    public Double getR() {
        return getDouble("r");
    }

    public Double getG() {
        return getDouble("g");
    }

    public Double getB() {
        return getDouble("b");
    }

    public Double getA() {
        return getDouble("a");
    }
}
