package com.sentientsimulations.projectzomboid.extralogging.containerhistory;

import io.pzstorm.storm.event.core.ClientCommand;
import io.pzstorm.storm.event.core.ClientCommandEvent;
import org.jetbrains.annotations.Nullable;
import se.krka.kahlua.vm.KahluaTable;
import zombie.characters.IsoPlayer;

@ClientCommand(module = "ExtraLogging", command = "queryContainerHistory")
public class QueryContainerHistoryCommand extends ClientCommandEvent {

    public QueryContainerHistoryCommand(IsoPlayer player, @Nullable KahluaTable args) {
        super(player, args);
    }

    public String getContainerRef() {
        return getString("ref");
    }

    public Integer getLimit() {
        Double d = getDouble("limit");
        return d == null ? null : d.intValue();
    }
}
