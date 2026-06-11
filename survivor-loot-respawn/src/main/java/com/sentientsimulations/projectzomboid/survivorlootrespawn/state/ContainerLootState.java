package com.sentientsimulations.projectzomboid.survivorlootrespawn.state;

public record ContainerLootState(
        int squareX,
        int squareY,
        int squareZ,
        String containerType,
        int containerIndex,
        double lootedGameHours,
        Double respawnQueuedAtHours,
        int fillAddedNothingCount) {}
