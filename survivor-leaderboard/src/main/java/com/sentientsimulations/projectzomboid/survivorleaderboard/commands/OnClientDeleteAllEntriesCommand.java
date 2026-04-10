package com.sentientsimulations.projectzomboid.survivorleaderboard.commands;

import io.pzstorm.storm.event.core.ClientCommand;
import io.pzstorm.storm.event.core.ClientCommandEvent;
import org.jspecify.annotations.Nullable;
import se.krka.kahlua.vm.KahluaTable;
import zombie.characters.IsoPlayer;

@ClientCommand(module = "Lifeboard", command = "DeleteAllEntries")
public class OnClientDeleteAllEntriesCommand extends ClientCommandEvent {
    public OnClientDeleteAllEntriesCommand(IsoPlayer player, @Nullable KahluaTable args) {
        super(player, args);
    }
}
