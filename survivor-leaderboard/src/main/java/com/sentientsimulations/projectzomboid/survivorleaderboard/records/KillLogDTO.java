package com.sentientsimulations.projectzomboid.survivorleaderboard.records;

public record KillLogDTO(
        long killerSteamId,
        String killerUsername,
        long victimSteamId,
        String victimUsername,
        boolean isAlly,
        long createdAt) {}
