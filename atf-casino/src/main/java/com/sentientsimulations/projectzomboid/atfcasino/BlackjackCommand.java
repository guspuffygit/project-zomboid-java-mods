package com.sentientsimulations.projectzomboid.atfcasino;

import io.pzstorm.storm.event.core.ClientCommand;
import io.pzstorm.storm.event.core.ClientCommandEvent;
import org.jetbrains.annotations.Nullable;
import se.krka.kahlua.vm.KahluaTable;
import zombie.characters.IsoPlayer;

/**
 * {@code AtfCasino:blackjack} — every table interaction rides one command with an {@code action}
 * field: {@code open, close, sit, leave, bet, hit, stand, double}. {@code bet} carries {@code
 * amount}.
 */
@ClientCommand(module = "AtfCasino", command = "blackjack")
public class BlackjackCommand extends ClientCommandEvent {

    public BlackjackCommand(IsoPlayer player, @Nullable KahluaTable args) {
        super(player, args);
    }

    @Nullable
    public String getAction() {
        return getString("action");
    }

    public int getAmount() {
        Double amount = getDouble("amount");
        if (amount == null || amount.isNaN() || amount.isInfinite()) {
            return 0;
        }
        return (int) Math.floor(Math.max(0.0, Math.min(amount, Integer.MAX_VALUE)));
    }
}
