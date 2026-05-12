package com.sentientsimulations.projectzomboid.survivoreconomy.records;

import org.jspecify.annotations.Nullable;

public record DiscordLink(
        String discordId,
        @Nullable String discordUsername,
        long steamId,
        long createdAtMs,
        long updatedAtMs) {}
