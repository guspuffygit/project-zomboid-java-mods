package com.sentientsimulations.projectzomboid.survivorskillobelisk;

import io.pzstorm.storm.event.core.ClientCommand;
import io.pzstorm.storm.event.core.ClientCommandEvent;
import org.jetbrains.annotations.Nullable;
import se.krka.kahlua.vm.KahluaTable;
import zombie.characters.IsoPlayer;

@ClientCommand(module = "SurvivorSkillObelisk", command = "listDeaths")
public class ListDeathsCommand extends ClientCommandEvent {

    public ListDeathsCommand(IsoPlayer player, @Nullable KahluaTable args) {
        super(player, args);
    }

    public Integer getLimit() {
        Double d = getDouble("limit");
        return d == null ? null : d.intValue();
    }

    public Integer getX() {
        Double d = getDouble("x");
        return d == null ? null : d.intValue();
    }

    public Integer getY() {
        Double d = getDouble("y");
        return d == null ? null : d.intValue();
    }

    public Integer getZ() {
        Double d = getDouble("z");
        return d == null ? null : d.intValue();
    }
}
