package com.sentientsimulations.projectzomboid.avcs.safehouse.commands;

import io.pzstorm.storm.event.core.ClientCommand;
import io.pzstorm.storm.event.core.ClientCommandEvent;
import org.jspecify.annotations.Nullable;
import se.krka.kahlua.vm.KahluaTable;
import zombie.characters.IsoPlayer;

@ClientCommand(module = "AVCSSafehouse", command = "removeAccess")
public class OnClientRemoveAccessCommand extends ClientCommandEvent {
    public OnClientRemoveAccessCommand(IsoPlayer player, @Nullable KahluaTable args) {
        super(player, args);
    }

    public String getAllowedUsername() {
        return getString("allowedUsername");
    }
}
