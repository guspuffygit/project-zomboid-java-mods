package com.sentientsimulations.projectzomboid.atfcasino;

import io.pzstorm.storm.event.core.ClientCommand;
import io.pzstorm.storm.event.core.ClientCommandEvent;
import org.jetbrains.annotations.Nullable;
import se.krka.kahlua.vm.KahluaTable;
import zombie.characters.IsoPlayer;

/**
 * {@code AtfCasino:roulette} — every table interaction rides one command with an {@code action}
 * field: {@code open, close, sit, leave, bet, clear}. {@code bet} carries {@code type} (see {@link
 * com.sentientsimulations.projectzomboid.atfcasino.roulette.RouletteTable.BetType#wire()}), {@code
 * target} and {@code amount}.
 */
@ClientCommand(module = "AtfCasino", command = "roulette")
public class RouletteCommand extends ClientCommandEvent {

    public RouletteCommand(IsoPlayer player, @Nullable KahluaTable args) {
        super(player, args);
    }

    @Nullable
    public String getAction() {
        return getString("action");
    }

    @Nullable
    public String getBetType() {
        return getString("type");
    }

    public int getTarget() {
        return clampInt(getDouble("target"), -1);
    }

    public int getAmount() {
        return clampInt(getDouble("amount"), 0);
    }

    private static int clampInt(@Nullable Double value, int fallback) {
        if (value == null || value.isNaN() || value.isInfinite()) {
            return fallback;
        }
        return (int) Math.floor(Math.max(-1.0, Math.min(value, Integer.MAX_VALUE)));
    }
}
