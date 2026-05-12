package com.sentientsimulations.projectzomboid.survivoreconomy.records;

import org.jspecify.annotations.Nullable;

/**
 * A row in {@code discord_link_codes}. {@code direction} is {@code 'INGAME'} when the code was
 * minted from a player's in-game action (steamId + username set at creation, discordId +
 * discordUsername filled at consume) and {@code 'DISCORD'} for the inverse. {@code consumedAtMs} is
 * null until the code is claimed.
 */
public record DiscordLinkCode(
        String code,
        String direction,
        @Nullable String discordId,
        @Nullable String discordUsername,
        @Nullable Long steamId,
        @Nullable String username,
        long createdAtMs,
        long expiresAtMs,
        @Nullable Long consumedAtMs) {

    public static final String DIRECTION_INGAME = "INGAME";
    public static final String DIRECTION_DISCORD = "DISCORD";
}
