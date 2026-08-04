package com.sentientsimulations.projectzomboid.jumpscarebanatfeconomy;

import io.pzstorm.storm.event.core.ClientCommand;
import io.pzstorm.storm.event.core.ClientCommandEvent;
import org.jetbrains.annotations.Nullable;
import se.krka.kahlua.vm.KahluaTable;
import zombie.characters.IsoPlayer;

@ClientCommand(module = "JumpscareBanEconomy", command = "purchaseGag")
public class PurchaseGagCommand extends ClientCommandEvent {

    public PurchaseGagCommand(IsoPlayer player, @Nullable KahluaTable args) {
        super(player, args);
    }

    @Nullable
    public String getGagId() {
        return getString("gag");
    }
}
