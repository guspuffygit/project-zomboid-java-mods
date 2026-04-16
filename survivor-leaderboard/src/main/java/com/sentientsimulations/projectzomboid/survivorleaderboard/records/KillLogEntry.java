package com.sentientsimulations.projectzomboid.survivorleaderboard.records;

public record KillLogEntry(
        long id,
        long killerSteamId,
        String killerUsername,
        long victimSteamId,
        String victimUsername,
        boolean isAlly,
        long createdAt) {}
