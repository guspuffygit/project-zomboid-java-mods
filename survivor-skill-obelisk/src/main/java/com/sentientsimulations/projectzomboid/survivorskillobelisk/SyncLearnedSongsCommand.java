package com.sentientsimulations.projectzomboid.survivorskillobelisk;

import io.pzstorm.storm.event.core.ClientCommand;
import io.pzstorm.storm.event.core.ClientCommandEvent;
import org.jetbrains.annotations.Nullable;
import se.krka.kahlua.vm.KahluaTable;
import zombie.characters.IsoPlayer;

@ClientCommand(module = "SurvivorSkillObelisk", command = "syncLearnedSongs")
public class SyncLearnedSongsCommand extends ClientCommandEvent {

    public SyncLearnedSongsCommand(IsoPlayer player, @Nullable KahluaTable args) {
        super(player, args);
    }

    /**
     * Map of Lifestyles instrument ModData key (e.g. {@code PianoLearnedTracks}) → Lua array of
     * song record tables. {@code null} when the client sent a malformed payload.
     */
    public @Nullable KahluaTable getTracks() {
        return rawget("tracks") instanceof KahluaTable tracks ? tracks : null;
    }
}
