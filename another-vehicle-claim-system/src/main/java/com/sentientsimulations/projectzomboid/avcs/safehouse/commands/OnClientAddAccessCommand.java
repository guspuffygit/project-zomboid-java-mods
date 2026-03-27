package com.sentientsimulations.projectzomboid.avcs.safehouse.commands;

import io.pzstorm.storm.event.core.ClientCommand;
import io.pzstorm.storm.event.core.ClientCommandEvent;
import org.jspecify.annotations.Nullable;
import se.krka.kahlua.vm.KahluaTable;
import zombie.characters.IsoPlayer;

@ClientCommand(module = "AVCSSafehouse", command = "addAccess")
public class OnClientAddAccessCommand extends ClientCommandEvent {
    public OnClientAddAccessCommand(IsoPlayer player, @Nullable KahluaTable args) {
        super(player, args);
    }

    public String getAllowedUsername() {
        return getString("allowedUsername");
    }
}
