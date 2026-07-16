package com.sentientsimulations.projectzomboid.survivorskillobelisk;

import io.pzstorm.storm.event.core.ClientCommand;
import io.pzstorm.storm.event.core.ClientCommandEvent;
import org.jetbrains.annotations.Nullable;
import se.krka.kahlua.vm.KahluaTable;
import zombie.characters.IsoPlayer;

@ClientCommand(module = "SurvivorSkillObelisk", command = "syncAmbitions")
public class SyncAmbitionsCommand extends ClientCommandEvent {

    public SyncAmbitionsCommand(IsoPlayer player, @Nullable KahluaTable args) {
        super(player, args);
    }

    /**
     * Lifestyles {@code Ambitions} table: ambition name (e.g. {@code LSTerminator}) → table with
     * {@code cat}, progress flags, and goal/progress slots. {@code null} when the client sent a
     * malformed payload.
     */
    public @Nullable KahluaTable getAmbitions() {
        return rawget("ambitions") instanceof KahluaTable ambitions ? ambitions : null;
    }
}
