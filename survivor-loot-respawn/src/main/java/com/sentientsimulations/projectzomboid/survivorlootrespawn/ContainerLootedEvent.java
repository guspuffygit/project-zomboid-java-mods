package com.sentientsimulations.projectzomboid.survivorlootrespawn;

import io.pzstorm.storm.event.core.ZomboidEvent;
import lombok.Getter;
import lombok.RequiredArgsConstructor;
import org.jetbrains.annotations.Nullable;
import zombie.characters.IsoPlayer;
import zombie.inventory.ItemContainer;

@RequiredArgsConstructor
public class ContainerLootedEvent implements ZomboidEvent {

    @Getter @Nullable private final IsoPlayer player;
    @Getter private final ItemContainer container;
    @Getter private final int x;
    @Getter private final int y;
    @Getter private final int z;

    @Override
    public String getName() {
        return "ContainerLooted";
    }
}
