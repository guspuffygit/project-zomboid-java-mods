package com.sentientsimulations.projectzomboid.survivorskillobelisk;

import io.pzstorm.storm.event.core.ClientCommand;
import io.pzstorm.storm.event.core.ClientCommandEvent;
import org.jetbrains.annotations.Nullable;
import se.krka.kahlua.vm.KahluaTable;
import zombie.characters.IsoPlayer;

@ClientCommand(module = "SurvivorSkillObelisk", command = "syncHiddenSkills")
public class SyncHiddenSkillsCommand extends ClientCommandEvent {

    public SyncHiddenSkillsCommand(IsoPlayer player, @Nullable KahluaTable args) {
        super(player, args);
    }

    /**
     * Lifestyles {@code LSHiddenSkills} table: skill name (e.g. {@code Yoga}) → Lua array of {@code
     * {level, xp, xpForNextLevel}}. {@code null} when the client sent a malformed payload.
     */
    public @Nullable KahluaTable getSkills() {
        return rawget("skills") instanceof KahluaTable skills ? skills : null;
    }
}
