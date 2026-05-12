package com.sentientsimulations.projectzomboid.survivoreconomy.records;

import org.jspecify.annotations.Nullable;

/**
 * Outcome of consuming a {@code discord_link_codes} row. On success the relevant identity fields
 * are populated; on failure {@code failureReason} is one of the {@code FAILURE_*} constants.
 */
public record DiscordLinkClaimResult(
        boolean ok,
        @Nullable String discordId,
        @Nullable String discordUsername,
        @Nullable Long steamId,
        @Nullable String username,
        @Nullable String failureReason) {

    public static final String FAILURE_NOT_FOUND = "NOT_FOUND";
    public static final String FAILURE_EXPIRED = "EXPIRED";
    public static final String FAILURE_ALREADY_CONSUMED = "ALREADY_CONSUMED";
    public static final String FAILURE_WRONG_DIRECTION = "WRONG_DIRECTION";

    public static DiscordLinkClaimResult successDiscordToPlayer(
            String discordId, @Nullable String discordUsername, long steamId, String username) {
        return new DiscordLinkClaimResult(
                true, discordId, discordUsername, steamId, username, null);
    }

    public static DiscordLinkClaimResult successPlayerToDiscord(
            long steamId, String username, String discordId, @Nullable String discordUsername) {
        return new DiscordLinkClaimResult(
                true, discordId, discordUsername, steamId, username, null);
    }

    public static DiscordLinkClaimResult failure(String reason) {
        return new DiscordLinkClaimResult(false, null, null, null, null, reason);
    }
}
