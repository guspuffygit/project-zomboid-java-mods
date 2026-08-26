package com.sentientsimulations.projectzomboid.atfcasino;

import io.pzstorm.storm.event.core.ClientCommand;
import io.pzstorm.storm.event.core.ClientCommandEvent;
import org.jetbrains.annotations.Nullable;
import se.krka.kahlua.vm.KahluaTable;
import zombie.characters.IsoPlayer;

@ClientCommand(module = "AtfCasino", command = "placeBet")
public class PlaceBetCommand extends ClientCommandEvent {

    public PlaceBetCommand(IsoPlayer player, @Nullable KahluaTable args) {
        super(player, args);
    }

    @Nullable
    public String getGameId() {
        return getString("game");
    }

    /** Player's pick within the game, e.g. {@code heads} — meaning is game-specific. */
    @Nullable
    public String getSelection() {
        return getString("selection");
    }

    public int getWager() {
        Double wager = getDouble("wager");
        return wager == null ? 0 : (int) Math.floor(wager);
    }
}
