package com.sentientsimulations.projectzomboid.atfcasino;

import io.pzstorm.storm.event.core.ClientCommand;
import io.pzstorm.storm.event.core.ClientCommandEvent;
import org.jetbrains.annotations.Nullable;
import se.krka.kahlua.vm.KahluaTable;
import zombie.characters.IsoPlayer;

/**
 * {@code AtfCasino:holdem} — every poker-table interaction rides one command with an {@code action}
 * field: {@code open, close, sit, leave, buyin, fold, check, call, raise, allin}. {@code buyin}
 * carries {@code amount} (chips to add); {@code raise} carries {@code amount} (the total bet to
 * raise to on this street).
 */
@ClientCommand(module = "AtfCasino", command = "holdem")
public class HoldemCommand extends ClientCommandEvent {

    public HoldemCommand(IsoPlayer player, @Nullable KahluaTable args) {
        super(player, args);
    }

    @Nullable
    public String getAction() {
        return getString("action");
    }

    public int getAmount() {
        Double value = getDouble("amount");
        if (value == null || value.isNaN() || value.isInfinite()) {
            return 0;
        }
        return (int) Math.floor(Math.max(0.0, Math.min(value, Integer.MAX_VALUE)));
    }
}
