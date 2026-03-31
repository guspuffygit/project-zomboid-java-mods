package com.sentientsimulations.projectzomboid.extralogging.events;

import io.pzstorm.storm.event.core.ZomboidEvent;
import zombie.characters.IsoPlayer;
import zombie.iso.objects.IsoDeadBody;

/** Dispatched on the server when {@link IsoPlayer#onDied} is called. */
public class PlayerDiedEvent implements ZomboidEvent {

    public final IsoPlayer player;
    public final IsoDeadBody body;

    public PlayerDiedEvent(IsoPlayer player, IsoDeadBody body) {
        this.player = player;
        this.body = body;
    }

    @Override
    public String getName() {
        return "PlayerDied";
    }
}
