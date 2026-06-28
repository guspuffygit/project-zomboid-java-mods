package com.sentientsimulations.projectzomboid.survivorskillobelisk;

import io.pzstorm.storm.event.core.ClientCommand;
import io.pzstorm.storm.event.core.ClientCommandEvent;
import org.jetbrains.annotations.Nullable;
import se.krka.kahlua.vm.KahluaTable;
import zombie.characters.IsoPlayer;

@ClientCommand(module = "SurvivorSkillObelisk", command = "listAllObelisks")
public class ListAllObelisksCommand extends ClientCommandEvent {

    public ListAllObelisksCommand(IsoPlayer player, @Nullable KahluaTable args) {
        super(player, args);
    }
}
