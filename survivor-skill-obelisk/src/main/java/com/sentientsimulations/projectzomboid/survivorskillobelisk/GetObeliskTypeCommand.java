package com.sentientsimulations.projectzomboid.survivorskillobelisk;

import io.pzstorm.storm.event.core.ClientCommand;
import io.pzstorm.storm.event.core.ClientCommandEvent;
import org.jetbrains.annotations.Nullable;
import se.krka.kahlua.vm.KahluaTable;
import zombie.characters.IsoPlayer;

@ClientCommand(module = "SurvivorSkillObelisk", command = "getObeliskType")
public class GetObeliskTypeCommand extends ClientCommandEvent {

    public GetObeliskTypeCommand(IsoPlayer player, @Nullable KahluaTable args) {
        super(player, args);
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
