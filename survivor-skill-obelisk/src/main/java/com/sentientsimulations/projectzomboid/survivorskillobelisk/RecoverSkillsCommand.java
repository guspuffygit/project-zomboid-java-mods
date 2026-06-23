package com.sentientsimulations.projectzomboid.survivorskillobelisk;

import io.pzstorm.storm.event.core.ClientCommand;
import io.pzstorm.storm.event.core.ClientCommandEvent;
import org.jetbrains.annotations.Nullable;
import se.krka.kahlua.vm.KahluaTable;
import zombie.characters.IsoPlayer;

@ClientCommand(module = "SurvivorSkillObelisk", command = "recoverSkills")
public class RecoverSkillsCommand extends ClientCommandEvent {

    public RecoverSkillsCommand(IsoPlayer player, @Nullable KahluaTable args) {
        super(player, args);
    }

    public Long getDeathId() {
        Double d = getDouble("id");
        return d == null ? null : d.longValue();
    }
}
